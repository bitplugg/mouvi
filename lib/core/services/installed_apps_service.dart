import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Установленное приложение для выбора в split tunneling.
class InstalledApp {
  const InstalledApp({required this.packageName, required this.label});

  factory InstalledApp.fromChannel(Object? value) {
    if (value is! Map) {
      throw const FormatException('Invalid installed app entry');
    }
    final packageName = value['package']?.toString();
    if (packageName == null || packageName.isEmpty) {
      throw const FormatException('Invalid installed app entry');
    }
    final label = value['label']?.toString();
    return InstalledApp(
      packageName: packageName,
      label: label == null || label.isEmpty ? packageName : label,
    );
  }

  final String packageName;
  final String label;
}

/// Доступ к списку установленных приложений через канал `mouvi/apps`.
class InstalledAppsService {
  const InstalledAppsService();

  static const MethodChannel _channel = MethodChannel('mouvi/apps');

  Future<List<InstalledApp>> listApps() async {
    try {
      final result = await _channel.invokeMethod<List<Object?>>('listApps');
      if (result == null) {
        return const <InstalledApp>[];
      }
      final apps = <InstalledApp>[];
      for (final entry in result) {
        try {
          apps.add(InstalledApp.fromChannel(entry));
        } on FormatException {
          // Пропускаем некорректную запись, остальные показываем.
        }
      }
      return apps;
    } on MissingPluginException {
      throw const VpnEngineUnavailableException();
    } on PlatformException catch (error) {
      throw InstalledAppsException(error.message ?? error.code);
    }
  }
}

class InstalledAppsException implements Exception {
  const InstalledAppsException(this.message);

  final String message;

  @override
  String toString() => 'InstalledAppsException($message)';
}

class VpnEngineUnavailableException implements Exception {
  const VpnEngineUnavailableException();
}

final installedAppsServiceProvider = Provider<InstalledAppsService>(
  (ref) => const InstalledAppsService(),
);
