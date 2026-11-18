package com.bitplugg.vpn_client

/** Данные, которые Dart передаёт для подключения. */
data class VpnConnectRequest(
    val configId: String,
    val name: String,
    val protocol: String,
    val content: String,
    val excludedApplications: List<String>,
    val includedApplications: List<String>,
    val dnsServers: List<String>,
)

/** Результат операции движка без использования stdlib Result в сигнатурах. */
sealed class VpnResult<out T> {
    data class Success<T>(val value: T) : VpnResult<T>()
    data class Failure(val code: String, val message: String?) : VpnResult<Nothing>()
}
