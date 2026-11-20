import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:mouvi/core/localization/app_localizations.dart';
import 'package:mouvi/core/plugins/plugin_models.dart';
import 'package:mouvi/core/services/plugin_service.dart';
import 'package:mouvi/state/locale_provider.dart';
import 'package:mouvi/state/plugins_provider.dart';

class PluginsScreen extends ConsumerWidget {
  const PluginsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final l10n = AppLocalizations(locale);
    final pluginsAsync = ref.watch(pluginsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('plugins')),
        actions: [
          IconButton(
            icon: const Icon(Icons.store_outlined),
            tooltip: l10n.t('openPluginStore'),
            onPressed: () => _openStore(context, ref, l10n),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.add),
            tooltip: l10n.t('installPlugin'),
            onSelected: (value) {
              switch (value) {
                case 'file':
                  unawaited(_installFromFile(context, ref, l10n));
                case 'url':
                  unawaited(_installFromUrl(context, ref, l10n));
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'file',
                child: ListTile(
                  leading: const Icon(Icons.folder_open),
                  title: Text(l10n.t('installFromFile')),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem<String>(
                value: 'url',
                child: ListTile(
                  leading: const Icon(Icons.link),
                  title: Text(l10n.t('installFromUrl')),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: pluginsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text(l10n.t('error'))),
        data: (plugins) => _buildBody(context, ref, l10n, plugins),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    List<InstalledPlugin> plugins,
  ) {
    final service = ref.read(pluginServiceProvider);
    final baseEnabled = service.isBaseEnabled(plugins);
    final others = plugins
        .where((p) => p.manifest.id != PluginService.basePluginId)
        .toList();
    final base = plugins
        .where((p) => p.manifest.id == PluginService.basePluginId)
        .toList();
    final ordered = [...base, ...others];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (!baseEnabled)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.t('pluginBaseDisabledWarning'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (!baseEnabled) const SizedBox(height: 12),
        if (plugins.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 48),
            child: Center(child: Text(l10n.t('pluginNoPlugins'))),
          )
        else
          ...ordered.map(
            (plugin) => _PluginCard(
              plugin: plugin,
              baseEnabled: baseEnabled,
              l10n: l10n,
            ),
          ),
        const SizedBox(height: 16),
        Text(
          l10n.t('pluginStore'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _openStore(context, ref, l10n),
          icon: const Icon(Icons.storefront),
          label: Text(l10n.t('openPluginStore')),
        ),
      ],
    );
  }

  Future<void> _installFromFile(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['mu'],
      );
      if (result.isEmpty) return;
      final path = result.first.path;
      if (path == null || path.isEmpty) return;
      final installResult = await ref
          .read(pluginsProvider.notifier)
          .installFromFile(path);
      if (!context.mounted) return;
      await _postInstall(context, ref, l10n, installResult);
    } on PluginServiceException catch (e) {
      if (!context.mounted) return;
      _showInstallError(context, l10n, e.code);
    } catch (_) {
      if (!context.mounted) return;
      _showInstallError(context, l10n, 'unknown');
    }
  }

  Future<void> _installFromUrl(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.t('installFromUrl')),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: l10n.t('pluginUrl'),
            hintText: 'https://.../plugin.mu',
          ),
          keyboardType: TextInputType.url,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(l10n.t('install')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (url == null || url.isEmpty || !context.mounted) return;
    try {
      final installResult = await ref
          .read(pluginsProvider.notifier)
          .installFromUrl(url);
      if (!context.mounted) return;
      await _postInstall(context, ref, l10n, installResult);
    } on PluginServiceException catch (e) {
      if (!context.mounted) return;
      _showInstallError(context, l10n, e.code);
    } catch (_) {
      if (!context.mounted) return;
      _showInstallError(context, l10n, 'unknown');
    }
  }

  Future<void> _postInstall(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    PluginInstallResult result,
  ) async {
    final plugin = result.plugin;
    if (!plugin.isOfficialStoreSource && !plugin.riskAccepted) {
      final accepted = await _showRiskDialog(context, l10n);
      if (accepted == true) {
        await ref
            .read(pluginsProvider.notifier)
            .setRiskAccepted(plugin.manifest.id, true);
      }
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l10n.t(result.replaced ? 'pluginUpdated' : 'pluginInstalled'),
        ),
      ),
    );
  }

  Future<bool?> _showRiskDialog(BuildContext context, AppLocalizations l10n) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.t('pluginRiskTitle')),
        content: Text(l10n.t('pluginRiskMessage')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.t('pluginRiskAccept')),
          ),
        ],
      ),
    );
  }

  void _showInstallError(
    BuildContext context,
    AppLocalizations l10n,
    String code,
  ) {
    final key = switch (code) {
      'invalid_archive' ||
      'manifest_missing' ||
      'manifest_invalid' ||
      'invalid_plugin_id' => 'pluginInvalidFormat',
      'incompatible_api' => 'pluginIncompatible',
      _ => 'pluginInstallFailed',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${l10n.t(key)}${code == 'unknown' ? '' : ' ($code)'}'),
      ),
    );
  }

  Future<void> _openStore(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (sheetInnerContext, scrollController) => _StoreSheet(
          scrollController: scrollController,
          l10n: l10n,
          onInstall: (url) async {
            Navigator.of(sheetInnerContext).pop();
            try {
              final result = await ref
                  .read(pluginsProvider.notifier)
                  .installFromUrl(url);
              if (!context.mounted) return;
              await _postInstall(context, ref, l10n, result);
            } on PluginServiceException catch (e) {
              if (!context.mounted) return;
              _showInstallError(context, l10n, e.code);
            } catch (_) {
              if (!context.mounted) return;
              _showInstallError(context, l10n, 'unknown');
            }
          },
        ),
      ),
    );
  }
}

class _PluginCard extends ConsumerWidget {
  const _PluginCard({
    required this.plugin,
    required this.baseEnabled,
    required this.l10n,
  });

  final InstalledPlugin plugin;
  final bool baseEnabled;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBase = plugin.manifest.id == PluginService.basePluginId;
    final effectivelyInactive = !isBase && !baseEnabled;
    final subtitleParts = <String>[
      'v${plugin.manifest.version}',
      plugin.manifest.author,
      if (isBase) l10n.t('pluginBase'),
      plugin.isOfficialStoreSource
          ? l10n.t('pluginOfficial')
          : l10n.t('pluginUnofficial'),
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          isBase ? Icons.extension : Icons.extension_outlined,
          color: effectivelyInactive
              ? Theme.of(context).disabledColor
              : (plugin.enabled ? Theme.of(context).colorScheme.primary : null),
        ),
        title: Text(plugin.manifest.name),
        subtitle: Text(subtitleParts.join(' · ')),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: plugin.enabled,
              onChanged: (value) => _toggle(context, ref, value),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'details':
                    _showDetails(context);
                  case 'remove':
                    unawaited(_remove(context, ref));
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  value: 'details',
                  child: Text(l10n.t('details')),
                ),
                PopupMenuItem<String>(
                  value: 'remove',
                  enabled: !isBase,
                  child: Text(l10n.t('remove')),
                ),
              ],
            ),
          ],
        ),
        onTap: () => _showDetails(context),
      ),
    );
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref, bool value) async {
    if (value && !plugin.isOfficialStoreSource && !plugin.riskAccepted) {
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.t('pluginRiskTitle')),
          content: Text(l10n.t('pluginRiskMessage')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.t('pluginRiskAccept')),
            ),
          ],
        ),
      );
      if (accepted != true) return;
      await ref
          .read(pluginsProvider.notifier)
          .setRiskAccepted(plugin.manifest.id, true);
    }
    await ref
        .read(pluginsProvider.notifier)
        .setEnabled(plugin.manifest.id, value);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.t(value ? 'pluginEnabled' : 'pluginDisabled')),
      ),
    );
  }

  void _showDetails(BuildContext context) {
    final m = plugin.manifest;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            Text(m.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(m.description),
            const SizedBox(height: 16),
            _kv(context, l10n.t('pluginVersion'), m.version),
            _kv(context, l10n.t('pluginAuthor'), m.author),
            _kv(context, l10n.t('pluginApiVersion'), m.apiVersion.toString()),
            _kv(
              context,
              l10n.t('pluginSource'),
              plugin.isOfficialStoreSource
                  ? l10n.t('pluginOfficial')
                  : '${l10n.t('pluginUnofficial')} (${plugin.sourceRef})',
            ),
            if (m.permissions.isNotEmpty)
              _kv(
                context,
                l10n.t('pluginPermissions'),
                m.permissions.map((p) => p.name).join(', '),
              ),
            if (m.hooks.isNotEmpty)
              _kv(
                context,
                l10n.t('pluginHooks'),
                m.hooks.map((h) => h.name).join(', '),
              ),
            if (m.importRules.isNotEmpty)
              _kv(
                context,
                'Import rules',
                m.importRules.map((r) => r.label).join(', '),
              ),
            if (m.id == PluginService.basePluginId) ...[
              const SizedBox(height: 12),
              Text(
                l10n.t('pluginBaseHint'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              key,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    if (plugin.manifest.id == PluginService.basePluginId) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.t('pluginCannotRemoveBase'))));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.t('remove')),
        content: Text(
          '${l10n.t('pluginRemoveConfirm')}\n${plugin.manifest.name}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.t('remove')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(pluginsProvider.notifier).remove(plugin.manifest.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.t('pluginRemoved'))));
    } on PluginServiceException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.code)));
    }
  }
}

class _StoreSheet extends StatefulWidget {
  const _StoreSheet({
    required this.scrollController,
    required this.l10n,
    required this.onInstall,
  });

  final ScrollController scrollController;
  final AppLocalizations l10n;
  final Future<void> Function(String url) onInstall;

  @override
  State<_StoreSheet> createState() => _StoreSheetState();
}

class _StoreEntry {
  const _StoreEntry({
    required this.name,
    required this.description,
    required this.downloadUrl,
    this.version,
    this.id,
  });

  final String name;
  final String description;
  final String downloadUrl;
  final String? version;
  final String? id;

  static _StoreEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.map((k, v) => MapEntry(k.toString(), v));
    final name = (map['name'] as String?)?.trim() ?? '';
    final url =
        (map['downloadUrl'] as String?)?.trim() ??
        (map['url'] as String?)?.trim() ??
        '';
    if (name.isEmpty || url.isEmpty) return null;
    return _StoreEntry(
      name: name,
      description: (map['description'] as String?)?.trim() ?? '',
      downloadUrl: url,
      version: (map['version'] as String?)?.trim(),
      id: (map['id'] as String?)?.trim(),
    );
  }
}

class _StoreSheetState extends State<_StoreSheet> {
  late Future<List<_StoreEntry>> _future;

  static const String _indexUrl =
      'https://raw.githubusercontent.com/bitplugg/mouvi-store/master/index.json';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<_StoreEntry>> _load() async {
    final response = await http
        .get(Uri.parse(_indexUrl))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('http_${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    final List<dynamic> items;
    if (decoded is List) {
      items = decoded;
    } else if (decoded is Map && decoded['plugins'] is List) {
      items = decoded['plugins'] as List<dynamic>;
    } else {
      return const <_StoreEntry>[];
    }
    final out = <_StoreEntry>[];
    for (final item in items) {
      final entry = _StoreEntry.fromJson(item);
      if (entry != null) out.add(entry);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.t('pluginStore'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => setState(() => _future = _load()),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: FutureBuilder<List<_StoreEntry>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '${l10n.t('pluginStoreFailed')}\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              final items = snapshot.data ?? const <_StoreEntry>[];
              if (items.isEmpty) {
                return Center(child: Text(l10n.t('pluginStoreEmpty')));
              }
              return ListView.builder(
                controller: widget.scrollController,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ListTile(
                    leading: const Icon(Icons.extension),
                    title: Text(
                      item.version == null
                          ? item.name
                          : '${item.name} · v${item.version}',
                    ),
                    subtitle: Text(item.description),
                    trailing: FilledButton.tonal(
                      onPressed: () => widget.onInstall(item.downloadUrl),
                      child: Text(l10n.t('install')),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
