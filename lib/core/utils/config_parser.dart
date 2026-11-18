import 'dart:convert';

import 'package:mouvi/core/models/vpn_config.dart';

/// Публичный ключ Cloudflare WARP.
///
/// WARP-конфиги иногда распространяются без `Endpoint`/`AllowedIPs`:
/// при подключении движок подставляет стандартные значения Cloudflare.
const String _warpPublicKey = 'bmXOC+F1FxEMF9dyiK2H5/56nH5M2nH0e3hv0Xw2FzY=';

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
      return _validateVless(trimmed);
    case VpnProtocolType.trojan:
      return _validateJsonOrUri(trimmed, protocol);
  }
}

/// Проверка VLESS-ссылки или v2ray-подобного JSON перед сохранением.
///
/// Движок Xray реально поддерживает TCP/WS с TLS или Reality, поэтому
/// остальные транспорты отвергаются сразу, а не после неудачного подключения.
ConfigValidationResult _validateVless(String content) {
  final errors = <String>[];
  if (content.startsWith('{')) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map) {
        errors.add('invalidConfigFormat');
      } else {
        final outbounds = decoded['outbounds'];
        Object? outbound;
        if (outbounds is List) {
          for (final item in outbounds) {
            if (item is Map &&
                item['protocol']?.toString().toLowerCase() == 'vless') {
              outbound = item;
              break;
            }
          }
        }
        outbound ??= decoded['vless'] ?? decoded;
        final settings = outbound is Map ? outbound['settings'] : null;
        final vnext = settings is Map ? settings['vnext'] : null;
        final first = vnext is List && vnext.isNotEmpty
            ? vnext.first
            : settings;
        final users = first is Map ? first['users'] : null;
        final user = users is List && users.isNotEmpty ? users.first : first;
        final id = user is Map ? user['id']?.toString() : null;
        final address = first is Map
            ? (first['address'] ?? first['server'])?.toString()
            : null;
        final port = first is Map ? first['port'] : null;
        if (id == null ||
            id.isEmpty ||
            address == null ||
            address.isEmpty ||
            port is! int ||
            port < 1 ||
            port > 65535) {
          errors.add('invalidConfigFormat');
        }
      }
    } on FormatException {
      errors.add('invalidConfigFormat');
    }
    return ConfigValidationResult(
      protocol: VpnProtocolType.vless,
      errors: errors.toSet().toList(),
    );
  }

  final uri = Uri.tryParse(content);
  if (uri == null || uri.scheme.toLowerCase() != 'vless') {
    return const ConfigValidationResult(
      protocol: VpnProtocolType.vless,
      errors: <String>['invalidConfigFormat'],
    );
  }
  final uuid = uri.userInfo;
  final host = uri.host;
  final port = uri.port;
  if (uuid.isEmpty || host.isEmpty || port < 1 || port > 65535) {
    errors.add('invalidConfigFormat');
  }
  final security = (uri.queryParameters['security'] ?? 'none').toLowerCase();
  final transport = (uri.queryParameters['type'] ?? 'tcp').toLowerCase();
  if (!const <String>{'none', 'tls', 'reality'}.contains(security) ||
      !const <String>{'tcp', 'ws'}.contains(transport)) {
    errors.add('invalidConfigFormat');
  }
  if (security == 'reality') {
    final params = uri.queryParameters;
    final publicKey = params['pbk'] ?? '';
    final shortId = params['sid'] ?? '';
    final validKey = RegExp(r'^[A-Za-z0-9_-]{43,44}$').hasMatch(publicKey);
    final validShortId =
        shortId.isEmpty || RegExp(r'^([0-9a-fA-F]{2})+$').hasMatch(shortId);
    if (!validKey || !validShortId || (params['sni'] ?? '').isEmpty) {
      errors.add('invalidConfigFormat');
    }
  }
  return ConfigValidationResult(
    protocol: VpnProtocolType.vless,
    errors: errors.toSet().toList(),
  );
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
    // WARP можно подключить без Endpoint/AllowedIPs: движок добавит
    // стандартные значения Cloudflare. Для обычного WireGuard такие
    // поля обязательны, иначе туннель заведомо не поднимется.
    final isWarp = (peer['publickey'] ?? '').trim() == _warpPublicKey;
    if ((peer['endpoint'] ?? '').isEmpty) {
      if (isWarp) {
        warnings.add('warpEndpointDefault');
      } else {
        errors.add('invalidConfigMissingEndpoint');
      }
    }
    if ((peer['allowedips'] ?? '').isEmpty) {
      if (isWarp) {
        warnings.add('warpAllowedIpsDefault');
      } else {
        errors.add('invalidConfigMissingAllowedIps');
      }
    }
  }
  if (protocol == VpnProtocolType.amneziawg && interfaceSections.isNotEmpty) {
    // Нативный AmneziaWG-движок требует все четыре заголовка H1–H4.
    // Без них он падает при старте туннеля, поэтому не пускаем такой
    // конфиг в список «поддерживаемых».
    final interface = interfaceSections.first.attributes;
    for (final key in const <String>['h1', 'h2', 'h3', 'h4']) {
      final value = interface[key] ?? '';
      if (value.isEmpty || int.tryParse(value) == null) {
        errors.add('invalidAmneziaHeader');
        break;
      }
    }
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
    final fragmentIndex = afterScheme.indexOf('#');
    if (fragmentIndex >= 0) {
      try {
        final fragment = Uri.decodeComponent(
          afterScheme.substring(fragmentIndex + 1),
        );
        if (fragment.trim().isNotEmpty) {
          return fragment.trim();
        }
      } on FormatException {
        // Битый fragment не должен мешать определить имя по хосту.
      }
    }
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
