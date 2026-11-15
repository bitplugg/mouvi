/// Протоколы, которые Mouvi умеет распознавать при импорте.
///
/// Важно: распознавание и импорт конфигурации не означают, что протокол
/// поддерживается VPN-движком. Реальная поддержка определяется
/// [VpnProtocolTypeX.engineSupported].
enum VpnProtocolType {
  wireguard,
  amneziawg,
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
      case VpnProtocolType.amneziawg:
        return 'protocolAmneziawg';
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

  /// Поддерживается ли протокол установленным VPN-движком.
  ///
  /// Сейчас нативный движок — WireGuard (userspace GoBackend).
  /// AmneziaWG требует отдельного форка движка и пока не поддерживается.
  bool get engineSupported => this == VpnProtocolType.wireguard;

  /// Идентификатор протокола для нативного канала.
  String get channelName => name;
}

/// Сохранённая конфигурация VPN-сервера.
///
/// Поле [content] содержит чувствительные данные (приватные ключи),
/// поэтому конфигурации сохраняются только в зашифрованном виде
/// на нативной стороне и никогда не пишутся в логи.
class VpnConfig {
  const VpnConfig({
    required this.id,
    required this.name,
    required this.protocol,
    required this.content,
    required this.createdAt,
  });

  factory VpnConfig.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final content = json['content'];
    final createdAt = json['createdAt'];
    if (id is! String || name is! String || content is! String) {
      throw const FormatException('Invalid VPN config entry');
    }
    final rawProtocol = json['protocol'];
    final protocol = VpnProtocolType.values.firstWhere(
      (value) => value.name == rawProtocol,
      orElse: () => VpnProtocolType.unknown,
    );
    return VpnConfig(
      id: id,
      name: name,
      protocol: protocol,
      content: content,
      createdAt: createdAt is String
          ? (DateTime.tryParse(createdAt) ?? DateTime.now())
          : DateTime.now(),
    );
  }

  final String id;
  final String name;
  final VpnProtocolType protocol;
  final String content;
  final DateTime createdAt;

  VpnConfig copyWith({
    String? name,
    VpnProtocolType? protocol,
    String? content,
  }) {
    return VpnConfig(
      id: id,
      name: name ?? this.name,
      protocol: protocol ?? this.protocol,
      content: content ?? this.content,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'protocol': protocol.name,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// Никогда не выводим [content] целиком: в нём приватный ключ.
  @override
  String toString() =>
      'VpnConfig(id: $id, name: $name, protocol: ${protocol.name})';
}
