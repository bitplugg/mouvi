<p align="center">
  <img src="docs/banner.svg" alt="Mouvi" width="800">
</p>

# Mouvi

**Mouvi** — кастомный VPN-клиент для Android, собранный на Flutter.

Быстрый, лёгкий и современный клиент с поддержкой WireGuard, AmneziaWG и Cloudflare WARP, разделением туннелирования (split tunneling), защитой DNS и Material You 3 дизайном.

[![Android Build](https://github.com/bitplugg/mouvi/actions/workflows/android_build.yml/badge.svg)](https://github.com/bitplugg/mouvi/actions/workflows/android_build.yml)
[![Flutter](https://img.shields.io/badge/Flutter-3.47-0255BD?logo=flutter)](https://docs.flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Android-3DDC84?logo=android)](https://developer.android.com)
[![Riverpod](https://img.shields.io/badge/Riverpod-3-ff6f00?logo=flutter)](https://riverpod.dev)

---

## 📖 О проекте

Mouvi — это собственный VPN-клиент, разработанный с акцентом на простоту использования, надёжность и расширяемость. Приложение состоит из двух слоёв:

* **Dart (Flutter)** — пользовательский интерфейс, управление состоянием (Riverpod 3), импорт конфигураций, локализация.
* **Kotlin (Android)** — нативный VPN-движок через `VpnService`, связь с Flutter по `MethodChannel`.

Архитектура нативной части построена вокруг интерфейса `ProtocolEngine`: новый VPN-протокол (WireGuard, AmneziaWG, OpenVPN, Trojan, VLESS, Shadowsocks и т.д.) добавляется отдельным движком и флагом поддержки в Dart-слое.

---

## ✨ Возможности

| Категория | Возможность | Статус |
|-----------|-------------|--------|
| **Протоколы** | WireGuard | ✅ Поддерживается |
| | AmneziaWG | ✅ Поддерживается (нужны H1–H4) |
| | WARP (Cloudflare) | ✅ Поддерживается как WireGuard |
| | OpenVPN | 📋 Подключение планируется |
| | Trojan / VLESS / Shadowsocks | 📋 Подключение планируется |
| **Импорт конфигураций** | Файл `.conf` / `.ovpn` / JSON / URI | ✅ Импорт и проверка |
| | Вставка текста из буфера обмена | ✅ |
| | Сканирование QR-кода камерой | ✅ |
| | Экспорт конфига в файл | ✅ С предупреждением о приватном ключе |
| **Защита и туннелирование** | Kill switch | ⛔ Только системный Always-on VPN |
| | Split tunneling: выключен / мимо VPN / только выбранные | ✅ UI + движок |
| | DNS protection | ✅ UI + движок |
| | Автоподключение при запуске | ✅ Только при уже выданном VPN-разрешении |
| **Интерфейс** | Material You 3 (Expressive) | ✅ |
| | Динамическая тема из обоев | ✅ |
| | Русский / английский языки | ✅ |
| | Статистика трафика и рукопожатия | ✅ Обновление раз в 2 секунды |
| **Уведомления** | Состояние соединения (подключён / отключён) | ✅ |
| | Действие «Отключить» в уведомлении | ✅ |
| | Плитка Quick Settings | ✅ |
| **Сборка** | GitHub Actions → подписанные split-APK + Release | ✅ |

---

## 🏗 Архитектура

### Стек технологий

| Слой | Технологии |
|------|------------|
| **Frontend** | Flutter 3.47+, Dart 3.13, Material 3 (Expressive) |
| **State management** | Riverpod 3 |
| **Платформенный канал** | Flutter `MethodChannel` (`mouvi/vpn`), `EventChannel` (`mouvi/vpn_events`, `mouvi/actions`) |
| **VPN-движок (Android)** | Нативный Kotlin, интерфейс `ProtocolEngine` |
| **WireGuard бэкенд** | `com.wireguard.android:tunnel:1.0.20260102` |
| **AmneziaWG бэкенд** | `com.zaneschepke:amneziawg-android:2.3.7` |
| **Сборка** | Gradle, GitHub Actions |

### Схема взаимодействия

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter (Dart, Riverpod)                 │
│  vpn_native_service.dart → MethodChannel('mouvi/vpn')       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ invokeMethod('connect', {...})
┌─────────────────────────────────────────────────────────────┐
│  MainActivity (FlutterActivity)                             │
│  • MethodChannel handler: connect / disconnect / getState   │
│  • activeEngine: ProtocolEngine?                            │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ ProtocolEngineFactory.forProtocol(protocol, context)
┌─────────────────────────────────────────────────────────────┐
│  ProtocolEngineFactory                                      │
│  ┌──────────────┐  ┌─────────────────────────────────────┐ │
│  │ "wireguard"  │─►│ WireGuardEngine (синглтон)          │ │
│  │ "amneziawg"  │─►│ AmneziaWgEngine (синглтон)          │ │
│  │ else         │─►│ null → VpnResult.Failure(...)       │ │
│  └──────────────┘  └─────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
          ┌───────────────────┴───────────────────┐
          ▼                                       ▼
┌───────────────────┐                 ┌───────────────────┐
│ WireGuardEngine   │                 │ AmneziaWgEngine   │
│ • GoBackend       │                 │ • GoBackend       │
│ • Tunnel (UP/DOWN)│                 │ • Tunnel (UP/DOWN)│
│ • RuntimeConfig   │                 │ • RuntimeConfig   │
│   Augmenter (DNS, │                 │   Augmenter (DNS, │
│   split, WARP)    │                 │   split)          │
│ • статистика      │                 │ • статистика      │
└───────────────────┘                 └───────────────────┘
```

`EngineControl` читает состояние и опускает оба движка одновременно: после
пересоздания Activity или вызова из уведомления/плитки заранее неизвестно,
какой протокол поднят.

### Интерфейс `ProtocolEngine`

Все нативные движки реализуют общий интерфейс `ProtocolEngine`:

```kotlin
interface ProtocolEngine {
    fun connect(request: VpnConnectRequest, callback: (VpnResult<String>) -> Unit)
    fun disconnect(callback: (VpnResult<Unit>) -> Unit)
    fun getState(): Map<String, Any?>
    fun currentStateMap(): Map<String, Any?>
    fun setStateListener(listener: ((Boolean) -> Unit)?)
}
```

Контракт с Dart-слоем (`VpnConnectRequest`, `VpnResult`) неизменен — это позволяет добавлять новые протоколы без правки кода на Flutter.

### Доступные движки

| Движок | Файл | Бэкенд | Протокол |
|--------|------|--------|----------|
| `WireGuardEngine` | `android/app/src/main/kotlin/com/bitplugg/vpn_client/WireGuardEngine.kt` | `com.wireguard.android.backend.GoBackend` | `wireguard` |
| `AmneziaWgEngine` | `android/app/src/main/kotlin/com/bitplugg/vpn_client/AmneziaWgEngine.kt` | `org.amnezia.awg.backend.GoBackend` | `amneziawg` |

### Процессный синглтон

Оба движка — процессные синглтоны. Это критически важно, потому что нативный `GoBackend` хранит туннель в памяти и сравнивает объекты `Tunnel` по ссылке. После пересоздания Activity новый экземпляр движка не смог бы распознать уже поднятый туннель. Синглтон гарантирует, что состояние туннеля сохраняется корректно.

### Как добавить новый протокол

1. Создать класс, реализующий `ProtocolEngine` (например, `VlessEngine`).
2. Добавить одну строку в `ProtocolEngineFactory.forProtocol()`:
   ```kotlin
   "vless" -> VlessEngine.get(context)
   ```
3. Dart-слой (`vpn_native_service.dart`, `connection_provider.dart`) не требует изменений — контракт MethodChannel неизменен.

### MethodChannel контракт

| Метод | Аргументы | Ответ |
|-------|-----------|-------|
| `connect` | `id`, `name`, `protocol`, `content`, `excludedApplications` или `includedApplications`, `dnsProtection`, `applyWarpDefaults` | `success(tunnelName)` или `error(code, message, null)` |
| `disconnect` | — | `success(null)` или `error(code, message, null)` |
| `getState` | — | `Map{status, tunnelName, alwaysOn, lockdown, rxBytes, txBytes, lastHandshakeMs}` |
| `hasVpnPermission` | — | `bool` |
| `openVpnSettings` | — | `success(null)` |

`EventChannel('mouvi/vpn_events')` присылает снимок состояния при подключении/отключении, а `EventChannel('mouvi/actions')` — действие `toggle` из плитки Quick Settings. Статистика трафика и время рукопожатия опрашиваются из Dart раз в 2 секунды, пока туннель поднят.

Коды ошибок: `unsupported_protocol`, `invalid_config`, `tunnel_start_failed`, `vpn_permission_denied`, `busy`, `native_unavailable`.

---

## 🚀 Быстрый старт

### Требования

* **Flutter** 3.47+
* **Dart** 3.13+
* **Android SDK** (compileSdk 35+, minSdk 24)
* **Kotlin** 1.9+
* **JDK** 17+

### Установка зависимостей

```bash
flutter pub get
```

### Локальная сборка

```bash
# Проверка кода
flutter analyze

# Сборка debug APK
flutter build apk --debug

# Установка на подключённое устройство
flutter install
```

### Сборка через GitHub Actions

Пуш в ветку `main` автоматически запускает workflow [`Android Build`](.github/workflows/android_build.yml), который:

1. Проверяет формат, запускает `flutter analyze` и Dart-тесты
2. Запускает нативные JUnit-тесты (`./gradlew :app:testDebugUnitTest`)
3. Собирает **debug APK**
4. Собирает **подписанные release APK** отдельно для `arm64-v8a` и `armeabi-v7a`
5. Публикует GitHub Release с обоими APK, SHA-256 и инструкцией по установке

### Подпись release APK

Для локальной подписи создайте файл `android/key.properties`:

```properties
storeFile=mouvi-release.jks
storePassword=your_store_password
keyAlias=your_key_alias
keyPassword=your_key_password
```

Файл `android/key.properties`, как и сам keystore, не коммитится (добавлены в `.gitignore`).

В GitHub Actions подпись берётся из secrets:

| Secret | Назначение |
|--------|------------|
| `ANDROID_KEYSTORE_BASE64` | keystore в base64 |
| `ANDROID_KEYSTORE_PASSWORD` | пароль хранилища |
| `ANDROID_KEY_ALIAS` | alias ключа |
| `ANDROID_KEY_PASSWORD` | пароль ключа |

Без этих secrets workflow собирает APK с debug-подписью и не публикует GitHub Release.

---

## 📁 Структура проекта

```
mouvi/
├── android/
│   ├── app/
│   │   ├── build.gradle.kts          # Зависимости: wireguard, amneziawg, подпись
│   │   └── src/main/kotlin/com/bitplugg/vpn_client/
│   │       ├── MainActivity.kt       # FlutterActivity, MethodChannel/EventChannel
│   │       ├── ProtocolEngine.kt     # Интерфейс движка
│   │       ├── ProtocolEngineFactory.kt  # Фабрика движков по протоколу
│   │       ├── WireGuardEngine.kt    # WireGuard реализация
│   │       ├── AmneziaWgEngine.kt    # AmneziaWG реализация
│   │       ├── RuntimeConfigAugmenter.kt # DNS, split tunneling, WARP
│   │       ├── EngineControl.kt      # Общее состояние/остановка обоих движков
│   │       ├── MouviTileService.kt   # Плитка Quick Settings
│   │       ├── MouviActionReceiver.kt # Кнопка «Отключить» в уведомлении
│   │       ├── MouviVpnEngine.kt     # VpnConnectRequest, VpnResult (контракт)
│   │       ├── MouviNotifications.kt # Системные уведомления
│   │       └── MouviSecureStorage.kt # Шифрованное хранилище конфигов
│   └── app/src/test/kotlin/...        # JUnit-тесты RuntimeConfigAugmenter
├── lib/
│   ├── core/
│   │   ├── services/
│   │   │   ├── vpn_native_service.dart   # MethodChannel/EventChannel обёртка
│   │   │   ├── config_export_service.dart # Экспорт через SAF
│   │   │   └── push_notification_service.dart
│   │   ├── models/
│   │   │   └── vpn_config.dart           # VpnConfig, VpnProtocolType
│   │   └── utils/
│   │       ├── config_parser.dart        # Парсинг конфигов
│   │       └── format_utils.dart         # Байты, рукопожатие, имя файла
│   ├── state/
│   │   ├── connection_provider.dart      # Состояние соединения и статистика
│   │   └── vpn_settings_provider.dart    # Split tunneling, DNS, автоподключение
│   └── ui/
│       ├── home/home_screen.dart         # Подключение, трафик, рукопожатие
│       ├── servers/servers_screen.dart   # Импорт, экспорт, меню сервера
│       ├── servers/qr_scan_screen.dart   # Сканирование QR-кода
│       └── settings/settings_screen.dart # Тема, язык, защита, split tunneling
├── test/
│   ├── config_parser_test.dart
│   ├── format_utils_test.dart
│   ├── localization_test.dart
│   ├── vpn_settings_test.dart
│   └── vpn_state_snapshot_test.dart
├── docs/
│   └── banner.svg
├── pubspec.yaml
├── analysis_options.yaml
├── README.md
└── LICENSE
```

---

## 🗺 Roadmap

Реализовано в 1.1.0: split tunneling в режимах «выключен / мимо VPN / только выбранные», защита DNS, автоподключение при запуске, импорт из файла/буфера/QR, экспорт конфига с предупреждением, статистика трафика и рукопожатия, плитка Quick Settings и кнопка «Отключить» в уведомлении, подписанные split-APK в CI.

- [ ] OpenVPN-движок (сейчас `.ovpn` только импортируется)
- [ ] Trojan / VLESS / Shadowsocks движки (сейчас только импорт)
- [ ] Поддержка iOS
- [ ] Поддержка Web

> Импорт конфигурации не означает, что протокол поддерживается движком. Для OpenVPN, Shadowsocks, VLESS и Trojan приложение честно показывает «Только импорт».

---

## 🤝 Вклад в проект

1. Сделайте форк репозитория
2. Создайте ветку для вашей функции (`git checkout -b feature/amazing-feature`)
3. Внесите изменения и закоммитьте их (`git commit -m 'feat: add amazing feature'`)
4. Запушьте в ветку (`git push origin feature/amazing-feature`)
5. Откройте Pull Request

Перед отправкой PR убедитесь, что:
* `flutter analyze` не выдаёт ошибок
* `flutter build apk --debug` проходит успешно
* Код следует стилю проекта (kotlin + dart linter)

---

## 📄 License

Пока без лицензии. Все права защищены.

---

## 📞 Контакты

* **GitHub**: https://github.com/bitplugg/mouvi
* **Автор**: bitplugg
