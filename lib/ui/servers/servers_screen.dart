import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mouvi/core/localization/app_localizations.dart';
import 'package:mouvi/core/models/vpn_config.dart';
import 'package:mouvi/core/plugins/plugin_models.dart';
import 'package:mouvi/core/plugins/plugin_registry.dart';
import 'package:mouvi/core/services/config_export_service.dart';
import 'package:mouvi/core/utils/config_parser.dart';
import 'package:mouvi/core/utils/format_utils.dart';
import 'package:mouvi/state/connection_provider.dart';
import 'package:mouvi/state/locale_provider.dart';
import 'package:mouvi/state/saved_configs_provider.dart';
import 'package:mouvi/ui/servers/qr_scan_screen.dart';

class ServersScreen extends ConsumerStatefulWidget {
  const ServersScreen({super.key});

  @override
  ConsumerState<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends ConsumerState<ServersScreen> {
  String _query = '';
  VpnProtocolType? _protocolFilter;

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final localizations = AppLocalizations(locale);
    final savedConfigs = ref.watch(savedConfigsProvider);
    final connection = ref.watch(connectionProvider);

    final filtered = _filterConfigs(savedConfigs);

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.t('servers')),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: localizations.t('addServer'),
            onPressed: connection.isBusy
                ? null
                : () => _openAddSheet(context, ref, localizations),
          ),
        ],
      ),
      body: Column(
        children: [
          if (savedConfigs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: localizations.t('searchServers'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(localizations.t('allProtocols')),
                            selected: _protocolFilter == null,
                            onSelected: (_) =>
                                setState(() => _protocolFilter = null),
                          ),
                        ),
                        for (final protocol in VpnProtocolType.values)
                          if (protocol != VpnProtocolType.unknown)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(localizations.t(protocol.labelKey)),
                                selected: _protocolFilter == protocol,
                                onSelected: (_) =>
                                    setState(() => _protocolFilter = protocol),
                              ),
                            ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: savedConfigs.isEmpty
                ? _buildEmptyState(context, ref, localizations)
                : filtered.isEmpty
                ? Center(child: Text(localizations.t('noResults')))
                : _buildConfigList(
                    context,
                    ref,
                    filtered,
                    connection,
                    localizations,
                  ),
          ),
        ],
      ),
    );
  }

  List<VpnConfig> _filterConfigs(List<VpnConfig> configs) {
    final q = _query.trim().toLowerCase();
    return configs
        .where((config) {
          if (_protocolFilter != null && config.protocol != _protocolFilter) {
            return false;
          }
          if (q.isEmpty) {
            return true;
          }
          return config.name.toLowerCase().contains(q) ||
              config.protocol.name.toLowerCase().contains(q);
        })
        .toList(growable: false);
  }

  Widget _buildEmptyState(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations localizations,
  ) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_off,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            localizations.t('noServersTitle'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              localizations.t('noServersHint'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => _openAddSheet(context, ref, localizations),
            icon: const Icon(Icons.add),
            label: Text(localizations.t('addServer')),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigList(
    BuildContext context,
    WidgetRef ref,
    List<VpnConfig> savedConfigs,
    VpnConnectionState connection,
    AppLocalizations localizations,
  ) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: savedConfigs.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final config = savedConfigs[index];
        return _ServerCard(
          config: config,
          localizations: localizations,
          isActive: connection.activeConfig?.id == config.id,
          isConnected:
              connection.status == VpnConnectionStatus.connected &&
              connection.activeConfig?.id == config.id,
          busy: connection.isBusy,
          onConnect: () => _connectTo(context, ref, config, localizations),
          onRename: () => _renameConfig(context, ref, config, localizations),
          onDuplicate: () =>
              _duplicateConfig(context, ref, config, localizations),
          onExport: () => _exportConfig(context, ref, config, localizations),
          onDelete: () => _deleteConfig(context, ref, config, localizations),
        );
      },
    );
  }

  void _connectTo(
    BuildContext context,
    WidgetRef ref,
    VpnConfig config,
    AppLocalizations localizations,
  ) {
    if (!config.protocol.engineSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.t('protocolNotSupported'))),
      );
      return;
    }
    unawaited(ref.read(connectionProvider.notifier).connect(config));
  }

  Future<void> _renameConfig(
    BuildContext context,
    WidgetRef ref,
    VpnConfig config,
    AppLocalizations localizations,
  ) async {
    final controller = TextEditingController(text: config.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.t('renameServer')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: localizations.t('serverName')),
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(localizations.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(localizations.t('save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null ||
        newName.trim().isEmpty ||
        newName.trim() == config.name) {
      return;
    }
    await ref
        .read(savedConfigsProvider.notifier)
        .renameConfig(config.id, newName);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(localizations.t('serverRenamed'))));
  }

  Future<void> _duplicateConfig(
    BuildContext context,
    WidgetRef ref,
    VpnConfig config,
    AppLocalizations localizations,
  ) async {
    final copy = VpnConfig(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      name: '${config.name} (copy)',
      protocol: config.protocol,
      content: config.content,
      createdAt: DateTime.now(),
    );
    await ref.read(savedConfigsProvider.notifier).addConfig(copy);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(localizations.t('configDuplicated'))),
    );
  }

  Future<void> _deleteConfig(
    BuildContext context,
    WidgetRef ref,
    VpnConfig config,
    AppLocalizations localizations,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.t('deleteConfirmTitle')),
        content: Text(localizations.t('deleteConfirmMessage')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(localizations.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(localizations.t('deleteAction')),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    final notifier = ref.read(savedConfigsProvider.notifier);
    await notifier.removeConfig(config.id);
    if (!context.mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(localizations.t('configDeleted')),
        action: SnackBarAction(
          label: localizations.t('undo'),
          onPressed: () {
            unawaited(notifier.addConfig(config));
            messenger.showSnackBar(
              SnackBar(content: Text(localizations.t('configRestored'))),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openAddSheet(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations localizations,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.file_upload),
                title: Text(localizations.t('importConfig')),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _pickFile(ref, context, localizations);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit),
                title: Text(localizations.t('pasteConfig')),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _showPasteDialog(ref, context, localizations);
                },
              ),
              ListTile(
                leading: const Icon(Icons.content_paste),
                title: Text(localizations.t('pasteFromClipboard')),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _pasteFromClipboard(ref, context, localizations);
                },
              ),
              ListTile(
                leading: const Icon(Icons.qr_code_scanner),
                title: Text(localizations.t('scanQr')),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _scanQr(ref, context, localizations);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickFile(
    WidgetRef ref,
    BuildContext context,
    AppLocalizations localizations,
  ) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['conf', 'config', 'ovpn', 'json', 'txt', 'wg'],
    );
    if (result.isEmpty) {
      return;
    }
    final file = result.first;
    final path = file.path;
    if (path == null) {
      return;
    }
    String content;
    try {
      content = await File(path).readAsString();
    } on FileSystemException {
      if (context.mounted) {
        _showImportError(context, localizations, const <String>[
          'invalidConfigFormat',
        ]);
      }
      return;
    }
    if (!context.mounted) {
      return;
    }
    await _addConfig(
      ref,
      context,
      localizations,
      content,
      name: file.name.replaceAll(RegExp(r'\.[^.]+$'), ''),
    );
  }

  Future<void> _showPasteDialog(
    WidgetRef ref,
    BuildContext context,
    AppLocalizations localizations,
  ) async {
    final nameController = TextEditingController();
    final contentController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.t('pasteConfig')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: localizations.t('serverName'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentController,
                maxLines: 8,
                decoration: InputDecoration(
                  labelText: localizations.t('importConfig'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
            },
            child: Text(localizations.t('cancel')),
          ),
          TextButton(
            onPressed: () async {
              final content = contentController.text.trim();
              if (content.isEmpty) {
                return;
              }
              Navigator.of(dialogContext).pop();
              await _addConfig(
                ref,
                context,
                localizations,
                content,
                name: nameController.text.trim(),
              );
            },
            child: Text(localizations.t('save')),
          ),
        ],
      ),
    );
    nameController.dispose();
    contentController.dispose();
  }

  Future<void> _pasteFromClipboard(
    WidgetRef ref,
    BuildContext context,
    AppLocalizations localizations,
  ) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final content = data?.text?.trim();
    if (content == null || content.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizations.t('clipboardEmpty'))),
        );
      }
      return;
    }
    if (!context.mounted) {
      return;
    }
    await _addConfig(ref, context, localizations, content);
  }

  Future<void> _scanQr(
    WidgetRef ref,
    BuildContext context,
    AppLocalizations localizations,
  ) async {
    final content = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (routeContext) => QrScanScreen(localizations: localizations),
      ),
    );
    final trimmed = content?.trim();
    if (trimmed == null || trimmed.isEmpty || !context.mounted) {
      return;
    }
    await _addConfig(ref, context, localizations, trimmed);
  }

  Future<void> _exportConfig(
    BuildContext context,
    WidgetRef ref,
    VpnConfig config,
    AppLocalizations localizations,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.t('exportWarningTitle')),
        content: Text(localizations.t('exportWarning')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(localizations.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(localizations.t('exportAction')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    String messageKey;
    try {
      final saved = await ref
          .read(configExportServiceProvider)
          .saveConfig(
            fileName: exportFileName(config.name, config.protocol),
            content: config.content,
          );
      messageKey = saved ? 'configExported' : 'configExportCancelled';
    } on ConfigExportException {
      messageKey = 'configExportFailed';
    }
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(localizations.t(messageKey))));
  }

  Future<bool> _addConfig(
    WidgetRef ref,
    BuildContext context,
    AppLocalizations localizations,
    String content, {
    String? name,
    bool showResult = true,
  }) async {
    var effectiveContent = content;
    final validation = validateConfig(effectiveContent);
    PluginImportMatch? pluginMatch;
    if (!validation.isValid) {
      pluginMatch = await ref
          .read(pluginRegistryProvider)
          .matchImport(effectiveContent);
      if (pluginMatch != null &&
          pluginMatch.content != null &&
          pluginMatch.content!.trim().isNotEmpty) {
        effectiveContent = pluginMatch.content!.trim();
      }
    }

    final effectiveValidation = validateConfig(effectiveContent);
    if (!effectiveValidation.isValid && pluginMatch == null) {
      if (context.mounted && showResult) {
        _showImportError(context, localizations, effectiveValidation.errors);
      }
      return false;
    }

    VpnProtocolType effectiveProtocol = effectiveValidation.isValid
        ? effectiveValidation.protocol
        : VpnProtocolType.unknown;
    if (!effectiveValidation.isValid &&
        pluginMatch != null &&
        pluginMatch.protocol != null) {
      final hinted = pluginMatch.protocol!.toLowerCase().trim();
      for (final p in VpnProtocolType.values) {
        if (p.name == hinted) {
          effectiveProtocol = p;
          break;
        }
      }
    }

    final suggestedName = (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : (pluginMatch?.name != null && pluginMatch!.name!.trim().isNotEmpty
              ? pluginMatch.name!.trim()
              : suggestConfigName(effectiveContent, fallback: 'Server'));

    final config = VpnConfig(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      name:
          pluginMatch != null &&
              name == null &&
              (pluginMatch.name == null || pluginMatch.name!.trim().isEmpty)
          ? '$suggestedName (${pluginMatch.label})'
          : suggestedName,
      protocol: effectiveProtocol,
      content: effectiveContent,
      createdAt: DateTime.now(),
    );
    final notifier = ref.read(savedConfigsProvider.notifier);
    await notifier.addConfig(config);
    if (!context.mounted || !showResult) {
      return true;
    }

    String message;
    if (notifier.lastWriteFailed) {
      message = localizations.t('storageWriteFailed');
    } else if (pluginMatch != null && !effectiveValidation.isValid) {
      message =
          '${localizations.t('configImportedByPlugin')}: ${pluginMatch.pluginName} · ${pluginMatch.label}';
    } else if (pluginMatch != null && effectiveValidation.isValid) {
      message =
          '${localizations.t('configImportedByPlugin')}: ${pluginMatch.pluginName} · ${pluginMatch.label}';
    } else if (effectiveValidation.engineSupported) {
      final details = effectiveValidation.warnings
          .toSet()
          .map(localizations.t)
          .join('\n');
      message = details.isEmpty
          ? localizations.t('configAdded')
          : '${localizations.t('configAdded')}\n$details';
    } else {
      message = localizations.t('configImportedUnsupported');
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    return true;
  }

  void _showImportError(
    BuildContext context,
    AppLocalizations localizations,
    List<String> errors,
  ) {
    final messages = errors.toSet().map(localizations.t).join('\n');
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.t('cannotImportTitle')),
        content: Text(messages),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(localizations.t('close')),
          ),
        ],
      ),
    );
  }
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({
    required this.config,
    required this.localizations,
    required this.isActive,
    required this.isConnected,
    required this.busy,
    required this.onConnect,
    required this.onRename,
    required this.onDuplicate,
    required this.onExport,
    required this.onDelete,
  });

  final VpnConfig config;
  final AppLocalizations localizations;
  final bool isActive;
  final bool isConnected;
  final bool busy;
  final VoidCallback onConnect;
  final VoidCallback onRename;
  final VoidCallback onDuplicate;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final supported = config.protocol.engineSupported;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: isActive
            ? BorderSide(color: colorScheme.primary, width: 1.5)
            : BorderSide.none,
      ),
      child: ListTile(
        leading: Icon(
          isConnected ? Icons.verified_user : Icons.shield,
          color: supported ? colorScheme.primary : colorScheme.error,
        ),
        title: Text(
          config.name,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                localizations.t(config.protocol.labelKey),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              _Badge(
                label: localizations.t(
                  supported ? 'supported' : 'notSupported',
                ),
                color: supported ? colorScheme.primary : colorScheme.error,
                background: supported
                    ? colorScheme.primaryContainer
                    : colorScheme.errorContainer,
              ),
              if (isConnected)
                _Badge(
                  label: localizations.t('connected'),
                  color: colorScheme.onTertiaryContainer,
                  background: colorScheme.tertiaryContainer,
                ),
            ],
          ),
        ),
        trailing: PopupMenuButton<String>(
          enabled: !busy,
          tooltip: localizations.t('servers'),
          onSelected: (value) {
            switch (value) {
              case 'rename':
                onRename();
              case 'duplicate':
                onDuplicate();
              case 'export':
                onExport();
              case 'delete':
                onDelete();
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'rename',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.edit_outlined),
                title: Text(localizations.t('rename')),
              ),
            ),
            PopupMenuItem(
              value: 'duplicate',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.copy_outlined),
                title: Text(localizations.t('duplicate')),
              ),
            ),
            PopupMenuItem(
              value: 'export',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.save_alt),
                title: Text(localizations.t('exportConfig')),
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.delete_outline),
                title: Text(localizations.t('delete')),
              ),
            ),
          ],
        ),
        onTap: busy ? null : onConnect,
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.color,
    required this.background,
  });

  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
