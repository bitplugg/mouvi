import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Режим split tunneling.
///
/// Android разрешает использовать только один список: либо исключения
/// (`ExcludedApplications`), либо «только выбранные» (`IncludedApplications`).
enum SplitTunnelingMode { off, exclude, include }

/// Режим DNS для туннеля.
enum DnsMode { system, protected, custom }

/// Настройки VPN, которые реально применяются к туннелю.
///
/// Kill switch здесь отсутствует намеренно: это системная настройка Android
/// (Always-on VPN + блокировка), приложение не может включить её за пользователя
/// и не должно показывать фиктивный переключатель.
class VpnSettings {
  const VpnSettings({
    this.splitMode = SplitTunnelingMode.off,
    this.selectedApplications = const <String>[],
    this.dnsMode = DnsMode.protected,
    this.customDnsServers = '',
    this.autoConnectOnLaunch = false,
    this.connectTimeoutSeconds = 60,
    this.autoReconnectEnabled = false,
    this.autoReconnectMaxAttempts = 3,
    this.wifiOnly = false,
    this.reconnectOnNetworkChange = false,
    this.loaded = false,
  });

  static const int minConnectTimeoutSeconds = 15;
  static const int maxConnectTimeoutSeconds = 180;
  static const int minReconnectAttempts = 1;
  static const int maxReconnectAttempts = 10;

  final SplitTunnelingMode splitMode;

  /// Пакеты, выбранные в UI. Значение зависит от [splitMode]:
  /// исключения для `exclude`, разрешённые для `include`.
  final List<String> selectedApplications;

  final DnsMode dnsMode;

  /// Пользовательские DNS-серверы (через запятую/пробел/перенос строки).
  /// Используются только при [dnsMode] == [DnsMode.custom].
  final String customDnsServers;

  /// Подключаться к последнему выбранному серверу при запуске приложения.
  final bool autoConnectOnLaunch;

  /// Таймаут ожидания установки соединения, секунды.
  final int connectTimeoutSeconds;

  /// Автоматически пытаться переподключиться после неожиданного обрыва/ошибки.
  final bool autoReconnectEnabled;
  final int autoReconnectMaxAttempts;

  /// Разрешать подключение/переподключение только в Wi-Fi сети.
  final bool wifiOnly;

  /// Переподключаться при смене типа сети (если туннель был поднят).
  final bool reconnectOnNetworkChange;

  /// Настройки прочитаны из SharedPreferences (нужно для автоподключения).
  final bool loaded;

  bool get splitTunnelingEnabled => splitMode != SplitTunnelingMode.off;

  /// Совместимость со старым контрактом: защищённый или кастомный DNS включён.
  bool get dnsProtectionEnabled => dnsMode != DnsMode.system;

  List<String> get resolvedCustomDnsServers =>
      parseDnsServers(customDnsServers);

  /// DNS-серверы, которые нужно передать движкам (пусто = не переопределять).
  List<String> get dnsServersForEngine => switch (dnsMode) {
    DnsMode.system => const <String>[],
    DnsMode.protected => const <String>['1.1.1.1', '1.0.0.1'],
    DnsMode.custom => resolvedCustomDnsServers,
  };

  VpnSettings copyWith({
    SplitTunnelingMode? splitMode,
    List<String>? selectedApplications,
    DnsMode? dnsMode,
    String? customDnsServers,
    bool? autoConnectOnLaunch,
    int? connectTimeoutSeconds,
    bool? autoReconnectEnabled,
    int? autoReconnectMaxAttempts,
    bool? wifiOnly,
    bool? reconnectOnNetworkChange,
    bool? loaded,
  }) {
    return VpnSettings(
      splitMode: splitMode ?? this.splitMode,
      selectedApplications: selectedApplications ?? this.selectedApplications,
      dnsMode: dnsMode ?? this.dnsMode,
      customDnsServers: customDnsServers ?? this.customDnsServers,
      autoConnectOnLaunch: autoConnectOnLaunch ?? this.autoConnectOnLaunch,
      connectTimeoutSeconds:
          (connectTimeoutSeconds ?? this.connectTimeoutSeconds).clamp(
            minConnectTimeoutSeconds,
            maxConnectTimeoutSeconds,
          ),
      autoReconnectEnabled: autoReconnectEnabled ?? this.autoReconnectEnabled,
      autoReconnectMaxAttempts:
          (autoReconnectMaxAttempts ?? this.autoReconnectMaxAttempts).clamp(
            minReconnectAttempts,
            maxReconnectAttempts,
          ),
      wifiOnly: wifiOnly ?? this.wifiOnly,
      reconnectOnNetworkChange:
          reconnectOnNetworkChange ?? this.reconnectOnNetworkChange,
      loaded: loaded ?? this.loaded,
    );
  }

  static List<String> parseDnsServers(String input) {
    final parts = input
        .split(RegExp(r'[\s,;]+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty);
    final result = <String>[];
    final seen = <String>{};
    for (final part in parts) {
      if (!_isDnsAddress(part)) {
        continue;
      }
      final key = part.toLowerCase();
      if (seen.add(key)) {
        result.add(part);
      }
    }
    return result;
  }

  static bool _isDnsAddress(String value) {
    final uri = Uri.tryParse('dns://[$value]');
    if (uri != null && uri.host.isNotEmpty) {
      return true;
    }
    final simple = value.startsWith('[') && value.endsWith(']')
        ? value.substring(1, value.length - 1)
        : value;
    return RegExp(r'^[0-9a-fA-F:.]+$').hasMatch(simple) &&
        (simple.contains('.') || simple.contains(':'));
  }
}

class VpnSettingsNotifier extends Notifier<VpnSettings> {
  static const String _modeKey = 'mouvi.settings.split_mode';
  static const String _legacySplitKey = 'mouvi.settings.split_tunneling';
  static const String _appsKey = 'mouvi.settings.excluded_apps';
  static const String _legacyDnsKey = 'mouvi.settings.dns_protection';
  static const String _dnsModeKey = 'mouvi.settings.dns_mode';
  static const String _customDnsKey = 'mouvi.settings.custom_dns';
  static const String _autoConnectKey = 'mouvi.settings.auto_connect';
  static const String _timeoutKey = 'mouvi.settings.connect_timeout_sec';
  static const String _autoReconnectKey = 'mouvi.settings.auto_reconnect';
  static const String _autoReconnectAttemptsKey =
      'mouvi.settings.auto_reconnect_attempts';
  static const String _wifiOnlyKey = 'mouvi.settings.wifi_only';
  static const String _reconnectNetworkKey =
      'mouvi.settings.reconnect_on_network_change';

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
      final rawDnsMode = prefs.getString(_dnsModeKey);
      final dnsMode = DnsMode.values.firstWhere(
        (value) => value.name == rawDnsMode,
        orElse: () => (prefs.getBool(_legacyDnsKey) ?? true)
            ? DnsMode.protected
            : DnsMode.system,
      );
      state = VpnSettings(
        splitMode: mode,
        selectedApplications: prefs.getStringList(_appsKey) ?? const <String>[],
        dnsMode: dnsMode,
        customDnsServers: prefs.getString(_customDnsKey) ?? '',
        autoConnectOnLaunch: prefs.getBool(_autoConnectKey) ?? false,
        connectTimeoutSeconds: prefs.getInt(_timeoutKey) ?? 60,
        autoReconnectEnabled: prefs.getBool(_autoReconnectKey) ?? false,
        autoReconnectMaxAttempts: prefs.getInt(_autoReconnectAttemptsKey) ?? 3,
        wifiOnly: prefs.getBool(_wifiOnlyKey) ?? false,
        reconnectOnNetworkChange: prefs.getBool(_reconnectNetworkKey) ?? false,
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
    await updateDnsMode(value ? DnsMode.protected : DnsMode.system);
  }

  Future<void> updateDnsMode(DnsMode mode) async {
    _userChanged = true;
    state = state.copyWith(dnsMode: mode, loaded: true);
    await _persist();
  }

  Future<void> updateCustomDnsServers(String value) async {
    _userChanged = true;
    state = state.copyWith(customDnsServers: value, loaded: true);
    await _persist();
  }

  Future<void> updateAutoConnectOnLaunch(bool value) async {
    _userChanged = true;
    state = state.copyWith(autoConnectOnLaunch: value, loaded: true);
    await _persist();
  }

  Future<void> updateConnectTimeoutSeconds(int value) async {
    _userChanged = true;
    state = state.copyWith(connectTimeoutSeconds: value, loaded: true);
    await _persist();
  }

  Future<void> updateAutoReconnectEnabled(bool value) async {
    _userChanged = true;
    state = state.copyWith(autoReconnectEnabled: value, loaded: true);
    await _persist();
  }

  Future<void> updateAutoReconnectMaxAttempts(int value) async {
    _userChanged = true;
    state = state.copyWith(autoReconnectMaxAttempts: value, loaded: true);
    await _persist();
  }

  Future<void> updateWifiOnly(bool value) async {
    _userChanged = true;
    state = state.copyWith(wifiOnly: value, loaded: true);
    await _persist();
  }

  Future<void> updateReconnectOnNetworkChange(bool value) async {
    _userChanged = true;
    state = state.copyWith(reconnectOnNetworkChange: value, loaded: true);
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_modeKey, state.splitMode.name);
      await prefs.setStringList(_appsKey, state.selectedApplications);
      await prefs.setString(_dnsModeKey, state.dnsMode.name);
      await prefs.setString(_customDnsKey, state.customDnsServers);
      await prefs.setBool(_autoConnectKey, state.autoConnectOnLaunch);
      await prefs.setInt(_timeoutKey, state.connectTimeoutSeconds);
      await prefs.setBool(_autoReconnectKey, state.autoReconnectEnabled);
      await prefs.setInt(
        _autoReconnectAttemptsKey,
        state.autoReconnectMaxAttempts,
      );
      await prefs.setBool(_wifiOnlyKey, state.wifiOnly);
      await prefs.setBool(_reconnectNetworkKey, state.reconnectOnNetworkChange);
      // Совместимость: старый ключ отражает «защита включена».
      await prefs.setBool(_legacyDnsKey, state.dnsProtectionEnabled);
    } catch (_) {
      // Не роняем UI из-за ошибки записи настроек.
    }
  }
}

final vpnSettingsProvider = NotifierProvider<VpnSettingsNotifier, VpnSettings>(
  VpnSettingsNotifier.new,
);
