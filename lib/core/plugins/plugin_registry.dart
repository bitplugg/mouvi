import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mouvi/core/plugins/plugin_models.dart';
import 'package:mouvi/state/plugins_provider.dart';

class PluginRegistry {
  PluginRegistry(this._ref);

  final Ref _ref;

  List<InstalledPlugin> get _active => _ref.read(activePluginsProvider);

  /// Ищет первое совпадение декларативного правила импорта среди активных плагинов.
  PluginImportMatch? matchImport(String content) {
    for (final plugin in _active) {
      if (!plugin.manifest.hooks.contains(PluginHook.importValidation) &&
          plugin.manifest.importRules.isEmpty) {
        continue;
      }
      for (final rule in plugin.manifest.importRules) {
        if (rule.matches(content)) {
          return PluginImportMatch(
            pluginId: plugin.manifest.id,
            pluginName: plugin.manifest.name,
            ruleId: rule.id,
            label: rule.label,
          );
        }
      }
    }
    return null;
  }

  bool get hasActiveUiExtensions =>
      _active.any((p) => p.manifest.hooks.contains(PluginHook.uiExtensions));

  bool get hasActiveEngineProviders =>
      _active.any((p) => p.manifest.hooks.contains(PluginHook.engineProvider));

  List<InstalledPlugin> pluginsWithHook(PluginHook hook) => _active
      .where((p) => p.manifest.hooks.contains(hook))
      .toList(growable: false);
}

class PluginImportMatch {
  const PluginImportMatch({
    required this.pluginId,
    required this.pluginName,
    required this.ruleId,
    required this.label,
  });

  final String pluginId;
  final String pluginName;
  final String ruleId;
  final String label;
}

final pluginRegistryProvider = Provider<PluginRegistry>((ref) {
  return PluginRegistry(ref);
});
