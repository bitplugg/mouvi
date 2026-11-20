import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mouvi/core/plugins/plugin_models.dart';
import 'package:mouvi/core/plugins/plugin_runtime.dart';

class PluginExtensionsSection extends ConsumerStatefulWidget {
  const PluginExtensionsSection({
    super.key,
    required this.plugins,
    this.hostState = const <String, dynamic>{},
  });

  final List<InstalledPlugin> plugins;
  final Map<String, dynamic> hostState;

  @override
  ConsumerState<PluginExtensionsSection> createState() =>
      _PluginExtensionsSectionState();
}

class _PluginExtensionsSectionState
    extends ConsumerState<PluginExtensionsSection> {
  late Future<List<_PluginUiEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant PluginExtensionsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plugins != widget.plugins) {
      _future = _load();
    }
  }

  Future<List<_PluginUiEntry>> _load() async {
    final runtime = ref.read(pluginRuntimeServiceProvider);
    final out = <_PluginUiEntry>[];
    for (final plugin in widget.plugins) {
      if (!plugin.manifest.hooks.contains(PluginHook.uiExtensions)) continue;
      if (!plugin.manifest.hasRuntime) continue;
      try {
        final items = await runtime.getUiExtensions(
          plugin: plugin,
          hostState: widget.hostState,
        );
        for (var i = 0; i < items.length; i++) {
          final ext = items[i];
          final id = (ext['id'] ?? '$i').toString();
          final title = (ext['title'] ?? plugin.manifest.name).toString();
          out.add(
            _PluginUiEntry(
              plugin: plugin,
              extensionId: id,
              title: title,
              extension: ext,
            ),
          );
        }
      } catch (_) {
        // Ошибка плагина не должна ломать экран.
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final candidates = widget.plugins
        .where(
          (p) =>
              p.manifest.hooks.contains(PluginHook.uiExtensions) &&
              p.manifest.hasRuntime,
        )
        .toList(growable: false);
    if (candidates.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<List<_PluginUiEntry>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          );
        }
        final entries = snapshot.data ?? const <_PluginUiEntry>[];
        if (entries.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(
              'Расширения плагинов',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            ...entries.map(
              (e) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.widgets_outlined),
                  title: Text(e.title),
                  subtitle: Text(e.plugin.manifest.name),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PluginExtensionScreen(
                        plugin: e.plugin,
                        extensionId: e.extensionId,
                        title: e.title,
                        extension: e.extension,
                        hostState: widget.hostState,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PluginUiEntry {
  const _PluginUiEntry({
    required this.plugin,
    required this.extensionId,
    required this.title,
    required this.extension,
  });

  final InstalledPlugin plugin;
  final String extensionId;
  final String title;
  final Map<String, dynamic> extension;
}

class PluginExtensionScreen extends ConsumerStatefulWidget {
  const PluginExtensionScreen({
    super.key,
    required this.plugin,
    required this.extensionId,
    required this.title,
    required this.extension,
    this.hostState = const <String, dynamic>{},
  });

  final InstalledPlugin plugin;
  final String extensionId;
  final String title;
  final Map<String, dynamic> extension;
  final Map<String, dynamic> hostState;

  @override
  ConsumerState<PluginExtensionScreen> createState() =>
      _PluginExtensionScreenState();
}

class _PluginExtensionScreenState extends ConsumerState<PluginExtensionScreen> {
  late Map<String, dynamic> _extension;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _extension = Map<String, dynamic>.from(widget.extension);
  }

  List<dynamic> get _items {
    final raw =
        _extension['items'] ?? _extension['content'] ?? _extension['children'];
    if (raw is List) return raw;
    return const <dynamic>[];
  }

  Future<void> _dispatch(
    String actionId, [
    Map<String, dynamic>? payload,
  ]) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final runtime = ref.read(pluginRuntimeServiceProvider);
      final result = await runtime.dispatchUiAction(
        plugin: widget.plugin,
        actionId: actionId,
        payload: <String, dynamic>{
          'extensionId': widget.extensionId,
          ...?payload,
        },
        hostState: widget.hostState,
      );
      if (!mounted) return;
      if (!result.ok) {
        setState(() => _message = result.error ?? 'Plugin action failed');
      } else {
        final map = result.mapValue;
        if (map != null) {
          final msg = map['message']?.toString();
          final nextItems = map['items'];
          setState(() {
            _message = msg;
            if (nextItems is List) {
              _extension = <String, dynamic>{..._extension, 'items': nextItems};
            }
            if (map['title'] != null) {
              _extension = <String, dynamic>{
                ..._extension,
                'title': map['title'].toString(),
              };
            }
          });
        } else if (result.value is String) {
          setState(() => _message = result.value as String);
        } else {
          setState(() => _message = null);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = (_extension['title'] ?? widget.title).toString();
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_message != null)
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_message!),
              ),
            ),
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          if (_items.isEmpty)
            const Text('Нет элементов UI от плагина.')
          else
            ..._items.map((item) => _buildItem(context, item)),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, dynamic raw) {
    if (raw is! Map) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(raw?.toString() ?? ''),
      );
    }
    final item = raw.map((k, v) => MapEntry(k.toString(), v));
    final type = (item['type'] ?? 'text').toString().toLowerCase();

    switch (type) {
      case 'text':
      case 'label':
        final styleName = (item['style'] ?? '').toString();
        TextStyle? style;
        if (styleName == 'title') {
          style = Theme.of(context).textTheme.titleMedium;
        }
        if (styleName == 'headline') {
          style = Theme.of(context).textTheme.titleLarge;
        }
        if (styleName == 'caption') {
          style = Theme.of(context).textTheme.bodySmall;
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            (item['text'] ?? item['value'] ?? '').toString(),
            style: style,
          ),
        );
      case 'section':
        final children = item['items'] ?? item['children'];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item['title'] != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    item['title'].toString(),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              if (children is List)
                ...children.map((c) => _buildItem(context, c)),
            ],
          ),
        );
      case 'button':
      case 'action':
        final action = (item['action'] ?? item['id'] ?? '').toString();
        final label = (item['label'] ?? item['text'] ?? action).toString();
        final payload = item['payload'] is Map
            ? (item['payload'] as Map).map((k, v) => MapEntry(k.toString(), v))
            : <String, dynamic>{};
        final primary = item['primary'] == true || item['filled'] == true;
        final onPressed = action.isEmpty
            ? null
            : () => unawaited(_dispatch(action, payload));
        final child = Text(label);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: primary
              ? FilledButton(onPressed: _busy ? null : onPressed, child: child)
              : OutlinedButton(
                  onPressed: _busy ? null : onPressed,
                  child: child,
                ),
        );
      case 'divider':
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Divider(),
        );
      case 'keyvalue':
      case 'row':
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 140,
                child: Text(
                  (item['key'] ?? item['label'] ?? '').toString(),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(child: Text((item['value'] ?? '').toString())),
            ],
          ),
        );
      case 'card':
        final children = item['items'] ?? item['children'];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item['title'] != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      item['title'].toString(),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                if (children is List)
                  ...children.map((c) => _buildItem(context, c))
                else if (item['text'] != null)
                  Text(item['text'].toString()),
              ],
            ),
          ),
        );
      default:
        final text = (item['text'] ?? item['value'] ?? item.toString())
            .toString();
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(text),
        );
    }
  }
}
