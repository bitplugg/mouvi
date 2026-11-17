package com.bitplugg.vpn_client

import android.app.PendingIntent
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import java.util.concurrent.Executors

/**
 * Плитка Quick Settings: показывает состояние туннеля и позволяет
 * отключиться одним тапом. Если туннель опущен, открывает приложение,
 * где Flutter сам подключит последний выбранный конфиг (единая логика
 * валидации и WARP-дефолтов остаётся в Dart).
 */
class MouviTileService : TileService() {

    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "mouvi-tile").apply { isDaemon = true }
    }
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onStartListening() {
        super.onStartListening()
        refresh()
    }

    override fun onClick() {
        super.onClick()
        executor.execute {
            val isUp = EngineControl.snapshot(this)["status"] == "up"
            if (isUp) {
                EngineControl.disconnectAll(this) {
                    mainHandler.post { refresh() }
                }
            } else {
                openAppForConnect()
            }
        }
    }

    private fun refresh() {
        executor.execute {
            val isUp = EngineControl.snapshot(this)["status"] == "up"
            mainHandler.post {
                val tile = qsTile ?: return@post
                tile.state = if (isUp) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
                tile.label = getString(R.string.app_name)
                tile.icon = Icon.createWithResource(this, R.drawable.ic_stat_mouvi)
                tile.updateTile()
            }
        }
    }

    private fun openAppForConnect() {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(MainActivity.EXTRA_QUICK_TOGGLE, true)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pendingIntent = PendingIntent.getActivity(
                this,
                2,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            startActivityAndCollapse(pendingIntent)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }

    override fun onDestroy() {
        executor.shutdown()
        super.onDestroy()
    }
}
