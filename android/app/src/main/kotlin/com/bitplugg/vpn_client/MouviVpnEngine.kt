package com.bitplugg.vpn_client

import android.content.Context
import com.wireguard.android.backend.GoBackend
import com.wireguard.android.backend.Tunnel
import com.wireguard.config.Config
import java.io.ByteArrayInputStream
import java.util.UUID

/**
 * Native VPN engine for Mouvi.
 *
 * Uses the WireGuard Android library backend (GoBackend — userspace BoringWrapper based
 * WireGuard implementation) to bring up and tear down WireGuard tunnels from a
 * wg-quick style configuration string.
 */
class MouviVpnEngine(private val context: Context) {

    private var backend: GoBackend? = null
    private var tunnel: Tunnel? = null
    private var tunnelName: String = DEFAULT_TUNNEL_NAME

    fun connect(configJson: String): Boolean = try {
        val name = tunnelName.ifBlank { "mouvi-${UUID.randomUUID().toString().substring(0, 8)}" }
        val newTunnel = object : Tunnel {
            override fun getName(): String = name

            override fun onStateChange(newState: Tunnel.State) {
                // Tunnel state callback; UI state updates can be added here later.
            }
        }
        val config = Config.parse(ByteArrayInputStream(configJson.toByteArray(Charsets.UTF_8)))
        val newBackend = GoBackend(context)
        newBackend.setState(newTunnel, Tunnel.State.UP, config)
        backend = newBackend
        tunnel = newTunnel
        tunnelName = name
        true
    } catch (e: Exception) {
        false
    }

    fun disconnect(): Boolean {
        val currentBackend = backend ?: return true
        val currentTunnel = tunnel ?: return true
        currentBackend.setState(currentTunnel, Tunnel.State.DOWN, null)
        backend = null
        tunnel = null
        return true
    }

    fun setKillSwitch(enabled: Boolean) {
        // The kill switch is expressed through the tunnel configuration (WireGuard allowed IPs
        // and allowed applications). When split tunneling gets its own configuration UI, the
        // tunnel can be re-established with restricted allowed applications.
        if (!enabled) {
            // TODO: re-establish tunnel with split tunneling (allowed applications) config.
        }
    }

    companion object {
        const val DEFAULT_TUNNEL_NAME = "mouvi"
    }
}
