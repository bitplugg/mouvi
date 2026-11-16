---
layout: default
title: Добавление нового протокола
---

# Как добавить новый VPN-протокол

Добавление нового протокола в Mouvi занимает три шага.

## Шаг 1: Создать класс движка

Создать новый файл `android/app/src/main/kotlin/com/bitplugg/vpn_client/VlessEngine.kt`:

```kotlin
package com.bitplugg.vpn_client

import android.content.Context
import org.amnezia.awg.backend.GoBackend // или другой бэкенд
import java.util.concurrent.Executors

class VlessEngine private constructor(context: Context) : ProtocolEngine {
    // Реализовать connect, disconnect, getState, setStateListener
    
    companion object {
        @Volatile private var instance: VlessEngine? = null
        fun get(context: Context): VlessEngine {
            return instance ?: synchronized(this) {
                instance ?: VlessEngine(context).also { instance = it }
            }
        }
    }
}
```

## Шаг 2: Зарегистрировать в фабрике

В `ProtocolEngineFactory.kt` добавить одну строку:

```kotlin
fun forProtocol(protocol: String, context: Context): ProtocolEngine? = when (protocol) {
    "wireguard" -> WireGuardEngine.get(context)
    "amneziawg" -> AmneziaWgEngine.get(context)
    "vless" -> VlessEngine.get(context)   // ← новая строка
    else -> null
}
```

## Шаг 3: Включить протокол в Dart-слое

В `lib/core/models/vpn_config.dart` добавить протокол в `VpnProtocolType.engineSupported`, проверить подпись (`labelKey`), импорт конфигурации и тесты. Контракт `MethodChannel` при этом не меняется.

## Шаг 4: Проверить сборку

```bash
dart format lib test
flutter analyze
flutter test
flutter build apk --debug
```
