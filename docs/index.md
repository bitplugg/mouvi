---
layout: default
title: Mouvi
---

# Mouvi

**Кастомный VPN-клиент для Android на Flutter.**

Быстрый, лёгкий и современный клиент с поддержкой WireGuard и AmneziaWG, разделением туннелирования, защитой DNS и Material You 3 дизайном.

Поддерживаются импорт из файла, буфера обмена и QR-кода, экспорт конфига, статистика трафика и рукопожатий, плитка Quick Settings и кнопка отключения в уведомлении.

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
| VLESS (TCP/WS + TLS/Reality) | ✅ Через Xray-core + tun2socks |
| OpenVPN | 📋 Импорт есть, подключение планируется |
| Trojan / Shadowsocks | 📋 Импорт есть, подключение планируется |

---

## 🚀 Быстрый старт

### Требования

- Android 7.0+ (API 24+)
- Разрешение на VPN в системе

### Установка

1. Скачайте APK из [GitHub Releases](https://github.com/bitplugg/mouvi/releases/latest): `arm64-v8a` для большинства современных устройств или `armeabi-v7a` для старых
2. Установите APK
3. Разрешите VPN-права в настройках
4. Импортируйте WireGuard/AmneziaWG/WARP-конфигурацию
5. Подключитесь

VLESS подключается через Xray-core: поддерживаются TCP/WS и TLS/Reality. OpenVPN, Shadowsocks и Trojan пока импортируются без подключения.

> Если у вас установлена версия 1.0.0 (debug-подпись), её нужно один раз удалить перед установкой 1.1.0: Android не разрешает обновление другим ключом. Перед удалением экспортируйте нужные конфигурации.

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
| VLESS backend | Xray-core (SOCKS5) + tun2socks + `MouviVpnService` |

---

## 📖 Документация

- [Архитектура VPN-движка](architecture.md)
- [Как добавить новый протокол](adding-protocol.md)
- [Сборка проекта](building.md)

---

## 🗺 Roadmap

- [x] Split tunneling UI (выключен / мимо VPN / только выбранные)
- [x] DNS protection UI
- [x] Локальные уведомления о состоянии соединения
- [x] Плитка Quick Settings и кнопка «Отключить» в уведомлении
- [x] Импорт из буфера обмена и QR-кода, экспорт конфига
- [x] VLESS-движок (TCP/WS + TLS/Reality)
- [ ] OpenVPN-движок
- [ ] Trojan / Shadowsocks движки
- [ ] Поддержка iOS
- [ ] Поддержка Web

---

*Сделано с ❤️ bitplugg*
