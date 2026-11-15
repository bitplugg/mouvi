package com.bitplugg.vpn_client

import android.content.Context

/**
 * Фабрика VPN-движков по протоколу.
 *
 * Возвращает null для неподдерживаемых протоколов — вызывающая сторона
 * сама сформирует VpnResult.Failure("unsupported_protocol", ...).
 * Добавить новый протокол можно одной строкой в when.
 */
object ProtocolEngineFactory {
    fun forProtocol(protocol: String, context: Context): ProtocolEngine? = when (protocol) {
        "wireguard" -> WireGuardEngine.get(context)
        // amneziawg, vless, trojan, shadowsocks, openvpn — пока не реализованы
        else -> null
    }
}