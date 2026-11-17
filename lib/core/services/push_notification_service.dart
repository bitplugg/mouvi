import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Локальные уведомления о состоянии соединения.
///
/// Канал `mouvi/push`:
/// - `isEnabled` / `setEnabled` — мастер-переключатель;
/// - `requestPermission` — запрос POST_NOTIFICATIONS (Android 13+);
/// - `notify` — показать уведомление о подключении/отключении.
class PushNotificationService {
  const PushNotificationService();

  static const MethodChannel _channel = MethodChannel('mouvi/push');

  Future<bool> isEnabled() async {
    try {
      final enabled = await _channel.invokeMethod<bool>('isEnabled');
      return enabled ?? true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> setEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setEnabled', <String, dynamic>{
        'enabled': enabled,
      });
    } on MissingPluginException {
      // Нативная часть недоступна — не роняем настройки.
    } on PlatformException {
      // Игнорируем: уведомления не критичны для VPN.
    }
  }

  Future<bool> requestPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> notify(
    String type, {
    String? serverName,
    String? protocol,
    String? title,
    String? text,
    String? disconnectAction,
  }) async {
    try {
      await _channel.invokeMethod<void>('notify', <String, dynamic>{
        'type': type,
        'serverName': serverName,
        'protocol': protocol,
        'title': title,
        'text': text,
        'disconnectAction': disconnectAction,
      });
    } on MissingPluginException {
      // Уведомления не должны ломать подключение.
    } on PlatformException {
      // Игнорируем ошибку показа уведомления.
    }
  }
}

final pushNotificationServiceProvider = Provider<PushNotificationService>(
  (ref) => const PushNotificationService(),
);

class PushNotificationsEnabled extends Notifier<bool> {
  static const String _prefsKey = 'mouvi.notifications.enabled';

  bool _userChanged = false;

  @override
  bool build() {
    unawaited(_load());
    return false;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!ref.mounted || _userChanged) {
        return;
      }
      final enabled = prefs.getBool(_prefsKey) ?? false;
      state = enabled;
      await ref.read(pushNotificationServiceProvider).setEnabled(enabled);
    } catch (_) {
      // Оставляем значение по умолчанию.
    }
  }

  Future<void> update(bool value) async {
    _userChanged = true;
    state = value;
    await ref.read(pushNotificationServiceProvider).setEnabled(value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, value);
    } catch (_) {
      // Настройка всё равно применилась на этот запуск.
    }
  }
}

final pushNotificationsEnabledProvider =
    NotifierProvider<PushNotificationsEnabled, bool>(
      PushNotificationsEnabled.new,
    );
