import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mouvi/core/plugins/plugin_models.dart';
import 'package:mouvi/core/plugins/plugin_runtime.dart';
import 'package:mouvi/core/services/plugin_service.dart';

class PluginsNotifier extends Notifier<AsyncValue<List<InstalledPlugin>>> {
  @override
  AsyncValue<List<InstalledPlugin>> build() {
    unawaited(_load());
    return const AsyncValue<List<InstalledPlugin>>.loading();
  }

  Future<void> _load() async {
    try {
      final list = await ref.read(pluginServiceProvider).loadInstalled();
      state = AsyncValue<List<InstalledPlugin>>.data(list);
    } catch (e, st) {
      state = AsyncValue<List<InstalledPlugin>>.error(e, st);
    }
  }

  Future<void> reload() => _load();

  Future<PluginInstallResult> installFromFile(String path) async {
    final service = ref.read(pluginServiceProvider);
    final result = await service.installFromFile(filePath: path);
    await ref
        .read(pluginRuntimeServiceProvider)
        .resetForPlugin(result.plugin.manifest.id);
    await _load();
    return result;
  }

  Future<PluginInstallResult> installFromUrl(String url) async {
    final service = ref.read(pluginServiceProvider);
    final result = await service.installFromUrl(url);
    await ref
        .read(pluginRuntimeServiceProvider)
        .resetForPlugin(result.plugin.manifest.id);
    await _load();
    return result;
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await ref.read(pluginServiceProvider).setEnabled(id, enabled);
    await _load();
  }

  Future<void> setRiskAccepted(String id, bool accepted) async {
    await ref.read(pluginServiceProvider).setRiskAccepted(id, accepted);
    await _load();
  }

  Future<void> remove(String id) async {
    await ref.read(pluginServiceProvider).remove(id);
    await ref.read(pluginRuntimeServiceProvider).resetForPlugin(id);
    await _load();
  }
}

final pluginsProvider =
    NotifierProvider<PluginsNotifier, AsyncValue<List<InstalledPlugin>>>(
      PluginsNotifier.new,
    );

/// Активные хуки с учётом базового плагина mouvi-engine.
final activePluginsProvider = Provider<List<InstalledPlugin>>((ref) {
  final plugins =
      ref.watch(pluginsProvider).asData?.value ?? const <InstalledPlugin>[];
  return ref.read(pluginServiceProvider).effectivelyActive(plugins);
});
