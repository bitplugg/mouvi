package com.bitplugg.vpn_client

import android.content.Context
import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executors

/**
 * AmneziaWG-реализация [ProtocolEngine].
 *
 * Заглушка под будущую интеграцию с AmneziaWG Go-бэкендом.
 * Настоящий connect() должен использовать нативную библиотеку AmneziaWG
 * (см. build.gradle.kts — зависимость добавлена).
 *
 * Пока библиотека не подключена, connect() возвращает
 * VpnResult.Failure("unsupported_protocol", ...).
 *
 * Singleton важен: как и WireGuardEngine, должен оставаться Prozess-синглтоном,
 * чтобы состояние туннеля сохранялось после пересоздания Activity.
 */
class AmneziaWgEngine private constructor(context: Context) : ProtocolEngine {

    private val appContext: Context = context.applicationContext
    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "mouvi-amneziawg-engine").apply { isDaemon = true }
    }
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var stateListener: ((Boolean) -> Unit)? = null

    override fun setStateListener(listener: ((Boolean) -> Unit)?) {
        stateListener = listener
    }

    override fun connect(request: VpnConnectRequest, callback: (VpnResult<String>) -> Unit) {
        executor.execute {
            // TODO: подключить AmneziaWG Go backend и парсинг конфига.
            // Примерный алгоритм:
            // 1. Проверить hasAmneziaAttributes(request.content)
            // 2. Внести runtime options (ExcludedApplications, DNS)
            // 3. Создать AmneziaWG туннель через нативный бэкенд
            // 4. setState(tunnel, UP, config)
            val result = VpnResult.Failure(
                "unsupported_protocol",
                "AmneziaWG engine is not yet implemented (native backend missing)",
            )
            mainHandler.post { callback(result) }
        }
    }

    override fun disconnect(callback: (VpnResult<Unit>) -> Unit) {
        executor.execute {
            val result = VpnResult.Success(Unit)
            mainHandler.post { callback(result) }
        }
    }

    override fun getState(): Map<String, Any?> {
        return mapOf(
            "status" to "down",
            "tunnelName" to TUNNEL_NAME,
            "alwaysOn" to false,
            "lockdown" to false,
        )
    }

    override fun currentStateMap(): Map<String, Any?> = getState()

    companion object {
        const val TUNNEL_NAME = "mouvi-amneziawg"

        @Volatile
        private var instance: AmneziaWgEngine? = null

        fun get(context: Context): AmneziaWgEngine {
            return instance ?: synchronized(this) {
                instance ?: AmneziaWgEngine(context).also { instance = it }
            }
        }
    }
}
