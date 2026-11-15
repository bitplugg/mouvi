import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mouvi/core/models/vpn_config.dart';
import 'package:mouvi/core/services/push_notification_service.dart';
import 'package:mouvi/core/services/vpn_native_service.dart';
import 'package:mouvi/state/vpn_settings_provider.dart';

enum VpnConnectionStatus { disconnected, connecting, connected }

class VpnConnectionState {
  const VpnConnectionState({
    this.status = VpnConnectionStatus.disconnected,
    this.activeConfig,
    this.connectedAt,
  });

  final VpnConnectionStatus status;
  final VpnConfig? activeConfig;
  final DateTime? connectedAt;
}

class ConnectionNotifier extends Notifier<VpnConnectionState> {
  @override
  VpnConnectionState build() => const VpnConnectionState();

  void connect(VpnConfig config) {
    state = VpnConnectionState(status: VpnConnectionStatus.connecting, activeConfig: config);
    unawaited(
      ref.read(vpnEngineProvider).connect(
            config,
            killSwitch: ref.read(vpnSettingsProvider).killSwitchEnabled,
            splitTunneling: ref.read(vpnSettingsProvider).splitTunnelingEnabled,
            dnsProtection: ref.read(vpnSettingsProvider).dnsProtectionEnabled,
          ).then((connected) {
        if (connected) {
          markConnected();
        } else {
          markDisconnected();
        }
      }),
    );
  }

  void disconnect() {
    unawaited(
      ref.read(vpnEngineProvider).disconnect().then((_) => markDisconnected()),
    );
  }

  void markConnected() {
    state = VpnConnectionState(
      status: VpnConnectionStatus.connected,
      activeConfig: state.activeConfig,
      connectedAt: DateTime.now(),
    );
    _notifyPush('connected');
  }

  void markDisconnected() {
    _notifyPush('disconnected');
    state = const VpnConnectionState();
  }

  void _notifyPush(String type) {
    final enabled = ref.read(pushNotificationsEnabledProvider);
    if (!enabled) {
      return;
    }
    unawaited(
      ref
          .read(pushNotificationServiceProvider)
          .notify(type, serverName: state.activeConfig?.name, protocol: state.activeConfig?.protocol.name),
    );
  }
}

final connectionProvider = NotifierProvider<ConnectionNotifier, VpnConnectionState>(ConnectionNotifier.new);
