import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mouvi/core/models/vpn_config.dart';
import 'package:mouvi/core/services/vpn_native_service.dart';

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
      ref.read(vpnEngineProvider).connect(config).then((connected) {
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
  }

  void markDisconnected() {
    state = const VpnConnectionState();
  }
}

final connectionProvider = NotifierProvider<ConnectionNotifier, VpnConnectionState>(ConnectionNotifier.new);
