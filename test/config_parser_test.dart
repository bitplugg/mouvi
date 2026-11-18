import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mouvi/core/models/vpn_config.dart';
import 'package:mouvi/core/utils/config_parser.dart';

String _key44() => List<String>.filled(44, 'A').join();

const String _warpPublicKey = 'bmXOC+F1FxEMF9dyiK2H5/56nH5M2nH0e3hv0Xw2FzY=';

String _wireGuardConfig({String? extraInterface}) {
  final key = _key44();
  return '''
[Interface]
PrivateKey = $key
Address = 10.0.0.2/32
${extraInterface ?? ''}
[Peer]
PublicKey = $key
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = vpn.example.com:51820
''';
}

void main() {
  group('detectProtocol', () {
    test('detects WireGuard', () {
      expect(detectProtocol(_wireGuardConfig()), VpnProtocolType.wireguard);
    });

    test('detects AmneziaWG by its extra keys', () {
      final config = _wireGuardConfig(
        extraInterface: 'Jc = 4\nJmin = 10\nJmax = 50\nS1 = 0\nS2 = 0\nH1 = 1',
      );
      expect(detectProtocol(config), VpnProtocolType.amneziawg);
    });

    test('detects OpenVPN', () {
      const config = '''
client
dev tun
proto udp
remote vpn.example.com 1194
''';
      expect(detectProtocol(config), VpnProtocolType.openvpn);
    });

    test('detects Shadowsocks JSON', () {
      const config =
          '{"server":"1.2.3.4","server_port":8388,"method":"aes-256-gcm","password":"secret"}';
      expect(detectProtocol(config), VpnProtocolType.shadowsocks);
    });

    test('detects VLESS URI', () {
      expect(
        detectProtocol(
          'vless://uuid@vpn.example.com:443?security=reality#node',
        ),
        VpnProtocolType.vless,
      );
    });

    test('detects Trojan URI', () {
      expect(
        detectProtocol('trojan://secret@vpn.example.com:443#node'),
        VpnProtocolType.trojan,
      );
    });

    test('returns unknown for garbage', () {
      expect(detectProtocol('hello world'), VpnProtocolType.unknown);
    });

    test('returns unknown for empty input', () {
      expect(detectProtocol('   '), VpnProtocolType.unknown);
    });
  });

  group('validateConfig', () {
    test('accepts a complete WireGuard config', () {
      final result = validateConfig(_wireGuardConfig());
      expect(result.isValid, isTrue);
      expect(result.protocol, VpnProtocolType.wireguard);
      expect(result.engineSupported, isTrue);
      expect(result.warnings, isEmpty);
    });

    test('rejects WireGuard without PrivateKey', () {
      final key = _key44();
      final result = validateConfig('''
[Interface]
Address = 10.0.0.2/32
[Peer]
PublicKey = $key
AllowedIPs = 0.0.0.0/0
Endpoint = vpn.example.com:51820
''');
      expect(result.isValid, isFalse);
      expect(result.errors, contains('invalidConfigMissingPrivateKey'));
    });

    test('rejects WireGuard without Peer', () {
      final result = validateConfig('''
[Interface]
PrivateKey = ${_key44()}
Address = 10.0.0.2/32
''');
      expect(result.isValid, isFalse);
      expect(result.errors, contains('invalidConfigMissingPeer'));
    });

    test('rejects WireGuard without Endpoint/AllowedIPs', () {
      final key = _key44();
      final result = validateConfig('''
[Interface]
PrivateKey = $key
[Peer]
PublicKey = $key
''');
      expect(result.isValid, isFalse);
      expect(
        result.errors,
        containsAll(<String>[
          'invalidConfigMissingEndpoint',
          'invalidConfigMissingAllowedIps',
        ]),
      );
    });

    test('imports AmneziaWG as a supported protocol', () {
      final config = _wireGuardConfig(
        extraInterface:
            'Jc = 4\nJmin = 10\nJmax = 50\nS1 = 0\nS2 = 0\n'
            'H1 = 1\nH2 = 2\nH3 = 3\nH4 = 4',
      );
      final result = validateConfig(config);
      expect(result.isValid, isTrue);
      expect(result.protocol, VpnProtocolType.amneziawg);
      expect(result.engineSupported, isTrue);
      expect(result.warnings, isEmpty);
    });

    test('rejects AmneziaWG without H1–H4 headers', () {
      final config = _wireGuardConfig(
        extraInterface: 'Jc = 4\nJmin = 10\nJmax = 50\nS1 = 0\nS2 = 0\nH1 = 1',
      );
      final result = validateConfig(config);
      expect(result.isValid, isFalse);
      expect(result.errors, contains('invalidAmneziaHeader'));
    });

    test('accepts WARP without Endpoint/AllowedIPs', () {
      final config =
          '''
[Interface]
PrivateKey = ${_key44()}
Address = 172.16.0.2/32
[Peer]
PublicKey = $_warpPublicKey
''';
      final result = validateConfig(config);
      expect(result.isValid, isTrue);
      expect(result.engineSupported, isTrue);
      expect(
        result.warnings,
        containsAll(<String>['warpEndpointDefault', 'warpAllowedIpsDefault']),
      );
    });

    test('rejects unknown config', () {
      final result = validateConfig('not a vpn config');
      expect(result.isValid, isFalse);
      expect(result.errors, contains('invalidConfigUnrecognized'));
    });

    test('rejects OpenVPN without remote', () {
      final result = validateConfig('client\ndev tun\n');
      expect(result.isValid, isFalse);
      expect(result.errors, contains('invalidConfigMissingRemote'));
    });

    test('accepts OpenVPN with remote but marks it unsupported', () {
      final result = validateConfig(
        'client\ndev tun\nremote vpn.example.com 1194\n',
      );
      expect(result.isValid, isTrue);
      expect(result.engineSupported, isFalse);
    });

    test('validates Shadowsocks JSON', () {
      final valid = validateConfig(
        '{"server":"1.2.3.4","server_port":8388,"method":"aes-256-gcm","password":"secret"}',
      );
      expect(valid.isValid, isTrue);
      expect(valid.protocol, VpnProtocolType.shadowsocks);
      expect(valid.engineSupported, isFalse);

      final invalid = validateConfig('{"server":"1.2.3.4"}');
      expect(invalid.isValid, isFalse);
    });

    test('validates VLESS Reality URI as supported', () {
      final result = validateConfig(
        'vless://uuid@vpn.example.com:443?security=reality&type=tcp'
        '&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
        '&sid=abcdef0123456789&sni=vpn.example.com#node',
      );
      expect(result.isValid, isTrue);
      expect(result.protocol, VpnProtocolType.vless);
      expect(result.engineSupported, isTrue);
      expect(result.warnings, isEmpty);
    });

    test('validates VLESS TLS WebSocket URI', () {
      final result = validateConfig(
        'vless://uuid@vpn.example.com:443?security=tls&type=ws&path=%2Fws',
      );
      expect(result.isValid, isTrue);
      expect(result.engineSupported, isTrue);
    });

    test('rejects VLESS with unsupported transport', () {
      final result = validateConfig(
        'vless://uuid@vpn.example.com:443?security=tls&type=grpc',
      );
      expect(result.isValid, isFalse);
      expect(result.errors, contains('invalidConfigFormat'));
    });

    test('rejects VLESS Reality without public key', () {
      final result = validateConfig(
        'vless://uuid@vpn.example.com:443?security=reality&type=tcp',
      );
      expect(result.isValid, isFalse);
    });
  });

  group('suggestConfigName', () {
    test('uses WireGuard endpoint host', () {
      expect(suggestConfigName(_wireGuardConfig()), 'vpn.example.com');
    });

    test('handles IPv6 endpoint', () {
      final key = _key44();
      final config =
          '''
[Interface]
PrivateKey = $key
[Peer]
PublicKey = $key
AllowedIPs = ::/0
Endpoint = [2001:db8::1]:51820
''';
      expect(suggestConfigName(config), '2001:db8::1');
    });

    test('uses VLESS fragment when present', () {
      expect(
        suggestConfigName('vless://uuid@vpn.example.com:443#My%20VLESS'),
        'My VLESS',
      );
    });

    test('uses JSON remarks', () {
      final config = jsonEncode(<String, dynamic>{
        'server': '1.2.3.4',
        'method': 'aes-256-gcm',
        'password': 'x',
        'remarks': 'Tokyo',
      });
      expect(suggestConfigName(config), 'Tokyo');
    });

    test('falls back when nothing is found', () {
      expect(suggestConfigName('garbage', fallback: 'Fallback'), 'Fallback');
    });
  });

  group('VpnConfig JSON', () {
    test('round-trips all fields', () {
      final config = VpnConfig(
        id: '42',
        name: 'Test',
        protocol: VpnProtocolType.amneziawg,
        content: _wireGuardConfig(),
        createdAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
      );
      final restored = VpnConfig.fromJson(config.toJson());
      expect(restored.id, config.id);
      expect(restored.name, config.name);
      expect(restored.protocol, config.protocol);
      expect(restored.content, config.content);
      expect(restored.createdAt, config.createdAt);
    });

    test('falls back to unknown protocol', () {
      final restored = VpnConfig.fromJson(<String, dynamic>{
        'id': '1',
        'name': 'x',
        'protocol': 'made-up',
        'content': 'x',
        'createdAt': 'not a date',
      });
      expect(restored.protocol, VpnProtocolType.unknown);
      expect(restored.createdAt, isA<DateTime>());
    });

    test('rejects entries without content', () {
      expect(
        () => VpnConfig.fromJson(<String, dynamic>{'id': '1', 'name': 'x'}),
        throwsFormatException,
      );
    });

    test('does not expose content in toString', () {
      final config = VpnConfig(
        id: '1',
        name: 'x',
        protocol: VpnProtocolType.wireguard,
        content: 'PrivateKey = supersecret',
        createdAt: DateTime.now(),
      );
      expect(config.toString(), isNot(contains('supersecret')));
    });

    test('engine support covers WireGuard, AmneziaWG and VLESS', () {
      for (final protocol in const <VpnProtocolType>[
        VpnProtocolType.wireguard,
        VpnProtocolType.amneziawg,
        VpnProtocolType.vless,
      ]) {
        expect(protocol.engineSupported, isTrue, reason: protocol.name);
      }
      for (final protocol in VpnProtocolType.values.where(
        (item) =>
            item != VpnProtocolType.wireguard &&
            item != VpnProtocolType.amneziawg &&
            item != VpnProtocolType.vless,
      )) {
        expect(protocol.engineSupported, isFalse, reason: protocol.name);
      }
    });
  });
}
