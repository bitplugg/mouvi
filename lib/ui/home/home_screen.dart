import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mouvi/core/localization/app_localizations.dart';
import 'package:mouvi/core/models/vpn_config.dart';
import 'package:mouvi/core/utils/format_utils.dart';
import 'package:mouvi/state/connection_provider.dart';
import 'package:mouvi/state/locale_provider.dart';
import 'package:mouvi/state/saved_configs_provider.dart';

String protocolLabelKey(VpnProtocolType protocol) => protocol.labelKey;

String formatUptime(DateTime start) {
  final duration = DateTime.now().difference(start);
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  final seconds = duration.inSeconds % 60;
  return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
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
      VpnConnectionStatus.disconnecting => localizations.t('disconnecting'),
      VpnConnectionStatus.error => localizations.t('error'),
    };

    final activeConfig = connection.activeConfig;

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
                Text(
                  statusText,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                if (activeConfig != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    activeConfig.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _ProtocolChip(
                        protocol: activeConfig.protocol,
                        localizations: localizations,
                      ),
                      if (connection.status == VpnConnectionStatus.connected &&
                          connection.connectedAt != null)
                        _UptimeChip(
                          start: connection.connectedAt!,
                          localizations: localizations,
                        ),
                    ],
                  ),
                ],
                if (connection.status == VpnConnectionStatus.error) ...[
                  const SizedBox(height: 16),
                  _ErrorBanner(
                    message: localizations.connectionError(
                      connection.errorCode,
                    ),
                  ),
                ],
                if (connection.status == VpnConnectionStatus.disconnected &&
                    savedConfigs.isEmpty) ...[
                  const SizedBox(height: 16),
                  Icon(
                    Icons.cloud_off,
                    size: 48,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
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
                if (connection.status == VpnConnectionStatus.disconnected &&
                    activeConfig == null &&
                    savedConfigs.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    localizations.t('noConfigSelected'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: 32),
                _buildAction(context, ref, localizations, connection),
                if (connection.status == VpnConnectionStatus.connected) ...[
                  const SizedBox(height: 24),
                  _TrafficPanel(
                    connection: connection,
                    localizations: localizations,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCircle(BuildContext context, VpnConnectionStatus status) {
    final colorScheme = Theme.of(context).colorScheme;
    final isError = status == VpnConnectionStatus.error;
    final icon = switch (status) {
      VpnConnectionStatus.disconnected => Icons.lock,
      VpnConnectionStatus.connecting => Icons.sync,
      VpnConnectionStatus.connected => Icons.lock_open,
      VpnConnectionStatus.disconnecting => Icons.sync,
      VpnConnectionStatus.error => Icons.gpp_bad,
    };
    return Container(
      width: 128,
      height: 128,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isError
              ? [colorScheme.error, colorScheme.errorContainer]
              : [colorScheme.primary, colorScheme.primaryContainer],
        ),
      ),
      child: Icon(
        icon,
        size: 56,
        color: isError ? colorScheme.onError : colorScheme.onPrimary,
        semanticLabel: status.name,
      ),
    );
  }

  Widget _buildAction(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations localizations,
    VpnConnectionState connection,
  ) {
    final notifier = ref.read(connectionProvider.notifier);
    final busy = connection.isBusy;
    switch (connection.status) {
      case VpnConnectionStatus.disconnected:
        // Подключаемся только к явно выбранному серверу, чтобы кнопка
        // не подключалась к «первому из списка» неожиданно для пользователя.
        final config = connection.activeConfig;
        return FilledButton.icon(
          onPressed: busy || config == null
              ? null
              : () => notifier.connect(config),
          icon: const Icon(Icons.link),
          label: Text(localizations.t('connect')),
        );
      case VpnConnectionStatus.connecting:
      case VpnConnectionStatus.disconnecting:
        return FilledButton.icon(
          onPressed: null,
          icon: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
          label: Text(
            localizations.t(
              connection.status == VpnConnectionStatus.connecting
                  ? 'connecting'
                  : 'disconnecting',
            ),
          ),
        );
      case VpnConnectionStatus.connected:
        return FilledButton.icon(
          onPressed: () => notifier.disconnect(),
          icon: const Icon(Icons.power_settings_new),
          label: Text(localizations.t('disconnect')),
        );
      case VpnConnectionStatus.error:
        final config = connection.activeConfig;
        if (config == null || !config.protocol.engineSupported) {
          return FilledButton.icon(
            onPressed: null,
            icon: const Icon(Icons.link),
            label: Text(localizations.t('connect')),
          );
        }
        return FilledButton.icon(
          onPressed: busy ? null : () => notifier.retry(),
          icon: const Icon(Icons.refresh),
          label: Text(localizations.t('retry')),
        );
    }
  }
}

class _ProtocolChip extends StatelessWidget {
  const _ProtocolChip({required this.protocol, required this.localizations});

  final VpnProtocolType protocol;
  final AppLocalizations localizations;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final supported = protocol.engineSupported;
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(
        supported ? Icons.verified_user : Icons.report_outlined,
        size: 16,
        color: supported ? colorScheme.primary : colorScheme.error,
      ),
      label: Text(
        '${localizations.t(protocol.labelKey)} · '
        '${localizations.t(supported ? 'supported' : 'notSupported')}',
      ),
      labelStyle: Theme.of(context).textTheme.labelMedium,
      side: BorderSide(
        color: supported ? colorScheme.outlineVariant : colorScheme.error,
      ),
      backgroundColor: supported
          ? colorScheme.surfaceContainerHighest
          : colorScheme.errorContainer,
    );
  }
}

class _UptimeChip extends StatefulWidget {
  const _UptimeChip({required this.start, required this.localizations});

  final DateTime start;
  final AppLocalizations localizations;

  @override
  State<_UptimeChip> createState() => _UptimeChipState();
}

class _UptimeChipState extends State<_UptimeChip> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: const Icon(Icons.timer_outlined, size: 16),
      label: Text(
        '${widget.localizations.t('uptime')} ${formatUptime(widget.start)}',
      ),
      labelStyle: Theme.of(context).textTheme.labelMedium,
    );
  }
}

class _TrafficPanel extends StatelessWidget {
  const _TrafficPanel({required this.connection, required this.localizations});

  final VpnConnectionState connection;
  final AppLocalizations localizations;

  @override
  Widget build(BuildContext context) {
    final age = handshakeAge(DateTime.now(), connection.lastHandshakeMs);
    final handshake = age == null
        ? localizations.t('handshakeNone')
        : '${age.value} ${localizations.t(_unitKey(age.unit))} '
              '${localizations.t('ago')}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: _TrafficItem(
                icon: Icons.arrow_downward,
                label: localizations.t('received'),
                value: formatBytes(connection.rxBytes),
              ),
            ),
            Expanded(
              child: _TrafficItem(
                icon: Icons.arrow_upward,
                label: localizations.t('sent'),
                value: formatBytes(connection.txBytes),
              ),
            ),
            Expanded(
              child: _TrafficItem(
                icon: Icons.handshake_outlined,
                label: localizations.t('handshake'),
                value: handshake,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _unitKey(String unit) {
    return switch (unit) {
      'seconds' => 'secondsShort',
      'minutes' => 'minutesShort',
      'hours' => 'hoursShort',
      _ => 'daysShort',
    };
  }
}

class _TrafficItem extends StatelessWidget {
  const _TrafficItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 6),
        Text(label, textAlign: TextAlign.center, style: textTheme.labelSmall),
        const SizedBox(height: 2),
        Text(value, textAlign: TextAlign.center, style: textTheme.bodyMedium),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
