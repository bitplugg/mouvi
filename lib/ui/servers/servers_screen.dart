import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mouvi/core/localization/app_localizations.dart';
import 'package:mouvi/core/models/vpn_config.dart';
import 'package:mouvi/core/utils/config_parser.dart';
import 'package:mouvi/state/connection_provider.dart';
import 'package:mouvi/state/locale_provider.dart';
import 'package:mouvi/state/saved_configs_provider.dart';

class ServersScreen extends ConsumerWidget {
  const ServersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final localizations = AppLocalizations(locale);
    final savedConfigs = ref.watch(savedConfigsProvider);
    final connection = ref.watch(connectionProvider);

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
      body: savedConfigs.isEmpty
          ? _buildEmptyState(context, ref, localizations)
          : _buildConfigList(
              context,
              ref,
              savedConfigs,
              connection,
              localizations,
            ),
    );
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
    final messageKey = notifier.lastWriteFailed
        ? 'storageWriteFailed'
        : 'configDeleted';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(localizations.t(messageKey))));
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
      allowedExtensions: ['conf', 'ovpn', 'json', 'txt'],
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

  Future<void> _addConfig(
    WidgetRef ref,
    BuildContext context,
    AppLocalizations localizations,
    String content, {
    String? name,
  }) async {
    final validation = validateConfig(content);
    if (!validation.isValid) {
      if (context.mounted) {
        _showImportError(context, localizations, validation.errors);
      }
      return;
    }
    final config = VpnConfig(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      name: name != null && name.trim().isNotEmpty
          ? name.trim()
          : suggestConfigName(content, fallback: 'Server'),
      protocol: validation.protocol,
      content: content,
      createdAt: DateTime.now(),
    );
    final notifier = ref.read(savedConfigsProvider.notifier);
    await notifier.addConfig(config);
    if (!context.mounted) {
      return;
    }
    final messageKey = notifier.lastWriteFailed
        ? 'storageWriteFailed'
        : (validation.engineSupported
              ? 'configAdded'
              : 'configImportedUnsupported');
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(localizations.t(messageKey))));
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
    required this.onDelete,
  });

  final VpnConfig config;
  final AppLocalizations localizations;
  final bool isActive;
  final bool isConnected;
  final bool busy;
  final VoidCallback onConnect;
  final VoidCallback onRename;
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
          onSelected: (value) {
            switch (value) {
              case 'rename':
                onRename();
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
