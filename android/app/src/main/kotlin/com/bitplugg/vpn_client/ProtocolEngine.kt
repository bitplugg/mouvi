package com.bitplugg.vpn_client

/**
 * Абстракция VPN-движка для конкретного протокола.
 *
 * Реализации инкапсулируют всю нативную логику подключения/отключения
 * и чтения состояния туннеля для своего протокола (WireGuard, AmneziaWG, VLESS и т.д.).
 *
 * Сигнатуры методов совпадают с предыдущими методами MouviVpnEngine,
 * чтобы вызывающий код (MainActivity / MethodChannel) не требовал изменений.
 */
interface ProtocolEngine {

    /** Поднять туннель. Результат возвращается асинхронно через callback. */
    fun connect(request: VpnConnectRequest, callback: (VpnResult<String>) -> Unit)

    /** Опустить туннель. Результат возвращается асинхронно через callback. */
    fun disconnect(callback: (VpnResult<Unit>) -> Unit)

    /** Синхронный снимок состояния туннеля (для getState и восстановления UI). */
    fun getState(): Map<String, Any?>

    /** Синоним [getState], используется потоком событий. */
    fun currentStateMap(): Map<String, Any?>

    /** Подписаться на изменения состояния туннеля (поднят / опущен). */
    fun setStateListener(listener: ((Boolean) -> Unit)?)
}