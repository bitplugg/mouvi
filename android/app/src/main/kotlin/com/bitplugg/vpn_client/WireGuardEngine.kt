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
                val runtimeConfig = RuntimeConfigAugmenter.augment(
                    content = request.content,
                    dnsProtection = request.dnsProtection,
                    excludedApplications = request.excludedApplications,
                    includedApplications = request.includedApplications,
                    applyWarpDefaults = true,
                )
                val config = Config.parse(
                    ByteArrayInputStream(runtimeConfig.toByteArray(Charsets.UTF_8)),
                )
                when (val state = requireBackend().setState(tunnel, Tunnel.State.UP, config)) {
                    Tunnel.State.UP -> VpnResult.Success(TUNNEL_NAME)
                    else -> VpnResult.Failure("tunnel_start_failed", "Tunnel state: $state")
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
        val statistics = if (isUp && activeBackend != null) {
            statisticsMap(activeBackend)
        } else {
            emptyStatisticsMap()
        }
        return mapOf(
            "status" to if (isUp) "up" else "down",
            "tunnelName" to TUNNEL_NAME,
            "alwaysOn" to alwaysOn,
            "lockdown" to lockdown,
        ) + statistics
    }

    /**
     * Трафик и время последнего рукопожатия.
     *
     * Если бэкенд ещё не отдал статистику, возвращаем нули: UI покажет
     * «нет данных», а не выдуманные значения.
     */
    private fun statisticsMap(activeBackend: GoBackend): Map<String, Any?> {
        return try {
            val stats = activeBackend.getStatistics(tunnel)
            var lastHandshake = 0L
            for (key in stats.peers()) {
                val peer = stats.peer(key) ?: continue
                lastHandshake = maxOf(
                    lastHandshake,
                    peer.latestHandshakeEpochMillis(),
                )
            }
            mapOf(
                "rxBytes" to stats.totalRx(),
                "txBytes" to stats.totalTx(),
                "lastHandshakeMs" to lastHandshake,
            )
        } catch (_: Throwable) {
            emptyStatisticsMap()
        }
    }

    private fun emptyStatisticsMap(): Map<String, Any?> = mapOf(
        "rxBytes" to 0L,
        "txBytes" to 0L,
        "lastHandshakeMs" to 0L,
    )

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

    companion object {
        const val TUNNEL_NAME = "mouvi"

        @Volatile
        private var instance: WireGuardEngine? = null

        fun get(context: Context): WireGuardEngine {
            return instance ?: synchronized(this) {
                instance ?: WireGuardEngine(context).also { instance = it }
            }
        }
    }
}
