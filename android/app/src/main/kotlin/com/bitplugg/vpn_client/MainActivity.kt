package com.bitplugg.vpn_client

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Единственная Activity приложения.
 *
 * Здесь находятся каналы Flutter ↔ Android:
 * - `mouvi/vpn` — подключение/отключение/состояние/системные настройки VPN;
 * - `mouvi/vpn_events` — события состояния туннеля;
 * - `mouvi/storage` — шифрованное хранилище конфигов;
 * - `mouvi/apps` — список приложений для split tunneling;
 * - `mouvi/push` — локальные уведомления.
 *
 * Разрешение VPN (VpnService.prepare) запрашивается через классический
 * startActivityForResult: FlutterActivity не наследует ComponentActivity,
 * поэтому ActivityResultRegistry здесь недоступен.
 */
class MainActivity : FlutterActivity() {

    private var vpnChannel: MethodChannel? = null
    private var storageChannel: MethodChannel? = null
    private var appsChannel: MethodChannel? = null
    private var pushChannel: MethodChannel? = null
    private var eventsChannel: EventChannel? = null

    private var activeEngine: ProtocolEngine? = null
    private lateinit var notifications: MouviNotifications

    private var pendingConnect: PendingConnect? = null
    private var pendingNotificationPermission: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        notifications = MouviNotifications(applicationContext)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        notifications = MouviNotifications(applicationContext)

        vpnChannel = MethodChannel(messenger, "mouvi/vpn").also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "connect" -> handleConnect(call, result)
                    "disconnect" -> handleDisconnect(result)
                    "getState" -> ioExecutor.execute {
                        val snapshot = currentSnapshot()
                        runOnUiThread { result.success(snapshot) }
                    }
                    "openVpnSettings" -> openVpnSettings(result)
                    else -> result.notImplemented()
                }
            }
        }

        storageChannel = MethodChannel(messenger, "mouvi/storage").also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "read" -> ioExecutor.execute {
                        val data = MouviSecureStorage.read(applicationContext)
                        runOnUiThread { result.success(data) }
                    }
                    "write" -> {
                        val data = call.argument<String>("data")
                        if (data == null) {
                            result.error("invalid_data", "Data is null", null)
                        } else {
                            val ok = MouviSecureStorage.write(applicationContext, data)
                            runOnUiThread { result.success(ok) }
                        }
                    }
                    "clear" -> ioExecutor.execute {
                        val ok = MouviSecureStorage.clear(applicationContext)
                        runOnUiThread { result.success(ok) }
                    }
                    else -> result.notImplemented()
                }
            }
        }

        appsChannel = MethodChannel(messenger, "mouvi/apps").also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "listApps" -> ioExecutor.execute {
                        val apps = try {
                            loadInstalledApps()
                        } catch (_: Throwable) {
                            null
                        }
                        runOnUiThread {
                            if (apps == null) {
                                result.error("apps_unavailable", "Could not read apps", null)
                            } else {
                                result.success(apps)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }

        pushChannel = MethodChannel(messenger, "mouvi/push").also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "isEnabled" -> result.success(notifications.isEnabled())
                    "requestPermission" -> requestNotificationPermission(result)
                    "setEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        notifications.setEnabled(enabled)
                        runOnUiThread { result.success(true) }
                    }
                    "notify" -> {
                        notifications.notifyConnection(
                            type = call.argument<String>("type") ?: "",
                            serverName = call.argument<String>("serverName"),
                            protocol = call.argument<String>("protocol"),
                            titleOverride = call.argument<String>("title"),
                            textOverride = call.argument<String>("text"),
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        eventsChannel = EventChannel(messenger, "mouvi/vpn_events").also { channel ->
            channel.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    // Слушаем оба движка: после пересоздания Activity заранее
                    // неизвестно, какой протокол сейчас подключён.
                    allEngines().forEach { engine ->
                        engine.setStateListener {
                            ioExecutor.execute {
                                val snapshot = currentSnapshot()
                                runOnUiThread { events?.success(snapshot) }
                            }
                        }
                    }
                    // Начальный снимок читаем вне UI-потока: GoBackend.getState
                    // может ждать привязки VpnService.
                    ioExecutor.execute {
                        val snapshot = currentSnapshot()
                        runOnUiThread { events?.success(snapshot) }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    allEngines().forEach { it.setStateListener(null) }
                }
            })
        }
    }

    private fun defaultStateMap(): Map<String, Any?> {
        return mapOf(
            "status" to "down",
            "tunnelName" to WireGuardEngine.TUNNEL_NAME,
            "alwaysOn" to false,
            "lockdown" to false,
        )
    }

    private fun allEngines(): List<ProtocolEngine> = listOf(
        WireGuardEngine.get(applicationContext),
        AmneziaWgEngine.get(applicationContext),
    )

    /**
     * Реальное состояние любого движка.
     *
     * После пересоздания Activity `activeEngine` пуст, поэтому состояние
     * нельзя хранить только в поле Activity — иначе UI покажет «отключено»
     * при работающем туннеле и не сможет его закрыть.
     */
    private fun currentSnapshot(): Map<String, Any?> {
        for (engine in allEngines()) {
            val snapshot = engine.getState()
            if (snapshot["status"] == "up") {
                return snapshot
            }
        }
        return defaultStateMap()
    }

    /** Опускает оба движка: активным может быть любой из них. */
    private fun disconnectAllEngines(onComplete: (VpnResult.Failure?) -> Unit) {
        val engines = allEngines()
        var firstFailure: VpnResult.Failure? = null

        fun step(index: Int) {
            if (index >= engines.size) {
                onComplete(firstFailure)
                return
            }
            engines[index].disconnect { outcome ->
                if (outcome is VpnResult.Failure && firstFailure == null) {
                    firstFailure = outcome
                }
                step(index + 1)
            }
        }
        step(0)
    }

    private fun handleConnect(call: MethodCall, result: MethodChannel.Result) {
        if (pendingConnect != null) {
            result.error("busy", "Another connection request is in progress", null)
            return
        }
        val content = call.argument<String>("content")
        val protocol = call.argument<String>("protocol") ?: ""

        // Выбор движка через фабрику: неподдерживаемые протоколы отвергаются здесь.
        val engine = ProtocolEngineFactory.forProtocol(protocol, applicationContext)
        if (engine == null) {
            result.error("unsupported_protocol", "Protocol $protocol is not supported", null)
            return
        }

        if (content.isNullOrBlank()) {
            result.error("invalid_config", "Empty configuration", null)
            return
        }
        val request = VpnConnectRequest(
            configId = call.argument<String>("id") ?: "",
            name = call.argument<String>("name") ?: "",
            protocol = protocol,
            content = content,
            excludedApplications = call.argument<List<*>>("excludedApplications")
                ?.mapNotNull { it as? String }
                ?: emptyList(),
            dnsProtection = call.argument<Boolean>("dnsProtection") ?: true,
        )
        val prepareIntent = try {
            VpnService.prepare(this)
        } catch (error: Throwable) {
            result.error("vpn_permission_denied", error.message ?: "VpnService.prepare failed", null)
            return
        }
        activeEngine = engine
        if (prepareIntent != null) {
            pendingConnect = PendingConnect(request, result)
            try {
                startActivityForResult(prepareIntent, REQUEST_VPN_PERMISSION)
            } catch (error: Throwable) {
                pendingConnect = null
                activeEngine = null
                result.error("vpn_permission_denied", error.message ?: "Could not request VPN permission", null)
            }
        } else {
            startConnect(request, result)
        }
    }

    private fun startConnect(request: VpnConnectRequest, result: MethodChannel.Result) {
        val engine = activeEngine
        if (engine == null) {
            result.error("unsupported_protocol", "No VPN engine selected", null)
            return
        }
        // Android разрешает только один активный VPN. Если туннель уже
        // поднят (например, после пересоздания Activity), сначала опускаем
        // его, иначе новый движок не сможет занять VpnService.
        disconnectAllEngines {
            engine.connect(request) { outcome ->
                when (outcome) {
                    is VpnResult.Success -> result.success(outcome.value)
                    is VpnResult.Failure -> result.error(outcome.code, outcome.message, null)
                }
            }
        }
    }

    private fun handleDisconnect(result: MethodChannel.Result) {
        disconnectAllEngines { failure ->
            activeEngine = null
            if (failure == null) {
                result.success(null)
            } else {
                result.error(failure.code, failure.message, null)
            }
        }
    }

    private fun openVpnSettings(result: MethodChannel.Result) {
        try {
            startActivity(Intent(Settings.ACTION_VPN_SETTINGS))
            result.success(null)
        } catch (_: Throwable) {
            try {
                startActivity(Intent(Settings.ACTION_SETTINGS))
                result.success(null)
            } catch (error: Throwable) {
                result.error("native_unavailable", error.message ?: "No settings activity", null)
            }
        }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        if (pendingNotificationPermission != null) {
            result.success(false)
            return
        }
        pendingNotificationPermission = result
        try {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
        } catch (_: Throwable) {
            pendingNotificationPermission = null
            result.success(false)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_VPN_PERMISSION) {
            return
        }
        val pending = pendingConnect
        pendingConnect = null
        if (pending == null) {
            return
        }
        if (resultCode == Activity.RESULT_OK) {
            startConnect(pending.request, pending.result)
        } else {
            pending.result.error("vpn_permission_denied", "VPN permission was not granted", null)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_NOTIFICATIONS) {
            return
        }
        val result = pendingNotificationPermission
        pendingNotificationPermission = null
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        result?.success(granted)
    }


    private fun loadInstalledApps(): List<Map<String, String>> {
        val manager = packageManager
        val intent = Intent(Intent.ACTION_MAIN, null).addCategory(Intent.CATEGORY_LAUNCHER)
        @Suppress("DEPRECATION")
        val resolved = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            manager.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(0))
        } else {
            manager.queryIntentActivities(intent, 0)
        }
        val seen = HashSet<String>()
        val apps = ArrayList<Map<String, String>>()
        for (info in resolved) {
            val packageName = info.activityInfo?.packageName ?: continue
            if (packageName == this.packageName || !seen.add(packageName)) {
                continue
            }
            val label = try {
                info.loadLabel(manager).toString()
            } catch (_: Throwable) {
                packageName
            }
            apps.add(mapOf("package" to packageName, "label" to label))
        }
        apps.sortBy { it["label"]?.lowercase() ?: "" }
        return apps
    }

    override fun onDestroy() {
        pendingConnect?.result?.error("native_unavailable", "Activity destroyed before connect", null)
        pendingConnect = null
        pendingNotificationPermission?.success(false)
        pendingNotificationPermission = null
        allEngines().forEach { it.setStateListener(null) }
        vpnChannel?.setMethodCallHandler(null)
        storageChannel?.setMethodCallHandler(null)
        appsChannel?.setMethodCallHandler(null)
        pushChannel?.setMethodCallHandler(null)
        eventsChannel?.setStreamHandler(null)
        vpnChannel = null
        storageChannel = null
        appsChannel = null
        pushChannel = null
        eventsChannel = null
        super.onDestroy()
    }

    private data class PendingConnect(
        val request: VpnConnectRequest,
        val result: MethodChannel.Result,
    )

    companion object {
        private const val REQUEST_VPN_PERMISSION = 4101
        private const val REQUEST_NOTIFICATIONS = 4102

        private val ioExecutor = Executors.newCachedThreadPool { runnable ->
            Thread(runnable, "mouvi-io").apply { isDaemon = true }
        }
    }
}
