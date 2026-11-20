import 'dart:convert';

enum PluginPermission {
  ownStorage,
  connectionState,
  trafficStats,
  configsMetadata,
  sensitiveData,
  manageConnection,
  engineAccess,
  uiExtensions,
  uriHandlers,
}

enum PluginHook {
  importValidation,
  engineProvider,
  connectionEvents,
  uiExtensions,
  uriHandlers,
}

enum PluginRuntimeKind { none, javascript }

enum PluginSourceKind { store, localFile, url, unknown }

class PluginManifest {
  const PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.apiVersion,
    required this.author,
    required this.description,
    this.minAppVersion,
    this.homepage,
    this.permissions = const <PluginPermission>[],
    this.hooks = const <PluginHook>[],
    this.importRules = const <PluginImportRule>[],
    this.dependencies = const <String, String>{},
    this.runtime = PluginRuntimeKind.none,
    this.entry,
    this.engine = const <String, dynamic>{},
    this.ui = const <String, dynamic>{},
  });

  final String id;
  final String name;
  final String version;
  final int apiVersion;
  final String author;
  final String description;
  final String? minAppVersion;
  final String? homepage;
  final List<PluginPermission> permissions;
  final List<PluginHook> hooks;
  final List<PluginImportRule> importRules;
  final Map<String, String> dependencies;
  final PluginRuntimeKind runtime;
  final String? entry;
  final Map<String, dynamic> engine;
  final Map<String, dynamic> ui;

  factory PluginManifest.fromJson(Map<String, dynamic> json) {
    String readString(String key, {String fallback = ''}) {
      final value = json[key];
      return value is String && value.trim().isNotEmpty
          ? value.trim()
          : fallback;
    }

    int readInt(String key, {int fallback = 1}) {
      final value = json[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? fallback;
      return fallback;
    }

    List<T> readEnumList<T>(
      String key,
      List<T> values,
      String Function(T) nameOf,
    ) {
      final raw = json[key];
      if (raw is! List) return <T>[];
      final out = <T>[];
      for (final item in raw) {
        if (item is! String) continue;
        for (final v in values) {
          if (nameOf(v) == item ||
              nameOf(v).toLowerCase() == item.toLowerCase()) {
            out.add(v);
            break;
          }
        }
      }
      return out;
    }

    String permName(PluginPermission p) => switch (p) {
      PluginPermission.ownStorage => 'ownStorage',
      PluginPermission.connectionState => 'connectionState',
      PluginPermission.trafficStats => 'trafficStats',
      PluginPermission.configsMetadata => 'configsMetadata',
      PluginPermission.sensitiveData => 'sensitiveData',
      PluginPermission.manageConnection => 'manageConnection',
      PluginPermission.engineAccess => 'engineAccess',
      PluginPermission.uiExtensions => 'uiExtensions',
      PluginPermission.uriHandlers => 'uriHandlers',
    };
    String hookName(PluginHook h) => switch (h) {
      PluginHook.importValidation => 'importValidation',
      PluginHook.engineProvider => 'engineProvider',
      PluginHook.connectionEvents => 'connectionEvents',
      PluginHook.uiExtensions => 'uiExtensions',
      PluginHook.uriHandlers => 'uriHandlers',
    };

    final importRules = <PluginImportRule>[];
    final rawRules = json['importRules'];
    if (rawRules is List) {
      for (final item in rawRules) {
        if (item is Map) {
          importRules.add(
            PluginImportRule.fromJson(
              item.map((k, v) => MapEntry(k.toString(), v)),
            ),
          );
        }
      }
    }

    final deps = <String, String>{};
    final rawDeps = json['dependencies'];
    if (rawDeps is Map) {
      for (final entry in rawDeps.entries) {
        deps[entry.key.toString()] = entry.value?.toString() ?? '*';
      }
    }

    PluginRuntimeKind readRuntime() {
      final raw = json['runtime'];
      if (raw is! String) return PluginRuntimeKind.none;
      final v = raw.trim().toLowerCase();
      if (v == 'javascript' || v == 'js' || v == 'quickjs') {
        return PluginRuntimeKind.javascript;
      }
      return PluginRuntimeKind.none;
    }

    String? readOptionalString(String key) {
      final v = json[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
      return null;
    }

    Map<String, dynamic> readObject(String key) {
      final v = json[key];
      if (v is Map) {
        return v.map((k, val) => MapEntry(k.toString(), val));
      }
      return const <String, dynamic>{};
    }

    return PluginManifest(
      id: readString('id'),
      name: readString('name'),
      version: readString('version', fallback: '0.0.0'),
      apiVersion: readInt('apiVersion', fallback: 1),
      author: readString('author', fallback: 'Unknown'),
      description: readString('description'),
      minAppVersion: json['minAppVersion'] is String
          ? (json['minAppVersion'] as String).trim()
          : null,
      homepage: json['homepage'] is String
          ? (json['homepage'] as String).trim()
          : null,
      permissions: readEnumList(
        'permissions',
        PluginPermission.values,
        permName,
      ),
      hooks: readEnumList('hooks', PluginHook.values, hookName),
      importRules: importRules,
      dependencies: deps,
      runtime: readRuntime(),
      entry: readOptionalString('entry'),
      engine: readObject('engine'),
      ui: readObject('ui'),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'version': version,
    'apiVersion': apiVersion,
    'author': author,
    'description': description,
    if (minAppVersion != null) 'minAppVersion': minAppVersion,
    if (homepage != null) 'homepage': homepage,
    'permissions': permissions.map((p) => p.name).toList(),
    'hooks': hooks.map((h) => h.name).toList(),
    'importRules': importRules.map((r) => r.toJson()).toList(),
    if (dependencies.isNotEmpty) 'dependencies': dependencies,
    if (runtime != PluginRuntimeKind.none) 'runtime': runtime.name,
    if (entry != null && entry!.isNotEmpty) 'entry': entry,
    if (engine.isNotEmpty) 'engine': engine,
    if (ui.isNotEmpty) 'ui': ui,
  };

  bool get hasRuntime =>
      runtime != PluginRuntimeKind.none && (entry?.isNotEmpty ?? false);

  bool get isValid => id.trim().isNotEmpty && name.trim().isNotEmpty;
}

/// Declarative import rule (MVP): allows plugins to detect/label configs
/// without executing arbitrary code.
class PluginImportRule {
  const PluginImportRule({
    required this.id,
    required this.label,
    this.uriSchemes = const <String>[],
    this.containsAll = const <String>[],
    this.containsAny = const <String>[],
    this.regex,
  });

  final String id;
  final String label;
  final List<String> uriSchemes;
  final List<String> containsAll;
  final List<String> containsAny;
  final String? regex;

  factory PluginImportRule.fromJson(Map<String, dynamic> json) {
    List<String> readStrings(String key) {
      final raw = json[key];
      if (raw is! List) return const <String>[];
      return raw
          .whereType<String>()
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    }

    return PluginImportRule(
      id: (json['id'] as String?)?.trim() ?? '',
      label: (json['label'] as String?)?.trim() ?? 'Plugin',
      uriSchemes: readStrings('uriSchemes'),
      containsAll: readStrings('containsAll'),
      containsAny: readStrings('containsAny'),
      regex: (json['regex'] as String?)?.trim(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'label': label,
    if (uriSchemes.isNotEmpty) 'uriSchemes': uriSchemes,
    if (containsAll.isNotEmpty) 'containsAll': containsAll,
    if (containsAny.isNotEmpty) 'containsAny': containsAny,
    if (regex != null && regex!.isNotEmpty) 'regex': regex,
  };

  bool matches(String content) {
    final trimmed = content.trim();
    final lower = trimmed.toLowerCase();
    for (final scheme in uriSchemes) {
      final s = scheme.toLowerCase();
      final prefix = s.endsWith('://') ? s : '$s://';
      if (lower.startsWith(prefix)) {
        return true;
      }
    }
    if (containsAll.isNotEmpty) {
      final ok = containsAll.every((t) => lower.contains(t.toLowerCase()));
      if (ok) return true;
    }
    if (containsAny.isNotEmpty) {
      final ok = containsAny.any((t) => lower.contains(t.toLowerCase()));
      if (ok) return true;
    }
    final r = regex;
    if (r != null && r.isNotEmpty) {
      try {
        if (RegExp(
          r,
          caseSensitive: false,
          multiLine: true,
        ).hasMatch(trimmed)) {
          return true;
        }
      } catch (_) {
        // Неверное выражение в манифесте — игнорируем.
      }
    }
    return false;
  }
}

class InstalledPlugin {
  const InstalledPlugin({
    required this.manifest,
    required this.installPath,
    required this.installedAt,
    required this.sourceKind,
    required this.sourceRef,
    required this.enabled,
    required this.riskAccepted,
    this.packageHash,
  });

  final PluginManifest manifest;
  final String installPath;
  final DateTime installedAt;
  final PluginSourceKind sourceKind;
  final String sourceRef; // file path, url, or store ref
  final bool enabled;
  final bool riskAccepted;
  final String?
  packageHash; // SHA-256 of installed .mu package bytes (if known)

  bool get isOfficialStoreSource {
    final ref = sourceRef.toLowerCase();
    return sourceKind == PluginSourceKind.store ||
        ref.contains('github.com/bitplugg/mouvi-store') ||
        ref.contains('raw.githubusercontent.com/bitplugg/mouvi-store');
  }

  InstalledPlugin copyWith({
    bool? enabled,
    bool? riskAccepted,
    String? packageHash,
  }) {
    return InstalledPlugin(
      manifest: manifest,
      installPath: installPath,
      installedAt: installedAt,
      sourceKind: sourceKind,
      sourceRef: sourceRef,
      enabled: enabled ?? this.enabled,
      riskAccepted: riskAccepted ?? this.riskAccepted,
      packageHash: packageHash ?? this.packageHash,
    );
  }

  Map<String, dynamic> toRuntimeContext() => <String, dynamic>{
    'id': manifest.id,
    'name': manifest.name,
    'version': manifest.version,
    'installPath': installPath,
    'permissions': manifest.permissions.map((p) => p.name).toList(),
    'hooks': manifest.hooks.map((h) => h.name).toList(),
  };

  Map<String, dynamic> toJson() => <String, dynamic>{
    'manifest': manifest.toJson(),
    'installPath': installPath,
    'installedAt': installedAt.toIso8601String(),
    'sourceKind': sourceKind.name,
    'sourceRef': sourceRef,
    'enabled': enabled,
    'riskAccepted': riskAccepted,
    if (packageHash != null && packageHash!.isNotEmpty)
      'packageHash': packageHash,
  };

  static InstalledPlugin? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.map((k, v) => MapEntry(k.toString(), v));
    final manifestRaw = map['manifest'];
    if (manifestRaw is! Map) return null;
    final manifest = PluginManifest.fromJson(
      manifestRaw.map((k, v) => MapEntry(k.toString(), v)),
    );
    if (!manifest.isValid) return null;
    final sourceKindName = (map['sourceKind'] as String?) ?? 'unknown';
    final sourceKind = PluginSourceKind.values.firstWhere(
      (e) => e.name == sourceKindName,
      orElse: () => PluginSourceKind.unknown,
    );
    final hash = (map['packageHash'] as String?)?.trim();
    return InstalledPlugin(
      manifest: manifest,
      installPath: (map['installPath'] as String?) ?? '',
      installedAt:
          DateTime.tryParse((map['installedAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      sourceKind: sourceKind,
      sourceRef: (map['sourceRef'] as String?) ?? '',
      enabled: map['enabled'] == true,
      riskAccepted: map['riskAccepted'] == true,
      packageHash: (hash == null || hash.isEmpty) ? null : hash,
    );
  }
}

class PluginImportMatch {
  const PluginImportMatch({
    required this.pluginId,
    required this.pluginName,
    required this.ruleId,
    required this.label,
    this.protocol,
    this.content,
    this.name,
    this.metadata = const <String, dynamic>{},
  });

  final String pluginId;
  final String pluginName;
  final String ruleId;
  final String label;
  final String? protocol;
  final String? content;
  final String? name;
  final Map<String, dynamic> metadata;
}

String encodeInstalledPlugins(List<InstalledPlugin> plugins) {
  return jsonEncode(plugins.map((p) => p.toJson()).toList());
}

List<InstalledPlugin> decodeInstalledPlugins(String raw) {
  if (raw.trim().isEmpty) return const <InstalledPlugin>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <InstalledPlugin>[];
    final out = <InstalledPlugin>[];
    for (final item in decoded) {
      final p = InstalledPlugin.fromJson(item);
      if (p != null) out.add(p);
    }
    return out;
  } catch (_) {
    return const <InstalledPlugin>[];
  }
}
