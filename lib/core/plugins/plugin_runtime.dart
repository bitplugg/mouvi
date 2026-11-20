import 'dart:convert';
import 'dart:io';

import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mouvi/core/plugins/plugin_models.dart';
import 'package:path/path.dart' as p;

class PluginRuntimeException implements Exception {
  const PluginRuntimeException(this.message);
  final String message;
  @override
  String toString() => 'PluginRuntimeException($message)';
}

class PluginHookResult {
  const PluginHookResult({required this.ok, this.value, this.error});

  final bool ok;
  final dynamic value;
  final String? error;

  Map<String, dynamic>? get mapValue {
    final v = value;
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
    return null;
  }

  List<dynamic>? get listValue {
    final v = value;
    if (v is List) return v;
    return null;
  }
}

class _RuntimeInstance {
  _RuntimeInstance({
    required this.pluginId,
    required this.installPath,
    required this.runtime,
  });

  final String pluginId;
  final String installPath;
  final JavascriptRuntime runtime;
  bool initialized = false;
  String? initError;
}

class PluginRuntimeService {
  final Map<String, _RuntimeInstance> _instances = <String, _RuntimeInstance>{};

  void dispose() {
    for (final instance in _instances.values) {
      try {
        instance.runtime.dispose();
      } catch (_) {}
    }
    _instances.clear();
  }

  void disposePlugin(String pluginId) {
    final instance = _instances.remove(pluginId);
    if (instance == null) return;
    try {
      instance.runtime.dispose();
    } catch (_) {}
  }

  Future<void> resetForPlugin(String pluginId) async {
    disposePlugin(pluginId);
  }

  Future<PluginHookResult> callHook({
    required InstalledPlugin plugin,
    required String hookName,
    Map<String, dynamic> payload = const <String, dynamic>{},
    Map<String, dynamic> hostState = const <String, dynamic>{},
  }) async {
    if (!plugin.manifest.hasRuntime) {
      return const PluginHookResult(ok: false, error: 'no_runtime');
    }
    if (plugin.installPath.isEmpty || plugin.installPath == 'builtin') {
      return const PluginHookResult(ok: false, error: 'invalid_install_path');
    }
    final instance = await _ensureInstance(plugin);
    if (instance == null) {
      return const PluginHookResult(ok: false, error: 'runtime_unavailable');
    }
    if (instance.initError != null) {
      return PluginHookResult(ok: false, error: instance.initError);
    }
    try {
      final storage = await _loadStorage(plugin);
      final safeHost = <String, dynamic>{
        'plugin': plugin.toRuntimeContext(),
        'state': hostState,
        'storage': storage,
      };
      final hostJson = jsonEncode(safeHost);
      final payloadJson = jsonEncode(payload);
      final setup = 'globalThis.__MOUVI_HOST__ = $hostJson;';
      instance.runtime.evaluate(setup);
      final callCode =
          '''
(function(){
  try {
    var host = globalThis.__MOUVI_HOST__ || {};
    var payload = $payloadJson;
    var hooks = (globalThis.MouviPlugin && globalThis.MouviPlugin.hooks) || globalThis.MouviHooks || globalThis;
    var fn = hooks && hooks["$hookName"];
    if (typeof fn !== "function") { return JSON.stringify({__ok:false,__err:"hook_not_found"}); }
    var res = fn(payload, host);
    var storage = (globalThis.__MOUVI_HOST__ && globalThis.__MOUVI_HOST__.storage) || null;
    return JSON.stringify({__ok:true,__value:res,__storage:storage});
  } catch (e) {
    var msg = (e && e.stack) ? String(e.stack) : String(e);
    return JSON.stringify({__ok:false,__err:msg});
  }
})()
''';
      final result = instance.runtime.evaluate(callCode);
      final raw = result.stringResult;
      if (raw.isEmpty) {
        return const PluginHookResult(ok: false, error: 'empty_result');
      }
      dynamic decoded;
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        // Some runtimes return already-encoded string quirks; try best effort.
        return PluginHookResult(ok: true, value: raw);
      }
      if (decoded is! Map) {
        return PluginHookResult(ok: true, value: decoded);
      }
      final map = decoded.map((k, v) => MapEntry(k.toString(), v));
      if (map['__storage'] is Map &&
          plugin.manifest.permissions.contains(PluginPermission.ownStorage)) {
        await _saveStorage(plugin, map['__storage'] as Map);
      }
      final ok = map['__ok'] == true;
      if (!ok) {
        return PluginHookResult(
          ok: false,
          error: map['__err']?.toString() ?? 'hook_failed',
        );
      }
      return PluginHookResult(ok: true, value: map['__value']);
    } catch (e) {
      return PluginHookResult(ok: false, error: e.toString());
    }
  }

  Future<_RuntimeInstance?> _ensureInstance(InstalledPlugin plugin) async {
    final existing = _instances[plugin.manifest.id];
    if (existing != null) return existing;

    final runtime = getJavascriptRuntime();
    final instance = _RuntimeInstance(
      pluginId: plugin.manifest.id,
      installPath: plugin.installPath,
      runtime: runtime,
    );
    _instances[plugin.manifest.id] = instance;

    try {
      final entry = plugin.manifest.entry?.trim();
      if (entry == null || entry.isEmpty) {
        instance.initError = 'entry_missing';
        return instance;
      }
      final entryPath = _resolvePath(plugin.installPath, entry);
      if (entryPath == null) {
        instance.initError = 'entry_outside_plugin';
        return instance;
      }
      final file = File(entryPath);
      if (!await file.exists()) {
        instance.initError = 'entry_not_found';
        return instance;
      }
      final code = await file.readAsString();
      _bootstrapHost(runtime, plugin);
      final eval = runtime.evaluate(code);
      if (eval.isError) {
        instance.initError = eval.stringResult.isNotEmpty
            ? eval.stringResult
            : 'entry_eval_error';
      } else {
        instance.initialized = true;
      }
    } catch (e) {
      instance.initError = e.toString();
    }
    return instance;
  }

  void _bootstrapHost(JavascriptRuntime runtime, InstalledPlugin plugin) {
    final perms = plugin.manifest.permissions.map((p) => p.name).toList();
    final permsJson = jsonEncode(perms);
    final bootstrap =
        '''
globalThis.Mouvi = globalThis.Mouvi || {};
globalThis.Mouvi.permissions = $permsJson;
globalThis.Mouvi.plugin = ${jsonEncode(plugin.toRuntimeContext())};
globalThis.Mouvi.log = function(level, msg) {
  // Host receives logs via hook result side effects in future; no-op for MVP.
  return true;
};
globalThis.Mouvi.storage = globalThis.Mouvi.storage || {};
globalThis.Mouvi.storage.get = function(key) {
  var s = (globalThis.__MOUVI_HOST__ && globalThis.__MOUVI_HOST__.storage) || {};
  return s[key];
};
globalThis.Mouvi.storage.set = function(key, value) {
  if (!globalThis.__MOUVI_HOST__) globalThis.__MOUVI_HOST__ = {};
  if (!globalThis.__MOUVI_HOST__.storage) globalThis.__MOUVI_HOST__.storage = {};
  globalThis.__MOUVI_HOST__.storage[String(key)] = value;
  return true;
};
globalThis.Mouvi.storage.remove = function(key) {
  if (globalThis.__MOUVI_HOST__ && globalThis.__MOUVI_HOST__.storage) {
    delete globalThis.__MOUVI_HOST__.storage[String(key)];
  }
  return true;
};
globalThis.Mouvi.storage.all = function() {
  return (globalThis.__MOUVI_HOST__ && globalThis.__MOUVI_HOST__.storage) || {};
};
''';
    runtime.evaluate(bootstrap);
  }

  String? _resolvePath(String baseDir, String relative) {
    final normalizedBase = p.normalize(baseDir);
    final joined = p.normalize(p.join(normalizedBase, relative));
    if (!p.isWithin(normalizedBase, joined) && joined != normalizedBase) {
      return null;
    }
    return joined;
  }

  Future<File> _storageFile(InstalledPlugin plugin) async {
    final dir = Directory(p.join(plugin.installPath, '.mouvi_storage'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File(p.join(dir.path, 'storage.json'));
  }

  Future<Map<String, dynamic>> _loadStorage(InstalledPlugin plugin) async {
    if (!plugin.manifest.permissions.contains(PluginPermission.ownStorage)) {
      return <String, dynamic>{};
    }
    try {
      final file = await _storageFile(plugin);
      if (!await file.exists()) return <String, dynamic>{};
      final content = await file.readAsString();
      if (content.trim().isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(content);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  Future<void> _saveStorage(
    InstalledPlugin plugin,
    Map<dynamic, dynamic> storage,
  ) async {
    if (!plugin.manifest.permissions.contains(PluginPermission.ownStorage)) {
      return;
    }
    try {
      final file = await _storageFile(plugin);
      final map = storage.map((k, v) => MapEntry(k.toString(), v));
      await file.writeAsString(jsonEncode(map));
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getUiExtensions({
    required InstalledPlugin plugin,
    Map<String, dynamic> hostState = const <String, dynamic>{},
  }) async {
    final result = await callHook(
      plugin: plugin,
      hookName: 'getUiExtensions',
      payload: const <String, dynamic>{},
      hostState: hostState,
    );
    if (!result.ok) return const <Map<String, dynamic>>[];
    final value = result.value;
    if (value is List) {
      return value
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList(growable: false);
    }
    if (value is Map) {
      final map = value.map((k, v) => MapEntry(k.toString(), v));
      final items = map['items'] ?? map['extensions'];
      if (items is List) {
        return items
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
            .toList(growable: false);
      }
      // Single extension object
      return <Map<String, dynamic>>[map];
    }
    return const <Map<String, dynamic>>[];
  }

  Future<PluginHookResult> dispatchUiAction({
    required InstalledPlugin plugin,
    required String actionId,
    Map<String, dynamic> payload = const <String, dynamic>{},
    Map<String, dynamic> hostState = const <String, dynamic>{},
  }) {
    return callHook(
      plugin: plugin,
      hookName: 'onUiAction',
      payload: <String, dynamic>{'action': actionId, 'payload': payload},
      hostState: hostState,
    );
  }
}

final pluginRuntimeServiceProvider = Provider<PluginRuntimeService>((ref) {
  final service = PluginRuntimeService();
  ref.onDispose(service.dispose);
  return service;
});
