enum VpnProtocolType {
  wireguard,
  openvpn,
  shadowsocks,
  vless,
  trojan,
  unknown,
}

extension VpnProtocolTypeX on VpnProtocolType {
  String get labelKey {
    switch (this) {
      case VpnProtocolType.wireguard:
        return 'protocolWireguard';
      case VpnProtocolType.openvpn:
        return 'protocolOpenvpn';
      case VpnProtocolType.shadowsocks:
        return 'protocolShadowsocks';
      case VpnProtocolType.vless:
        return 'protocolVless';
      case VpnProtocolType.trojan:
        return 'protocolTrojan';
      case VpnProtocolType.unknown:
        return 'protocolUnknown';
    }
  }
}

class VpnConfig {
  const VpnConfig({
    required this.id,
    required this.name,
    required this.protocol,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String name;
  final VpnProtocolType protocol;
  final String content;
  final DateTime createdAt;
}
