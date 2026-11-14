import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ThemePreference { system, light, dark }

class ThemePreferenceNotifier extends Notifier<ThemePreference> {
  @override
  ThemePreference build() => ThemePreference.system;

  void updateThemePreference(ThemePreference preference) {
    state = preference;
  }
}

final themePreferenceProvider = NotifierProvider<ThemePreferenceNotifier, ThemePreference>(ThemePreferenceNotifier.new);
