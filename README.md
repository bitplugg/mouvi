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
- **WireGuard**
- **AmneziaWG** (экспериментальные/производные конфигурации Amnezia)
- **OpenVPN**
- **Trojan** и подобные (VLESS, Shadowsocks и др.)

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

- **Frontend**: Flutter + Material 3 (Expressive), динамическая тема
- **State**: Riverpod 3
- **VPN engine**: нативный (BoringWrapper / WireGuard / AmneziaWG / OpenVPN / Trojan / Shadowsocks / VLESS) через MethodChannel
- **Сборка**: GitHub Actions → APK + Release

---

## 🗺 Roadmap

- [ ] Полноценный нативный VPN-движок (BoringWrapper и форки)
- [ ] Split tunneling UI
- [ ] DNS protection UI
- [ ] Push-уведомления (FCM)
- [ ] Dark/Light авто-тема из обоев
- [ ] Более форматы конфигураций
- [ ] Web / iOS

---

## 📄 License

Пока без лицензии. Все права защищены.
