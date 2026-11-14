package com.bitplugg.vpn_client

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var vpnChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        vpnChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "mouvi/vpn",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "connect" -> result.success(true)
                    "disconnect" -> result.success(true)
                    "setKillSwitch" -> result.success(true)
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
