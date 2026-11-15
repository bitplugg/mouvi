package com.bitplugg.vpn_client

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.wireguard.android.backend.BackendException
import com.wireguard.android.backend.GoBackend
import com.wireguard.android.backend.Tunnel
import com.wireguard.config.BadConfigException
import com.wireguard.config.Config
import java.io.ByteArrayInputStream
import java.util.concurrent.Executors

/**
 * WireGuard-реализация [ProtocolEngine].
 *
 * Единственный на процесс экземпляр. Singleton важен: GoBackend хранит текущий туннель
 * в памяти и сравнивает объекты Tunnel по ссылке. После пересоздания Activity новый
 * экземпляр считал бы туннель выключенным, хотя он работает. Процессный синглтон
 * позволяет корректно восстанавливать состояние в UI.
 */
class WireGuardEngine private constructor(context: Context) : ProtocolEngine {

    private val appContext: Context = context.applicationContext
    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "mouvi-vpn-engine").apply { isDaemon = true }
    }
    private val mainHandler = Handler(Looper.getMainLooper())

    private val tunnel: Tunnel = object : Tunnel {
        override fun getName(): String = TUNNEL_NAME

        override fun onStateChange(newState: Tunnel.State) {
            val connected = newState == Tunnel.State.UP
            mainHandler.post {
                synchronized(this@WireGuardEngine) { stateListener }?.invoke(connected)
            }
        }
    }

    @Volatile
    private var stateListener: ((Boolean) -> Unit)? = null

    @Volatile
    private var backend: GoBackend? = null

    override fun setStateListener(listener: ((Boolean) -> Unit)?) {
        stateListener = listener
    }

    override fun connect(request: VpnConnectRequest, callback: (VpnResult<String>) -> Unit) {
        executor.execute {
            val result = try {
                when {
                    hasAmneziaAttributes(request.content) -> VpnResult.Failure(
                        "unsupported_protocol",
                        "AmneziaWG parameters are not supported by the WireGuard engine",
                    )
                    else -> {
                        val runtimeConfig = injectRuntimeOptions(request)
                        val config = Config.parse(
                            ByteArrayInputStream(runtimeConfig.toByteArray(Charsets.UTF_8)),
                        )
                        when (val state = requireBackend().setState(tunnel, Tunnel.State.UP, config)) {
                            Tunnel.State.UP -> VpnResult.Success(TUNNEL_NAME)
                            else -> VpnResult.Failure("tunnel_start_failed", "Tunnel state: $state")
                        }
                    }
                }
            } catch (error: BackendException) {
                mapBackendError(error)
            } catch (error: BadConfigException) {
                VpnResult.Failure("invalid_config", error.message)
            } catch (error: Throwable) {
                VpnResult.Failure("tunnel_start_failed", error.message ?: error.javaClass.simpleName)
            }
            mainHandler.post { callback(result) }
        }
    }

    override fun disconnect(callback: (VpnResult<Unit>) -> Unit) {
        executor.execute {
            val result = try {
                val activeBackend = backend
                if (activeBackend == null || TUNNEL_NAME !in activeBackend.getRunningTunnelNames()) {
                    VpnResult.Success(Unit)
                } else {
                    activeBackend.setState(tunnel, Tunnel.State.DOWN, null)
                    VpnResult.Success(Unit)
                }
            } catch (error: BackendException) {
                mapBackendError(error)
            } catch (error: Throwable) {
                VpnResult.Failure("tunnel_start_failed", error.message ?: error.javaClass.simpleName)
            }
            mainHandler.post { callback(result) }
        }
    }

    /** Синхронный снимок состояния. Используется для восстановления UI. */
    override fun getState(): Map<String, Any?> {
        val activeBackend = try {
            requireBackend()
        } catch (_: Throwable) {
            null
        }
        val isUp = try {
            activeBackend != null && activeBackend.getState(tunnel) == Tunnel.State.UP
        } catch (_: Throwable) {
            false
        }
        val alwaysOn = try {
            activeBackend?.isAlwaysOn == true
        } catch (_: Throwable) {
            false
        }
        val lockdown = try {
            activeBackend?.isLockdownEnabled == true
        } catch (_: Throwable) {
            false
        }
        return mapOf(
            "status" to if (isUp) "up" else "down",
            "tunnelName" to TUNNEL_NAME,
            "alwaysOn" to alwaysOn,
            "lockdown" to lockdown,
        )
    }

    override fun currentStateMap(): Map<String, Any?> = getState()

    @Synchronized
    private fun requireBackend(): GoBackend {
        return backend ?: GoBackend(appContext).also { backend = it }
    }
    private fun mapBackendError(error: BackendException): VpnResult.Failure {
        val code = when (error.reason) {
            BackendException.Reason.VPN_NOT_AUTHORIZED -> "vpn_permission_denied"
            BackendException.Reason.TUNNEL_MISSING_CONFIG -> "invalid_config"
            BackendException.Reason.DNS_RESOLUTION_FAILURE -> "tunnel_start_failed"
            else -> "tunnel_start_failed"
        }
        return VpnResult.Failure(code, error.reason.name)
    }

    /**
     * Добавляет к конфигу параметры, выбранные в приложении:
     * исключённые приложения (реальный split tunneling) и защищённый DNS,
     * если в конфиге DNS не задан.
     */
    private fun injectRuntimeOptions(request: VpnConnectRequest): String {
        val lines = request.content.trim().removePrefix("\uFEFF").lines().toMutableList()
        val interfaceStart = lines.indexOfFirst { it.trim().equals("[Interface]", ignoreCase = true) }
        if (interfaceStart < 0) {
            // Config.parse ниже вернёт понятную ошибку.
            return request.content
        }
        var interfaceEnd = lines.size
        var dnsLineIndex = -1
        var hasDnsValue = false
        var excludedLineIndex = -1
        val existingExcluded = LinkedHashSet<String>()
        for (index in interfaceStart + 1 until lines.size) {
            val line = lines[index].trim()
            if (line.startsWith("[") && line.endsWith("]")) {
                interfaceEnd = index
                break
            }
            val key = line.substringBefore('=').trim().lowercase()
            val value = line.substringAfter('=').trim()
            when {
                key.equals("dns", ignoreCase = true) -> {
                    dnsLineIndex = index
                    if (value.isNotEmpty()) {
                        hasDnsValue = true
                    }
                }
                key.equals("excludedapplications", ignoreCase = true) -> {
                    excludedLineIndex = index
                    value.split(',')
                        .map { it.trim() }
                        .filter { it.isNotEmpty() }
                        .forEach { existingExcluded.add(it) }
                }
            }
        }
        val additions = mutableListOf<String>()
        if (request.dnsProtection && !hasDnsValue) {
            // Если в конфиге есть пустой DNS =, заменяем строку, а не
            // добавляем вторую (WireGuard не допускает дубликаты ключей).
            val dnsLine = "DNS = 1.1.1.1, 1.0.0.1"
            if (dnsLineIndex >= 0) {
                lines[dnsLineIndex] = dnsLine
            } else {
                additions.add(dnsLine)
            }
        }
        val selectedExcluded = request.excludedApplications
            .asSequence()
            .map { it.trim() }
            .filter { PACKAGE_PATTERN.matches(it) }
            .toList()
        if (selectedExcluded.isNotEmpty() || existingExcluded.isNotEmpty()) {
            val merged = LinkedHashSet<String>()
            merged.addAll(existingExcluded)
            merged.addAll(selectedExcluded)
            val excludedLine = "ExcludedApplications = ${merged.joinToString(", ")}"
            // Если приложение уже задало список, объединяем его с выбором
            // пользователя вместо создания второго ключа.
            if (excludedLineIndex >= 0) {
                lines[excludedLineIndex] = excludedLine
            } else {
                additions.add(excludedLine)
            }
        }
        if (additions.isNotEmpty()) {
            lines.addAll(interfaceEnd, additions)
        }
        return lines.joinToString("\n")
    }

    private fun hasAmneziaAttributes(content: String): Boolean {
        var inInterface = false
        for (rawLine in content.lines()) {
            val line = rawLine.trim()
            if (line.startsWith("[") && line.endsWith("]")) {
                inInterface = line.equals("[Interface]", ignoreCase = true)
                continue
            }
            if (!inInterface || !line.contains('=')) {
                continue
            }
            val key = line.substringBefore('=').trim().lowercase()
            if (key in AMNEZIA_KEYS) {
                return true
            }
        }
        return false
    }

    companion object {
        const val TUNNEL_NAME = "mouvi"

        private val PACKAGE_PATTERN = Regex("^[A-Za-z0-9_]+(\\.[A-Za-z0-9_]+)+$")

        private val AMNEZIA_KEYS = setOf(
            "jc", "jmin", "jmax", "s1", "s2", "s3", "s4",
            "h1", "h2", "h3", "h4", "i1", "i2", "i3", "i4", "i5", "j1", "j2", "j3",
        )

        @Volatile
        private var instance: WireGuardEngine? = null

        fun get(context: Context): WireGuardEngine {
            return instance ?: synchronized(this) {
                instance ?: WireGuardEngine(context).also { instance = it }
            }
        }
    }
}
