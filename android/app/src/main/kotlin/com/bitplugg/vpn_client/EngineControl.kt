package com.bitplugg.vpn_client

import android.content.Context
import android.provider.Settings

/**
 * Общие операции над обоими VPN-движками.
 *
 * После пересоздания Activity или при вызове из уведомления/quick tile
 * неизвестно, какой протокол сейчас поднят, поэтому состояние читается
 * и туннель опускается у WireGuard и AmneziaWG одновременно.
 */
object EngineControl {

    // Публичных констант для этих ключей в SDK нет, но сами ключи
    // стабильны и доступны только на чтение сторонним приложениям.
    private const val ALWAYS_ON_VPN_APP = "always_on_vpn_app"
    private const val ALWAYS_ON_VPN_LOCKDOWN = "always_on_vpn_lockdown"

    fun allEngines(context: Context): List<ProtocolEngine> = listOf(
        WireGuardEngine.get(context.applicationContext),
        AmneziaWgEngine.get(context.applicationContext),
    )

    fun defaultStateMap(): Map<String, Any?> = mapOf(
        "status" to "down",
        "tunnelName" to WireGuardEngine.TUNNEL_NAME,
        "alwaysOn" to false,
        "lockdown" to false,
        "rxBytes" to 0L,
        "txBytes" to 0L,
        "lastHandshakeMs" to 0L,
    )

    /** Реальное состояние любого движка (первый поднятый туннель). */
    fun snapshot(context: Context): Map<String, Any?> {
        for (engine in allEngines(context)) {
            val snapshot = engine.getState()
            if (snapshot["status"] == "up") {
                return withSystemLockState(context, snapshot)
            }
        }
        return withSystemLockState(context, defaultStateMap())
    }

    /**
     * Дополняет снимок состоянием Always-on/Lockdown из системных настроек.
     *
     * AmneziaWG-бэкенд не умеет отдавать эти флаги, а WireGuard может
     * возвращать `false`, пока сервис ещё не инициализирован. Читаем
     * системные настройки, чтобы карточка «Системная блокировка» не
     * показывала неверное состояние.
     */
    private fun withSystemLockState(
        context: Context,
        snapshot: Map<String, Any?>,
    ): Map<String, Any?> {
        val systemState = try {
            val resolver = context.contentResolver
            val alwaysOnPackage = Settings.Secure.getString(
                resolver,
                ALWAYS_ON_VPN_APP,
            )
            if (alwaysOnPackage == null) {
                null
            } else {
                val enabled = alwaysOnPackage == context.packageName
                val lockdown = enabled && Settings.Secure.getInt(
                    resolver,
                    ALWAYS_ON_VPN_LOCKDOWN,
                    0,
                ) != 0
                enabled to lockdown
            }
        } catch (_: Throwable) {
            null
        } ?: return snapshot
        return snapshot + mapOf(
            "alwaysOn" to systemState.first,
            "lockdown" to systemState.second,
        )
    }

    /** Опускает оба движка: активным может быть любой из них. */
    fun disconnectAll(context: Context, onComplete: (VpnResult.Failure?) -> Unit) {
        val engines = allEngines(context)
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
}
