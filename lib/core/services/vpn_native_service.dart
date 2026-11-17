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
    this.rxBytes = 0,
    this.txBytes = 0,
    this.lastHandshakeMs = 0,
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
      rxBytes: _toInt(value['rxBytes']),
      txBytes: _toInt(value['txBytes']),
      lastHandshakeMs: _toInt(value['lastHandshakeMs']),
    );
  }

  static int _toInt(Object? value) {
    if (value is int) {
      return value < 0 ? 0 : value;
    }
    if (value is num) {
      final rounded = value.round();
      return rounded < 0 ? 0 : rounded;
    }
    return 0;
  }

  final VpnEngineStatus status;
  final String? tunnelName;

  /// Включён ли системный Always-on VPN (настройка Android, не Mouvi).
  final bool alwaysOn;

  /// Включён ли системный режим блокировки (Lockdown) для Always-on VPN.
  final bool lockdown;

  /// Получено байт с момента подключения.
  final int rxBytes;

  /// Отправлено байт с момента подключения.
  final int txBytes;

  /// Время последнего рукопожатия (Unix ms) или 0, если его ещё не было.
  final int lastHandshakeMs;

  bool get isConnected => status == VpnEngineStatus.up;

  bool get hasHandshake => lastHandshakeMs > 0;

  @override
  String toString() =>
      'VpnStateSnapshot(${status.name}, tunnel: $tunnelName, '
      'rx: $rxBytes, tx: $txBytes)';
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
    List<String> includedApplications = const <String>[],
    bool dnsProtection = true,
  });

  /// Опустить туннель. Бросает [VpnEngineException] при ошибке.
  Future<void> disconnect();

  /// Действие, с которым приложение открыли (плитка Quick Settings).
  /// Возвращает `toggle` один раз, затем `null`.
  Future<String?> getLaunchAction();

  /// Действия, приходящие при повторном открытии Activity из плитки.
  Stream<String> get launchActions;

  /// Есть ли уже выданное системе разрешение VPN (без запроса диалога).
  Future<bool> hasVpnPermission();

  /// Реальное состояние туннеля (в том числе после пересоздания Activity).
  Future<VpnStateSnapshot> getState();

  /// Поток изменений состояния из нативного слоя.
  Stream<VpnStateSnapshot> get stateChanges;

  /// Открыть системные настройки VPN (Always-on / блокировка).
  Future<void> openVpnSettings();
}

class MethodChannelVpnEngine extends VpnEngine {
  MethodChannelVpnEngine({
    MethodChannel? channel,
    EventChannel? eventChannel,
    EventChannel? actionChannel,
  }) : _channel = channel ?? const MethodChannel('mouvi/vpn'),
       _eventChannel = eventChannel ?? const EventChannel('mouvi/vpn_events'),
       _actionChannel = actionChannel ?? const EventChannel('mouvi/actions');

  final MethodChannel _channel;
  final EventChannel _eventChannel;
  final EventChannel _actionChannel;

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
    List<String> includedApplications = const <String>[],
    bool dnsProtection = true,
  }) async {
    try {
      await _channel.invokeMethod<void>('connect', <String, dynamic>{
        'id': config.id,
        'name': config.name,
        'protocol': config.protocol.channelName,
        'content': config.content,
        'excludedApplications': excludedApplications,
        'includedApplications': includedApplications,
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
  Stream<String> get launchActions {
    return _actionChannel
        .receiveBroadcastStream()
        .map((event) => event?.toString() ?? '')
        .where((event) => event.isNotEmpty);
  }

  @override
  Future<String?> getLaunchAction() async {
    try {
      return await _channel.invokeMethod<String>('getLaunchAction');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<bool> hasVpnPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasVpnPermission') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
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
