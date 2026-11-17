import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mouvi/core/localization/app_localizations.dart';
import 'package:mouvi/core/services/vpn_native_service.dart';
import 'package:mouvi/state/connection_provider.dart';
import 'package:mouvi/state/locale_provider.dart';
import 'package:mouvi/state/saved_configs_provider.dart';
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
  StreamSubscription<String>? _launchActionSubscription;
  bool _toggleInFlight = false;

  @override
  void initState() {
    super.initState();
    _launchActionSubscription = ref
        .read(vpnEngineProvider)
        .launchActions
        .listen(
          (action) {
            if (action == 'toggle') {
              unawaited(_handleQuickToggle());
            }
          },
          onError: (Object _) {
            // Канал действий недоступен — обычный запуск приложения.
          },
        );
  }

  @override
  void dispose() {
    unawaited(_launchActionSubscription?.cancel());
    super.dispose();
  }

  /// Подключение/отключение по плитке Quick Settings.
  ///
  /// Вся проверка конфигурации и WARP-настроек остаётся в Dart: плитка
  /// только просит приложение выполнить переключение.
  Future<void> _handleQuickToggle() async {
    if (_toggleInFlight) {
      return;
    }
    _toggleInFlight = true;
    try {
      final handled = await ref.read(connectionProvider.notifier).quickToggle();
      if (!mounted || handled) {
        return;
      }
      final localizations = AppLocalizations(ref.read(localeProvider));
      final hasConfigs = ref.read(savedConfigsProvider).isNotEmpty;
      setState(() => _currentIndex = 1);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            localizations.t(hasConfigs ? 'noConfigSelected' : 'noServersHint'),
          ),
        ),
      );
    } finally {
      _toggleInFlight = false;
    }
  }

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
