import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mouvi/core/localization/app_localizations.dart';
import 'package:mouvi/state/locale_provider.dart';
import 'package:mouvi/state/theme_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final themePreference = ref.watch(themePreferenceProvider);
    final localizations = AppLocalizations(locale);

    final themeSelection = switch (themePreference) {
      ThemePreference.system => 'system',
      ThemePreference.light => 'light',
      ThemePreference.dark => 'dark',
    };

    final languageSelection = locale.languageCode == 'ru' ? 'ru' : 'en';

    return Scaffold(
      appBar: AppBar(title: Text(localizations.t('settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(localizations.t('appearance'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'system', label: Text(localizations.t('themeSystem'))),
                  ButtonSegment(value: 'light', label: Text(localizations.t('themeLight'))),
                  ButtonSegment(value: 'dark', label: Text(localizations.t('themeDark'))),
                ],
                selected: <String>{themeSelection},
                onSelectionChanged: (value) {
                  if (value.length == 1) {
                    final key = value.first;
                    ref.read(themePreferenceProvider.notifier).updateThemePreference(
                          switch (key) {
                            'light' => ThemePreference.light,
                            'dark' => ThemePreference.dark,
                            _ => ThemePreference.system,
                          },
                        );
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(localizations.t('language'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'ru', label: Text(localizations.t('russian'))),
                  ButtonSegment(value: 'en', label: Text(localizations.t('english'))),
                ],
                selected: <String>{languageSelection},
                onSelectionChanged: (value) {
                  final language = value.first;
                  ref.read(localeProvider.notifier).updateLocale(Locale(language));
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
