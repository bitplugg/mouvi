package com.bitplugg.vpn_client

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RuntimeConfigAugmenterTest {

    private val key = "a".repeat(43) + "="
    private val cloudflareKey = RuntimeConfigAugmenter.WARP_PUBLIC_KEY

    private fun baseConfig(peerExtra: String = ""): String = buildString {
        appendLine("[Interface]")
        appendLine("PrivateKey = $key")
        appendLine("Address = 10.0.0.2/32")
        appendLine()
        appendLine("[Peer]")
        appendLine("PublicKey = $key")
        appendLine("AllowedIPs = 0.0.0.0/0")
        appendLine("Endpoint = vpn.example.com:51820")
        if (peerExtra.isNotEmpty()) appendLine(peerExtra)
    }

    @Test
    fun `adds default DNS when interface has none`() {
        val result = RuntimeConfigAugmenter.augment(
            content = baseConfig(),
            dnsProtection = true,
            excludedApplications = emptyList(),
            includedApplications = emptyList(),
            applyWarpDefaults = false,
        )
        assertTrue(result.contains("DNS = 1.1.1.1, 1.0.0.1"))
    }

    @Test
    fun `keeps existing DNS and does not duplicate`() {
        val config = baseConfig().replace("[Peer]", "DNS = 9.9.9.9\n[Peer]")
        val result = RuntimeConfigAugmenter.augment(
            content = config,
            dnsProtection = true,
            excludedApplications = emptyList(),
            includedApplications = emptyList(),
            applyWarpDefaults = false,
        )
        assertEquals(1, Regex("(?m)^DNS\\s*=").findAll(result).count())
        assertTrue(result.contains("DNS = 9.9.9.9"))
    }

    @Test
    fun `replaces empty DNS line`() {
        val config = baseConfig().replace("[Peer]", "DNS =\n[Peer]")
        val result = RuntimeConfigAugmenter.augment(
            content = config,
            dnsProtection = true,
            excludedApplications = emptyList(),
            includedApplications = emptyList(),
            applyWarpDefaults = false,
        )
        assertEquals(1, Regex("(?m)^DNS\\s*=").findAll(result).count())
        assertTrue(result.contains("DNS = 1.1.1.1, 1.0.0.1"))
    }

    @Test
    fun `respects disabled DNS protection`() {
        val result = RuntimeConfigAugmenter.augment(
            content = baseConfig(),
            dnsProtection = false,
            excludedApplications = emptyList(),
            includedApplications = emptyList(),
            applyWarpDefaults = false,
        )
        assertFalse(result.contains("DNS = 1.1.1.1"))
    }

    @Test
    fun `adds excluded applications and merges existing list`() {
        val config = baseConfig().replace(
            "[Peer]",
            "ExcludedApplications = com.existing.app\n[Peer]",
        )
        val result = RuntimeConfigAugmenter.augment(
            content = config,
            dnsProtection = false,
            excludedApplications = listOf("com.example.app"),
            includedApplications = emptyList(),
            applyWarpDefaults = false,
        )
        assertEquals(1, Regex("(?m)^ExcludedApplications\\s*=").findAll(result).count())
        assertTrue(result.contains("com.existing.app"))
        assertTrue(result.contains("com.example.app"))
    }

    @Test
    fun `include mode removes excluded applications`() {
        val config = baseConfig().replace(
            "[Peer]",
            "ExcludedApplications = com.existing.app\n[Peer]",
        )
        val result = RuntimeConfigAugmenter.augment(
            content = config,
            dnsProtection = false,
            excludedApplications = emptyList(),
            includedApplications = listOf("com.example.app"),
            applyWarpDefaults = false,
        )
        assertFalse(result.contains("ExcludedApplications"))
        assertTrue(result.contains("IncludedApplications = com.example.app"))
    }

    @Test
    fun `exclude mode removes included applications`() {
        val config = baseConfig().replace(
            "[Peer]",
            "IncludedApplications = com.existing.app\n[Peer]",
        )
        val result = RuntimeConfigAugmenter.augment(
            content = config,
            dnsProtection = false,
            excludedApplications = listOf("com.example.app"),
            includedApplications = emptyList(),
            applyWarpDefaults = false,
        )
        assertFalse(result.contains("IncludedApplications"))
        assertTrue(result.contains("ExcludedApplications = com.example.app"))
    }

    @Test
    fun `invalid package names are ignored`() {
        val result = RuntimeConfigAugmenter.augment(
            content = baseConfig(),
            dnsProtection = false,
            excludedApplications = listOf("not a package", "com.example.app"),
            includedApplications = emptyList(),
            applyWarpDefaults = false,
        )
        assertTrue(result.contains("ExcludedApplications = com.example.app"))
        assertFalse(result.contains("not a package"))
    }

    @Test
    fun `warp config gets endpoint and allowed ips`() {
        val config = """
            [Interface]
            PrivateKey = $key
            Address = 172.16.0.2/32

            [Peer]
            PublicKey = $cloudflareKey
        """.trimIndent()
        val result = RuntimeConfigAugmenter.augment(
            content = config,
            dnsProtection = false,
            excludedApplications = emptyList(),
            includedApplications = emptyList(),
            applyWarpDefaults = true,
        )
        assertTrue(result.contains("Endpoint = engage.cloudflareclient.com:2408"))
        assertTrue(result.contains("AllowedIPs = 0.0.0.0/0, ::/0"))
    }

    @Test
    fun `regular wireguard config is not modified by warp defaults`() {
        val config = """
            [Interface]
            PrivateKey = $key
            Address = 10.0.0.2/32

            [Peer]
            PublicKey = $key
        """.trimIndent()
        val result = RuntimeConfigAugmenter.augment(
            content = config,
            dnsProtection = false,
            excludedApplications = emptyList(),
            includedApplications = emptyList(),
            applyWarpDefaults = true,
        )
        assertFalse(result.contains("engage.cloudflareclient.com"))
    }

    @Test
    fun `existing warp endpoint is preserved`() {
        val config = """
            [Interface]
            PrivateKey = $key
            Address = 172.16.0.2/32

            [Peer]
            PublicKey = $cloudflareKey
            Endpoint = 162.159.192.1:2408
        """.trimIndent()
        val result = RuntimeConfigAugmenter.augment(
            content = config,
            dnsProtection = false,
            excludedApplications = emptyList(),
            includedApplications = emptyList(),
            applyWarpDefaults = true,
        )
        assertTrue(result.contains("Endpoint = 162.159.192.1:2408"))
        assertFalse(result.contains("engage.cloudflareclient.com"))
    }

    @Test
    fun `amnezia parameters are preserved`() {
        val config = baseConfig()
            .replace("[Peer]", "H1 = 12345\nH2 = 23456\nH3 = 34567\nH4 = 45678\n[Peer]")
        val result = RuntimeConfigAugmenter.augment(
            content = config,
            dnsProtection = false,
            excludedApplications = emptyList(),
            includedApplications = emptyList(),
            applyWarpDefaults = false,
        )
        assertTrue(result.contains("H1 = 12345"))
        assertTrue(result.contains("H4 = 45678"))
    }

    @Test
    fun `content without interface is returned unchanged`() {
        val content = "garbage"
        val result = RuntimeConfigAugmenter.augment(
            content = content,
            dnsProtection = true,
            excludedApplications = listOf("com.example.app"),
            includedApplications = emptyList(),
            applyWarpDefaults = true,
        )
        assertEquals(content, result)
    }
}
