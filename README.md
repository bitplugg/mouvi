<p align="center">
  <img src="docs/banner.svg" alt="Mouvi" width="800">
</p>

# Mouvi

**Mouvi** — кастомный VPN-клиент для Android, собранный на Flutter.

Быстрый, лёгкий и красивый клиент с поддержкой современных VPN-протоколов и Material You 3.

[![Android Build](https://github.com/bitplugg/mouvi/actions/workflows/android_build.yml/badge.svg)](https://github.com/bitplugg/mouvi/actions/workflows/android_build.yml)
[![Flutter](https://img.shields.io/badge/Flutter-3.47-0255BD?logo=flutter)](https://docs.flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Android-3DDC84?logo=android)](https://developer.android.com)

---

## ✨ Возможности

### Протоколы

| Протокол | Статус | Движок |
|----------|--------|--------|
| **WireGuard** | ✅ Поддерживается | `WireGuardEngine` (`com.wireguard.android:tunnel`) |
| **AmneziaWG** | ✅ Поддерживается | `AmneziaWgEngine` (`com.zaneschepke:amneziawg-android:2.3.7`) |
| **OpenVPN** | 📋 Планируется | — |
| **Trojan** и podobные (VLESS, Shadowsocks и др.) | 📋 Планируется | — |

### Импорт конфигураций

- Файлы **`.ovpn`**
- **Shadowsocks** JSON
- **VLESS** конфигурации

### Защитные функции (полный пакет)

- **Kill switch** — при отключении VPN весь трафик блокируется
- **Split tunneling** — выбор, какие приложения идут через VPN
- **DNS protection** — защита DNS-запросов

### Дизайн

- **Material You 3** (Expressive) + авто-тема из обоев устройства
- Кастомная иконка и фирменный стиль

### Интерфейс

- Русский и английский языки (переключатель в настройках)

### Уведомления

- Push-уведомления: включение / отключение / состояние соединения

### Сборка

- Весь процесс сборки — через **GitHub Actions** (workflow)

---

## 📸 Баннер

<p align="center">
  <img src="docs/banner.svg" alt="Mouvi Banner" width="600">
</p>

---

## 🚀 Быстрый старт

### Требования

- Flutter 3.47+
- Android SDK (API 35+)
- Kotlin

### Сборка

#### Через GitHub Actions (рекомендуется)

Пуш в ветку `main` автоматически запускает workflow [`Android Build`](.github/workflows/android_build.yml), который:

1. Устанавливает Flutter
2. Настраивает Android SDK
3. Выполняет `flutter pub get`
4. Запускает `flutter analyze`
5. Собирает **debug APK**
6. Загружает артефакт и создаёт **GitHub Release** со сгенерированными release notes

#### Локальная сборка

```bash
flutter pub get
flutter analyze
flutter build apk --debug
```

### Установка на Android

1. Установите APK
2. Разрешите **VPN-права** в системе (терминальное приложение или экран VPN)
3. Импортируйте конфигурацию (.ovpn / JSON / VLESS)
4. Подключитесь

---

## 🏗 Архитектура

### Стек

| Слой | Технологии |
|------|------------|
| **Frontend** | Flutter + Material 3 (Expressive), динамическая тема |
| **State management** | Riverpod 3 |
| **Платформенный канал** | Flutter MethodChannel (`mouvi/vpn`, `mouvi/vpn_events`) |
| **VPN-движок (Android)** | Нативный Kotlin, абстракция `ProtocolEngine` |

### VPN-движок (нативная часть, Android)

Движок вынесен за интерфейс `ProtocolEngine`, чтобы легко добавлять новые протоколы без изменения Dart-слоя.

```
MainActivity (MethodChannel «mouvi/vpn»)
    │
    ├── connect(request) ──► ProtocolEngineFactory.forProtocol(protocol)
    │                          │
    │              ┌───────────┴───────────┐
    │              ▼                       ▼
    │         "wireguard"               "amneziawg"
    │              │                       │
    │              ▼                       ▼
    │        WireGuardEngine            AmneziaWgEngine
    │        (com.wireguard.android)    (com.zaneschepke:amneziawg-android)
    │              │                       │
    │              ▼                       ▼
    │        GoBackend.setState(UP)     GoBackend.setState(UP)
```

#### Классы

| Класс | Файл | Описание |
|-------|------|----------|
| `ProtocolEngine` | `android/app/src/main/kotlin/com/bitplugg/vpn_client/ProtocolEngine.kt` | Интерфейс движка: `connect`, `disconnect`, `getState`, `currentStateMap`, `setStateListener` |
| `WireGuardEngine` | `…/WireGuardEngine.kt` | Реализация для WireGuard через `com.wireguard.android.backend.GoBackend` |
| `AmneziaWgEngine` | `…/AmneziaWgEngine.kt` | Реализация для AmneziaWG через `org.amnezia.awg.backend.GoBackend` |
| `ProtocolEngineFactory` | `…/ProtocolEngineFactory.kt` | Фабрика: возвращает движок по имени протокола или `null` |
| `VpnConnectRequest` / `VpnResult` | `…/MouviVpnEngine.kt` | Контракт данных с Dart-слоем (MethodChannel) |

#### Процессный синглтон

Оба движка (`WireGuardEngine`, `AmneziaWgEngine`) — процессные синглтоны. Это важно, потому что нативный `GoBackend` хранит туннель в памяти и сравнивает объекты `Tunnel` по ссылке. После пересоздания Activity новый экземпляр движка не смог бы распознать уже поднятый туннель.

#### Как добавить новый протокол

1. Создать класс, реализующий `ProtocolEngine`.
2. Добавить одну строку в `ProtocolEngineFactory.forProtocol()`:
   ```kotlin
   "vless" -> VlessEngine.get(context)
   ```
3. Dart-слой (`vpn_native_service.dart`) не требует изменений — контракт MethodChannel неизменен.

---

## 🗺 Roadmap

- [ ] Split tunneling UI
- [ ] DNS protection UI
- [ ] Push-уведомления (FCM)
- [ ] Dark/Light авто-тема из обоев
- [ ] OpenVPN-движок
- [ ] Trojan / VLESS / Shadowsocks движки
- [ ] Web / iOS

---

## 📄 License

Пока без лицензии. Все права защищены.
