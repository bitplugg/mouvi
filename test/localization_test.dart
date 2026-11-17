import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mouvi/core/localization/app_localizations.dart';

void main() {
  test('English and Russian dictionaries have the same keys', () {
    final strings = AppLocalizations.strings;
    final english = strings['en']!;
    final russian = strings['ru']!;

    expect(english.keys.toSet(), russian.keys.toSet());
    expect(english, isNotEmpty);
    expect(russian, isNotEmpty);
  });

  test('no localized value is empty', () {
    for (final entry in AppLocalizations.strings.entries) {
      for (final string in entry.value.entries) {
        expect(
          string.value.trim(),
          isNotEmpty,
          reason: '${entry.key}/${string.key} is empty',
        );
      }
    }
  });

  test('new v1.1.0 keys resolve in both languages', () {
    final keys = <String>[
      'splitOff',
      'splitExclude',
      'splitInclude',
      'autoConnect',
      'autoConnectHint',
      'scanQr',
      'qrScanTitle',
      'pasteFromClipboard',
      'clipboardEmpty',
      'exportConfig',
      'exportWarning',
      'configExported',
      'configExportCancelled',
      'configExportFailed',
      'cameraPermissionDenied',
      'received',
      'sent',
      'handshake',
      'handshakeNone',
      'secondsShort',
      'minutesShort',
      'hoursShort',
      'daysShort',
    ];
    for (final language in <String>['en', 'ru']) {
      final localizations = AppLocalizations(Locale(language));
      for (final key in keys) {
        expect(
          localizations.t(key),
          isNot(key),
          reason: '$language is missing $key',
        );
      }
    }
  });

  test('unknown keys fall back to the key itself', () {
    final localizations = AppLocalizations(const Locale('ru'));
    expect(localizations.t('definitely-not-a-key'), 'definitely-not-a-key');
  });

  test('unsupported locale falls back to English', () {
    final localizations = AppLocalizations(const Locale('de'));
    expect(localizations.t('connect'), 'Connect');
  });
}
