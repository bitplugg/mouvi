---
layout: default
title: Сборка проекта
---

# Сборка проекта

## Локальная сборка

```bash
# Установить зависимости
flutter pub get

# Проверить код
flutter analyze

# Собрать debug APK
flutter build apk --debug

# Установить на устройство
flutter install
```

## Сборка release APK

Для подписанного release APK создайте файл `android/key.properties`:

```properties
storeFile=mouvi-release.jks
storePassword=your_store_password
keyAlias=your_key_alias
keyPassword=your_key_password
```

Файл `android/key.properties` не коммитится (в `.gitignore`).

Затем:

```bash
flutter build apk --release
```

Результат: `build/app/outputs/flutter-apk/app-release.apk`

## GitHub Actions

Пуш в ветку `main` запускает workflow `.github/workflows/android_build.yml`:

1. `checks` — формат, анализ, тесты
2. `debug-apk` — сборка debug APK
3. `release-apk` — сборка release APK + публикация GitHub Release

Релиз создаётся автоматически с тегом `v<version_name>` из `pubspec.yaml` и развёрнутыми release notes.

## Требования

| Компонент | Версия |
|-----------|--------|
| Flutter | 3.47+ |
| Dart | 3.13+ |
| Android SDK | API 35+ (compile), API 24+ (min) |
| Kotlin | 1.9+ |
| JDK | 17 |
