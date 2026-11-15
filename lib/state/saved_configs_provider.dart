import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mouvi/core/models/vpn_config.dart';
import 'package:mouvi/core/services/secure_config_storage.dart';

/// Список сохранённых конфигураций с постоянным зашифрованным хранением.
///
/// Хранилище нативное (Android Keystore + AES-GCM). Здесь только
/// сериализация, обработка повреждённых записей и запись изменений.
class SavedConfigsNotifier extends Notifier<List<VpnConfig>> {
  static const int _envelopeVersion = 1;

  Future<void> _writeQueue = Future<void>.value();

  /// Последняя запись в зашифрованное хранилище не удалась.
  bool lastWriteFailed = false;

  @override
  List<VpnConfig> build() {
    unawaited(_load());
    return const <VpnConfig>[];
  }

  Future<void> _load() async {
    final raw = await ref.read(secureConfigStorageProvider).read();
    if (raw == null || raw.trim().isEmpty) {
      return;
    }
    final List<VpnConfig> loaded = <VpnConfig>[];
    try {
      final decoded = jsonDecode(raw);
      final List<dynamic> entries;
      if (decoded is Map<String, dynamic> && decoded['configs'] is List) {
        entries = decoded['configs'] as List<dynamic>;
      } else if (decoded is List) {
        entries = decoded;
      } else {
        entries = const <dynamic>[];
      }
      for (final entry in entries) {
        if (entry is Map<String, dynamic>) {
          try {
            loaded.add(VpnConfig.fromJson(entry));
          } on FormatException {
            // Повреждённую запись пропускаем, остальные сохраняем.
          }
        }
      }
    } on FormatException {
      // Хранилище повреждено целиком — не удаляем его автоматически.
      return;
    }
    if (!ref.mounted) {
      return;
    }
    // Объединяем загруженное с уже добавленным, пока шла загрузка,
    // чтобы не потерять старые или только что добавленные конфиги.
    final merged = <String, VpnConfig>{
      for (final config in loaded) config.id: config,
      for (final config in state) config.id: config,
    };
    if (merged.isNotEmpty) {
      state = List<VpnConfig>.unmodifiable(
        merged.values.toList(growable: false),
      );
    }
  }

  Future<void> _persist() {
    final snapshot = state
        .map((config) => config.toJson())
        .toList(growable: false);
    final raw = jsonEncode(<String, dynamic>{
      'version': _envelopeVersion,
      'configs': snapshot,
    });
    _writeQueue = _writeQueue.then((_) async {
      final saved = await ref.read(secureConfigStorageProvider).write(raw);
      lastWriteFailed = !saved;
    });
    return _writeQueue;
  }

  Future<void> addConfig(VpnConfig config) async {
    final withoutDuplicate = state
        .where((item) => item.id != config.id)
        .toList();
    state = List<VpnConfig>.unmodifiable(<VpnConfig>[
      ...withoutDuplicate,
      config,
    ]);
    await _persist();
  }

  Future<void> removeConfig(String id) async {
    state = List<VpnConfig>.unmodifiable(
      state.where((config) => config.id != id),
    );
    await _persist();
  }

  Future<void> renameConfig(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }
    state = List<VpnConfig>.unmodifiable(
      state.map(
        (config) => config.id == id ? config.copyWith(name: trimmed) : config,
      ),
    );
    await _persist();
  }

  VpnConfig? findById(String? id) {
    if (id == null) {
      return null;
    }
    for (final config in state) {
      if (config.id == id) {
        return config;
      }
    }
    return null;
  }
}

final savedConfigsProvider =
    NotifierProvider<SavedConfigsNotifier, List<VpnConfig>>(
      SavedConfigsNotifier.new,
    );
