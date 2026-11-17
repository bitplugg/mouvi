package com.bitplugg.vpn_client

/**
 * Дополнение WireGuard/AmneziaWG-конфига рантайм-опциями приложения.
 *
 * Чистая Kotlin-логика без Android API — её можно покрыть JVM-тестами.
 * Что делает:
 * - подставляет защищённый DNS, если в конфиге DNS не задан;
 * - применяет split tunneling в одном из режимов: исключить выбранные
 *   приложения или пускать через VPN только выбранные;
 * - для WARP-конфигов Cloudflare подставляет Endpoint/AllowedIPs,
 *   если их нет (обычные WireGuard-конфиги не трогает).
 *
 * Если в конфиге уже есть ExcludedApplications/IncludedApplications,
 * они объединяются с выбором пользователя. Взаимоисключающие ключи
 * удаляются: Android разрешает использовать только один режим.
 */
object RuntimeConfigAugmenter {

    const val WARP_PUBLIC_KEY = "bmXOC+F1FxEMF9dyiK2H5/56nH5M2nH0e3hv0Xw2FzY="

    private val PACKAGE_PATTERN = Regex("^[A-Za-z0-9_]+(\\.[A-Za-z0-9_]+)+$")
    private const val DEFAULT_DNS = "1.1.1.1, 1.0.0.1"
    private const val WARP_ENDPOINT = "engage.cloudflareclient.com:2408"
    private const val WARP_ALLOWED_IPS = "0.0.0.0/0, ::/0"

    fun augment(
        content: String,
        dnsProtection: Boolean,
        excludedApplications: List<String>,
        includedApplications: List<String>,
        applyWarpDefaults: Boolean,
    ): String {
        val selectedExcluded = sanitizePackages(excludedApplications)
        val selectedIncluded = sanitizePackages(includedApplications)
        val useInclude = selectedIncluded.isNotEmpty()
        val useExclude = !useInclude && selectedExcluded.isNotEmpty()

        val lines = content.trim().removePrefix("\uFEFF").lines().toMutableList()
        val interfaceStart = lines.indexOfFirst {
            it.trim().equals("[Interface]", ignoreCase = true)
        }
        if (interfaceStart < 0) {
            // Config.parse ниже вернёт понятную ошибку.
            return content
        }
        var interfaceEnd = lines.size
        for (index in interfaceStart + 1 until lines.size) {
            val line = lines[index].trim()
            if (line.startsWith("[") && line.endsWith("]")) {
                interfaceEnd = index
                break
            }
        }

        val keptInterface = mutableListOf<String>()
        val existingExcluded = LinkedHashSet<String>()
        val existingIncluded = LinkedHashSet<String>()
        var hasDnsValue = false

        for (index in interfaceStart + 1 until interfaceEnd) {
            val raw = lines[index]
            val line = raw.trim()
            if (!line.contains('=')) {
                keptInterface.add(raw)
                continue
            }
            val key = line.substringBefore('=').trim()
            val value = line.substringAfter('=').trim()
            when {
                key.equals("dns", ignoreCase = true) -> {
                    if (value.isNotEmpty()) {
                        hasDnsValue = true
                        keptInterface.add(raw)
                    } else if (dnsProtection) {
                        keptInterface.add("DNS = $DEFAULT_DNS")
                        hasDnsValue = true
                    } else {
                        keptInterface.add(raw)
                    }
                }
                key.equals("excludedapplications", ignoreCase = true) -> {
                    if (useInclude) {
                        // В режиме «только выбранные» исключения несовместимы.
                    } else {
                        value.split(',')
                            .map { it.trim() }
                            .filter { it.isNotEmpty() }
                            .forEach { existingExcluded.add(it) }
                        if (!useExclude) {
                            keptInterface.add(raw)
                        }
                    }
                }
                key.equals("includedapplications", ignoreCase = true) -> {
                    if (useExclude) {
                        // В режиме исключений список включённых несовместим.
                    } else {
                        value.split(',')
                            .map { it.trim() }
                            .filter { it.isNotEmpty() }
                            .forEach { existingIncluded.add(it) }
                        if (!useInclude) {
                            keptInterface.add(raw)
                        }
                    }
                }
                else -> keptInterface.add(raw)
            }
        }
        if (dnsProtection && !hasDnsValue) {
            keptInterface.add("DNS = $DEFAULT_DNS")
        }
        if (useExclude) {
            existingExcluded.addAll(selectedExcluded)
            keptInterface.add("ExcludedApplications = ${existingExcluded.joinToString(", ")}")
        } else if (useInclude) {
            existingIncluded.addAll(selectedIncluded)
            keptInterface.add("IncludedApplications = ${existingIncluded.joinToString(", ")}")
        }

        val rebuilt = mutableListOf<String>()
        rebuilt.addAll(lines.subList(0, interfaceStart + 1))
        rebuilt.addAll(keptInterface)
        rebuilt.addAll(lines.subList(interfaceEnd, lines.size))

        return if (applyWarpDefaults) {
            injectWarpDefaults(rebuilt)
        } else {
            rebuilt.joinToString("\n")
        }
    }

    private fun injectWarpDefaults(lines: MutableList<String>): String {
        // Ищем Peer-секцию с публичным ключом Cloudflare WARP.
        var peerStart = -1
        var peerEnd = lines.size
        var cursor = 0
        while (cursor < lines.size) {
            if (lines[cursor].trim().equals("[Peer]", ignoreCase = true)) {
                peerStart = cursor
                peerEnd = lines.size
                for (index in cursor + 1 until lines.size) {
                    val line = lines[index].trim()
                    if (line.startsWith("[") && line.endsWith("]")) {
                        peerEnd = index
                        break
                    }
                }
                var isWarp = false
                var hasEndpoint = false
                var hasAllowedIps = false
                for (index in peerStart + 1 until peerEnd) {
                    val line = lines[index].trim()
                    if (!line.contains('=')) {
                        continue
                    }
                    val key = line.substringBefore('=').trim()
                    val value = line.substringAfter('=').trim()
                    when {
                        key.equals("publickey", ignoreCase = true) && value == WARP_PUBLIC_KEY ->
                            isWarp = true
                        key.equals("endpoint", ignoreCase = true) && value.isNotEmpty() ->
                            hasEndpoint = true
                        key.equals("allowedips", ignoreCase = true) && value.isNotEmpty() ->
                            hasAllowedIps = true
                    }
                }
                if (isWarp) {
                    val additions = mutableListOf<String>()
                    if (!hasEndpoint) additions.add("Endpoint = $WARP_ENDPOINT")
                    if (!hasAllowedIps) additions.add("AllowedIPs = $WARP_ALLOWED_IPS")
                    if (additions.isNotEmpty()) {
                        lines.addAll(peerEnd, additions)
                    }
                    break
                }
                cursor = peerEnd
                continue
            }
            cursor += 1
        }
        return lines.joinToString("\n")
    }

    private fun sanitizePackages(packages: List<String>): List<String> =
        packages.asSequence()
            .map { it.trim() }
            .filter { PACKAGE_PATTERN.matches(it) }
            .distinct()
            .toList()
}
