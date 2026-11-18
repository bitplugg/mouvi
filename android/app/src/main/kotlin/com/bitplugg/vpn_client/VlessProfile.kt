package com.bitplugg.vpn_client

import java.net.URLDecoder
import org.json.JSONObject

/**
 * Разобранная VLESS-ссылка или v2ray-подобный JSON.
 *
 * Это чистая JVM-логика: парсер покрывается unit-тестами и не зависит
 * от Android SDK. Поддерживаются транспорты TCP и WebSocket, а также
 * TLS и Reality — те режимы, которые реально запускаются нашим Xray-движком.
 */
data class VlessProfile(
    val uuid: String,
    val address: String,
    val port: Int,
    val name: String,
    val security: String,
    val network: String,
    val path: String,
    val host: String,
    val serverName: String,
    val flow: String,
    val fingerprint: String,
    val publicKey: String,
    val shortId: String,
    val alpn: String,
    val allowInsecure: Boolean,
) {
    companion object {
        const val SECURITY_NONE = "none"
        const val SECURITY_TLS = "tls"
        const val SECURITY_REALITY = "reality"
        const val NETWORK_TCP = "tcp"
        const val NETWORK_WS = "ws"
    }
}

class VlessConfigException(val errorCode: String, message: String) : Exception(message)

object VlessConfigParser {

    private val REALITY_KEY = Regex("^[A-Za-z0-9_-]{43,44}$")
    private val REALITY_SHORT_ID = Regex("^([0-9a-fA-F]{2})+$")

    fun parse(content: String): VlessProfile {
        val trimmed = content.trim().removePrefix("\uFEFF")
        if (trimmed.isEmpty()) {
            throw VlessConfigException("invalid_config", "Empty VLESS config")
        }
        return if (trimmed.startsWith("{")) {
            parseJson(trimmed)
        } else {
            parseUri(trimmed)
        }
    }

    private fun parseUri(input: String): VlessProfile {
        val schemeIndex = input.indexOf("://")
        if (schemeIndex < 0 ||
            !input.substring(0, schemeIndex).equals("vless", ignoreCase = true)
        ) {
            throw VlessConfigException("invalid_config", "Not a VLESS URI")
        }
        val afterScheme = input.substring(schemeIndex + 3)
        val fragmentIndex = afterScheme.indexOf('#')
        val name = if (fragmentIndex >= 0) {
            decode(afterScheme.substring(fragmentIndex + 1))
        } else {
            ""
        }
        val withoutFragment = if (fragmentIndex >= 0) {
            afterScheme.substring(0, fragmentIndex)
        } else {
            afterScheme
        }
        val queryIndex = withoutFragment.indexOf('?')
        val authority = if (queryIndex >= 0) {
            withoutFragment.substring(0, queryIndex)
        } else {
            withoutFragment
        }
        val params = if (queryIndex >= 0) {
            parseQuery(withoutFragment.substring(queryIndex + 1))
        } else {
            emptyMap()
        }

        val atIndex = authority.lastIndexOf('@')
        val uuid = decode(if (atIndex >= 0) authority.substring(0, atIndex) else "")
        val hostPart = if (atIndex >= 0) authority.substring(atIndex + 1) else authority
        val (address, port) = splitHostPort(hostPart)

        return build(
            uuid = uuid,
            address = address,
            port = port,
            name = name,
            params = params,
            userFlow = "",
        )
    }

    private fun parseJson(input: String): VlessProfile {
        val root = try {
            JSONObject(input)
        } catch (_: Throwable) {
            throw VlessConfigException("invalid_config", "Invalid VLESS JSON")
        }
        val outbound = findVlessOutbound(root)
            ?: throw VlessConfigException("invalid_config", "VLESS outbound not found")
        val settings = outbound.optJSONObject("settings") ?: JSONObject()
        val vnext = settings.optJSONArray("vnext")
        val first = when {
            vnext != null && vnext.length() > 0 -> vnext.optJSONObject(0)
            settings.has("address") -> settings
            else -> null
        } ?: throw VlessConfigException("invalid_config", "VLESS vnext is missing")

        val users = first.optJSONArray("users")
        val user = when {
            users != null && users.length() > 0 -> users.optJSONObject(0)
            first.has("id") -> first
            else -> null
        } ?: throw VlessConfigException("invalid_config", "VLESS user is missing")

        val uuid = user.optString("id", "").trim()
        val address = first.optString("address", "")
            .ifEmpty { first.optString("server", "") }
            .trim()
        val port = first.optInt("port", 0)
        val stream = outbound.optJSONObject("streamSettings") ?: JSONObject()
        val tls = stream.optJSONObject("tlsSettings") ?: JSONObject()
        val reality = stream.optJSONObject("realitySettings") ?: JSONObject()
        val ws = stream.optJSONObject("wsSettings") ?: JSONObject()
        val headers = ws.optJSONObject("headers") ?: JSONObject()

        val params = mutableMapOf<String, String>()
        params["security"] = stream.optString("security", "").ifEmpty {
            when {
                reality.length() > 0 -> VlessProfile.SECURITY_REALITY
                tls.length() > 0 -> VlessProfile.SECURITY_TLS
                else -> VlessProfile.SECURITY_NONE
            }
        }
        params["type"] = stream.optString("network", VlessProfile.NETWORK_TCP)
        params["path"] = ws.optString("path", "")
        params["host"] = firstNonEmpty(
            headers.optString("Host", ""),
            headers.optString("host", ""),
        )
        params["sni"] = firstNonEmpty(
            reality.optString("serverName", ""),
            tls.optString("serverName", ""),
        )
        params["fp"] = firstNonEmpty(
            reality.optString("fingerprint", ""),
            tls.optString("fingerprint", ""),
        )
        params["pbk"] = reality.optString("publicKey", "")
        params["sid"] = reality.optString("shortId", "")
        val alpn = tls.optJSONArray("alpn")
        if (alpn != null && alpn.length() > 0) {
            params["alpn"] = (0 until alpn.length()).joinToString(",") {
                alpn.optString(it)
            }
        }
        if (tls.optBoolean("allowInsecure", false)) {
            params["allowInsecure"] = "1"
        }

        return build(
            uuid = uuid,
            address = address,
            port = port,
            name = firstNonEmpty(
                outbound.optString("tag", ""),
                root.optString("remarks", ""),
                root.optString("ps", ""),
            ),
            params = params,
            userFlow = firstNonEmpty(
                user.optString("flow", ""),
                user.optString("security", ""),
            ),
        )
    }

    private fun findVlessOutbound(root: JSONObject): JSONObject? {
        val outbounds = root.optJSONArray("outbounds")
        if (outbounds != null) {
            for (index in 0 until outbounds.length()) {
                val outbound = outbounds.optJSONObject(index) ?: continue
                if (outbound.optString("protocol", "").equals("vless", ignoreCase = true)) {
                    return outbound
                }
            }
        }
        val nested = root.optJSONObject("vless")
        if (nested != null) {
            val wrapper = JSONObject()
            wrapper.put("protocol", "vless")
            wrapper.put("settings", nested)
            wrapper.put("streamSettings", root.optJSONObject("streamSettings") ?: JSONObject())
            return wrapper
        }
        return null
    }

    private fun parseQuery(query: String): Map<String, String> {
        val result = mutableMapOf<String, String>()
        if (query.isEmpty()) {
            return result
        }
        for (pair in query.split('&')) {
            if (pair.isEmpty()) {
                continue
            }
            val separator = pair.indexOf('=')
            val rawKey = if (separator >= 0) pair.substring(0, separator) else pair
            val rawValue = if (separator >= 0) pair.substring(separator + 1) else ""
            result[decode(rawKey).lowercase()] = decode(rawValue)
        }
        return result
    }

    private fun decode(value: String): String = try {
        URLDecoder.decode(value, "UTF-8")
    } catch (_: Throwable) {
        value
    }

    private fun splitHostPort(input: String): Pair<String, Int> {
        val bracketEnd = if (input.startsWith("[")) input.indexOf(']') else -1
        val host = if (bracketEnd > 0) {
            input.substring(1, bracketEnd)
        } else {
            val colon = input.lastIndexOf(':')
            if (colon > 0) input.substring(0, colon) else input
        }
        val rawPort = if (bracketEnd > 0 && input.length > bracketEnd + 1) {
            input.substring(bracketEnd + 1).removePrefix(":")
        } else {
            val colon = input.lastIndexOf(':')
            if (colon > 0) input.substring(colon + 1) else ""
        }
        val port = rawPort.toIntOrNull()
            ?: throw VlessConfigException("invalid_config", "VLESS port is missing")
        return host to port
    }

    private fun build(
        uuid: String,
        address: String,
        port: Int,
        name: String,
        params: Map<String, String>,
        userFlow: String,
    ): VlessProfile {
        if (uuid.isEmpty()) {
            throw VlessConfigException("invalid_config", "VLESS uuid is missing")
        }
        if (address.isEmpty() || address == "0.0.0.0" || address == "::") {
            throw VlessConfigException("invalid_config", "VLESS address is missing")
        }
        if (port !in 1..65535) {
            throw VlessConfigException("invalid_config", "VLESS port is invalid")
        }

        val security = when (params["security"]?.lowercase().orEmpty().ifEmpty { "none" }) {
            "tls" -> VlessProfile.SECURITY_TLS
            "reality" -> VlessProfile.SECURITY_REALITY
            "none", "" -> VlessProfile.SECURITY_NONE
            else -> throw VlessConfigException(
                "unsupported_transport",
                "Unsupported VLESS security",
            )
        }
        val network = when (params["type"]?.lowercase().orEmpty().ifEmpty { "tcp" }) {
            "tcp" -> VlessProfile.NETWORK_TCP
            "ws" -> VlessProfile.NETWORK_WS
            else -> throw VlessConfigException(
                "unsupported_transport",
                "Unsupported VLESS transport",
            )
        }
        val serverName = firstNonEmpty(params["sni"].orEmpty(), params["host"].orEmpty())
        if (security == VlessProfile.SECURITY_REALITY) {
            val publicKey = params["pbk"].orEmpty()
            if (!REALITY_KEY.matches(publicKey)) {
                throw VlessConfigException("invalid_config", "Reality public key is invalid")
            }
            if (serverName.isEmpty()) {
                throw VlessConfigException("invalid_config", "Reality SNI is missing")
            }
            val shortId = params["sid"].orEmpty()
            if (shortId.isNotEmpty() && !REALITY_SHORT_ID.matches(shortId)) {
                throw VlessConfigException("invalid_config", "Reality shortId is invalid")
            }
        }

        return VlessProfile(
            uuid = uuid,
            address = address,
            port = port,
            name = name.ifEmpty { address },
            security = security,
            network = network,
            path = params["path"].orEmpty().ifEmpty { "/" },
            host = params["host"].orEmpty(),
            serverName = serverName,
            flow = firstNonEmpty(params["flow"].orEmpty(), userFlow),
            fingerprint = params["fp"].orEmpty().ifEmpty { "chrome" },
            publicKey = params["pbk"].orEmpty(),
            shortId = params["sid"].orEmpty(),
            alpn = params["alpn"].orEmpty(),
            allowInsecure = when (params["allowInsecure"]?.lowercase()) {
                "1", "true", "yes" -> true
                else -> false
            },
        )
    }

    private fun firstNonEmpty(vararg values: String): String =
        values.firstOrNull { it.isNotBlank() }?.trim().orEmpty()
}
