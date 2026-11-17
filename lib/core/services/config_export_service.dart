import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Сохранение конфигурации в файл через системный диалог Android.
///
/// Канал `mouvi/export`:
/// - `saveConfig` → `true`, если пользователь сохранил файл;
///   `false`, если отменил выбор; ошибка — если запись не удалась.
///
/// Приватные ключи не покидают приложение без явного действия
/// пользователя: файл создаётся только по нажатию «Экспорт».
class ConfigExportService {
  const ConfigExportService();

  static const MethodChannel _channel = MethodChannel('mouvi/export');

  Future<bool> saveConfig({
    required String fileName,
    required String content,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('saveConfig', {
        'fileName': fileName,
        'content': content,
      });
      return result ?? false;
    } on MissingPluginException {
      throw const ConfigExportException('native_unavailable');
    } on PlatformException catch (error) {
      throw ConfigExportException(error.code, details: error.message);
    }
  }
}

class ConfigExportException implements Exception {
  const ConfigExportException(this.code, {this.details});

  final String code;
  final String? details;

  @override
  String toString() => 'ConfigExportException($code)';
}

final configExportServiceProvider = Provider<ConfigExportService>(
  (ref) => const ConfigExportService(),
);
