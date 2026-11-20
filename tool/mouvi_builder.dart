#!/usr/bin/env dart

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

const int currentApiVersion = 1;

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    _printUsage();
    exitCode = 64;
    return;
  }
  final command = args.first;
  final rest = args.skip(1).toList();
  try {
    switch (command) {
      case 'build':
        await _build(rest);
      case 'validate':
        await _validate(rest);
      case 'init':
        await _init(rest);
      case 'help':
      case '--help':
      case '-h':
        _printUsage();
      default:
        stderr.writeln('Unknown command: $command');
        _printUsage();
        exitCode = 64;
    }
  } on _BuilderException catch (e) {
    stderr.writeln('Error: ${e.message}');
    exitCode = 1;
  } catch (e) {
    stderr.writeln('Error: $e');
    exitCode = 1;
  }
}

class _BuilderException implements Exception {
  _BuilderException(this.message);
  final String message;
  @override
  String toString() => message;
}

void _printUsage() {
  print('mouvi-builder — build and validate Mouvi .mu plugins');
  print('');
  print('Usage:');
  print('  dart run tool/mouvi_builder.dart <command> [options]');
  print('');
  print('Commands:');
  print(
    '  build <plugin_dir> [-o <output.mu>]   Package a plugin directory into a .mu file',
  );
  print(
    '  validate <path>                        Validate a plugin directory or .mu file',
  );
  print(
    '  init <dir> [--id <id>] [--name <name>] [--with-code] Scaffold a new plugin project',
  );
  print('  help                                   Show this help');
  print('');
  print('Examples:');
  print(
    '  dart run tool/mouvi_builder.dart build ./my-plugin -o ./my-plugin.mu',
  );
  print('  dart run tool/mouvi_builder.dart validate ./my-plugin');
  print(
    '  dart run tool/mouvi_builder.dart init ./my-plugin --id com.example.myplugin --with-code',
  );
}

String? _opt(List<String> args, String name) {
  final i = args.indexOf(name);
  if (i < 0 || i + 1 >= args.length) return null;
  return args[i + 1];
}

Future<void> _build(List<String> args) async {
  if (args.isEmpty || args.first.startsWith('-')) {
    throw _BuilderException('build requires <plugin_dir>');
  }
  final dirPath = args.first;
  final dir = Directory(dirPath);
  if (!await dir.exists()) {
    throw _BuilderException('Directory not found: $dirPath');
  }
  final manifest = await _readManifestFromDir(dir);
  _validateManifestMap(manifest);
  _validateEntryIfPresent(dir, manifest);

  final id = (manifest['id'] as String).trim();
  final version = (manifest['version'] as String?)?.trim();
  final outOpt = _opt(args, '-o') ?? _opt(args, '--output');
  final outPath =
      outOpt ??
      p.join(
        Directory.current.path,
        '${_safeName(id)}-${_safeName(version ?? '0.0.0')}.mu',
      );

  final outFile = File(outPath);
  await outFile.parent.create(recursive: true);
  if (await outFile.exists()) {
    await outFile.delete();
  }

  final encoder = ZipFileEncoder();
  encoder.create(outPath);

  final entries = await dir.list(recursive: true, followLinks: false).toList();
  entries.sort((a, b) => a.path.compareTo(b.path));
  var count = 0;
  for (final entity in entries) {
    if (entity is! File) continue;
    final rel = p.relative(entity.path, from: dir.path);
    final normalized = rel.replaceAll('\\', '/');
    if (normalized.isEmpty || normalized.startsWith('.git/')) continue;
    // Keep manifest.json at root; include everything else as-is.
    await encoder.addFile(entity, normalized);
    count++;
  }
  await encoder.close();

  print('OK: built $outPath');
  print('  id: $id');
  print('  name: ${manifest['name']}');
  print('  version: ${version ?? '0.0.0'}');
  if (manifest['runtime'] is String) {
    print('  runtime: ${manifest['runtime']}');
  }
  print('  files: $count');
}

void _validateEntryIfPresent(Directory dir, Map<String, dynamic> manifest) {
  final runtime = manifest['runtime'];
  final entry = manifest['entry'];
  if (runtime is! String || runtime.trim().isEmpty) return;
  if (entry is! String || entry.trim().isEmpty) return;
  final normalizedBase = p.normalize(dir.path);
  final joined = p.normalize(p.join(normalizedBase, entry.trim()));
  if (!p.isWithin(normalizedBase, joined) && joined != normalizedBase) {
    throw _BuilderException(
      'manifest.entry must be inside the plugin directory',
    );
  }
  final file = File(joined);
  if (!file.existsSync()) {
    throw _BuilderException('manifest.entry file not found: ${entry.trim()}');
  }
}

Future<void> _validate(List<String> args) async {
  if (args.isEmpty) {
    throw _BuilderException(
      'validate requires <path> to a plugin directory or .mu file',
    );
  }
  final target = args.first;
  final type = await FileSystemEntity.type(target);
  if (type == FileSystemEntityType.notFound) {
    throw _BuilderException('Path not found: $target');
  }
  Map<String, dynamic> manifest;
  if (type == FileSystemEntityType.directory) {
    manifest = await _readManifestFromDir(Directory(target));
    _validateManifestMap(manifest);
    _validateEntryIfPresent(Directory(target), manifest);
  } else {
    manifest = await _readManifestFromMu(File(target));
    _validateManifestMap(manifest);
  }
  print('OK: manifest is valid');
  print('  id: ${manifest['id']}');
  print('  name: ${manifest['name']}');
  print('  version: ${manifest['version'] ?? '0.0.0'}');
  print('  apiVersion: ${manifest['apiVersion'] ?? 1}');
  final runtime = manifest['runtime'];
  if (runtime is String && runtime.trim().isNotEmpty) {
    print('  runtime: ${runtime.trim()}');
  }
  final entry = manifest['entry'];
  if (entry is String && entry.trim().isNotEmpty) {
    print('  entry: ${entry.trim()}');
  }
  final hooks = manifest['hooks'];
  if (hooks is List && hooks.isNotEmpty) {
    print('  hooks: ${hooks.join(', ')}');
  }
  final perms = manifest['permissions'];
  if (perms is List && perms.isNotEmpty) {
    print('  permissions: ${perms.join(', ')}');
  }
}

Future<void> _init(List<String> args) async {
  if (args.isEmpty) {
    throw _BuilderException('init requires <dir>');
  }
  final dirPath = args.first;
  final id = _opt(args, '--id') ?? 'com.example.my-plugin';
  final name = _opt(args, '--name') ?? 'My Plugin';
  final dir = Directory(dirPath);
  if (await dir.exists()) {
    final empty = await dir.list().isEmpty;
    if (!empty) {
      throw _BuilderException('Directory is not empty: $dirPath');
    }
  } else {
    await dir.create(recursive: true);
  }

  final withCode = args.contains('--with-code') || args.contains('--runtime');

  final manifest = <String, dynamic>{
    'id': id,
    'name': name,
    'version': '1.0.0',
    'apiVersion': currentApiVersion,
    'author': 'Your Name',
    'description': 'Describe what this plugin does.',
    'minAppVersion': '1.4.0',
    'permissions': [
      'ownStorage',
      'connectionState',
      'configsMetadata',
      'uiExtensions',
    ],
    'hooks': withCode
        ? [
            'importValidation',
            'connectionEvents',
            'uiExtensions',
            'engineProvider',
          ]
        : ['importValidation'],
    'importRules': [
      {
        'id': 'example-rule',
        'label': 'Example',
        'uriSchemes': ['myproto://'],
        'containsAny': ['[MyPluginConfig]'],
      },
    ],
    'dependencies': <String, String>{},
    if (withCode) ...<String, dynamic>{
      'runtime': 'javascript',
      'entry': 'main.js',
      'engine': {
        'type': 'adapter',
        'note': 'prepareEngineConnection may transform unsupported config to a supported protocol (e.g. wireguard/vless) when possible',
      },
      'ui': {'entryScreen': 'main'},
    },
  };

  final manifestFile = File(p.join(dir.path, 'manifest.json'));
  await manifestFile.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
  );

  if (withCode) {
    final mainJs = File(p.join(dir.path, 'main.js'));
    await mainJs.writeAsString(
      r'''// Mouvi plugin runtime (QuickJS). Hooks are synchronous.
// Exports: globalThis.MouviPlugin.hooks = { ... }

function _now() { return Date.now ? Date.now() : 0; }

globalThis.MouviPlugin = {
  hooks: {
    // Runtime import validation/parsing. Return {match:true,...} to handle.
    onImportValidate: function (payload, host) {
      var content = String((payload && payload.content) || '');
      var trimmed = content.trim();
      if (trimmed.indexOf('myproto://') === 0) {
        return {
          match: true,
          label: 'My Protocol',
          name: 'MyProto config',
          // Optional: transform to a natively supported protocol config.
          // protocol: 'wireguard',
          // content: '[Interface]...'
          metadata: { recognizedBy: 'runtime' }
        };
      }
      return null;
    },

    // Connection lifecycle events: beforeConnect, afterConnect, disconnect, connectError, networkChange
    onConnectionEvent: function (payload, host) {
      var s = (host && host.storage) || {};
      var events = Array.isArray(s.events) ? s.events : [];
      events.push({ t: _now(), event: payload && payload.event, data: payload && payload.data });
      if (events.length > 20) events = events.slice(events.length - 20);
      host.storage.events = events;
      return { ok: true };
    },

    // Declarative UI extensions rendered by Mouvi settings.
    getUiExtensions: function (payload, host) {
      var events = ((host && host.storage && host.storage.events) || []);
      var last = events.length ? events[events.length - 1] : null;
      return [{
        id: 'main',
        title: 'Plugin UI',
        items: [
          { type: 'text', style: 'title', text: 'Runtime plugin is active' },
          { type: 'keyValue', key: 'Last event', value: last ? String(last.event) : 'none' },
          { type: 'button', label: 'Ping', action: 'ping', primary: true },
          { type: 'button', label: 'Clear events', action: 'clearEvents' }
        ]
      }];
    },

    onUiAction: function (payload, host) {
      var action = payload && payload.action;
      if (action === 'ping') {
        return { message: 'pong from plugin runtime' };
      }
      if (action === 'clearEvents') {
        host.storage.events = [];
        return { message: 'Events cleared', items: [
          { type: 'text', style: 'title', text: 'Runtime plugin is active' },
          { type: 'keyValue', key: 'Last event', value: 'none' },
          { type: 'button', label: 'Ping', action: 'ping', primary: true },
          { type: 'button', label: 'Clear events', action: 'clearEvents' }
        ] };
      }
      return { message: 'Unknown action: ' + String(action) };
    },

    // Engine adapter hook: may return {handled:true, protocol:"wireguard"|"amneziawg"|"vless", content:"..."}
    // to bridge unsupported/custom configs to a natively supported engine.
    prepareEngineConnection: function (payload, host) {
      // Example stub: not handling by default.
      // if (String(payload && payload.protocol) === 'unknown') { return {handled:true, protocol:'wireguard', content:'...'}; }
      return { handled: false };
    }
  }
};
''',
    );
  }

  final readme = File(p.join(dir.path, 'README.md'));
  await readme.writeAsString('''# $name

Plugin id: `$id`

## Build
From the Mouvi repository root:

```bash
dart run tool/mouvi_builder.dart build ${dir.path}
```

Or validate:

```bash
dart run tool/mouvi_builder.dart validate ${dir.path}
```

## Install
Open Mouvi → Settings → Plugins → Install from file → select the generated `.mu` file.

Non-store plugins require accepting the risk warning: "Я согласен со всеми рисками".
''');

  final sample = File(p.join(dir.path, 'sample-config.txt'));
  await sample.writeAsString(
    'myproto://example\n# or include marker: [MyPluginConfig]\n',
  );

  print('OK: initialized plugin project at $dirPath');
  print('  manifest: ${manifestFile.path}');
  if (withCode) {
    print('  entry: ${p.join(dir.path, 'main.js')}');
  }
  print(
    '  next: edit manifest.json${withCode ? ' and main.js' : ''}, then run:',
  );
  print('        dart run tool/mouvi_builder.dart build $dirPath');
}

Future<Map<String, dynamic>> _readManifestFromDir(Directory dir) async {
  final file = File(p.join(dir.path, 'manifest.json'));
  if (!await file.exists()) {
    throw _BuilderException('manifest.json not found in ${dir.path}');
  }
  try {
    final content = await file.readAsString();
    final decoded = jsonDecode(content);
    if (decoded is! Map) {
      throw _BuilderException('manifest.json must be a JSON object');
    }
    return decoded.map((k, v) => MapEntry(k.toString(), v));
  } on FormatException catch (e) {
    throw _BuilderException('manifest.json is not valid JSON: ${e.message}');
  }
}

Future<Map<String, dynamic>> _readManifestFromMu(File file) async {
  final lower = file.path.toLowerCase();
  if (!lower.endsWith('.mu') && !lower.endsWith('.zip')) {
    throw _BuilderException('Expected a .mu (or .zip) file: ${file.path}');
  }
  final bytes = await file.readAsBytes();
  final archive = ZipDecoder().decodeBytes(bytes);
  ArchiveFile? manifestFile;
  for (final f in archive.files) {
    final name = f.name.replaceAll('\\', '/');
    if (name == 'manifest.json') {
      manifestFile = f;
      break;
    }
    if (name.endsWith('/manifest.json')) {
      manifestFile ??= f;
    }
  }
  if (manifestFile == null || !manifestFile.isFile) {
    throw _BuilderException('manifest.json not found inside ${file.path}');
  }
  try {
    final content = utf8.decode(manifestFile.content as List<int>);
    final decoded = jsonDecode(content);
    if (decoded is! Map) {
      throw _BuilderException('manifest.json must be a JSON object');
    }
    return decoded.map((k, v) => MapEntry(k.toString(), v));
  } on FormatException catch (e) {
    throw _BuilderException(
      'manifest.json in archive is not valid JSON: ${e.message}',
    );
  }
}

void _validateManifestMap(Map<String, dynamic> manifest) {
  final id = manifest['id'];
  if (id is! String || id.trim().isEmpty) {
    throw _BuilderException('manifest.id is required (non-empty string)');
  }
  final idOk = RegExp(r'^[a-zA-Z0-9._-]{1,64}$').hasMatch(id.trim());
  if (!idOk) {
    throw _BuilderException(
      'manifest.id must match ^[a-zA-Z0-9._-]{1,64}\$ (got "$id")',
    );
  }
  final name = manifest['name'];
  if (name is! String || name.trim().isEmpty) {
    throw _BuilderException('manifest.name is required (non-empty string)');
  }
  final version = manifest['version'];
  if (version is! String || version.trim().isEmpty) {
    throw _BuilderException('manifest.version is required (non-empty string)');
  }
  final api = manifest['apiVersion'] ?? 1;
  final apiInt = api is int
      ? api
      : (api is num ? api.toInt() : int.tryParse('$api'));
  if (apiInt == null || apiInt < 1) {
    throw _BuilderException('manifest.apiVersion must be a positive integer');
  }
  if (apiInt > currentApiVersion) {
    throw _BuilderException(
      'manifest.apiVersion $apiInt is newer than supported ($currentApiVersion)',
    );
  }
  final hooks = manifest['hooks'];
  if (hooks != null && hooks is! List) {
    throw _BuilderException('manifest.hooks must be an array if present');
  }
  final perms = manifest['permissions'];
  if (perms != null && perms is! List) {
    throw _BuilderException('manifest.permissions must be an array if present');
  }
  final rules = manifest['importRules'];
  if (rules != null && rules is! List) {
    throw _BuilderException('manifest.importRules must be an array if present');
  }
  final runtime = manifest['runtime'];
  if (runtime != null && runtime is! String) {
    throw _BuilderException('manifest.runtime must be a string if present');
  }
  final runtimeName = runtime is String ? runtime.trim().toLowerCase() : '';
  if (runtimeName.isNotEmpty &&
      runtimeName != 'javascript' &&
      runtimeName != 'js' &&
      runtimeName != 'quickjs') {
    throw _BuilderException(
      'manifest.runtime "$runtime" is not supported (use "javascript")',
    );
  }
  final entry = manifest['entry'];
  if (entry != null && entry is! String) {
    throw _BuilderException('manifest.entry must be a string if present');
  }
  if (runtimeName.isNotEmpty && (entry is! String || entry.trim().isEmpty)) {
    throw _BuilderException('manifest.entry is required when runtime is set');
  }
  final engine = manifest['engine'];
  if (engine != null && engine is! Map) {
    throw _BuilderException('manifest.engine must be an object if present');
  }
  final ui = manifest['ui'];
  if (ui != null && ui is! Map) {
    throw _BuilderException('manifest.ui must be an object if present');
  }
}

String _safeName(String s) {
  final cleaned = s.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '-');
  return cleaned.isEmpty ? 'plugin' : cleaned;
}
