---
layout: default
title: Mouvi
---

# Mouvi

**Кастомный VPN-клиент для Android на Flutter.**

Быстрый, лёгкий и современный клиент с поддержкой WireGuard и AmneziaWG, разделением туннелирования, защитой DNS и Material You 3 дизайном.

[![Android Build](https://github.com/bitplugg/mouvi/actions/workflows/android_build.yml/badge.svg)](https://github.com/bitplugg/mouvi/actions/workflows/android_build.yml)

---

## 📥 Скачать

### Последняя версия

[Скачать APK (GitHub Releases)](https://github.com/bitplugg/mouvi/releases/latest)

При первой установке потребуется разрешить **VPN-права** в настройках системы.

### Поддерживаемые протоколы

| Протокол | Статус |
|----------|--------|
| WireGuard | ✅ |
| AmneziaWG | ✅ (нужны H1–H4) |
| WARP (Cloudflare) | ✅ как WireGuard |
| OpenVPN | 📋 Импорт есть, подключение планируется |
| Trojan / VLESS / Shadowsocks | 📋 Импорт есть, подключение планируется |

---

## 🚀 Быстрый старт

### Требования

- Android 7.0+ (API 24+)
- Разрешение на VPN в системе

### Установка

1. Скачайте APK из [GitHub Releases](https://github.com/bitplugg/mouvi/releases/latest)
2. Установите APK
3. Разрешите VPN-права в настройках
4. Импортируйте WireGuard/AmneziaWG/WARP-конфигурацию
5. Подключитесь

OpenVPN, Shadowsocks, VLESS и Trojan пока импортируются без подключения.

---

## 🏗 Архитектура

| Слой | Технологии |
|------|------------|
| Frontend | Flutter 3.47, Dart 3.13, Material 3 |
| State management | Riverpod 3 |
| Platform channel | Flutter MethodChannel |
| VPN engine | Native Kotlin (`ProtocolEngine`) |
| WireGuard backend | `com.wireguard.android:tunnel` |
| AmneziaWG backend | `com.zaneschepke:amneziawg-android` |

---

## 📖 Документация

- [Архитектура VPN-движка](architecture.md)
- [Как добавить новый протокол](adding-protocol.md)
- [Сборка проекта](building.md)

---

## 🗺 Roadmap

- [ ] Split tunneling UI
- [ ] DNS protection UI
- [ ] Push-уведомления (FCM)
- [ ] OpenVPN-движок
- [ ] Trojan / VLESS / Shadowsocks движки
- [ ] Поддержка iOS
- [ ] Поддержка Web

---

*Сделано с ❤️ bitplugg*
