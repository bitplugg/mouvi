import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Режим split tunneling.
///
/// Android разрешает использовать только один список: либо исключения
/// (`ExcludedApplications`), либо «только выбранные» (`IncludedApplications`).
enum SplitTunnelingMode { off, exclude, include }

/// Настройки VPN, которые реально применяются к туннелю.
///
/// Kill switch здесь отсутствует намеренно: это системная настройка Android
/// (Always-on VPN + блокировка), приложение не может включить её за пользователя
/// и не должно показывать фиктивный переключатель.
class VpnSettings {
  const VpnSettings({
    this.splitMode = SplitTunnelingMode.off,
    this.selectedApplications = const <String>[],
    this.dnsProtectionEnabled = true,
    this.autoConnectOnLaunch = false,
    this.loaded = false,
  });

  final SplitTunnelingMode splitMode;

  /// Пакеты, выбранные в UI. Значение зависит от [splitMode]:
  /// исключения для `exclude`, разрешённые для `include`.
  final List<String> selectedApplications;

  /// Если в конфиге нет DNS, добавить защищённый DNS (1.1.1.1 / 1.0.0.1).
  final bool dnsProtectionEnabled;

  /// Подключаться к последнему выбранному серверу при запуске приложения.
  final bool autoConnectOnLaunch;

  /// Настройки прочитаны из SharedPreferences (нужно для автоподключения).
  final bool loaded;

  bool get splitTunnelingEnabled => splitMode != SplitTunnelingMode.off;

  VpnSettings copyWith({
    SplitTunnelingMode? splitMode,
    List<String>? selectedApplications,
    bool? dnsProtectionEnabled,
    bool? autoConnectOnLaunch,
    bool? loaded,
  }) {
    return VpnSettings(
      splitMode: splitMode ?? this.splitMode,
      selectedApplications: selectedApplications ?? this.selectedApplications,
      dnsProtectionEnabled: dnsProtectionEnabled ?? this.dnsProtectionEnabled,
      autoConnectOnLaunch: autoConnectOnLaunch ?? this.autoConnectOnLaunch,
      loaded: loaded ?? this.loaded,
    );
  }
}

class VpnSettingsNotifier extends Notifier<VpnSettings> {
  static const String _modeKey = 'mouvi.settings.split_mode';
  static const String _legacySplitKey = 'mouvi.settings.split_tunneling';
  static const String _appsKey = 'mouvi.settings.excluded_apps';
  static const String _dnsKey = 'mouvi.settings.dns_protection';
  static const String _autoConnectKey = 'mouvi.settings.auto_connect';

  final Completer<void> _ready = Completer<void>();
  bool _userChanged = false;

  /// Завершается после чтения настроек (успешного или нет).
  Future<void> get ready => _ready.future;

  @override
  VpnSettings build() {
    unawaited(_load());
    return const VpnSettings();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!ref.mounted || _userChanged) {
        return;
      }
      final rawMode = prefs.getString(_modeKey);
      final mode = SplitTunnelingMode.values.firstWhere(
        (value) => value.name == rawMode,
        orElse: () => (prefs.getBool(_legacySplitKey) ?? false)
            ? SplitTunnelingMode.exclude
            : SplitTunnelingMode.off,
      );
      state = VpnSettings(
        splitMode: mode,
        selectedApplications: prefs.getStringList(_appsKey) ?? const <String>[],
        dnsProtectionEnabled: prefs.getBool(_dnsKey) ?? true,
        autoConnectOnLaunch: prefs.getBool(_autoConnectKey) ?? false,
        loaded: true,
      );
    } catch (_) {
      // Настройки по умолчанию уже установлены.
      if (ref.mounted && !_userChanged) {
        state = state.copyWith(loaded: true);
      }
    } finally {
      if (!_ready.isCompleted) {
        _ready.complete();
      }
    }
  }

  Future<void> updateSplitMode(SplitTunnelingMode mode) async {
    _userChanged = true;
    state = state.copyWith(splitMode: mode, loaded: true);
    await _persist();
  }

  Future<void> updateSelectedApplications(List<String> packages) async {
    _userChanged = true;
    final unique = packages.toSet().toList(growable: false);
    state = state.copyWith(selectedApplications: unique, loaded: true);
    await _persist();
  }

  Future<void> updateDnsProtectionEnabled(bool value) async {
    _userChanged = true;
    state = state.copyWith(dnsProtectionEnabled: value, loaded: true);
    await _persist();
  }

  Future<void> updateAutoConnectOnLaunch(bool value) async {
    _userChanged = true;
    state = state.copyWith(autoConnectOnLaunch: value, loaded: true);
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_modeKey, state.splitMode.name);
      await prefs.setStringList(_appsKey, state.selectedApplications);
      await prefs.setBool(_dnsKey, state.dnsProtectionEnabled);
      await prefs.setBool(_autoConnectKey, state.autoConnectOnLaunch);
    } catch (_) {
      // Не роняем UI из-за ошибки записи настроек.
    }
  }
}

final vpnSettingsProvider = NotifierProvider<VpnSettingsNotifier, VpnSettings>(
  VpnSettingsNotifier.new,
);
