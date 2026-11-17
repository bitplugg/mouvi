package com.bitplugg.vpn_client

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Действие «Отключить» из уведомления.
 *
 * Туннель живёт в процессе приложения, поэтому отключение возможно без
 * запуска Activity. Состояние в UI обновится через `mouvi/vpn_events`,
 * если Flutter-часть ещё жива.
 */
class MouviActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_DISCONNECT) {
            return
        }
        val appContext = context.applicationContext
        val pendingResult = goAsync()
        EngineControl.disconnectAll(appContext) { failure ->
            if (failure == null) {
                MouviNotifications(appContext).notifyConnection(
                    type = "disconnected",
                    serverName = null,
                    protocol = null,
                )
            }
            pendingResult.finish()
        }
    }

    companion object {
        const val ACTION_DISCONNECT = "com.bitplugg.vpn_client.action.DISCONNECT"
    }
}
