import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mouvi/core/models/vpn_config.dart';

enum VpnConnectionStatus { disconnected, connecting, connected }

class VpnConnectionState {
  const VpnConnectionState({this.status = VpnConnectionStatus.disconnected, this.activeConfig});

  final VpnConnectionStatus status;
  final VpnConfig? activeConfig;
}

class ConnectionNotifier extends Notifier<VpnConnectionState> {
  @override
  VpnConnectionState build() => const VpnConnectionState();

  void connect(VpnConfig config) {
    state = VpnConnectionState(status: VpnConnectionStatus.connecting, activeConfig: config);
  }

  void disconnect() {
    state = const VpnConnectionState();
  }

  void markConnected() {
    state = VpnConnectionState(status: VpnConnectionStatus.connected, activeConfig: state.activeConfig);
  }

  void markDisconnected() {
    state = const VpnConnectionState();
  }
}

final connectionProvider = NotifierProvider<ConnectionNotifier, VpnConnectionState>(ConnectionNotifier.new);
