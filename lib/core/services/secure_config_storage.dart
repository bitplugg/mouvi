import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Зашифрованное хранилище конфигураций.
///
/// Конфиги содержат приватные ключи, поэтому на Android они сохраняются
/// в SharedPreferences только в зашифрованном виде: ключ AES-256-GCM
/// генерируется и хранится в Android Keystore (не покидает устройство).
///
/// Канал `mouvi/storage`:
/// - `read` → `String?` — расшифрованные данные или `null`;
/// - `write` — зашифровать и сохранить строку;
/// - `clear` — удалить сохранённые данные (используется только по явному
///   действию пользователя, не автоматически).
class SecureConfigStorage {
  const SecureConfigStorage();

  static const MethodChannel _channel = MethodChannel('mouvi/storage');

  Future<String?> read() async {
    try {
      return await _channel.invokeMethod<String>('read');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<bool> write(String data) async {
    try {
      await _channel.invokeMethod<void>('write', <String, dynamic>{
        'data': data,
      });
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> clear() async {
    try {
      await _channel.invokeMethod<void>('clear');
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

final secureConfigStorageProvider = Provider<SecureConfigStorage>(
  (ref) => const SecureConfigStorage(),
);
