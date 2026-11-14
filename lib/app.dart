import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mouvi/core/localization/app_localizations.dart';
import 'package:mouvi/state/locale_provider.dart';
import 'package:mouvi/state/theme_provider.dart';
import 'package:mouvi/theme/app_theme.dart';
import 'package:mouvi/ui/shell/main_shell.dart';

Widget mouviMaterialApp({
  required Color lightSeed,
  required Color darkSeed,
  required Locale locale,
  required ThemeMode themeMode,
}) {
  final ColorScheme lightScheme = ColorScheme.fromSeed(seedColor: lightSeed, brightness: Brightness.light);
  final ColorScheme darkScheme = ColorScheme.fromSeed(seedColor: darkSeed, brightness: Brightness.dark);
  return MaterialApp(
    title: 'Mouvi',
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: lightTheme(lightScheme),
    darkTheme: darkTheme(darkScheme),
    themeMode: themeMode,
    home: const MainShell(),
    debugShowCheckedModeBanner: false,
  );
}

class MouviApp extends ConsumerWidget {
  const MouviApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final themePreference = ref.watch(themePreferenceProvider);

    final ThemeMode resolvedThemeMode = switch (themePreference) {
      ThemePreference.light => ThemeMode.light,
      ThemePreference.dark => ThemeMode.dark,
      ThemePreference.system => ThemeMode.system,
    };

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) => mouviMaterialApp(
        lightSeed: lightDynamic?.primary ?? const Color(0xFF6750A4),
        darkSeed: darkDynamic?.primary ?? const Color(0xFF6750A4),
        locale: locale,
        themeMode: resolvedThemeMode,
      ),
    );
  }
}
