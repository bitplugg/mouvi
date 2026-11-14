import 'package:mouvi/core/models/vpn_config.dart';

VpnProtocolType detectProtocol(String content) {
  final lower = content.trim().toLowerCase();
  if (lower.startsWith('{')) {
    // JSON based configs: Shadowsocks, VLESS, Trojan
    if (lower.contains('"method"')) {
      return VpnProtocolType.shadowsocks;
    }
    if (lower.contains('"vless"')) {
      return VpnProtocolType.vless;
    }
    if (lower.contains('"trojan"')) {
      return VpnProtocolType.trojan;
    }
    return VpnProtocolType.unknown;
  }
  if (lower.contains('dev tun') || lower.contains('dev tap')) {
    return VpnProtocolType.openvpn;
  }
  // WireGuard and AmneziaWG (fork of WireGuard) share the same config format
  if (lower.contains('[interface]') || lower.contains('privatekey')) {
    return VpnProtocolType.wireguard;
  }
  return VpnProtocolType.unknown;
}

String suggestConfigName(String content, {String fallback = 'Server'}) {
  final lines = content.split('\n');
  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('[')) {
      continue;
    }
    final separatorIndex = line.indexOf('=');
    if (separatorIndex <= 0) {
      continue;
    }
    final key = line.substring(0, separatorIndex).trim().toLowerCase();
    final value = line.substring(separatorIndex + 1).trim();
    if (key == 'endpoint') {
      final host = value.split('::').first.split(':').first.trim();
      if (host.isNotEmpty && host != '0.0.0.0') {
        return host;
      }
    }
  }
  return fallback;
}
