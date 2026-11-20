import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:mouvi/core/plugins/plugin_models.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PluginInstallResult {
  const PluginInstallResult({required this.plugin, this.replaced = false});

  final InstalledPlugin plugin;
  final bool replaced;
}

class PluginServiceException implements Exception {
  const PluginServiceException(this.code, [this.details]);

  final String code;
  final String? details;

  @override
  String toString() =>
      'PluginServiceException($code${details == null ? '' : ': $details'})';
}

class PluginService {
  PluginService({http.Client? client}) : _client = client ?? http.Client();

  static const String _prefsKey = 'mouvi.plugins.v1';
  static const int currentApiVersion = 1;

  static const String basePluginId = 'mouvi-engine';

  static const String officialStoreRepo = 'bitplugg/mouvi-store';
  static const String officialStoreUrl =
      'https://github.com/bitplugg/mouvi-store';
  static const String officialStoreRawPrefix =
      'https://raw.githubusercontent.com/bitplugg/mouvi-store';

  final http.Client _client;

  Future<Directory> _pluginsRoot() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'plugins'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<List<InstalledPlugin>> loadInstalled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      List<InstalledPlugin> plugins;
      if (raw == null || raw.trim().isEmpty) {
        plugins = const <InstalledPlugin>[];
      } else {
        plugins = decodeInstalledPlugins(raw);
      }
      return _ensureBasePlugin(plugins);
    } catch (_) {
      return _ensureBasePlugin(const <InstalledPlugin>[]);
    }
  }

  List<InstalledPlugin> _ensureBasePlugin(List<InstalledPlugin> plugins) {
    final list = plugins.toList();
    final idx = list.indexWhere((p) => p.manifest.id == basePluginId);
    if (idx >= 0) {
      // Базовый плагин всегда считается официальным и принятым.
      final current = list[idx];
      if (!current.isOfficialStoreSource || !current.riskAccepted) {
        list[idx] = current.copyWith(riskAccepted: true);
      }
      return List<InstalledPlugin>.unmodifiable(list);
    }
    final base = InstalledPlugin(
      manifest: const PluginManifest(
        id: basePluginId,
        name: 'Mouvi Engine',
        version: '1.0.0',
        apiVersion: 1,
        author: 'Mouvi',
        description: 'Базовый системный плагин Mouvi. При отключении работа остальных плагинов приостанавливается.',
        permissions: <PluginPermission>[
          PluginPermission.ownStorage,
          PluginPermission.connectionState,
          PluginPermission.trafficStats,
          PluginPermission.configsMetadata,
          PluginPermission.manageConnection,
          PluginPermission.engineAccess,
        ],
        hooks: <PluginHook>[
          PluginHook.importValidation,
          PluginHook.engineProvider,
          PluginHook.connectionEvents,
          PluginHook.uiExtensions,
          PluginHook.uriHandlers,
        ],
      ),
      installPath: 'builtin',
      installedAt: DateTime.fromMillisecondsSinceEpoch(0),
      sourceKind: PluginSourceKind.store,
      sourceRef: officialStoreUrl,
      enabled: true,
      riskAccepted: true,
    );
    return List<InstalledPlugin>.unmodifiable(<InstalledPlugin>[base, ...list]);
  }

  Future<void> _saveInstalled(List<InstalledPlugin> plugins) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, encodeInstalledPlugins(plugins));
  }

  Future<PluginInstallResult> installFromFile({
    required String filePath,
    String? sourceRef,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw const PluginServiceException('file_not_found');
    }
    final bytes = await file.readAsBytes();
    return installFromBytes(
      bytes: bytes,
      sourceKind: PluginSourceKind.localFile,
      sourceRef: sourceRef ?? filePath,
    );
  }

  Future<PluginInstallResult> installFromUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
      throw const PluginServiceException('invalid_url');
    }
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw PluginServiceException('http_${response.statusCode}');
    }
    final kind = _isOfficialStoreUrl(url)
        ? PluginSourceKind.store
        : PluginSourceKind.url;
    return installFromBytes(
      bytes: response.bodyBytes,
      sourceKind: kind,
      sourceRef: url.trim(),
    );
  }

  bool _isOfficialStoreUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains(officialStoreRepo.toLowerCase()) ||
        lower.startsWith(officialStoreRawPrefix.toLowerCase());
  }

  Future<PluginInstallResult> installFromBytes({
    required List<int> bytes,
    required PluginSourceKind sourceKind,
    required String sourceRef,
  }) async {
    final archive = _decodeArchive(bytes);
    final manifest = _readManifest(archive);
    _validateManifest(manifest);

    final plugins = (await loadInstalled()).toList();
    final existingIndex = plugins.indexWhere(
      (p) => p.manifest.id == manifest.id,
    );
    final replaced = existingIndex >= 0;

    final root = await _pluginsRoot();
    final safeId = _safeId(manifest.id);
    final installDir = Directory(p.join(root.path, safeId));
    if (await installDir.exists()) {
      await installDir.delete(recursive: true);
    }
    await installDir.create(recursive: true);
    await _extractArchive(archive, installDir);

    final prev = replaced ? plugins[existingIndex] : null;
    final packageHash = sha256.convert(bytes).toString();
    final installed = InstalledPlugin(
      manifest: manifest,
      installPath: installDir.path,
      installedAt: DateTime.now(),
      sourceKind: sourceKind,
      sourceRef: sourceRef,
      enabled: prev?.enabled ?? false,
      riskAccepted:
          prev?.riskAccepted == true ||
          _isOfficialSource(sourceKind, sourceRef),
      packageHash: packageHash,
    );

    if (replaced) {
      plugins[existingIndex] = installed;
    } else {
      plugins.add(installed);
    }
    await _saveInstalled(plugins);
    return PluginInstallResult(plugin: installed, replaced: replaced);
  }

  bool _isOfficialSource(PluginSourceKind kind, String ref) {
    if (kind == PluginSourceKind.store) return true;
    return _isOfficialStoreUrl(ref);
  }

  Archive _decodeArchive(List<int> bytes) {
    try {
      return ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const PluginServiceException('invalid_archive');
    }
  }

  PluginManifest _readManifest(Archive archive) {
    ArchiveFile? file;
    for (final f in archive.files) {
      final name = f.name.replaceAll('\\', '/');
      if (name == 'manifest.json' || name.endsWith('/manifest.json')) {
        // Prefer root manifest.json
        if (name == 'manifest.json') {
          file = f;
          break;
        }
        file ??= f;
      }
    }
    if (file == null || !file.isFile) {
      throw const PluginServiceException('manifest_missing');
    }
    try {
      final content = utf8.decode(file.content as List<int>);
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        if (decoded is Map) {
          return PluginManifest.fromJson(
            decoded.map((k, v) => MapEntry(k.toString(), v)),
          );
        }
        throw const PluginServiceException('manifest_invalid');
      }
      return PluginManifest.fromJson(decoded);
    } catch (e) {
      if (e is PluginServiceException) rethrow;
      throw const PluginServiceException('manifest_invalid');
    }
  }

  void _validateManifest(PluginManifest manifest) {
    if (!manifest.isValid) {
      throw const PluginServiceException('manifest_invalid');
    }
    if (manifest.apiVersion > currentApiVersion) {
      throw const PluginServiceException('incompatible_api');
    }
    final idOk = RegExp(r'^[a-zA-Z0-9._-]{1,64}$').hasMatch(manifest.id);
    if (!idOk) {
      throw const PluginServiceException('invalid_plugin_id');
    }
  }

  String _safeId(String id) {
    return id.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  Future<void> _extractArchive(Archive archive, Directory targetDir) async {
    final targetPath = p.normalize(targetDir.path);
    for (final file in archive.files) {
      final name = file.name.replaceAll('\\', '/');
      if (name.isEmpty) continue;
      final outPath = p.normalize(p.join(targetPath, name));
      if (!p.isWithin(targetPath, outPath) && outPath != targetPath) {
        // Path traversal attempt — skip.
        continue;
      }
      if (file.isFile) {
        final outFile = File(outPath);
        await outFile.parent.create(recursive: true);
        final data = file.content as List<int>;
        await outFile.writeAsBytes(data, flush: true);
      } else {
        await Directory(outPath).create(recursive: true);
      }
    }
  }

  Future<void> setEnabled(String pluginId, bool enabled) async {
    final plugins = (await loadInstalled()).toList();
    final idx = plugins.indexWhere((p) => p.manifest.id == pluginId);
    if (idx < 0) return;
    plugins[idx] = plugins[idx].copyWith(enabled: enabled);
    await _saveInstalled(plugins);
  }

  Future<void> setRiskAccepted(String pluginId, bool accepted) async {
    final plugins = (await loadInstalled()).toList();
    final idx = plugins.indexWhere((p) => p.manifest.id == pluginId);
    if (idx < 0) return;
    plugins[idx] = plugins[idx].copyWith(riskAccepted: accepted);
    await _saveInstalled(plugins);
  }

  Future<void> remove(String pluginId) async {
    if (pluginId == basePluginId) {
      throw const PluginServiceException('cannot_remove_base');
    }
    final plugins = (await loadInstalled()).toList();
    final idx = plugins.indexWhere((p) => p.manifest.id == pluginId);
    if (idx < 0) return;
    final plugin = plugins[idx];
    plugins.removeAt(idx);
    await _saveInstalled(plugins);
    try {
      if (plugin.installPath.isNotEmpty && plugin.installPath != 'builtin') {
        final dir = Directory(plugin.installPath);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    } catch (_) {
      // Метаданные удалены — остатки на диске не критичны.
    }
  }

  bool isBaseEnabled(List<InstalledPlugin> plugins) {
    for (final p in plugins) {
      if (p.manifest.id == basePluginId) {
        return p.enabled;
      }
    }
    return false;
  }

  Future<List<InstalledPlugin>> enabledPlugins() async {
    final all = await loadInstalled();
    final baseEnabled = isBaseEnabled(all);
    if (!baseEnabled) {
      return const <InstalledPlugin>[];
    }
    return all.where((p) => p.enabled).toList(growable: false);
  }

  /// Плагины, чьи хуки реально активны (учитывает базовый mouvi-engine).
  List<InstalledPlugin> effectivelyActive(List<InstalledPlugin> plugins) {
    final baseEnabled = isBaseEnabled(plugins);
    if (!baseEnabled) {
      return const <InstalledPlugin>[];
    }
    return plugins.where((p) => p.enabled).toList(growable: false);
  }
}

final pluginServiceProvider = Provider<PluginService>((ref) {
  return PluginService();
});
