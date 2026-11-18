---
layout: default
title: Архитектура VPN-движка
---

# Архитектура VPN-движка

Mouvi использует нативный Android VPN-движок, вынесенный за интерфейс
`ProtocolEngine`. Новый протокол добавляется отдельным движком и флагом
поддержки в Dart-слое (`engineSupported`).

## Схема взаимодействия

```
Flutter (Dart, Riverpod)
    │
    ▼ MethodChannel('mouvi/vpn')
MainActivity (FlutterActivity)
    │
    ▼ ProtocolEngineFactory.forProtocol(protocol)
┌──────────────┬──────────────────────────────────────────┐
│ "wireguard"  │ WireGuardEngine → GoBackend               │
│ "amneziawg"  │ AmneziaWgEngine → GoBackend               │
│ "vless"      │ VlessEngine → Xray + tun2socks + VpnService│
│ else         │ null → unsupported_protocol               │
└──────────────┴──────────────────────────────────────────┘
    │
    ▼ (WG/AWG) RuntimeConfigAugmenter.augment(...)
    ▼ (WG/AWG) GoBackend.setState(Tunnel, UP/DOWN, Config)
```

## Каналы Flutter ↔ Android

| Канал | Тип | Назначение |
|-------|-----|------------|
| `mouvi/vpn` | `MethodChannel` | connect, disconnect, getState, hasVpnPermission, openVpnSettings |
| `mouvi/vpn_events` | `EventChannel` | Снимок состояния туннеля при UP/DOWN |
| `mouvi/actions` | `EventChannel` | Действие `toggle` из плитки Quick Settings |
| `mouvi/storage` | `MethodChannel` | Шифрованное хранилище конфигов (Android Keystore) |
| `mouvi/apps` | `MethodChannel` | Список приложений для split tunneling |
| `mouvi/push` | `MethodChannel` | Локальные уведомления и запрос разрешения |
| `mouvi/export` | `MethodChannel` | Экспорт конфига через `ACTION_CREATE_DOCUMENT` |

## Классы

| Класс | Файл | Описание |
|-------|------|----------|
| `ProtocolEngine` | `android/.../ProtocolEngine.kt` | Интерфейс движка |
| `WireGuardEngine` | `android/.../WireGuardEngine.kt` | WireGuard через `com.wireguard.android.backend.GoBackend` |
| `AmneziaWgEngine` | `android/.../AmneziaWgEngine.kt` | AmneziaWG через `org.amnezia.awg.backend.GoBackend` |
| `VlessEngine` | `android/.../VlessEngine.kt` | VLESS через Xray-core (SOCKS5) + tun2socks |
| `VlessConfigParser` | `android/.../VlessProfile.kt` | Разбор VLESS URI и v2ray JSON |
| `XrayConfigBuilder` | `android/.../XrayConfigBuilder.kt` | Генерация конфига Xray |
| `MouviVpnService` | `android/.../MouviVpnService.kt` | TUN, DNS, split tunneling и запуск tun2socks |
| `ProtocolEngineFactory` | `android/.../ProtocolEngineFactory.kt` | Фабрика движков |
| `RuntimeConfigAugmenter` | `android/.../RuntimeConfigAugmenter.kt` | DNS, split tunneling, WARP-параметры в тексте конфига |
| `EngineControl` | `android/.../EngineControl.kt` | Состояние и остановка всех движков |
| `MouviTileService` | `android/.../MouviTileService.kt` | Плитка Quick Settings |
| `MouviActionReceiver` | `android/.../MouviActionReceiver.kt` | Кнопка «Отключить» в уведомлении |
| `VpnConnectRequest` / `VpnResult` | `android/.../MouviVpnEngine.kt` | Контракт данных |

## RuntimeConfigAugmenter

Перед передачей конфигурации в `GoBackend` движки вызывают
`RuntimeConfigAugmenter.augment(...)`, который:

- добавляет `DNS = 1.1.1.1, 1.0.0.1`, если включена защита DNS и в конфиге нет DNS;
- добавляет `ExcludedApplications` **или** `IncludedApplications` в зависимости
  от выбранного режима split tunneling (ровно один из них);
- подставляет публичный ключ и endpoint Cloudflare WARP, если включён WARP.

Логика покрыта JUnit-тестами `RuntimeConfigAugmenterTest` (13 тестов) и не
зависит от Android UI.

## VLESS: Xray-core + tun2socks

VLESS не использует `GoBackend`:

1. `VlessConfigParser` превращает `vless://…` или v2ray-подобный JSON в профиль.
2. `XrayConfigBuilder` создаёт конфиг с SOCKS5-inbound на `127.0.0.1:10800`
   и VLESS-outbound с TCP/WS + TLS/Reality.
3. `VlessEngine` запускает бинарник Xray из `jniLibs/<abi>/libxray.so`,
   скопированный в `filesDir`, и ждёт открытия SOCKS-порта.
4. `MouviVpnService` поднимает Android TUN, применяет DNS и split tunneling,
   затем передаёт TUN-дескриптор процессу tun2socks через stdin.
5. Статистика RX/TX читается реальным вызовом `xray api statsquery`. Handshake,
   как у WireGuard, у VLESS отсутствует — поле остаётся `0`.

## Процессный синглтон

Все движки — процессные синглтоны. `GoBackend` хранит туннель в памяти и
сравнивает `Tunnel` по ссылке; `VlessEngine` хранит процессы Xray/tun2socks и
состояние `MouviVpnService`. После пересоздания Activity состояние восстанавливается.

`EngineControl` читает состояние и опускает все движки одновременно: после
пересоздания Activity или вызова из уведомления/плитки заранее неизвестно,
какой протокол поднят.

## Плитка Quick Settings

Если туннель поднят, плитка опускает его нативно, без запуска Activity. Если
туннель опущен, плитка открывает `MainActivity` с one-shot действием
`toggle`; Dart-слой проверяет наличие конфигурации, WARP и разрешения VPN и
выполняет подключение. При уже открытом приложении действие приходит через
`EventChannel('mouvi/actions')`, при холодном старте — при первой подписке.

## Как добавить новый протокол

1. Создать класс, реализующий `ProtocolEngine`.
2. Добавить строку в `ProtocolEngineFactory.forProtocol()`:
   ```kotlin
   "vless" -> VlessEngine.get(context)
   ```
3. Включить протокол в `VpnProtocolType.engineSupported`, добавить подпись/тесты
   и проверить импорт конфигурации на стороне Dart.
