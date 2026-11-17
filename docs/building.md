---
layout: default
title: Сборка проекта
---

# Сборка проекта

## Локальная сборка

```bash
# Установить зависимости
flutter pub get

# Проверить формат и код
dart format --output=none --set-exit-if-changed lib test
flutter analyze

# Dart-тесты
flutter test

# Нативные JUnit-тесты
cd android && ./gradlew :app:testDebugUnitTest && cd ..

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

Keystore положите в `android/app/mouvi-release.jks`. И файл, и keystore
добавлены в `.gitignore` — их нельзя коммитить.

Затем:

```bash
flutter build apk --release --split-per-abi
```

Результат:

```
build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
```

Отдельные APK для каждой ABI уменьшают размер загрузки. Универсальный APK
намеренно не собирается.

### Обновление с 1.0.0

Версия 1.0.0 была подписана debug-ключом. Android не позволит обновить её
release-сборкой: приложение нужно один раз удалить и установить заново.
Конфигурации хранятся на устройстве, поэтому перед удалением экспортируйте
нужные профили.

## GitHub Actions

Пуш в ветку `main` запускает workflow `.github/workflows/android_build.yml`:

1. `checks` — формат, анализ, Dart-тесты
2. `android-unit-tests` — JUnit-тесты нативного слоя
3. `debug-apk` — сборка debug APK
4. `release-apk` — сборка подписанных split-APK + публикация GitHub Release

Релиз создаётся автоматически с тегом `v<version_name>` из `pubspec.yaml` и
release notes, включающими SHA-256 файлов и предупреждение о миграции с 1.0.0.

### Secrets для подписи

| Secret | Назначение |
|--------|------------|
| `ANDROID_KEYSTORE_BASE64` | keystore в base64 (`base64 -w0 mouvi-release.jks`) |
| `ANDROID_KEYSTORE_PASSWORD` | пароль хранилища |
| `ANDROID_KEY_ALIAS` | alias ключа |
| `ANDROID_KEY_PASSWORD` | пароль ключа |

Если secrets не заданы, workflow соберёт APK с debug-подписью, но не будет
публиковать GitHub Release.

## Требования

| Компонент | Версия |
|-----------|--------|
| Flutter | 3.47+ |
| Dart | 3.13+ |
| Android SDK | API 35+ (compile), API 24+ (min) |
| Kotlin | 1.9+ |
| JDK | 17 |
