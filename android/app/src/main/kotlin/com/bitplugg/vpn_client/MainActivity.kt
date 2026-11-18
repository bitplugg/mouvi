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
    private var exportChannel: MethodChannel? = null
    private var eventsChannel: EventChannel? = null
    private var actionsChannel: EventChannel? = null
    private var actionsSink: EventChannel.EventSink? = null

    private var activeEngine: ProtocolEngine? = null
    private lateinit var notifications: MouviNotifications

    private var pendingConnect: PendingConnect? = null
    private var pendingNotificationPermission: MethodChannel.Result? = null
    private var pendingExport: PendingExport? = null
    private var pendingLaunchAction: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        notifications = MouviNotifications(applicationContext)
        pendingLaunchAction = readLaunchAction(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val action = readLaunchAction(intent)
        if (action != null) {
            deliverLaunchAction(action)
        }
    }

    /**
     * Передаёт действие в Dart, если канал уже слушают.
     *
     * Иначе сохраняет его до подписки: Activity создаётся раньше, чем
     * Flutter успевает подключить EventChannel.
     */
    private fun deliverLaunchAction(action: String) {
        val sink = actionsSink
        if (sink != null) {
            pendingLaunchAction = null
            sink.success(action)
        } else {
            pendingLaunchAction = action
        }
    }

    private fun readLaunchAction(intent: Intent?): String? {
        return if (intent?.getBooleanExtra(EXTRA_QUICK_TOGGLE, false) == true) {
            "toggle"
        } else {
            null
        }
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
                        val snapshot = EngineControl.snapshot(applicationContext)
                        runOnUiThread { result.success(snapshot) }
                    }
                    "getLaunchAction" -> {
                        val action = pendingLaunchAction
                        pendingLaunchAction = null
                        result.success(action)
                    }
                    "hasVpnPermission" -> result.success(VpnService.prepare(this) == null)
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
                            disconnectActionOverride =
                                call.argument<String>("disconnectAction"),
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        exportChannel = MethodChannel(messenger, "mouvi/export").also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveConfig" -> saveConfigToFile(call, result)
                    else -> result.notImplemented()
                }
            }
        }

        eventsChannel = EventChannel(messenger, "mouvi/vpn_events").also { channel ->
            channel.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    // Слушаем оба движка: после пересоздания Activity заранее
                    // неизвестно, какой протокол сейчас подключён.
                    EngineControl.allEngines(applicationContext).forEach { engine ->
                        engine.setStateListener {
                            ioExecutor.execute {
                                val snapshot = EngineControl.snapshot(applicationContext)
                                runOnUiThread { events?.success(snapshot) }
                            }
                        }
                    }
                    // Начальный снимок читаем вне UI-потока: GoBackend.getState
                    // может ждать привязки VpnService.
                    ioExecutor.execute {
                        val snapshot = EngineControl.snapshot(applicationContext)
                        runOnUiThread { events?.success(snapshot) }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    EngineControl.allEngines(applicationContext)
                        .forEach { it.setStateListener(null) }
                }
            })
        }

        actionsChannel = EventChannel(messenger, "mouvi/actions").also { channel ->
            channel.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    actionsSink = events
                    val pending = pendingLaunchAction
                    if (pending != null) {
                        pendingLaunchAction = null
                        events?.success(pending)
                    }
                }

                override fun onCancel(arguments: Any?) {
                    actionsSink = null
                }
            })
        }
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
        val dnsServers = call.argument<List<*>>("dnsServers")
            ?.mapNotNull { it as? String }
            ?: if (call.argument<Boolean>("dnsProtection") != false) {
                listOf("1.1.1.1", "1.0.0.1")
            } else {
                emptyList()
            }
        val request = VpnConnectRequest(
            configId = call.argument<String>("id") ?: "",
            name = call.argument<String>("name") ?: "",
            protocol = protocol,
            content = content,
            excludedApplications = call.argument<List<*>>("excludedApplications")
                ?.mapNotNull { it as? String }
                ?: emptyList(),
            includedApplications = call.argument<List<*>>("includedApplications")
                ?.mapNotNull { it as? String }
                ?: emptyList(),
            dnsServers = dnsServers,
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
        EngineControl.disconnectAll(applicationContext) {
            engine.connect(request) { outcome ->
                when (outcome) {
                    is VpnResult.Success -> result.success(outcome.value)
                    is VpnResult.Failure -> result.error(outcome.code, outcome.message, null)
                }
            }
        }
    }

    private fun handleDisconnect(result: MethodChannel.Result) {
        EngineControl.disconnectAll(applicationContext) { failure ->
            activeEngine = null
            if (failure == null) {
                result.success(null)
            } else {
                result.error(failure.code, failure.message, null)
            }
        }
    }

    private fun saveConfigToFile(call: MethodCall, result: MethodChannel.Result) {
        if (pendingExport != null) {
            result.error("busy", "Another export is already in progress", null)
            return
        }
        val content = call.argument<String>("content")
        if (content.isNullOrEmpty()) {
            result.error("invalid_data", "Config content is empty", null)
            return
        }
        val rawName = call.argument<String>("fileName") ?: "mouvi.conf"
        val fileName = rawName.replace(Regex("[^A-Za-z0-9._-]"), "_").ifBlank { "mouvi.conf" }
        // text/plain заставляет DocumentsUI дописывать .txt, поэтому для
        // профилей используем octet-stream, а JSON — application/json.
        val mimeType = when {
            fileName.endsWith(".json", ignoreCase = true) -> "application/json"
            fileName.endsWith(".conf", ignoreCase = true) -> "application/octet-stream"
            fileName.endsWith(".ovpn", ignoreCase = true) -> "application/octet-stream"
            else -> "text/plain"
        }
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeType
            putExtra(Intent.EXTRA_TITLE, fileName)
        }
        pendingExport = PendingExport(result, content)
        try {
            startActivityForResult(intent, REQUEST_EXPORT)
        } catch (error: Throwable) {
            pendingExport = null
            result.error("native_unavailable", error.message ?: "No document picker", null)
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
        if (requestCode == REQUEST_EXPORT) {
            val pending = pendingExport
            pendingExport = null
            if (pending == null) {
                return
            }
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null) {
                pending.result.success(false)
                return
            }
            ioExecutor.execute {
                val saved = try {
                    contentResolver.openOutputStream(uri)?.use { stream ->
                        stream.write(pending.content.toByteArray(Charsets.UTF_8))
                    } != null
                } catch (_: Throwable) {
                    false
                }
                runOnUiThread {
                    if (saved) {
                        pending.result.success(true)
                    } else {
                        pending.result.error("export_failed", "Could not write the file", null)
                    }
                }
            }
            return
        }
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
        pendingExport?.result?.error("native_unavailable", "Activity destroyed before export", null)
        pendingExport = null
        EngineControl.allEngines(applicationContext).forEach { it.setStateListener(null) }
        vpnChannel?.setMethodCallHandler(null)
        storageChannel?.setMethodCallHandler(null)
        appsChannel?.setMethodCallHandler(null)
        pushChannel?.setMethodCallHandler(null)
        exportChannel?.setMethodCallHandler(null)
        eventsChannel?.setStreamHandler(null)
        actionsChannel?.setStreamHandler(null)
        vpnChannel = null
        storageChannel = null
        appsChannel = null
        pushChannel = null
        exportChannel = null
        eventsChannel = null
        actionsChannel = null
        actionsSink = null
        super.onDestroy()
    }

    private data class PendingConnect(
        val request: VpnConnectRequest,
        val result: MethodChannel.Result,
    )

    private data class PendingExport(
        val result: MethodChannel.Result,
        val content: String,
    )

    companion object {
        const val EXTRA_QUICK_TOGGLE = "com.bitplugg.vpn_client.extra.QUICK_TOGGLE"

        private const val REQUEST_VPN_PERMISSION = 4101
        private const val REQUEST_NOTIFICATIONS = 4102
        private const val REQUEST_EXPORT = 4103

        private val ioExecutor = Executors.newCachedThreadPool { runnable ->
            Thread(runnable, "mouvi-io").apply { isDaemon = true }
        }
    }
}
