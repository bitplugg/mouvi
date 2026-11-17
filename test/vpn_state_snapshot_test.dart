import 'package:flutter_test/flutter_test.dart';
import 'package:mouvi/core/services/vpn_native_service.dart';

void main() {
  group('VpnStateSnapshot.fromChannel', () {
    test('parses connected state with statistics', () {
      final snapshot = VpnStateSnapshot.fromChannel(<Object?, Object?>{
        'status': 'UP',
        'tunnelName': 'mouvi',
        'alwaysOn': true,
        'lockdown': true,
        'rxBytes': 4096,
        'txBytes': 2048,
        'lastHandshakeMs': 1_700_000_000_000,
      });

      expect(snapshot.status, VpnEngineStatus.up);
      expect(snapshot.isConnected, isTrue);
      expect(snapshot.tunnelName, 'mouvi');
      expect(snapshot.alwaysOn, isTrue);
      expect(snapshot.lockdown, isTrue);
      expect(snapshot.rxBytes, 4096);
      expect(snapshot.txBytes, 2048);
      expect(snapshot.lastHandshakeMs, 1_700_000_000_000);
      expect(snapshot.hasHandshake, isTrue);
    });

    test('accepts numeric values and clamps negatives', () {
      final snapshot = VpnStateSnapshot.fromChannel(<Object?, Object?>{
        'status': 'up',
        'rxBytes': 10.6,
        'txBytes': -3,
        'lastHandshakeMs': -1,
      });

      expect(snapshot.rxBytes, 11);
      expect(snapshot.txBytes, 0);
      expect(snapshot.lastHandshakeMs, 0);
      expect(snapshot.hasHandshake, isFalse);
    });

    test('ignores malformed statistics', () {
      final snapshot = VpnStateSnapshot.fromChannel(<Object?, Object?>{
        'status': 'up',
        'rxBytes': 'many',
        'txBytes': null,
        'lastHandshakeMs': <String>[],
      });

      expect(snapshot.rxBytes, 0);
      expect(snapshot.txBytes, 0);
      expect(snapshot.lastHandshakeMs, 0);
    });

    test('falls back to down for missing values', () {
      final snapshot = VpnStateSnapshot.fromChannel(null);
      expect(snapshot.status, VpnEngineStatus.down);
      expect(snapshot.isConnected, isFalse);
      expect(snapshot.tunnelName, isNull);
      expect(snapshot.rxBytes, 0);
    });

    test('ignores empty tunnel name', () {
      final snapshot = VpnStateSnapshot.fromChannel(<Object?, Object?>{
        'status': 'down',
        'tunnelName': '',
      });
      expect(snapshot.tunnelName, isNull);
    });
  });
}
