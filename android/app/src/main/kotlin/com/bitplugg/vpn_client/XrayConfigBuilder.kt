package com.bitplugg.vpn_client

/**
 * Собирает конфиг Xray для реального VLESS-подключения.
 *
 * Наружу ВСЕГДА отдаётся только SOCKS5 на loopback: маршрутизацию и TUN
 * делает MouviVpnService + tun2socks. Это позволяет использовать один и тот
 * же движок для split tunneling и не доверять Xray управление Android VpnService.
 */
object XrayConfigBuilder {

    const val SOCKS_PORT = 10800
    const val API_PORT = 10801
    const val PROXY_TAG = "proxy"
    const val SOCKS_TAG = "socks-in"
    const val API_TAG = "api-in"

    fun build(profile: VlessProfile): String {
        val securityFields = mutableListOf<String>()
        when (profile.security) {
            VlessProfile.SECURITY_TLS -> {
                securityFields += field("serverName", json(profile.serverName.ifEmpty { profile.address }))
                securityFields += field("allowInsecure", profile.allowInsecure.toString())
                val alpnValues = profile.alpn.split(',')
                    .map { it.trim() }
                    .filter { it.isNotEmpty() }
                if (alpnValues.isNotEmpty()) {
                    securityFields += field(
                        "alpn",
                        alpnValues.joinToString(",", prefix = "[", postfix = "]") { json(it) },
                    )
                }
            }
            VlessProfile.SECURITY_REALITY -> {
                securityFields += field("serverName", json(profile.serverName))
                securityFields += field("publicKey", json(profile.publicKey))
                securityFields += field("shortId", json(profile.shortId))
                securityFields += field("fingerprint", json(profile.fingerprint))
            }
        }
        val securityBlock = if (securityFields.isEmpty()) {
            field("security", json(VlessProfile.SECURITY_NONE))
        } else {
            field("security", json(profile.security)) + "," +
                field("${profile.security}Settings", obj(securityFields))
        }

        val networkFields = mutableListOf<String>()
        when (profile.network) {
            VlessProfile.NETWORK_WS -> {
                networkFields += field("network", json(VlessProfile.NETWORK_WS))
                val headers = if (profile.host.isBlank()) {
                    "{}"
                } else {
                    obj(listOf(field("Host", json(profile.host))))
                }
                networkFields += field(
                    "wsSettings",
                    obj(
                        listOf(
                            field("path", json(profile.path)),
                            field("headers", headers),
                        ),
                    ),
                )
            }
            else -> networkFields += field("network", json(VlessProfile.NETWORK_TCP))
        }
        val streamSettings = obj(securityFields = securityBlock, networkFields = networkFields)

        val userFields = mutableListOf(field("id", json(profile.uuid)))
        if (profile.flow.isNotBlank()) {
            userFields += field("flow", json(profile.flow))
        }
        userFields += field("encryption", json("none"))

        return """
{
  "log": {"loglevel": "warning"},
  "api": {"tag": "${API_TAG}", "services": ["StatsService"]},
  "stats": {},
  "policy": {
    "levels": {
      "0": {
        "statsInboundUplink": true,
        "statsInboundDownlink": true,
        "statsOutboundUplink": true,
        "statsOutboundDownlink": true
      }
    }
  },
  "inbounds": [
    {
      "tag": "${SOCKS_TAG}",
      "port": $SOCKS_PORT,
      "listen": "127.0.0.1",
      "protocol": "socks",
      "settings": {"auth": "noauth", "udp": true}
    },
    {
      "tag": "${API_TAG}",
      "port": $API_PORT,
      "listen": "127.0.0.1",
      "protocol": "dokodemo-door",
      "settings": {"address": "127.0.0.1"}
    }
  ],
  "outbounds": [
    {
      "tag": "${PROXY_TAG}",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": ${json(profile.address)},
            "port": ${profile.port},
            "users": [${obj(userFields)}]
          }
        ]
      },
      "streamSettings": $streamSettings
    },
    {"tag": "direct", "protocol": "freedom", "settings": {"domainStrategy": "AsIs"}},
    {"tag": "block", "protocol": "blackhole"}
  ],
  "routing": {
    "rules": [
      {
        "ip": [
          "0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8",
          "169.254.0.0/16", "172.16.0.0/12", "192.0.0.0/24",
          "192.168.0.0/16", "198.18.0.0/15", "224.0.0.0/4", "240.0.0.0/4"
        ],
        "outboundTag": "direct"
      },
      {"domain": ["localhost"], "outboundTag": "direct"}
    ]
  }
}
""".trimIndent()
    }

    private fun obj(fields: List<String>): String = fields.joinToString(",", prefix = "{", postfix = "}")

    private fun obj(securityFields: String, networkFields: List<String>): String =
        (listOf(securityFields) + networkFields).joinToString(",", prefix = "{", postfix = "}")

    private fun field(name: String, value: String): String = "\"$name\":$value"

    private fun json(value: String): String {
        val builder = StringBuilder(value.length + 2)
        builder.append('"')
        for (char in value) {
            when (char) {
                '"' -> builder.append("\\\"")
                '\\' -> builder.append("\\\\")
                '\n' -> builder.append("\\n")
                '\r' -> builder.append("\\r")
                '\t' -> builder.append("\\t")
                else -> if (char.code < 0x20) {
                    builder.append(String.format("\\u%04x", char.code))
                } else {
                    builder.append(char)
                }
            }
        }
        builder.append('"')
        return builder.toString()
    }
}
