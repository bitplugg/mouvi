import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mouvi/core/localization/app_localizations.dart';
import 'package:mouvi/state/locale_provider.dart';
import 'package:mouvi/ui/home/home_screen.dart';
import 'package:mouvi/ui/servers/servers_screen.dart';
import 'package:mouvi/ui/settings/settings_screen.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final localizations = AppLocalizations(locale);

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [HomeScreen(), ServersScreen(), SettingsScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.home),
            label: localizations.t('home'),
          ),
          NavigationDestination(
            icon: Icon(Icons.shield),
            label: localizations.t('servers'),
          ),
          NavigationDestination(
            icon: Icon(Icons.settings),
            label: localizations.t('settings'),
          ),
        ],
      ),
    );
  }
}
