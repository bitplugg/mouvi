import 'package:flutter_test/flutter_test.dart';
import 'package:mouvi/core/models/vpn_config.dart';
import 'package:mouvi/core/utils/format_utils.dart';

void main() {
  group('formatBytes', () {
    test('formats zero and negative values', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(-5), '0 B');
    });

    test('keeps bytes without decimals', () {
      expect(formatBytes(1), '1 B');
      expect(formatBytes(1023), '1023 B');
    });

    test('uses binary units', () {
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(100 * 1024), '100 KB');
      expect(formatBytes(1024 * 1024), '1.0 MB');
      expect(formatBytes(1024 * 1024 * 1024), '1.0 GB');
    });
  });

  group('handshakeAge', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000);

    test('returns null without a handshake', () {
      expect(handshakeAge(now, 0), isNull);
      expect(handshakeAge(now, -1), isNull);
    });

    test('formats seconds, minutes, hours and days', () {
      expect(
        handshakeAge(
          now,
          now.subtract(const Duration(seconds: 5)).millisecondsSinceEpoch,
        ),
        (value: 5, unit: 'seconds'),
      );
      expect(
        handshakeAge(
          now,
          now.subtract(const Duration(seconds: 90)).millisecondsSinceEpoch,
        ),
        (value: 1, unit: 'minutes'),
      );
      expect(
        handshakeAge(
          now,
          now.subtract(const Duration(hours: 3)).millisecondsSinceEpoch,
        ),
        (value: 3, unit: 'hours'),
      );
      expect(
        handshakeAge(
          now,
          now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
        ),
        (value: 2, unit: 'days'),
      );
    });

    test('clamps timestamps from the future', () {
      expect(
        handshakeAge(
          now,
          now.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
        ),
        (value: 0, unit: 'seconds'),
      );
    });
  });

  group('exportFileName', () {
    test('uses the right extension for each protocol', () {
      expect(
        exportFileName('My Server', VpnProtocolType.wireguard),
        'My_Server.conf',
      );
      expect(
        exportFileName('amnezia node', VpnProtocolType.amneziawg),
        'amnezia_node.conf',
      );
      expect(exportFileName('office', VpnProtocolType.openvpn), 'office.ovpn');
      expect(
        exportFileName('proxy', VpnProtocolType.shadowsocks),
        'proxy.json',
      );
      expect(exportFileName('node', VpnProtocolType.vless), 'node.txt');
      expect(exportFileName('node', VpnProtocolType.trojan), 'node.txt');
    });

    test('does not duplicate an existing extension', () {
      expect(
        exportFileName('my-tunnel.conf', VpnProtocolType.wireguard),
        'my-tunnel.conf',
      );
    });

    test('sanitizes unsafe characters and empty names', () {
      expect(
        exportFileName('../etc/pass wd', VpnProtocolType.wireguard),
        'etc_pass_wd.conf',
      );
      expect(
        exportFileName('***', VpnProtocolType.wireguard),
        'mouvi-config.conf',
      );
    });
  });
}
