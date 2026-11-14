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

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.t('servers')),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: localizations.t('addServer'),
            onPressed: () => _openAddSheet(context, ref, localizations),
          ),
        ],
      ),
      body: savedConfigs.isEmpty
          ? _buildEmptyState(context, localizations)
          : _buildConfigList(context, ref, savedConfigs, localizations),
    );
  }

  Widget _buildEmptyState(BuildContext context, AppLocalizations localizations) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(localizations.t('noServersTitle'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              localizations.t('noServersHint'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigList(
    BuildContext context,
    WidgetRef ref,
    List<VpnConfig> savedConfigs,
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
          onConnect: () => ref.read(connectionProvider.notifier).connect(config),
          onDelete: () => ref.read(savedConfigsProvider.notifier).removeConfig(config.id),
        );
      },
    );
  }

  Future<void> _openAddSheet(BuildContext context, WidgetRef ref, AppLocalizations localizations) async {
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
  Future<void> _pickFile(WidgetRef ref, BuildContext context, AppLocalizations localizations) async {
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
    final content = await File(path).readAsString();
    if (!context.mounted) {
      return;
    }
    await _addConfig(ref, context, localizations, content, name: file.name.replaceAll(RegExp(r'\.[^.]+$'), ''));
  }

  Future<void> _showPasteDialog(WidgetRef ref, BuildContext context, AppLocalizations localizations) async {
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
                decoration: InputDecoration(labelText: localizations.t('serverName')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentController,
                maxLines: 8,
                decoration: InputDecoration(labelText: localizations.t('importConfig')),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(localizations.t('cancel'))),
          TextButton(
            onPressed: () async {
              final content = contentController.text.trim();
              if (content.isEmpty) {
                return;
              }
              Navigator.of(dialogContext).pop();
              await _addConfig(ref, context, localizations, content, name: nameController.text.trim());
            },
            child: Text(localizations.t('save')),
          ),
        ],
      ),
    );
  }

  Future<void> _addConfig(
    WidgetRef ref,
    BuildContext context,
    AppLocalizations localizations,
    String content, {
    String? name,
  }) async {
    final config = VpnConfig(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      name: name != null && name.trim().isNotEmpty ? name.trim() : suggestConfigName(content, fallback: 'Server'),
      protocol: detectProtocol(content),
      content: content,
      createdAt: DateTime.now(),
    );
    ref.read(savedConfigsProvider.notifier).addConfig(config);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(localizations.t('configAdded'))));
    }
  }
}

class _ServerCard extends ConsumerWidget {
  const _ServerCard({
    required this.config,
    required this.onConnect,
    required this.onDelete,
  });

  final VpnConfig config;
  final VoidCallback onConnect;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations(ref.watch(localeProvider));
    return Card(
      child: ListTile(
        leading: Icon(Icons.shield, color: Theme.of(context).colorScheme.primary),
        title: Text(config.name, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(localizations.t(config.protocol.labelKey), style: Theme.of(context).textTheme.bodySmall),
        trailing: IconButton(
          icon: const Icon(Icons.delete),
          onPressed: onDelete,
        ),
        onTap: onConnect,
      ),
    );
  }
}
