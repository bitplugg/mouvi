package com.bitplugg.vpn_client

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var vpnChannel: MethodChannel? = null
    private val vpnEngine: MouviVpnEngine by lazy { MouviVpnEngine(this) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        vpnChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "mouvi/vpn",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "connect" -> {
                        val configJson = call.argument<String>("config")
                        val connected = configJson != null && vpnEngine.connect(configJson)
                        result.success(connected)
                    }

                    "disconnect" -> result.success(vpnEngine.disconnect())

                    "setKillSwitch" -> {
                        vpnEngine.setKillSwitch(call.argument<Boolean>("enabled") ?: true)
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onDestroy() {
        vpnChannel?.setMethodCallHandler(null)
        super.onDestroy()
    }
}
