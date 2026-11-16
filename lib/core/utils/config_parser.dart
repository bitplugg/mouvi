import 'dart:convert';

import 'package:mouvi/core/models/vpn_config.dart';

/// Ключи, которые добавляет AmneziaWG в секцию `[Interface]`.
///
/// Формат файла совместим с WireGuard, но стандартный WireGuard-движок
/// не умеет их разбирать, поэтому такие конфиги определяются отдельно.
const Set<String> _amneziaInterfaceKeys = <String>{
  'jc',
  'jmin',
  'jmax',
  's1',
  's2',
  's3',
  's4',
  'h1',
  'h2',
  'h3',
  'h4',
  'i1',
  'i2',
  'i3',
  'i4',
  'i5',
  'j1',
  'j2',
  'j3',
};

/// Результат разбора и проверки импортированного конфига.
class ConfigValidationResult {
  const ConfigValidationResult({
    required this.protocol,
    this.errors = const <String>[],
    this.warnings = const <String>[],
  });

  final VpnProtocolType protocol;

  /// Ключи локализации с описанием проблем. Если список не пуст,
  /// конфигурацию импортировать нельзя.
  final List<String> errors;

  /// Ключи локализации с некритичными замечаниями.
  final List<String> warnings;

  bool get isValid => errors.isEmpty;

  /// Поддерживает ли установленный движок реальное подключение.
  bool get engineSupported => protocol.engineSupported;

  /// Можно ли сохранить конфиг: формат распознан и разобран без ошибок.
  bool get canImport => isValid;
}

class _ParsedSection {
  _ParsedSection(this.name);

  final String name;
  final Map<String, String> attributes = <String, String>{};
}

List<_ParsedSection> _parseIniSections(String content) {
  final sections = <_ParsedSection>[];
  _ParsedSection? current;
  for (final rawLine in const LineSplitter().convert(content)) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) {
      continue;
    }
    if (line.startsWith('[') && line.endsWith(']')) {
      current = _ParsedSection(
        line.substring(1, line.length - 1).trim().toLowerCase(),
      );
      sections.add(current);
      continue;
    }
    final separator = line.indexOf('=');
    if (separator <= 0 || current == null) {
      continue;
    }
    final key = line.substring(0, separator).trim().toLowerCase();
    final value = line.substring(separator + 1).trim();
    current.attributes.putIfAbsent(key, () => value);
  }
  return sections;
}

bool _hasAmneziaKeys(List<_ParsedSection> sections) {
  for (final section in sections) {
    if (section.name != 'interface') {
      continue;
    }
    if (section.attributes.keys.any(_amneziaInterfaceKeys.contains)) {
      return true;
    }
  }
  return false;
}

VpnProtocolType _detectJsonProtocol(Object? decoded) {
  if (decoded is! Map) {
    return VpnProtocolType.unknown;
  }
  final map = <String, Object?>{};
  for (final entry in decoded.entries) {
    map[entry.key.toString().toLowerCase()] = entry.value;
  }
  if (map.containsKey('method') ||
      map.containsKey('server_port') ||
      map.containsKey('server')) {
    return VpnProtocolType.shadowsocks;
  }
  if (map.containsKey('vless') ||
      map['protocol'] == 'vless' ||
      map['type'] == 'vless') {
    return VpnProtocolType.vless;
  }
  if (map.containsKey('trojan') || map['protocol'] == 'trojan') {
    return VpnProtocolType.trojan;
  }
  if (map.containsKey('wireguard') || map.containsKey('privatekey')) {
    return VpnProtocolType.wireguard;
  }
  return VpnProtocolType.unknown;
}

/// Определяет протокол по содержимому конфигурации.
VpnProtocolType detectProtocol(String content) {
  final trimmed = content.trim().replaceFirst('\uFEFF', '');
  final lower = trimmed.toLowerCase();
  if (trimmed.isEmpty) {
    return VpnProtocolType.unknown;
  }
  if (lower.startsWith('vless://')) {
    return VpnProtocolType.vless;
  }
  if (lower.startsWith('trojan://')) {
    return VpnProtocolType.trojan;
  }
  if (lower.startsWith('ss://')) {
    return VpnProtocolType.shadowsocks;
  }
  if (lower.startsWith('{')) {
    try {
      return _detectJsonProtocol(jsonDecode(trimmed));
    } on FormatException {
      return VpnProtocolType.unknown;
    }
  }
  final sections = _parseIniSections(trimmed);
  final hasInterfaceSection = sections.any(
    (section) => section.name == 'interface',
  );
  final hasWireGuardKey = sections.any(
    (section) => section.attributes.containsKey('privatekey'),
  );
  if (hasInterfaceSection || hasWireGuardKey) {
    return _hasAmneziaKeys(sections)
        ? VpnProtocolType.amneziawg
        : VpnProtocolType.wireguard;
  }
  if (lower.contains('dev tun') ||
      lower.contains('dev tap') ||
      (lower.contains('client') && lower.contains('remote '))) {
    return VpnProtocolType.openvpn;
  }
  return VpnProtocolType.unknown;
}

/// Проверяет структуру конфигурации перед сохранением.
///
/// Возвращает коды локализации, чтобы UI показал понятную ошибку.
ConfigValidationResult validateConfig(String content) {
  final trimmed = content.trim().replaceFirst('\uFEFF', '');
  final protocol = detectProtocol(trimmed);
  switch (protocol) {
    case VpnProtocolType.unknown:
      return const ConfigValidationResult(
        protocol: VpnProtocolType.unknown,
        errors: <String>['invalidConfigUnrecognized'],
      );
    case VpnProtocolType.wireguard:
    case VpnProtocolType.amneziawg:
      return _validateWireGuard(trimmed, protocol);
    case VpnProtocolType.openvpn:
      return _validateOpenVpn(trimmed);
    case VpnProtocolType.shadowsocks:
      return _validateJsonOrUri(
        trimmed,
        protocol,
        requiredJsonKeys: const <String>['method', 'password'],
        requireServer: true,
      );
    case VpnProtocolType.vless:
    case VpnProtocolType.trojan:
      return _validateJsonOrUri(trimmed, protocol);
  }
}

ConfigValidationResult _validateWireGuard(
  String content,
  VpnProtocolType protocol,
) {
  final errors = <String>[];
  final warnings = <String>[];
  final sections = _parseIniSections(content);
  final interfaceSections = sections
      .where((section) => section.name == 'interface')
      .toList();
  final peerSections = sections
      .where((section) => section.name == 'peer')
      .toList();
  if (interfaceSections.isEmpty) {
    errors.add('invalidConfigMissingInterface');
  } else {
    final privateKey = interfaceSections.first.attributes['privatekey'] ?? '';
    if (privateKey.isEmpty) {
      errors.add('invalidConfigMissingPrivateKey');
    } else if (privateKey.length != 44) {
      warnings.add('invalidConfigKeyFormat');
    }
  }
  if (peerSections.isEmpty) {
    errors.add('invalidConfigMissingPeer');
  } else {
    final peer = peerSections.first.attributes;
    final publicKey = peer['publickey'] ?? '';
    if (publicKey.isEmpty) {
      errors.add('invalidConfigMissingPublicKey');
    } else if (publicKey.length != 44) {
      warnings.add('invalidConfigKeyFormat');
    }
    if ((peer['endpoint'] ?? '').isEmpty) {
      warnings.add('invalidConfigMissingEndpoint');
    }
    if ((peer['allowedips'] ?? '').isEmpty) {
      warnings.add('invalidConfigMissingAllowedIps');
    }
  }
  if (protocol == VpnProtocolType.amneziawg) {
    warnings.add('protocolNotSupportedHint');
  }
  return ConfigValidationResult(
    protocol: protocol,
    errors: errors,
    warnings: warnings,
  );
}

ConfigValidationResult _validateOpenVpn(String content) {
  final lower = content.toLowerCase();
  final errors = <String>[];
  if (!lower.contains('remote ')) {
    errors.add('invalidConfigMissingRemote');
  }
  return ConfigValidationResult(
    protocol: VpnProtocolType.openvpn,
    errors: errors,
    warnings: const <String>['protocolNotSupportedHint'],
  );
}

ConfigValidationResult _validateJsonOrUri(
  String content,
  VpnProtocolType protocol, {
  List<String> requiredJsonKeys = const <String>[],
  bool requireServer = false,
}) {
  final errors = <String>[];
  final warnings = const <String>['protocolNotSupportedHint'];
  if (content.toLowerCase().startsWith('{')) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map) {
        return ConfigValidationResult(
          protocol: protocol,
          errors: const <String>['invalidConfigFormat'],
          warnings: warnings,
        );
      }
      final map = <String, Object?>{};
      for (final entry in decoded.entries) {
        map[entry.key.toString().toLowerCase()] = entry.value;
      }
      for (final key in requiredJsonKeys) {
        final value = map[key];
        if (value == null || value.toString().isEmpty) {
          errors.add('invalidConfigFormat');
        }
      }
      if (requireServer) {
        final server = map['server'] ?? map['address'];
        if (server == null || server.toString().isEmpty) {
          errors.add('invalidConfigFormat');
        }
      }
    } on FormatException {
      errors.add('invalidConfigFormat');
    }
    return ConfigValidationResult(
      protocol: protocol,
      errors: errors.toSet().toList(),
      warnings: warnings,
    );
  }
  // URI-формат: scheme://userinfo@host:port?params
  final schemeIndex = content.indexOf('://');
  final afterScheme = schemeIndex >= 0
      ? content.substring(schemeIndex + 3)
      : '';
  final authority = afterScheme.split(RegExp(r'[/?#]')).first;
  final hostPart = authority.contains('@')
      ? authority.split('@').last
      : authority;
  if (hostPart.isEmpty) {
    errors.add('invalidConfigFormat');
  }
  return ConfigValidationResult(
    protocol: protocol,
    errors: errors,
    warnings: warnings,
  );
}

String? _extractHost(String endpoint) {
  final value = endpoint.trim();
  if (value.isEmpty) {
    return null;
  }
  if (value.startsWith('[')) {
    final closing = value.indexOf(']');
    if (closing > 1) {
      return value.substring(1, closing);
    }
    return null;
  }
  final colon = value.lastIndexOf(':');
  final host = colon > 0 ? value.substring(0, colon) : value;
  if (host.isEmpty || host == '0.0.0.0' || host == '::') {
    return null;
  }
  return host;
}

/// Пытается предложить осмысленное имя сервера по содержимому конфига.
String suggestConfigName(String content, {String fallback = 'Server'}) {
  final trimmed = content.trim().replaceFirst('\uFEFF', '');
  final lower = trimmed.toLowerCase();
  if (lower.startsWith('{')) {
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        for (final key in const <String>[
          'remarks',
          'ps',
          'tag',
          'name',
          'address',
          'server',
        ]) {
          final value = decoded[key];
          if (value is String && value.trim().isNotEmpty) {
            return value.trim();
          }
        }
      }
    } on FormatException {
      // Ниже попробуем вытащить хост из URI/INI.
    }
  }
  final schemeIndex = lower.indexOf('://');
  if (schemeIndex >= 0) {
    final afterScheme = trimmed.substring(schemeIndex + 3);
    final authority = afterScheme.split(RegExp(r'[/?#]')).first;
    final hostPart = authority.contains('@')
        ? authority.split('@').last
        : authority;
    final host = _extractHost(hostPart);
    if (host != null) {
      return host;
    }
  }
  for (final section in _parseIniSections(trimmed)) {
    final endpoint = section.attributes['endpoint'];
    if (endpoint != null) {
      final host = _extractHost(endpoint);
      if (host != null) {
        return host;
      }
    }
  }
  return fallback;
}
