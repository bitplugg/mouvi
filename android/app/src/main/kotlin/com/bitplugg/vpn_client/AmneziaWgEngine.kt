package com.bitplugg.vpn_client

import android.content.Context
import android.os.Handler
import android.os.Looper
import org.amnezia.awg.backend.GoBackend
import org.amnezia.awg.backend.NoopTunnelActionHandler
import org.amnezia.awg.backend.Tunnel
import org.amnezia.awg.config.Config
import org.amnezia.awg.config.BadConfigException
import java.io.ByteArrayInputStream
import java.util.concurrent.Executors

/**
 * AmneziaWG-реализация [ProtocolEngine].
 *
 * Использует org.amnezia.awg.backend.GoBackend — нативный бэкенд AmneziaWG,
 * аналогичный com.wireguard.android.backend.GoBackend.
 *
 * Процессный синглтон важен: GoBackend хранит текущий туннель в памяти и
 * сравнивает объекты Tunnel по ссылке. После пересоздания Activity новый
 * экземпляр считал бы туннель выключенным, хотя он работает.
 */
class AmneziaWgEngine private constructor(context: Context) : ProtocolEngine {

    private val appContext: Context = context.applicationContext
    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "mouvi-amneziawg-engine").apply { isDaemon = true }
    }
    private val mainHandler = Handler(Looper.getMainLooper())

    private val tunnel: Tunnel = object : Tunnel {
        override fun getName(): String = TUNNEL_NAME

        override fun onStateChange(newState: Tunnel.State) {
            val connected = newState == Tunnel.State.UP
            mainHandler.post {
                synchronized(this@AmneziaWgEngine) { stateListener }?.invoke(connected)
            }
        }

        override fun isIpv4ResolutionPreferred(): Boolean = false

        override fun isMetered(): Boolean = false
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
                    applyWarpDefaults = false,
                )
                val config = Config.parse(
                    ByteArrayInputStream(runtimeConfig.toByteArray(Charsets.UTF_8))
                )
                when (val state = requireBackend().setState(tunnel, Tunnel.State.UP, config)) {
                    Tunnel.State.UP -> VpnResult.Success(TUNNEL_NAME)
                    else -> VpnResult.Failure("tunnel_start_failed", "Tunnel state: $state")
                }
            } catch (error: org.amnezia.awg.backend.BackendException) {
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
            } catch (error: org.amnezia.awg.backend.BackendException) {
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
        val statistics = if (isUp && activeBackend != null) {
            statisticsMap(activeBackend)
        } else {
            emptyStatisticsMap()
        }
        return mapOf(
            "status" to if (isUp) "up" else "down",
            "tunnelName" to TUNNEL_NAME,
            "alwaysOn" to false,
            "lockdown" to false,
        ) + statistics
    }

    /** Трафик и время последнего рукопожатия из нативного бэкенда. */
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
        return backend ?: GoBackend(appContext, NoopTunnelActionHandler()).also { backend = it }
    }

    private fun mapBackendError(error: org.amnezia.awg.backend.BackendException): VpnResult.Failure {
        val code = when (error.reason) {
            org.amnezia.awg.backend.BackendException.Reason.VPN_NOT_AUTHORIZED -> "vpn_permission_denied"
            org.amnezia.awg.backend.BackendException.Reason.TUNNEL_MISSING_CONFIG -> "invalid_config"
            org.amnezia.awg.backend.BackendException.Reason.DNS_RESOLUTION_FAILURE -> "tunnel_start_failed"
            else -> "tunnel_start_failed"
        }
        return VpnResult.Failure(code, error.reason.name)
    }

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
