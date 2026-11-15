import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mouvi/core/localization/app_localizations.dart';
import 'package:mouvi/core/services/installed_apps_service.dart';
import 'package:mouvi/core/services/push_notification_service.dart';
import 'package:mouvi/core/services/vpn_native_service.dart';
import 'package:mouvi/state/locale_provider.dart';
import 'package:mouvi/state/theme_provider.dart';
import 'package:mouvi/state/vpn_settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final themePreference = ref.watch(themePreferenceProvider);
    final localizations = AppLocalizations(locale);
    final settings = ref.watch(vpnSettingsProvider);
    final notificationsEnabled = ref.watch(pushNotificationsEnabledProvider);

    final themeSelection = switch (themePreference) {
      ThemePreference.system => 'system',
      ThemePreference.light => 'light',
      ThemePreference.dark => 'dark',
    };

    final languageSelection = locale.languageCode == 'ru' ? 'ru' : 'en';

    return Scaffold(
      appBar: AppBar(title: Text(localizations.t('settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            localizations.t('appearance'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
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
                  if (value.length == 1) {
                    final key = value.first;
                    unawaited(
                      ref
                          .read(themePreferenceProvider.notifier)
                          .updateThemePreference(switch (key) {
                            'light' => ThemePreference.light,
                            'dark' => ThemePreference.dark,
                            _ => ThemePreference.system,
                          }),
                    );
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            localizations.t('language'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
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
                  final language = value.first;
                  unawaited(
                    ref
                        .read(localeProvider.notifier)
                        .updateLocale(Locale(language)),
                  );
                },
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
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: Text(localizations.t('splitTunneling')),
                  subtitle: Text(localizations.t('splitTunnelingHint')),
                  value: settings.splitTunnelingEnabled,
                  onChanged: (value) {
                    unawaited(
                      ref
                          .read(vpnSettingsProvider.notifier)
                          .updateSplitTunnelingEnabled(value),
                    );
                  },
                ),
                ListTile(
                  enabled: settings.splitTunnelingEnabled,
                  leading: const Icon(Icons.apps),
                  title: Text(localizations.t('chooseApps')),
                  subtitle: Text(
                    '${localizations.t('appsSelected')}: ${settings.excludedApplications.length}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: settings.splitTunnelingEnabled
                      ? () => _pickApps(
                          context,
                          ref,
                          localizations,
                          settings.excludedApplications,
                        )
                      : null,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: Text(localizations.t('dnsProtection')),
                  subtitle: Text(localizations.t('dnsProtectionHint')),
                  value: settings.dnsProtectionEnabled,
                  onChanged: (value) {
                    unawaited(
                      ref
                          .read(vpnSettingsProvider.notifier)
                          .updateDnsProtectionEnabled(value),
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
        ],
      ),
    );
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
        .updateExcludedApplications(result.toList());
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
