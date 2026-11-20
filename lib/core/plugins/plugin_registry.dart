import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mouvi/core/plugins/plugin_models.dart';
import 'package:mouvi/core/plugins/plugin_runtime.dart';
import 'package:mouvi/state/plugins_provider.dart';

class PluginRegistry {
  PluginRegistry(this._ref);

  final Ref _ref;

  List<InstalledPlugin> get _active => _ref.read(activePluginsProvider);
  PluginRuntimeService get _runtime => _ref.read(pluginRuntimeServiceProvider);

  /// Проверяет импорт через runtime-хук и декларативные правила активных плагинов.
  Future<PluginImportMatch?> matchImport(
    String content, {
    Map<String, dynamic> hostState = const <String, dynamic>{},
  }) async {
    for (final plugin in _active) {
      final hasHook = plugin.manifest.hooks.contains(
        PluginHook.importValidation,
      );
      final hasRules = plugin.manifest.importRules.isNotEmpty;
      if (!hasHook && !hasRules) continue;

      if (hasHook && plugin.manifest.hasRuntime) {
        try {
          final result = await _runtime.callHook(
            plugin: plugin,
            hookName: 'onImportValidate',
            payload: <String, dynamic>{'content': content},
            hostState: hostState,
          );
          final match = _parseRuntimeImportMatch(plugin, result);
          if (match != null) return match;
        } catch (_) {
          // Изоляция: ошибка плагина не ломает импорт.
        }
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

  PluginImportMatch? _parseRuntimeImportMatch(
    InstalledPlugin plugin,
    PluginHookResult result,
  ) {
    if (!result.ok) return null;
    final value = result.value;
    if (value == null || value == false) return null;
    if (value == true) {
      return PluginImportMatch(
        pluginId: plugin.manifest.id,
        pluginName: plugin.manifest.name,
        ruleId: 'runtime',
        label: plugin.manifest.name,
      );
    }
    if (value is! Map) return null;
    final map = value.map((k, v) => MapEntry(k.toString(), v));
    final matched =
        map['match'] == true ||
        map['ok'] == true ||
        map['recognized'] == true ||
        map['handled'] == true;
    if (!matched) return null;
    final protocol = map['protocol']?.toString();
    final transformed = map['content']?.toString();
    final name = map['name']?.toString();
    final label = (map['label'] ?? map['ruleId'] ?? plugin.manifest.name)
        .toString();
    return PluginImportMatch(
      pluginId: plugin.manifest.id,
      pluginName: plugin.manifest.name,
      ruleId: (map['ruleId'] ?? 'runtime').toString(),
      label: label,
      protocol: protocol,
      content: transformed,
      name: name,
      metadata: map,
    );
  }

  Future<void> emitConnectionEvent(
    String event, {
    Map<String, dynamic> data = const <String, dynamic>{},
    Map<String, dynamic> hostState = const <String, dynamic>{},
  }) async {
    final plugins = pluginsWithHook(PluginHook.connectionEvents)
        .where((p) => p.manifest.hasRuntime)
        .toList(growable: false);
    for (final plugin in plugins) {
      try {
        await _runtime.callHook(
          plugin: plugin,
          hookName: 'onConnectionEvent',
          payload: <String, dynamic>{'event': event, 'data': data},
          hostState: hostState,
        );
      } catch (_) {
        // Изоляция: сбой плагина не влияет на соединение.
      }
    }
  }

  /// Подготовка подключения движком-плагином (адаптер/трансформация конфига).
  /// Возвращает карту с ключами protocol/content/name при успехе или null.
  Future<Map<String, dynamic>?> prepareEngineConnection({
    required Map<String, dynamic> request,
    Map<String, dynamic> hostState = const <String, dynamic>{},
  }) async {
    final plugins = pluginsWithHook(PluginHook.engineProvider)
        .where((p) => p.manifest.hasRuntime)
        .toList(growable: false);
    for (final plugin in plugins) {
      try {
        final result = await _runtime.callHook(
          plugin: plugin,
          hookName: 'prepareEngineConnection',
          payload: request,
          hostState: hostState,
        );
        if (!result.ok) continue;
        final map = result.mapValue;
        if (map == null) continue;
        final handled =
            map['handled'] == true ||
            map['ok'] == true ||
            map['match'] == true ||
            map['protocol'] != null ||
            map['content'] != null;
        if (!handled) continue;
        return <String, dynamic>{
          'pluginId': plugin.manifest.id,
          'pluginName': plugin.manifest.name,
          ...map,
        };
      } catch (_) {}
    }
    return null;
  }

  Future<Map<String, dynamic>?> handleUri(
    String uri, {
    Map<String, dynamic> hostState = const <String, dynamic>{},
  }) async {
    final plugins = pluginsWithHook(PluginHook.uriHandlers)
        .where((p) => p.manifest.hasRuntime)
        .toList(growable: false);
    for (final plugin in plugins) {
      try {
        final result = await _runtime.callHook(
          plugin: plugin,
          hookName: 'handleUri',
          payload: <String, dynamic>{'uri': uri},
          hostState: hostState,
        );
        if (!result.ok) continue;
        final map = result.mapValue;
        if (map == null) continue;
        if (map['handled'] == true ||
            map['ok'] == true ||
            map['match'] == true) {
          return <String, dynamic>{
            'pluginId': plugin.manifest.id,
            'pluginName': plugin.manifest.name,
            ...map,
          };
        }
      } catch (_) {}
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

final pluginRegistryProvider = Provider<PluginRegistry>((ref) {
  return PluginRegistry(ref);
});
