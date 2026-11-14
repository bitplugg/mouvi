import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mouvi/core/models/vpn_config.dart';

/// Контракт платформенного VPN-движка.
///
/// Реализации:
/// - `MethodChannelVpnEngine` — вызовы в Kotlin/Java нативного кода
///   (BoringWrapper / WireGuard / AmneziaWG / OpenVPN / Trojan / Shadowsocks / VLESS).
/// - Позже — дополнительные реализации (например, тестовая/заглушка для MVP.
abstract class VpnEngine {
  /// Подключиться к серверу. Возвращает `true`, если соединение
  /// было успешно установлено на нативной стороне.
  Future<bool> connect(VpnConfig config);

  /// Отключиться от текущего VPN-соединения.
  Future<bool> disconnect();

  /// Включить/выключить системный kill switch.
  Future<void> setKillSwitch({required bool enabled});
}

/// Реализация VpnEngine через Flutter MethodChannel `mouvi/vpn`.
class MethodChannelVpnEngine extends VpnEngine {
  MethodChannelVpnEngine({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('mouvi/vpn');

  final MethodChannel _channel;

  @override
  Future<bool> connect(VpnConfig config) async {
    final result = await _channel.invokeMethod<bool>('connect', <String, dynamic>{
      'protocol': config.protocol.name,
      'name': config.name,
      'content': config.content,
    });
    return result ?? false;
  }

  @override
  Future<bool> disconnect() async {
    final result = await _channel.invokeMethod<bool>('disconnect');
    return result ?? false;
  }

  @override
  Future<void> setKillSwitch({required bool enabled}) async {
    await _channel.invokeMethod<void>('setKillSwitch', <String, dynamic>{
      'enabled': enabled,
    });
  }
}

final vpnEngineProvider = Provider<VpnEngine>((ref) => MethodChannelVpnEngine());
