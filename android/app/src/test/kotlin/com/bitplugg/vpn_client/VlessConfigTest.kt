package com.bitplugg.vpn_client

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class VlessConfigTest {

    @Test
    fun parsesTlsWebSocketUri() {
        val profile = VlessConfigParser.parse(
            "vless://11111111-2222-3333-4444-555555555555@example.com:443" +
                "?security=tls&type=ws&path=%2Fws&host=cdn.example.com&sni=example.com" +
                "&alpn=h2%2Chttp%2F1.1#My%20VLESS",
        )
        assertEquals("11111111-2222-3333-4444-555555555555", profile.uuid)
        assertEquals("example.com", profile.address)
        assertEquals(443, profile.port)
        assertEquals("My VLESS", profile.name)
        assertEquals(VlessProfile.SECURITY_TLS, profile.security)
        assertEquals(VlessProfile.NETWORK_WS, profile.network)
        assertEquals("/ws", profile.path)
        assertEquals("cdn.example.com", profile.host)
        assertEquals("example.com", profile.serverName)
        assertEquals("h2,http/1.1", profile.alpn)
    }

    @Test
    fun parsesRealityVisionUri() {
        val profile = VlessConfigParser.parse(
            "vless://uuid-reality@reality.example:443?security=reality" +
                "&type=tcp&flow=xtls-rprx-vision" +
                "&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&sid=abcdef0123456789" +
                "&sni=www.microsoft.com&fp=chrome",
        )
        assertEquals(VlessProfile.SECURITY_REALITY, profile.security)
        assertEquals("xtls-rprx-vision", profile.flow)
        assertEquals("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", profile.publicKey)
        assertEquals("abcdef0123456789", profile.shortId)
        assertEquals("www.microsoft.com", profile.serverName)
    }

    @Test(expected = VlessConfigException::class)
    fun rejectsUnsupportedTransport() {
        VlessConfigParser.parse(
            "vless://uuid@example.com:443?security=tls&type=grpc",
        )
    }

    @Test(expected = VlessConfigException::class)
    fun rejectsRealityWithoutPublicKey() {
        VlessConfigParser.parse(
            "vless://uuid@example.com:443?security=reality&type=tcp&sni=example.com",
        )
    }

    @Test
    fun builderEmitsRealXrayOutbound() {
        val profile = VlessConfigParser.parse(
            "vless://uuid@example.com:443?security=reality&type=tcp" +
                "&flow=xtls-rprx-vision" +
                "&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&sid=abcdef0123456789" +
                "&sni=example.com",
        )
        val config = XrayConfigBuilder.build(profile)
        assertTrue(config.contains("\"protocol\": \"vless\""))
        assertTrue(config.contains("\"address\": \"example.com\""))
        assertTrue(
            config.contains("\"publicKey\":\"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\""),
        )
        assertTrue(config.contains("\"flow\":\"xtls-rprx-vision\""))
        assertTrue(config.contains("\"protocol\": \"socks\""))
        assertTrue(config.contains("\"port\": ${XrayConfigBuilder.API_PORT}"))
        assertTrue(config.contains("\"stats\": {}"))
    }
}
