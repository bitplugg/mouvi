import 'package:flutter_riverpod/flutter_riverpod.dart';

class VpnSettings {
  const VpnSettings({
    this.killSwitchEnabled = true,
    this.splitTunnelingEnabled = false,
    this.dnsProtectionEnabled = true,
  });

  final bool killSwitchEnabled;
  final bool splitTunnelingEnabled;
  final bool dnsProtectionEnabled;
}

class VpnSettingsNotifier extends Notifier<VpnSettings> {
  @override
  VpnSettings build() => const VpnSettings();

  VpnSettings _copyWith({
    bool? killSwitchEnabled,
    bool? splitTunnelingEnabled,
    bool? dnsProtectionEnabled,
  }) {
    return VpnSettings(
      killSwitchEnabled: killSwitchEnabled ?? state.killSwitchEnabled,
      splitTunnelingEnabled: splitTunnelingEnabled ?? state.splitTunnelingEnabled,
      dnsProtectionEnabled: dnsProtectionEnabled ?? state.dnsProtectionEnabled,
    );
  }

  void updateKillSwitchEnabled(bool value) {
    state = _copyWith(killSwitchEnabled: value);
  }

  void updateSplitTunnelingEnabled(bool value) {
    state = _copyWith(splitTunnelingEnabled: value);
  }

  void updateDnsProtectionEnabled(bool value) {
    state = _copyWith(dnsProtectionEnabled: value);
  }
}

final vpnSettingsProvider = NotifierProvider<VpnSettingsNotifier, VpnSettings>(VpnSettingsNotifier.new);
