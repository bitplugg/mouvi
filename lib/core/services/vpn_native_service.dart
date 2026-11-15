import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mouvi/core/models/vpn_config.dart';

/// Состояние нативного VPN-движка.
enum VpnEngineStatus { up, down }

class VpnStateSnapshot {
  const VpnStateSnapshot({
    required this.status,
    this.tunnelName,
    this.alwaysOn = false,
    this.lockdown = false,
  });

  factory VpnStateSnapshot.fromChannel(Object? value) {
    if (value is! Map) {
      return const VpnStateSnapshot(status: VpnEngineStatus.down);
    }
    final rawStatus = value['status']?.toString().toLowerCase();
    final tunnelName = value['tunnelName'];
    return VpnStateSnapshot(
      status: rawStatus == 'up' ? VpnEngineStatus.up : VpnEngineStatus.down,
      tunnelName: tunnelName is String && tunnelName.isNotEmpty
          ? tunnelName
          : null,
      alwaysOn: value['alwaysOn'] == true,
      lockdown: value['lockdown'] == true,
    );
  }

  final VpnEngineStatus status;
  final String? tunnelName;

  /// Включён ли системный Always-on VPN (настройка Android, не Mouvi).
  final bool alwaysOn;

  /// Включён ли системный режим блокировки (Lockdown) для Always-on VPN.
  final bool lockdown;

  bool get isConnected => status == VpnEngineStatus.up;

  @override
  String toString() => 'VpnStateSnapshot(${status.name}, tunnel: $tunnelName)';
}

/// Ошибка нативного VPN-движка с машинным кодом.
class VpnEngineException implements Exception {
  const VpnEngineException(this.code, {this.details});

  static const String unsupportedProtocol = 'unsupported_protocol';
  static const String vpnPermissionDenied = 'vpn_permission_denied';
  static const String invalidConfig = 'invalid_config';
  static const String tunnelStartFailed = 'tunnel_start_failed';
  static const String notConnected = 'not_connected';
  static const String nativeUnavailable = 'native_unavailable';
  static const String busy = 'busy';
  static const String unknown = 'unknown';

  final String code;
  final String? details;

  @override
  String toString() =>
      'VpnEngineException($code${details == null ? '' : ': $details'})';
}

/// Контракт платформенного VPN-движка.
///
/// Реальная реализация — WireGuard (userspace GoBackend) на Android.
/// Kotlin-сторона использует единый типизированный набор аргументов
/// и возвращает ошибки через [PlatformException] с кодами из
/// [VpnEngineException].
abstract class VpnEngine {
  /// Поднять туннель. Бросает [VpnEngineException] при ошибке.
  Future<void> connect(
    VpnConfig config, {
    List<String> excludedApplications = const <String>[],
    bool dnsProtection = true,
  });

  /// Опустить туннель. Бросает [VpnEngineException] при ошибке.
  Future<void> disconnect();

  /// Реальное состояние туннеля (в том числе после пересоздания Activity).
  Future<VpnStateSnapshot> getState();

  /// Поток изменений состояния из нативного слоя.
  Stream<VpnStateSnapshot> get stateChanges;

  /// Открыть системные настройки VPN (Always-on / блокировка).
  Future<void> openVpnSettings();
}

class MethodChannelVpnEngine extends VpnEngine {
  MethodChannelVpnEngine({MethodChannel? channel, EventChannel? eventChannel})
    : _channel = channel ?? const MethodChannel('mouvi/vpn'),
      _eventChannel = eventChannel ?? const EventChannel('mouvi/vpn_events');

  final MethodChannel _channel;
  final EventChannel _eventChannel;

  VpnEngineException _mapPlatformException(PlatformException error) {
    final details = error.message;
    switch (error.code) {
      case VpnEngineException.unsupportedProtocol:
      case VpnEngineException.vpnPermissionDenied:
      case VpnEngineException.invalidConfig:
      case VpnEngineException.tunnelStartFailed:
      case VpnEngineException.notConnected:
      case VpnEngineException.busy:
        return VpnEngineException(error.code, details: details);
      default:
        return VpnEngineException(
          VpnEngineException.tunnelStartFailed,
          details: details ?? error.code,
        );
    }
  }

  @override
  Future<void> connect(
    VpnConfig config, {
    List<String> excludedApplications = const <String>[],
    bool dnsProtection = true,
  }) async {
    try {
      await _channel.invokeMethod<void>('connect', <String, dynamic>{
        'id': config.id,
        'name': config.name,
        'protocol': config.protocol.channelName,
        'content': config.content,
        'excludedApplications': excludedApplications,
        'dnsProtection': dnsProtection,
      });
    } on PlatformException catch (error) {
      throw _mapPlatformException(error);
    } on MissingPluginException {
      throw const VpnEngineException(VpnEngineException.nativeUnavailable);
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await _channel.invokeMethod<void>('disconnect');
    } on PlatformException catch (error) {
      throw _mapPlatformException(error);
    } on MissingPluginException {
      throw const VpnEngineException(VpnEngineException.nativeUnavailable);
    }
  }

  @override
  Future<VpnStateSnapshot> getState() async {
    try {
      final result = await _channel.invokeMethod<Object?>('getState');
      return VpnStateSnapshot.fromChannel(result);
    } on PlatformException {
      return const VpnStateSnapshot(status: VpnEngineStatus.down);
    } on MissingPluginException {
      return const VpnStateSnapshot(status: VpnEngineStatus.down);
    }
  }

  @override
  Stream<VpnStateSnapshot> get stateChanges {
    return _eventChannel.receiveBroadcastStream().map(
      VpnStateSnapshot.fromChannel,
    );
  }

  @override
  Future<void> openVpnSettings() async {
    try {
      await _channel.invokeMethod<void>('openVpnSettings');
    } on MissingPluginException {
      throw const VpnEngineException(VpnEngineException.nativeUnavailable);
    } on PlatformException catch (error) {
      throw _mapPlatformException(error);
    }
  }
}

final vpnEngineProvider = Provider<VpnEngine>(
  (ref) => MethodChannelVpnEngine(),
);
