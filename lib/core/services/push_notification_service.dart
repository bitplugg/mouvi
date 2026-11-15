import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Native push notification service (FCM-ready).
///
/// Talks to the Kotlin side over the `mouvi/push` method channel:
/// - `isEnabled` / `setEnabled` — master switch.
/// - `notify` — connection state notifications (connected / disconnected).
class PushNotificationService {
  PushNotificationService();

  static const MethodChannel _channel = MethodChannel('mouvi/push');

  Future<bool> isEnabled() async {
    final enabled = await _channel.invokeMethod<bool>('isEnabled');
    return enabled ?? true;
  }

  Future<void> setEnabled(bool enabled) async {
    await _channel.invokeMethod<void>('setEnabled', <String, dynamic>{
      'enabled': enabled,
    });
  }

  Future<void> notify(String type, {String? serverName, String? protocol}) async {
    await _channel.invokeMethod<void>('notify', <String, dynamic>{
      'type': type,
      'serverName': serverName,
      'protocol': protocol,
    });
  }
}

final pushNotificationServiceProvider = Provider<PushNotificationService>((ref) => PushNotificationService());

class PushNotificationsEnabled extends Notifier<bool> {
  @override
  bool build() => true;

  void update(bool value) => state = value;
}

final pushNotificationsEnabledProvider = NotifierProvider<PushNotificationsEnabled, bool>(PushNotificationsEnabled.new);
