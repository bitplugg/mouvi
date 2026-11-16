---
layout: default
title: Архитектура VPN-движка
---

# Архитектура VPN-движка

Mouvi использует нативный Android VPN-движок, вынесенный за интерфейс `ProtocolEngine`. Новый протокол добавляется отдельным движком и флагом поддержки в Dart-слое (`engineSupported`).

## Схема взаимодействия

```
Flutter (Dart, Riverpod)
    │
    ▼ MethodChannel('mouvi/vpn')
MainActivity (FlutterActivity)
    │
    ▼ ProtocolEngineFactory.forProtocol(protocol)
┌──────────────┬────────────────────────────────┐
│ "wireguard"  │ WireGuardEngine (синглтон)     │
│ "amneziawg"  │ AmneziaWgEngine (синглтон)     │
│ else         │ null → unsupported_protocol    │
└──────────────┴────────────────────────────────┘
    │
    ▼ GoBackend.setState(Tunnel, UP/DOWN, Config)
```

## Классы

| Класс | Файл | Описание |
|-------|------|----------|
| `ProtocolEngine` | `android/.../ProtocolEngine.kt` | Интерфейс движка |
| `WireGuardEngine` | `android/.../WireGuardEngine.kt` | WireGuard через `com.wireguard.android.backend.GoBackend` |
| `AmneziaWgEngine` | `android/.../AmneziaWgEngine.kt` | AmneziaWG через `org.amnezia.awg.backend.GoBackend` |
| `ProtocolEngineFactory` | `android/.../ProtocolEngineFactory.kt` | Фабрика движков |
| `VpnConnectRequest` / `VpnResult` | `android/.../MouviVpnEngine.kt` | Контракт данных |

## Процессный синглтон

Оба движка — процессные синглтоны. `GoBackend` хранит туннель в памяти и сравнивает `Tunnel` по ссылке. После пересоздания Activity новый экземпляр не смог бы распознать активный туннель.

## Как добавить новый протокол

1. Создать класс, реализующий `ProtocolEngine`.
2. Добавить строку в `ProtocolEngineFactory.forProtocol()`:
   ```kotlin
   "vless" -> VlessEngine.get(context)
   ```
3. Включить протокол в `VpnProtocolType.engineSupported`, добавить подпись/тесты и проверить импорт конфигурации на стороне Dart.
