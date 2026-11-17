import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mouvi/state/vpn_settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<VpnSettings> _loadedSettings(ProviderContainer container) async {
  final notifier = container.read(vpnSettingsProvider.notifier);
  await notifier.ready;
  return container.read(vpnSettingsProvider);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('loads safe defaults', () async {
    final container = ProviderContainer.test();
    final settings = await _loadedSettings(container);

    expect(settings.loaded, isTrue);
    expect(settings.splitMode, SplitTunnelingMode.off);
    expect(settings.splitTunnelingEnabled, isFalse);
    expect(settings.selectedApplications, isEmpty);
    expect(settings.dnsProtectionEnabled, isTrue);
    expect(settings.autoConnectOnLaunch, isFalse);
  });

  test('migrates the legacy split tunneling flag to exclude mode', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'mouvi.settings.split_tunneling': true,
      'mouvi.settings.excluded_apps': <String>['com.example.app'],
    });

    final container = ProviderContainer.test();
    final settings = await _loadedSettings(container);

    expect(settings.splitMode, SplitTunnelingMode.exclude);
    expect(settings.selectedApplications, <String>['com.example.app']);
  });

  test('legacy disabled flag stays off', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'mouvi.settings.split_tunneling': false,
    });

    final container = ProviderContainer.test();
    final settings = await _loadedSettings(container);

    expect(settings.splitMode, SplitTunnelingMode.off);
  });

  test('persists the split mode and deduplicates applications', () async {
    final container = ProviderContainer.test();
    final notifier = container.read(vpnSettingsProvider.notifier);
    await notifier.ready;

    await notifier.updateSplitMode(SplitTunnelingMode.include);
    await notifier.updateSelectedApplications(<String>[
      'com.example.b',
      'com.example.a',
      'com.example.b',
    ]);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('mouvi.settings.split_mode'), 'include');
    expect(prefs.getStringList('mouvi.settings.excluded_apps'), <String>[
      'com.example.b',
      'com.example.a',
    ]);
    expect(container.read(vpnSettingsProvider).selectedApplications, <String>[
      'com.example.b',
      'com.example.a',
    ]);
  });

  test('persists DNS protection and auto-connect toggles', () async {
    final container = ProviderContainer.test();
    final notifier = container.read(vpnSettingsProvider.notifier);
    await notifier.ready;

    await notifier.updateDnsProtectionEnabled(false);
    await notifier.updateAutoConnectOnLaunch(true);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('mouvi.settings.dns_protection'), isFalse);
    expect(prefs.getBool('mouvi.settings.auto_connect'), isTrue);
    final settings = container.read(vpnSettingsProvider);
    expect(settings.dnsProtectionEnabled, isFalse);
    expect(settings.autoConnectOnLaunch, isTrue);
  });
}
