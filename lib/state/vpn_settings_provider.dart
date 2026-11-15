import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Настройки VPN, которые реально применяются к туннелю.
///
/// Kill switch здесь отсутствует намеренно: это системная настройка Android
/// (Always-on VPN + блокировка), приложение не может включить её за пользователя
/// и не должно показывать фиктивный переключатель.
class VpnSettings {
  const VpnSettings({
    this.splitTunnelingEnabled = false,
    this.excludedApplications = const <String>[],
    this.dnsProtectionEnabled = true,
  });

  final bool splitTunnelingEnabled;

  /// Пакеты, трафик которых идёт мимо VPN (ExcludedApplications).
  final List<String> excludedApplications;

  /// Если в конфиге нет DNS, добавить защищённый DNS (1.1.1.1 / 1.0.0.1).
  final bool dnsProtectionEnabled;
}

class VpnSettingsNotifier extends Notifier<VpnSettings> {
  static const String _splitKey = 'mouvi.settings.split_tunneling';
  static const String _appsKey = 'mouvi.settings.excluded_apps';
  static const String _dnsKey = 'mouvi.settings.dns_protection';

  bool _userChanged = false;

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
      state = VpnSettings(
        splitTunnelingEnabled: prefs.getBool(_splitKey) ?? false,
        excludedApplications: prefs.getStringList(_appsKey) ?? const <String>[],
        dnsProtectionEnabled: prefs.getBool(_dnsKey) ?? true,
      );
    } catch (_) {
      // Настройки по умолчанию уже установлены.
    }
  }

  VpnSettings _copyWith({
    bool? splitTunnelingEnabled,
    List<String>? excludedApplications,
    bool? dnsProtectionEnabled,
  }) {
    return VpnSettings(
      splitTunnelingEnabled:
          splitTunnelingEnabled ?? state.splitTunnelingEnabled,
      excludedApplications: excludedApplications ?? state.excludedApplications,
      dnsProtectionEnabled: dnsProtectionEnabled ?? state.dnsProtectionEnabled,
    );
  }

  Future<void> updateSplitTunnelingEnabled(bool value) async {
    _userChanged = true;
    state = _copyWith(splitTunnelingEnabled: value);
    await _persist();
  }

  Future<void> updateExcludedApplications(List<String> packages) async {
    _userChanged = true;
    final unique = packages.toSet().toList(growable: false);
    state = _copyWith(excludedApplications: unique);
    await _persist();
  }

  Future<void> updateDnsProtectionEnabled(bool value) async {
    _userChanged = true;
    state = _copyWith(dnsProtectionEnabled: value);
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_splitKey, state.splitTunnelingEnabled);
      await prefs.setStringList(_appsKey, state.excludedApplications);
      await prefs.setBool(_dnsKey, state.dnsProtectionEnabled);
    } catch (_) {
      // Не роняем UI из-за ошибки записи настроек.
    }
  }
}

final vpnSettingsProvider = NotifierProvider<VpnSettingsNotifier, VpnSettings>(
  VpnSettingsNotifier.new,
);
