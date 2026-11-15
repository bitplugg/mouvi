import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ThemePreference { system, light, dark }

class ThemePreferenceNotifier extends Notifier<ThemePreference> {
  static const String _prefsKey = 'mouvi.theme';

  bool _userChanged = false;

  @override
  ThemePreference build() {
    unawaited(_load());
    return ThemePreference.system;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!ref.mounted || _userChanged) {
        return;
      }
      final stored = prefs.getString(_prefsKey);
      if (stored == null) {
        return;
      }
      for (final preference in ThemePreference.values) {
        if (preference.name == stored) {
          state = preference;
          return;
        }
      }
    } catch (_) {
      // Оставляем системную тему.
    }
  }

  Future<void> updateThemePreference(ThemePreference preference) async {
    _userChanged = true;
    state = preference;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, preference.name);
    } catch (_) {
      // Тема всё равно применилась на этот запуск.
    }
  }
}

final themePreferenceProvider =
    NotifierProvider<ThemePreferenceNotifier, ThemePreference>(
      ThemePreferenceNotifier.new,
    );
