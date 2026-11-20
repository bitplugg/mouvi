<p align="center">
  <img src="docs/banner.svg" alt="Mouvi" width="800">
</p>

# Mouvi

**Mouvi** — кастомный VPN-клиент для Android, собранный на Flutter.

Быстрый, лёгкий и расширяемый клиент с поддержкой WireGuard, AmneziaWG, Cloudflare WARP и VLESS, разделением туннелирования (split tunneling), защитой DNS, системой плагинов `.mu` и Material You 3 дизайном.

[![Android Build](https://github.com/bitplugg/mouvi/actions/workflows/android_build.yml/badge.svg)](https://github.com/bitplugg/mouvi/actions/workflows/android_build.yml)
[![Flutter](https://img.shields.io/badge/Flutter-3.47-0255BD?logo=flutter)](https://docs.flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Android-3DDC84?logo=android)](https://developer.android.com)
[![Riverpod](https://img.shields.io/badge/Riverpod-3-ff6f00?logo=flutter)](https://riverpod.dev)

---

## 📖 О проекте

Mouvi — это собственный VPN-клиент, разработанный с акцентом на простоту использования, надёжность и расширяемость. Приложение состоит из двух слоёв:

* **Dart (Flutter)** — пользовательский интерфейс, управление состоянием (Riverpod 3), импорт/парсинг конфигураций, система плагинов, локализация.
* **Kotlin (Android)** — нативный VPN/TUN-слой через `VpnService`, движки протоколов и связь с Flutter по `MethodChannel`/`EventChannel`.

Нативная часть построена вокруг интерфейса `ProtocolEngine`: протокол (WireGuard, AmneziaWG, VLESS и др.) добавляется отдельным движком и флагом поддержки в Dart-слое. Поверх этого реализована плагинная система (`.mu`) для расширения логики импорта, событий соединения, UI и адаптации подключений.

---

## ✨ Возможности

| Категория | Возможность | Статус |
|-----------|-------------|--------|
| **Протоколы** | WireGuard | ✅ Поддерживается |
| | AmneziaWG | ✅ Поддерживается (нужны H1–H4) |
| | WARP (Cloudflare) | ✅ Поддерживается как WireGuard |
| | VLESS (TCP/WS + TLS/Reality) | ✅ Через Xray-core + tun2socks |
| | OpenVPN | 📋 Подключение планируется (сейчас импорт) |
| | Trojan / Shadowsocks | 📋 Подключение планируется (сейчас импорт) |
| **Импорт конфигураций** | Файл `.conf` / `.ovpn` / JSON / URI / текст | ✅ Импорт и проверка |
| | Вставка текста из буфера обмена | ✅ |
| | Сканирование QR-кода камерой | ✅ |
| | Экспорт конфига в файл | ✅ С предупреждением о приватном ключе |
| | Обработка импорта плагинами (декларативно и runtime) | ✅ |
| **Защита и туннелирование** | Kill switch | ⛔ Только системный Always-on VPN |
| | Split tunneling: выключен / мимо VPN / только выбранные | ✅ UI + движок |
| | DNS protection | ✅ UI + движок |
| | Автоподключение при запуске | ✅ Только при уже выданном VPN-разрешении |
| **Плагины** | Формат `.mu` (ZIP + `manifest.json`), установка из файла/URL/каталога | ✅ |
| | Каталог плагинов `mouvi-store`, обновление и удаление | ✅ |
| | Runtime-код плагина (JavaScript, QuickJS) и хуки | ✅ |
| | UI-расширения плагинов в настройках | ✅ |
| | Метаданные: автор, версии, разрешения, источник, SHA-256, обновления | ✅ |
| **Интерфейс** | Material You 3 (Expressive) | ✅ |
| | Динамическая тема из обоев | ✅ |
| | Русский / английский языки | ✅ |
| | Статистика трафика и рукопожатия | ✅ Обновление раз в 2 секунды |
| **Уведомления и обновления** | Состояние соединения и действие «Отключить» | ✅ |
| | Плитка Quick Settings | ✅ |
| | Проверка обновлений приложения и установка/скачивание из релиза | ✅ |
| **Сборка** | GitHub Actions → подписанные split-APK + Release | ✅ |

> Импорт конфигурации не означает, что протокол поддерживается нативным движком. Для неподдерживаемых форматов приложение может предложить обработку активными плагинами (распознавание, трансформация или адаптация к поддерживаемому движку).

---

## 🧩 Система плагинов (`.mu`)

Mouvi поддерживает плагины в едином формате **`.mu`** — ZIP-архив, содержащий `manifest.json`, опциональный runtime-код, ресурсы и документацию.

Подробная спецификация: [`HOW_WRITE_PLUGIN.md`](HOW_WRITE_PLUGIN.md).

### Возможности

- **Установка и управление:** из локального файла, по URL или из каталога магазина; обновление (повторная установка того же `id`), включение/выключение, удаление.
- **Официальный каталог:** [bitplugg/mouvi-store](https://github.com/bitplugg/mouvi-store) (`index.json` на `master`). Плагины из официального источника считаются доверенными источником установки.
- **Базовый плагин:** `mouvi-engine` — встроенный системный плагин, его нельзя удалить. Если `mouvi-engine` отключён, хуки и работа остальных плагинов приостанавливаются.
- **Runtime-код:** JavaScript в QuickJS (`flutter_js`, AOT-совместимо) с точкой входа `entry` (например `main.js`), синхронными хуками и изоляцией ошибок (сбой плагина не должен ломать приложение/импорт/соединение).
- **Собственное хранилище:** персистентное хранилище плагина при разрешении `ownStorage`.
- **UI-расширения:** плагины могут отдавать декларативные экраны/элементы и обрабатывать действия пользователя в разделе плагинов.

### Поддерживаемые хуки (API v1)

| Хук | Назначение |
|-----|------------|
| `importValidation` | Распознавание, валидация и (опционально) трансформация импортируемого конфига. Поддерживаются декларативные `importRules` и runtime-хук `onImportValidate`. |
| `connectionEvents` | События жизненного цикла подключения (`beforeConnect`, `afterConnect`, `disconnect`, `connectError`, `networkChange`). |
| `uiExtensions` | Получение UI-расширений (`getUiExtensions`) и обработка действий (`onUiAction`). |
| `uriHandlers` | Обработка URI/ссылок (`handleUri`, контракт/интеграция по сценарию). |
| `engineProvider` | Подготовка/адаптация подключения (`prepareEngineConnection`) для неподдерживаемых форматов. |

### Движки-плагины (адаптеры)

Текущий VPN/TUN-стек и движки реализованы нативно (Kotlin/Go/Xray через `VpnService` и `MethodChannel`). **Произвольная динамическая загрузка нативного/бинарного движка из `.mu` в рантайме не поддерживается.**

Хук `engineProvider` предназначен для **адаптера/трансформации**: плагин может разобрать свой формат и вернуть конфиг для **поддерживаемого нативного движка** (`wireguard`, `amneziawg`, `vless`), который затем подключается обычным стеком Mouvi. Полноценный контракт для сторонних нативных/TUN-движков требует отдельной проработки.

### Безопасность и метаданные

- Плагины не из официального `mouvi-store` перед активацией требуют подтверждения: **«Я согласен со всеми рисками»**.
- В UI управления плагинами отображаются: автор, версия плагина, версия API, минимальная версия приложения, версия приложения пользователя, запрашиваемые разрешения, хуки/runtime, источник загрузки и SHA-256 хэш файла `.mu`.
- Для плагинов из каталога выполняется проверка обновлений (сравнение версий с `index.json`): при наличии обновления показывается доступная версия и описание/«что нового» из каталога, с возможностью обновить.

### Инструменты разработчика плагинов

- **CLI `mouvi-builder`** (`tool/mouvi_builder.dart`, обёртки `./mouvi-builder`, `mouvi-builder.bat`): `init` (шаблон, опция `--with-code`), `validate`, `build` упаковка в `.mu`.
- **Документация:** [`HOW_WRITE_PLUGIN.md`](HOW_WRITE_PLUGIN.md).
- **Эталон:** `examples/plugins/hello-import/` (runtime-пример: import, события, UI, engine-адаптер stub, URI) и собранный `.mu`.

Пример сборки:

```bash
./mouvi-builder init ./my-plugin --id com.example.myplugin --name "My Plugin" --with-code
./mouvi-builder validate ./my-plugin
./mouvi-builder build ./my-plugin -o ./my-plugin.mu
```

---

## 🏗 Архитектура

### Стек технологий

| Слой | Технологии |
|------|------------|
| **Frontend** | Flutter 3.47+, Dart 3.13, Material 3 (Expressive) |
| **State management** | Riverpod 3 |
| **Плагины** | `.mu` (ZIP), `manifest.json`, QuickJS runtime (`flutter_js`), декларативные `importRules` |
| **Платформенный канал** | `MethodChannel` (`mouvi/vpn`), `EventChannel` (`mouvi/vpn_events`, `mouvi/actions`) |
| **VPN-движок (Android)** | Нативный Kotlin, интерфейс `ProtocolEngine` |
| **WireGuard бэкенд** | `com.wireguard.android:tunnel:1.0.20260102` |
| **AmneziaWG бэкенд** | `com.zaneschepke:amneziawg-android:2.3.7` |
| **VLESS бэкенд** | Xray-core (SOCKS5) + tun2socks + `MouviVpnService` |
| **Сборка** | Gradle, GitHub Actions |

### Схема взаимодействия

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter (Dart, Riverpod)                 │
│  UI / Plugins / Import / Connection                         │
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
│  │ "vless"      │─►│ VlessEngine (синглтон)              │ │
│  │ else         │─►│ null → VpnResult.Failure(...)       │ │
│  └──────────────┘  └─────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

`EngineControl` читает состояние и останавливает движки корректно после пересоздания Activity или вызова из уведомления/плитки, когда активный протокол заранее неизвестен.

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

Контракт с Dart-слоем (`VpnConnectRequest`, `VpnResult`) сохраняется — новые нативные протоколы добавляются без правки Flutter-логики подключения.

### Доступные нативные движки

| Движок | Файл | Бэкенд | Протокол |
|--------|------|--------|----------|
| `WireGuardEngine` | `android/app/src/main/kotlin/com/bitplugg/vpn_client/WireGuardEngine.kt` | `com.wireguard.android.backend.GoBackend` | `wireguard` |
| `AmneziaWgEngine` | `android/app/src/main/kotlin/com/bitplugg/vpn_client/AmneziaWgEngine.kt` | `org.amnezia.awg.backend.GoBackend` | `amneziawg` |
| `VlessEngine` | `android/app/src/main/kotlin/com/bitplugg/vpn_client/VlessEngine.kt` | Xray-core (SOCKS5) + tun2socks + `MouviVpnService` | `vless` |

### Процессный синглтон

Движки — процессные синглтоны. Для WireGuard/AmneziaWG это важно, так как нативный `GoBackend` хранит туннель в памяти и сравнивает объекты `Tunnel` по ссылке. Для VLESS синглтон хранит процессы Xray/tun2socks и состояние сервиса. После пересоздания Activity состояние восстанавливается корректно.

### Как добавить новый нативный протокол

1. Создать класс, реализующий `ProtocolEngine` (пример — `VlessEngine`).
2. Добавить строку в `ProtocolEngineFactory.forProtocol()`.
3. Отметить протокол как поддерживаемый в `VpnProtocolTypeX.engineSupported` и добавить валидацию в `config_parser.dart`.
4. MethodChannel-контракт менять не нужно.

### MethodChannel контракт

| Метод | Аргументы | Ответ |
|-------|-----------|-------|
| `connect` | `id`, `name`, `protocol`, `content`, `excludedApplications` или `includedApplications`, `dnsProtection`, `applyWarpDefaults` | `success(tunnelName)` или `error(code, message, null)` |
| `disconnect` | — | `success(null)` или `error(code, message, null)` |
| `getState` | — | `Map{status, tunnelName, alwaysOn, lockdown, rxBytes, txBytes, lastHandshakeMs}` |
| `hasVpnPermission` | — | `bool` |
| `openVpnSettings` | — | `success(null)` |

`EventChannel('mouvi/vpn_events')` присылает снимок состояния при подключении/отключении, а `EventChannel('mouvi/actions')` — действие `toggle` из плитки Quick Settings. Статистика трафика и время рукопожатия опрашиваются из Dart раз в 2 секунды, пока туннель поднят.

Типичные коды ошибок: `unsupported_protocol`, `invalid_config`, `tunnel_start_failed`, `vpn_permission_denied`, `busy`, `native_unavailable`.

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
flutter test

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
├── android/                               # Android-приложение, нативные VPN-движки, тесты
│   └── app/src/main/kotlin/com/bitplugg/vpn_client/
│       ├── MainActivity.kt
│       ├── ProtocolEngine.kt
│       ├── ProtocolEngineFactory.kt
│       ├── WireGuardEngine.kt
│       ├── AmneziaWgEngine.kt
│       ├── VlessEngine.kt
│       └── ...
├── lib/
│   ├── core/
│   │   ├── models/                        # Модели конфигов и состояния
│   │   ├── plugins/                       # Модели, runtime (QuickJS), реестр хуков плагинов
│   │   ├── services/                      # VPN, OTA/обновления, плагины, экспорт и др.
│   │   └── utils/                         # Парсинг конфигов, форматирование
│   ├── state/                             # Riverpod-провайдеры (соединение, настройки, плагины)
│   └── ui/                                # Экраны: home, servers, settings, плагины, UI-расширения
├── tool/
│   └── mouvi_builder.dart                 # CLI для сборки/валидации/инициализации .mu
├── examples/
│   └── plugins/hello-import/              # Эталонный runtime-плагин (+ .mu)
├── docs/
│   └── banner.svg
├── HOW_WRITE_PLUGIN.md                    # Спецификация и руководство по плагинам
├── mouvi-builder                          # Обёртка для запуска mouvi-builder (Unix)
├── mouvi-builder.bat                      # Обёртка для запуска mouvi-builder (Windows)
├── pubspec.yaml
├── analysis_options.yaml
├── README.md
└── LICENSE
```

---

## 🗺 Roadmap

Реализовано (актуально): WireGuard/AmneziaWG/WARP/VLESS (TCP/WS + TLS/Reality), split tunneling, защита DNS, автоподключение, импорт из файла/буфера/QR, экспорт, статистика трафика и рукопожатия, Quick Settings/уведомления, проверка и установка обновлений приложения, система плагинов `.mu` (runtime JS, UI-расширения, engine-адаптеры, магазин `mouvi-store`, метаданные и проверка обновлений плагинов), подписанные split-APK в CI.

- [ ] OpenVPN-движок (сейчас `.ovpn` только импортируется)
- [ ] Trojan / Shadowsocks движки (сейчас только импорт)
- [ ] Дополнительные VLESS-транспорты (gRPC, QUIC, HTTP Upgrade)
- [ ] Расширенный контракт для нативных/TUN-движков из плагинов (при проработке безопасности)
- [ ] Поддержка iOS
- [ ] Поддержка Web

---

## 🤝 Вклад в проект

1. Сделайте форк репозитория
2. Создайте ветку для вашей функции (`git checkout -b feature/amazing-feature`)
3. Внесите изменения и закоммитьте их (`git commit -m 'feat: add amazing feature'`)
4. Запушьте в ветку (`git push origin feature/amazing-feature`)
5. Откройте Pull Request

Перед отправкой PR убедитесь, что:
* `dart format .` выполнен
* `flutter analyze` не выдаёт ошибок
* `flutter test` проходит успешно
* код соответствует стилю проекта (Kotlin + Dart linter)

---

## 📄 License

Пока без лицензии. Все права защищены.

---

## 📞 Контакты

* **GitHub**: https://github.com/bitplugg/mouvi
* **Плагины (каталог)**: https://github.com/bitplugg/mouvi-store
* **Автор**: bitplugg
