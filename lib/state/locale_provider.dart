import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleNotifier extends Notifier<Locale> {
  static const String _prefsKey = 'mouvi.locale';

  bool _userChanged = false;

  @override
  Locale build() {
    unawaited(_load());
    return const Locale('ru');
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!ref.mounted || _userChanged) {
        return;
      }
      final code = prefs.getString(_prefsKey);
      if (code == 'ru' || code == 'en') {
        state = Locale(code!);
      }
    } catch (_) {
      // Оставляем язык по умолчанию.
    }
  }

  Future<void> updateLocale(Locale value) async {
    _userChanged = true;
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, value.languageCode);
    } catch (_) {
      // Язык всё равно применился на этот запуск.
    }
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale>(
  LocaleNotifier.new,
);
