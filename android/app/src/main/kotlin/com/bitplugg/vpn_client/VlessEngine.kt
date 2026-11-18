package com.bitplugg.vpn_client

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import java.io.File
import java.net.InetSocketAddress
import java.net.Socket
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.json.JSONObject

/**
 * Реальный VLESS-движок: Xray-core как SOCKS5-прокси + tun2socks + VpnService.
 *
 * Никаких заглушек: если бинарники отсутствуют или Xray не поднялся,
 * подключение завершается ошибкой. Процессные синглтоны нужны, чтобы
 * состояние выживало после пересоздания Activity.
 */
class VlessEngine private constructor(context: Context) : ProtocolEngine {

    private val appContext: Context = context.applicationContext
    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "mouvi-vless-engine").apply { isDaemon = true }
    }
    private val mainHandler = Handler(Looper.getMainLooper())

    private val filesDir: File get() = appContext.filesDir
    private val xrayBinary: File get() = File(filesDir, BINARY_XRAY)
    private val tunBinary: File get() = File(filesDir, MouviVpnService.BINARY_TUN2SOCKS)
    private val configFile: File get() = File(filesDir, "vless-xray.json")

    @Volatile
    private var stateListener: ((Boolean) -> Unit)? = null

    @Volatile
    private var serviceUp = false

    @Volatile
    private var xrayProcess: Process? = null

    @Volatile
    private var statsCache: Stats = Stats(0L, 0L)

    @Volatile
    private var statsCachedAt = 0L

    override fun setStateListener(listener: ((Boolean) -> Unit)?) {
        stateListener = listener
    }

    override fun connect(request: VpnConnectRequest, callback: (VpnResult<String>) -> Unit) {
        executor.execute {
            val result = try {
                val profile = VlessConfigParser.parse(request.content)
                installBinaries()
                val config = XrayConfigBuilder.build(profile)
                writeConfig(config)
                startXray()
                waitForSocksPort()
                startVpnService(request, profile)
                waitForService()
                VpnResult.Success(TUNNEL_NAME)
            } catch (error: VlessConfigException) {
                cleanup()
                VpnResult.Failure("invalid_config", error.message)
            } catch (error: Throwable) {
                cleanup()
                VpnResult.Failure("tunnel_start_failed", error.message ?: error.javaClass.simpleName)
            }
            mainHandler.post { callback(result) }
        }
    }

    override fun disconnect(callback: (VpnResult<Unit>) -> Unit) {
        executor.execute {
            cleanup()
            mainHandler.post { callback(VpnResult.Success(Unit)) }
        }
    }

    override fun getState(): Map<String, Any?> {
        val isUp = serviceUp && processAlive(xrayProcess)
        if (!isUp) {
            return baseMap("down") + emptyStats()
        }
        val stats = readStats()
        return baseMap("up") + mapOf(
            "rxBytes" to stats.rx,
            "txBytes" to stats.tx,
            // VLESS не имеет handshake-счётчика analogue WireGuard.
            "lastHandshakeMs" to 0L,
        )
    }

    override fun currentStateMap(): Map<String, Any?> = getState()

    internal fun setServiceUp(up: Boolean) {
        serviceUp = up
        mainHandler.post {
            synchronized(this) { stateListener }?.invoke(up)
        }
        if (!up) {
            synchronized(this) {
                xrayProcess?.destroy()
                xrayProcess = null
            }
        }
    }

    private fun baseMap(status: String): Map<String, Any?> = mapOf(
        "status" to status,
        "tunnelName" to TUNNEL_NAME,
        "alwaysOn" to false,
        "lockdown" to false,
    )

    private fun emptyStats(): Map<String, Any?> = mapOf(
        "rxBytes" to 0L,
        "txBytes" to 0L,
        "lastHandshakeMs" to 0L,
    )

    private fun installBinaries() {
        val nativeLibraryDir = appContext.applicationInfo.nativeLibraryDir
        listOf(
            NativeBinary("libxray.so", xrayBinary),
            NativeBinary("libtun2socks.so", tunBinary),
        ).forEach { binary ->
            val source = File(nativeLibraryDir, binary.assetName)
            if (!source.exists()) {
                throw IllegalStateException("Native library ${binary.assetName} is missing")
            }
            val sourceHash = sha256(source)
            val marker = File(filesDir, ".${binary.target.name}.sha256")
            val currentHash = marker.takeIf { it.exists() }?.readText()?.trim()
            if (binary.target.exists() && currentHash == sourceHash) {
                return@forEach
            }
            val temporary = File(filesDir, "${binary.target.name}.tmp")
            source.inputStream().use { input ->
                temporary.outputStream().use { output -> input.copyTo(output) }
            }
            if (!temporary.renameTo(binary.target)) {
                temporary.delete()
                throw IllegalStateException("Could not install ${binary.target.name}")
            }
            binary.target.setExecutable(true, false)
            marker.writeText(sourceHash)
        }
    }

    private fun writeConfig(content: String) {
        configFile.writeText(content, Charsets.UTF_8)
        if (!configFile.setReadable(true, true)) {
            throw IllegalStateException("Could not protect Xray config")
        }
    }

    private fun startXray() {
        if (!xrayBinary.exists()) {
            throw IllegalStateException("Xray binary is missing")
        }
        val process = ProcessBuilder(
            listOf(xrayBinary.absolutePath, "run", "-c", configFile.absolutePath),
        )
            .directory(filesDir)
            .redirectErrorStream(true)
            .redirectOutput(ProcessBuilder.Redirect.appendTo(File(filesDir, "xray.log")))
            .start()
        synchronized(this) {
            xrayProcess?.destroy()
            xrayProcess = process
        }
        watchProcess(process)
    }

    private fun watchProcess(process: Process) {
        Thread({
            val exit = try {
                process.waitFor()
            } catch (_: Throwable) {
                -1
            }
            if (synchronized(this) { xrayProcess === process }) {
                serviceUp = false
                MouviVpnService.stop(appContext)
                mainHandler.post {
                    synchronized(this) { stateListener }?.invoke(false)
                }
            }
            if (exit != 0) {
                // В лог пишем только код возврата, без содержимого конфига.
                File(filesDir, "xray.log").appendText("xray exited with code $exit\n")
            }
        }, "mouvi-vless-watch").apply { isDaemon = true }.start()
    }

    private fun waitForSocksPort() {
        val deadline = System.currentTimeMillis() + STARTUP_TIMEOUT_MS
        while (System.currentTimeMillis() < deadline) {
            if (!processAlive(xrayProcess)) {
                throw IllegalStateException("Xray process exited during startup")
            }
            try {
                Socket().use { socket ->
                    socket.connect(InetSocketAddress("127.0.0.1", XrayConfigBuilder.SOCKS_PORT), 200)
                    return
                }
            } catch (_: Throwable) {
                Thread.sleep(100)
            }
        }
        throw IllegalStateException("Xray SOCKS port did not open in time")
    }

    private fun startVpnService(request: VpnConnectRequest, profile: VlessProfile) {
        val dns = request.dnsServers.ifEmpty { DEFAULT_DNS_LIST }.joinToString(",")
        val intent = Intent(appContext, MouviVpnService::class.java)
            .putExtra(MouviVpnService.EXTRA_SOCKS_PORT, XrayConfigBuilder.SOCKS_PORT)
            .putExtra(MouviVpnService.EXTRA_DNS, dns)
            .putExtra(MouviVpnService.EXTRA_EXCLUDED, request.excludedApplications.toTypedArray())
            .putExtra(MouviVpnService.EXTRA_INCLUDED, request.includedApplications.toTypedArray())
            .putExtra(MouviVpnService.EXTRA_NAME, request.name.ifBlank { profile.name })
            .putExtra(MouviVpnService.EXTRA_PROTOCOL, "VLESS")
            .putExtra(MouviVpnService.EXTRA_CONFIG_ID, request.configId)
        MouviVpnService.start(appContext, intent)
    }

    private fun waitForService() {
        val deadline = System.currentTimeMillis() + STARTUP_TIMEOUT_MS
        while (System.currentTimeMillis() < deadline && !serviceUp) {
            Thread.sleep(100)
        }
        if (!serviceUp) {
            throw IllegalStateException("VpnService did not start")
        }
    }

    private fun readStats(): Stats {
        val now = System.currentTimeMillis()
        if (now - statsCachedAt < STATS_CACHE_MS) {
            return statsCache
        }
        val output = runXrayApi() ?: return statsCache
        var rx = 0L
        var tx = 0L
        var fallbackRx = 0L
        var fallbackTx = 0L
        try {
            val root = JSONObject(output)
            val stats = root.optJSONArray("stat") ?: return statsCache
            for (index in 0 until stats.length()) {
                val item = stats.optJSONObject(index) ?: continue
                val name = item.optString("name", "")
                val value = item.optString("value", "").toLongOrNull() ?: continue
                when {
                    name.contains("outbound>>${XrayConfigBuilder.PROXY_TAG}") &&
                        name.endsWith("downlink") -> rx += value
                    name.contains("outbound>>${XrayConfigBuilder.PROXY_TAG}") &&
                        name.endsWith("uplink") -> tx += value
                    name.contains("inbound>>${XrayConfigBuilder.SOCKS_TAG}") &&
                        name.endsWith("downlink") -> fallbackRx += value
                    name.contains("inbound>>${XrayConfigBuilder.SOCKS_TAG}") &&
                        name.endsWith("uplink") -> fallbackTx += value
                }
            }
        } catch (_: Throwable) {
            return statsCache
        }
        val resolved = Stats(
            rx = if (rx > 0) rx else fallbackRx,
            tx = if (tx > 0) tx else fallbackTx,
        )
        statsCache = resolved
        statsCachedAt = now
        return resolved
    }

    private fun runXrayApi(): String? {
        if (!xrayBinary.exists() || !processAlive(xrayProcess)) {
            return null
        }
        return try {
            val process = ProcessBuilder(
                listOf(
                    xrayBinary.absolutePath,
                    "api",
                    "statsquery",
                    "-server",
                    "127.0.0.1:${XrayConfigBuilder.API_PORT}",
                ),
            )
                .redirectErrorStream(true)
                .start()
            val output = process.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
            if (!process.waitFor(API_TIMEOUT_MS, TimeUnit.MILLISECONDS)) {
                process.destroyForcibly()
                null
            } else if (process.exitValue() == 0) {
                output
            } else {
                null
            }
        } catch (_: Throwable) {
            null
        }
    }

    private fun cleanup() {
        MouviVpnService.stop(appContext)
        val process = synchronized(this) {
            val current = xrayProcess
            xrayProcess = null
            current
        }
        process?.destroy()
        serviceUp = false
        mainHandler.post {
            synchronized(this) { stateListener }?.invoke(false)
        }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count <= 0) {
                    break
                }
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun processAlive(process: Process?): Boolean {
        if (process == null) {
            return false
        }
        return try {
            process.exitValue()
            false
        } catch (_: IllegalThreadStateException) {
            true
        }
    }

    private data class NativeBinary(
        val assetName: String,
        val target: File,
    )

    private data class Stats(val rx: Long, val tx: Long)

    companion object {
        const val TUNNEL_NAME = "mouvi-vless"
        private const val BINARY_XRAY = "xray"
        private val DEFAULT_DNS_LIST = listOf("1.1.1.1", "1.0.0.1")
        private const val STARTUP_TIMEOUT_MS = 10_000L
        private const val STATS_CACHE_MS = 1_000L
        private const val API_TIMEOUT_MS = 2_000L

        @Volatile
        private var instance: VlessEngine? = null

        fun get(context: Context): VlessEngine = instance ?: synchronized(this) {
            instance ?: VlessEngine(context).also { instance = it }
        }
    }
}
