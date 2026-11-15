import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mouvi/core/localization/app_localizations.dart';
import 'package:mouvi/core/models/vpn_config.dart';
import 'package:mouvi/state/connection_provider.dart';
import 'package:mouvi/state/locale_provider.dart';
import 'package:mouvi/state/saved_configs_provider.dart';

String protocolLabelKey(VpnProtocolType protocol) {
  return switch (protocol) {
    VpnProtocolType.wireguard => 'protocolWireguard',
    VpnProtocolType.openvpn => 'protocolOpenvpn',
    VpnProtocolType.shadowsocks => 'protocolShadowsocks',
    VpnProtocolType.vless => 'protocolVless',
    VpnProtocolType.trojan => 'protocolTrojan',
    VpnProtocolType.unknown => 'protocolUnknown',
  };
}

String formatUptime(DateTime start) {
  final duration = DateTime.now().difference(start);
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
  }
  return duration.inMinutes.toString();
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final localizations = AppLocalizations(locale);
    final connection = ref.watch(connectionProvider);
    final savedConfigs = ref.watch(savedConfigsProvider);

    final statusText = switch (connection.status) {
      VpnConnectionStatus.disconnected => localizations.t('disconnected'),
      VpnConnectionStatus.connecting => localizations.t('connecting'),
      VpnConnectionStatus.connected => localizations.t('connected'),
    };

    return Scaffold(
      appBar: AppBar(title: Text(localizations.t('appTitle'))),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildStatusCircle(context, connection.status),
                const SizedBox(height: 20),
                Text(statusText, style: Theme.of(context).textTheme.headlineMedium),
                if (connection.status == VpnConnectionStatus.connected && connection.activeConfig != null) ...[
                  const SizedBox(height: 8),
                  Text(connection.activeConfig!.name, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    localizations.t(protocolLabelKey(connection.activeConfig!.protocol)),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (connection.connectedAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${localizations.t('uptime')} ${formatUptime(connection.connectedAt!)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ],
                if (connection.status == VpnConnectionStatus.disconnected && savedConfigs.isEmpty) ...[
                  const SizedBox(height: 16),
                  Icon(Icons.cloud_off, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      localizations.t('noServersHint'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                _buildAction(context, ref, localizations, connection),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCircle(BuildContext context, VpnConnectionStatus status) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = switch (status) {
      VpnConnectionStatus.disconnected => Icons.lock,
      VpnConnectionStatus.connecting => Icons.sync,
      VpnConnectionStatus.connected => Icons.lock_open,
    };
    return Container(
      width: 128,
      height: 128,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colorScheme.primary, colorScheme.primaryContainer],
        ),
      ),
      child: Icon(icon, size: 56, color: colorScheme.onPrimary),
    );
  }

  Widget _buildAction(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations localizations,
    VpnConnectionState connection,
  ) {
    final notifier = ref.read(connectionProvider.notifier);
    return switch (connection.status) {
      VpnConnectionStatus.disconnected => FilledButton.icon(
        onPressed: () {
          final config = connection.activeConfig;
          if (config != null) {
            notifier.connect(config);
          }
        },
        icon: const Icon(Icons.link),
        label: Text(localizations.t('connect')),
      ),
      VpnConnectionStatus.connecting => FilledButton.icon(
        onPressed: null,
        icon: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary),
        ),
        label: Text(localizations.t('connecting')),
      ),
      VpnConnectionStatus.connected => FilledButton.icon(
        onPressed: () => notifier.disconnect(),
        icon: const Icon(Icons.power_settings_new),
        label: Text(localizations.t('disconnect')),
      ),
    };
  }
}
