import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mouvi/core/localization/app_localizations.dart';
import 'package:mouvi/core/services/installed_apps_service.dart';
import 'package:mouvi/core/services/push_notification_service.dart';
import 'package:mouvi/core/services/vpn_native_service.dart';
import 'package:mouvi/state/locale_provider.dart';
import 'package:mouvi/state/theme_provider.dart';
import 'package:mouvi/state/update_provider.dart';
import 'package:mouvi/state/vpn_settings_provider.dart';
import 'package:mouvi/ui/settings/diagnostics_screen.dart';
import 'package:mouvi/ui/settings/plugins_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

final packageInfoProvider = FutureProvider<PackageInfo>((ref) async {
  return PackageInfo.fromPlatform();
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final themePreference = ref.watch(themePreferenceProvider);
    final localizations = AppLocalizations(locale);
    final settings = ref.watch(vpnSettingsProvider);
    final notificationsEnabled = ref.watch(pushNotificationsEnabledProvider);
    final packageInfoAsync = ref.watch(packageInfoProvider);
    final updateState = ref.watch(updateProvider);

    final themeSelection = switch (themePreference) {
      ThemePreference.system => 'system',
      ThemePreference.light => 'light',
      ThemePreference.dark => 'dark',
    };

    final languageSelection = locale.languageCode;

    return Scaffold(
      appBar: AppBar(title: Text(localizations.t('settings'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            localizations.t('appearance'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    localizations.t('theme'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                          value: 'system',
                          label: Text(localizations.t('themeSystem')),
                        ),
                        ButtonSegment(
                          value: 'light',
                          label: Text(localizations.t('themeLight')),
                        ),
                        ButtonSegment(
                          value: 'dark',
                          label: Text(localizations.t('themeDark')),
                        ),
                      ],
                      selected: <String>{themeSelection},
                      onSelectionChanged: (value) {
                        final selected = value.first;
                        final preference = switch (selected) {
                          'light' => ThemePreference.light,
                          'dark' => ThemePreference.dark,
                          _ => ThemePreference.system,
                        };
                        unawaited(
                          ref
                              .read(themePreferenceProvider.notifier)
                              .updateThemePreference(preference),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    localizations.t('language'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                          value: 'ru',
                          label: Text(localizations.t('russian')),
                        ),
                        ButtonSegment(
                          value: 'en',
                          label: Text(localizations.t('english')),
                        ),
                      ],
                      selected: <String>{languageSelection},
                      onSelectionChanged: (value) {
                        unawaited(
                          ref
                              .read(localeProvider.notifier)
                              .updateLocale(Locale(value.first)),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            localizations.t('protection'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          _SystemVpnCard(localizations: localizations),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        localizations.t('splitTunneling'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        localizations.t('splitTunnelingHint'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<SplitTunnelingMode>(
                          segments: [
                            ButtonSegment(
                              value: SplitTunnelingMode.off,
                              label: Text(localizations.t('splitOff')),
                            ),
                            ButtonSegment(
                              value: SplitTunnelingMode.exclude,
                              label: Text(localizations.t('splitExclude')),
                            ),
                            ButtonSegment(
                              value: SplitTunnelingMode.include,
                              label: Text(localizations.t('splitInclude')),
                            ),
                          ],
                          selected: <SplitTunnelingMode>{settings.splitMode},
                          onSelectionChanged: (value) {
                            unawaited(
                              ref
                                  .read(vpnSettingsProvider.notifier)
                                  .updateSplitMode(value.first),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                if (settings.splitTunnelingEnabled) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.apps),
                    title: Text(localizations.t('chooseApps')),
                    subtitle: Text(
                      '${localizations.t('appsSelected')}: ${settings.selectedApplications.length}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _pickApps(
                      context,
                      ref,
                      localizations,
                      settings.selectedApplications,
                    ),
                  ),
                ],
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        localizations.t('dnsMode'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<DnsMode>(
                          segments: [
                            ButtonSegment(
                              value: DnsMode.system,
                              label: Text(localizations.t('dnsModeSystem')),
                            ),
                            ButtonSegment(
                              value: DnsMode.protected,
                              label: Text(localizations.t('dnsModeProtected')),
                            ),
                            ButtonSegment(
                              value: DnsMode.custom,
                              label: Text(localizations.t('dnsModeCustom')),
                            ),
                          ],
                          selected: <DnsMode>{settings.dnsMode},
                          onSelectionChanged: (value) {
                            unawaited(
                              ref
                                  .read(vpnSettingsProvider.notifier)
                                  .updateDnsMode(value.first),
                            );
                          },
                        ),
                      ),
                      if (settings.dnsMode == DnsMode.custom) ...[
                        const SizedBox(height: 8),
                        TextFormField(
                          key: ValueKey(
                            'dns-${settings.dnsMode}-${settings.customDnsServers.isEmpty}',
                          ),
                          initialValue: settings.customDnsServers,
                          decoration: InputDecoration(
                            labelText: localizations.t('customDns'),
                            hintText: localizations.t('customDnsHint'),
                            border: const OutlineInputBorder(),
                            helperText:
                                settings.resolvedCustomDnsServers.isEmpty
                                ? localizations.t('customDnsInvalid')
                                : null,
                          ),
                          minLines: 1,
                          maxLines: 3,
                          onChanged: (value) {
                            unawaited(
                              ref
                                  .read(vpnSettingsProvider.notifier)
                                  .updateCustomDnsServers(value),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  title: Text(localizations.t('connectTimeout')),
                  subtitle: Text(localizations.t('connectTimeoutHint')),
                  trailing: Text(
                    '${settings.connectTimeoutSeconds}${localizations.t('secondsValue')}',
                  ),
                ),
                Slider(
                  value: settings.connectTimeoutSeconds.toDouble(),
                  min: VpnSettings.minConnectTimeoutSeconds.toDouble(),
                  max: VpnSettings.maxConnectTimeoutSeconds.toDouble(),
                  divisions:
                      VpnSettings.maxConnectTimeoutSeconds -
                      VpnSettings.minConnectTimeoutSeconds,
                  label:
                      '${settings.connectTimeoutSeconds}${localizations.t('secondsValue')}',
                  onChanged: (value) {
                    unawaited(
                      ref
                          .read(vpnSettingsProvider.notifier)
                          .updateConnectTimeoutSeconds(value.round()),
                    );
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: Text(localizations.t('autoReconnect')),
                  subtitle: Text(localizations.t('autoReconnectHint')),
                  value: settings.autoReconnectEnabled,
                  onChanged: (value) {
                    unawaited(
                      ref
                          .read(vpnSettingsProvider.notifier)
                          .updateAutoReconnectEnabled(value),
                    );
                  },
                ),
                if (settings.autoReconnectEnabled)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${localizations.t('reconnectAttempts')}: ${settings.autoReconnectMaxAttempts}',
                          ),
                        ),
                        IconButton(
                          onPressed:
                              settings.autoReconnectMaxAttempts >
                                  VpnSettings.minReconnectAttempts
                              ? () => ref
                                    .read(vpnSettingsProvider.notifier)
                                    .updateAutoReconnectMaxAttempts(
                                      settings.autoReconnectMaxAttempts - 1,
                                    )
                              : null,
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        IconButton(
                          onPressed:
                              settings.autoReconnectMaxAttempts <
                                  VpnSettings.maxReconnectAttempts
                              ? () => ref
                                    .read(vpnSettingsProvider.notifier)
                                    .updateAutoReconnectMaxAttempts(
                                      settings.autoReconnectMaxAttempts + 1,
                                    )
                              : null,
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 1),
                SwitchListTile(
                  title: Text(localizations.t('reconnectOnNetworkChange')),
                  subtitle: Text(
                    localizations.t('reconnectOnNetworkChangeHint'),
                  ),
                  value: settings.reconnectOnNetworkChange,
                  onChanged: (value) {
                    unawaited(
                      ref
                          .read(vpnSettingsProvider.notifier)
                          .updateReconnectOnNetworkChange(value),
                    );
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: Text(localizations.t('wifiOnly')),
                  subtitle: Text(localizations.t('wifiOnlyHint')),
                  value: settings.wifiOnly,
                  onChanged: (value) {
                    unawaited(
                      ref
                          .read(vpnSettingsProvider.notifier)
                          .updateWifiOnly(value),
                    );
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: Text(localizations.t('autoConnect')),
                  subtitle: Text(localizations.t('autoConnectHint')),
                  value: settings.autoConnectOnLaunch,
                  onChanged: (value) {
                    unawaited(
                      ref
                          .read(vpnSettingsProvider.notifier)
                          .updateAutoConnectOnLaunch(value),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            localizations.t('notifications'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Card(
            child: SwitchListTile(
              title: Text(localizations.t('notifications')),
              subtitle: Text(localizations.t('notificationsHint')),
              value: notificationsEnabled,
              onChanged: (value) =>
                  _toggleNotifications(context, ref, localizations, value),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            localizations.t('engine'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.shield),
                  title: Text(localizations.t('engineWireguard')),
                  subtitle: Text(localizations.t('engineHint')),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: Text(localizations.t('storageEncrypted')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            localizations.t('plugins'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.extension_outlined),
              title: Text(localizations.t('plugins')),
              subtitle: Text(localizations.t('pluginsHint')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const PluginsScreen(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          Text(
            localizations.t('about'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(localizations.t('appVersion')),
                  subtitle: packageInfoAsync.when(
                    data: (info) => Text('${info.version}+${info.buildNumber}'),
                    loading: () => Text(localizations.t('appVersion')),
                    error: (error, stackTrace) => Text('1.3.0+4'),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.system_update_alt),
                  title: Text(localizations.t('updates')),
                  subtitle: _buildUpdateSubtitle(
                    context,
                    localizations,
                    updateState,
                  ),
                  trailing: updateState.status == UpdateCheckStatus.checking
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : FilledButton.tonal(
                          onPressed: () => unawaited(
                            ref.read(updateProvider.notifier).check(),
                          ),
                          child: Text(localizations.t('checkForUpdates')),
                        ),
                ),
                if (updateState.status == UpdateCheckStatus.updateAvailable &&
                    updateState.info != null) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${localizations.t('latestVersion')}: ${updateState.info!.latestVersion.isEmpty ? updateState.info!.tagName : updateState.info!.latestVersion}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        if (updateState.info!.releaseNotes.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            localizations.t('releaseNotes'),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _shortNotes(updateState.info!.releaseNotes),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: () => unawaited(
                                _downloadUpdate(context, updateState),
                              ),
                              icon: const Icon(Icons.download),
                              label: Text(localizations.t('downloadUpdate')),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => unawaited(
                                _openReleasePage(context, updateState),
                              ),
                              icon: const Icon(Icons.open_in_new),
                              label: Text(localizations.t('openReleasePage')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ] else if (updateState.status == UpdateCheckStatus.upToDate ||
                    updateState.status == UpdateCheckStatus.error) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: updateState.info == null
                            ? null
                            : () => unawaited(
                                _openReleasePage(context, updateState),
                              ),
                        icon: const Icon(Icons.open_in_new),
                        label: Text(localizations.t('openReleasePage')),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            localizations.t('diagnostics'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.bug_report_outlined),
                  title: Text(localizations.t('diagnostics')),
                  subtitle: Text(localizations.t('diagnosticsHint')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const DiagnosticsScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _shortNotes(String notes) {
    final trimmed = notes.trim();
    if (trimmed.length <= 400) {
      return trimmed;
    }
    return '${trimmed.substring(0, 400).trimRight()}…';
  }

  Widget _buildUpdateSubtitle(
    BuildContext context,
    AppLocalizations localizations,
    UpdateState updateState,
  ) {
    return switch (updateState.status) {
      UpdateCheckStatus.idle => Text(localizations.t('checkForUpdates')),
      UpdateCheckStatus.checking => Text(localizations.t('checkingUpdates')),
      UpdateCheckStatus.upToDate => Text(localizations.t('upToDate')),
      UpdateCheckStatus.updateAvailable => Text(
        '${localizations.t('newVersionAvailable')}: ${updateState.info?.latestVersion ?? updateState.info?.tagName ?? ''}',
      ),
      UpdateCheckStatus.error => Text(
        '${localizations.t('updateCheckFailed')}${updateState.errorCode == null ? '' : ' (${updateState.errorCode})'}',
      ),
    };
  }

  Future<void> _downloadUpdate(
    BuildContext context,
    UpdateState updateState,
  ) async {
    final info = updateState.info;
    if (info == null) {
      return;
    }
    final asset = info.preferredApkAsset();
    final url = asset?.browserDownloadUrl ?? info.releaseUrl;
    await _launchExternal(context, url);
  }

  Future<void> _openReleasePage(
    BuildContext context,
    UpdateState updateState,
  ) async {
    final info = updateState.info;
    if (info == null) {
      await _launchExternal(
        context,
        'https://github.com/bitplugg/mouvi/releases/latest',
      );
      return;
    }
    await _launchExternal(context, info.releaseUrl);
  }

  Future<void> _launchExternal(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not open link')));
    }
  }

  Future<void> _toggleNotifications(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations localizations,
    bool value,
  ) async {
    if (value) {
      final granted = await ref
          .read(pushNotificationServiceProvider)
          .requestPermission();
      if (!granted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(localizations.t('notificationsDenied'))),
          );
        }
        return;
      }
    }
    await ref.read(pushNotificationsEnabledProvider.notifier).update(value);
  }

  Future<void> _pickApps(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations localizations,
    List<String> selected,
  ) async {
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.85,
        child: _AppPickerSheet(
          localizations: localizations,
          initialSelection: selected.toSet(),
        ),
      ),
    );
    if (result == null || !context.mounted) {
      return;
    }
    await ref
        .read(vpnSettingsProvider.notifier)
        .updateSelectedApplications(result.toList());
  }
}

class _SystemVpnCard extends ConsumerStatefulWidget {
  const _SystemVpnCard({required this.localizations});

  final AppLocalizations localizations;

  @override
  ConsumerState<_SystemVpnCard> createState() => _SystemVpnCardState();
}

class _SystemVpnCardState extends ConsumerState<_SystemVpnCard> {
  VpnStateSnapshot? _snapshot;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final snapshot = await ref.read(vpnEngineProvider).getState();
    if (!mounted) {
      return;
    }
    setState(() {
      _snapshot = snapshot;
      _loading = false;
    });
  }

  Future<void> _openSettings() async {
    final localizations = widget.localizations;
    try {
      await ref.read(vpnEngineProvider).openVpnSettings();
    } on VpnEngineException {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.t('vpnSettingsUnavailable'))),
      );
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = widget.localizations;
    final colorScheme = Theme.of(context).colorScheme;
    final snapshot = _snapshot;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined, color: colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    localizations.t('killSwitchInfoTitle'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              localizations.t('killSwitchInfo'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            if (_loading)
              const LinearProgressIndicator()
            else if (snapshot != null)
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _StatusBadge(
                    label: localizations.t(
                      snapshot.alwaysOn
                          ? 'alwaysOnEnabled'
                          : 'alwaysOnDisabled',
                    ),
                    active: snapshot.alwaysOn,
                  ),
                  if (snapshot.alwaysOn)
                    _StatusBadge(
                      label: localizations.t(
                        snapshot.lockdown
                            ? 'lockdownEnabled'
                            : 'lockdownDisabled',
                      ),
                      active: snapshot.lockdown,
                    ),
                ],
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _openSettings,
                icon: const Icon(Icons.open_in_new),
                label: Text(localizations.t('openVpnSettings')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: active
              ? colorScheme.onPrimaryContainer
              : colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _AppPickerSheet extends StatefulWidget {
  const _AppPickerSheet({
    required this.localizations,
    required this.initialSelection,
  });

  final AppLocalizations localizations;
  final Set<String> initialSelection;

  @override
  State<_AppPickerSheet> createState() => _AppPickerSheetState();
}

class _AppPickerSheetState extends State<_AppPickerSheet> {
  late final Set<String> _selected = Set<String>.of(widget.initialSelection);
  List<InstalledApp>? _apps;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final apps = await const InstalledAppsService().listApps();
      if (!mounted) {
        return;
      }
      setState(() {
        _apps = apps;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = widget.localizations;
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    localizations.t('chooseApps'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(_selected),
                  child: Text(localizations.t('done')),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody(context, localizations)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations localizations) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(localizations.t('appsLoadFailed')),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _load,
              child: Text(localizations.t('retry')),
            ),
          ],
        ),
      );
    }
    final apps = _apps ?? const <InstalledApp>[];
    if (apps.isEmpty) {
      return Center(child: Text(localizations.t('noApps')));
    }
    return ListView.builder(
      itemCount: apps.length,
      itemBuilder: (context, index) {
        final app = apps[index];
        final checked = _selected.contains(app.packageName);
        return CheckboxListTile(
          value: checked,
          title: Text(app.label),
          subtitle: Text(app.packageName),
          onChanged: (value) {
            setState(() {
              if (value == true) {
                _selected.add(app.packageName);
              } else {
                _selected.remove(app.packageName);
              }
            });
          },
        );
      },
    );
  }
}
