import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mouvi/core/localization/app_localizations.dart';
import 'package:mouvi/core/models/vpn_config.dart';
import 'package:mouvi/core/services/push_notification_service.dart';
import 'package:mouvi/core/services/vpn_native_service.dart';
import 'package:mouvi/core/utils/config_parser.dart';
import 'package:mouvi/state/locale_provider.dart';
import 'package:mouvi/state/saved_configs_provider.dart';
import 'package:mouvi/state/vpn_settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum VpnConnectionStatus {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error,
}

class VpnConnectionState {
  const VpnConnectionState({
    this.status = VpnConnectionStatus.disconnected,
    this.activeConfig,
    this.connectedAt,
    this.errorCode,
    this.errorDetails,
    this.rxBytes = 0,
    this.txBytes = 0,
    this.lastHandshakeMs = 0,
    this.reconnectAttempt = 0,
  });

  final VpnConnectionStatus status;
  final VpnConfig? activeConfig;
  final DateTime? connectedAt;

  /// Трафик и рукопожатие из нативного бэкенда. Нули означают, что
  /// статистика ещё не получена (UI не выдумывает значения).
  final int rxBytes;
  final int txBytes;
  final int lastHandshakeMs;

  /// Машинный код ошибки (см. [VpnEngineException]).
  final String? errorCode;
  final String? errorDetails;

  /// Номер текущей попытки автопереподключения (0 = не выполняется).
  final int reconnectAttempt;

  bool get isBusy =>
      status == VpnConnectionStatus.connecting ||
      status == VpnConnectionStatus.disconnecting;

  VpnConnectionState copyWith({
    VpnConnectionStatus? status,
    VpnConfig? activeConfig,
    DateTime? connectedAt,
    bool clearConnectedAt = false,
    String? errorCode,
    String? errorDetails,
    bool clearError = false,
    int? rxBytes,
    int? txBytes,
    int? lastHandshakeMs,
    int? reconnectAttempt,
  }) {
    return VpnConnectionState(
      status: status ?? this.status,
      activeConfig: activeConfig ?? this.activeConfig,
      connectedAt: clearConnectedAt ? null : (connectedAt ?? this.connectedAt),
      errorCode: clearError ? null : (errorCode ?? this.errorCode),
      errorDetails: clearError ? null : (errorDetails ?? this.errorDetails),
      rxBytes: rxBytes ?? this.rxBytes,
      txBytes: txBytes ?? this.txBytes,
      lastHandshakeMs: lastHandshakeMs ?? this.lastHandshakeMs,
      reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
    );
  }
}

class ConnectionNotifier extends Notifier<VpnConnectionState> {
  static const String _activeConfigPrefsKey = 'mouvi.active_config_id';
  static const String _connectedAtPrefsKey = 'mouvi.connected_at_ms';

  StreamSubscription<VpnStateSnapshot>? _nativeSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _statsTimer;
  Timer? _reconnectTimer;
  String? _activeConfigId;
  bool _autoConnectTried = false;
  bool _autoConnectInFlight = false;
  bool _connectCancelRequested = false;
  bool _userInitiatedDisconnect = false;
  int _connectGeneration = 0;

  @override
  VpnConnectionState build() {
    ref.onDispose(() {
      _statsTimer?.cancel();
      _statsTimer = null;
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      unawaited(_nativeSubscription?.cancel());
      unawaited(_connectivitySubscription?.cancel());
    });
    _nativeSubscription = ref
        .read(vpnEngineProvider)
        .stateChanges
        .listen(
          _onNativeState,
          onError: (Object _) {
            // Канал событий может быть недоступен — состояние продолжает
            // обновляться по результатам connect/disconnect.
          },
        );
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      _onConnectivityChanged,
    );
    ref.listen<List<VpnConfig>>(savedConfigsProvider, (previous, next) {
      if (!ref.mounted) {
        return;
      }
      if (state.activeConfig == null) {
        final config = ref
            .read(savedConfigsProvider.notifier)
            .findById(_activeConfigId);
        if (config != null) {
          state = state.copyWith(activeConfig: config);
        }
      }
      unawaited(_maybeAutoConnect());
    });
    ref.listen<VpnSettings>(vpnSettingsProvider, (previous, next) {
      if (next.loaded) {
        unawaited(_maybeAutoConnect());
      }
    });
    unawaited(_restoreFromNative());
    return const VpnConnectionState();
  }

  Future<void> _maybeAutoConnect() async {
    if (_autoConnectTried || _autoConnectInFlight || !ref.mounted) {
      return;
    }
    final settings = ref.read(vpnSettingsProvider);
    if (!settings.loaded || !settings.autoConnectOnLaunch) {
      return;
    }
    if (state.isBusy || state.status != VpnConnectionStatus.disconnected) {
      _autoConnectTried = true;
      return;
    }
    final config = state.activeConfig;
    if (config == null) {
      return;
    }
    if (!config.protocol.engineSupported) {
      _autoConnectTried = true;
      return;
    }
    if (settings.wifiOnly && !await _isWifiAvailable()) {
      _autoConnectTried = true;
      return;
    }
    _autoConnectInFlight = true;
    try {
      final hasPermission = await ref
          .read(vpnEngineProvider)
          .hasVpnPermission();
      if (!ref.mounted) {
        return;
      }
      if (!hasPermission) {
        _autoConnectTried = true;
        return;
      }
      _autoConnectTried = true;
      await connect(config);
    } finally {
      _autoConnectInFlight = false;
    }
  }

  Future<void> _restoreFromNative() async {
    final snapshot = await ref.read(vpnEngineProvider).getState();
    if (!ref.mounted || state.isBusy) {
      return;
    }
    final storedId = await _readActiveConfigId();
    final storedConnectedAt = await _readConnectedAt();
    if (!ref.mounted) {
      return;
    }
    if (state.activeConfig != null) {
      return;
    }
    _activeConfigId = storedId;
    final config = _resolveConfig(storedId);
    if (snapshot.isConnected) {
      state = VpnConnectionState(
        status: VpnConnectionStatus.connected,
        activeConfig: config,
        connectedAt: storedConnectedAt ?? DateTime.now(),
        rxBytes: snapshot.rxBytes,
        txBytes: snapshot.txBytes,
        lastHandshakeMs: snapshot.lastHandshakeMs,
      );
      _startStatsPolling();
    } else if (config != null) {
      state = VpnConnectionState(
        status: VpnConnectionStatus.disconnected,
        activeConfig: config,
      );
    }
    await _maybeAutoConnect();
  }

  Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  Future<String?> _readActiveConfigId() async {
    final prefs = await _prefs();
    return prefs?.getString(_activeConfigPrefsKey);
  }

  Future<DateTime?> _readConnectedAt() async {
    final prefs = await _prefs();
    final millis = prefs?.getInt(_connectedAtPrefsKey);
    if (millis == null) {
      return null;
    }
    final value = DateTime.fromMillisecondsSinceEpoch(millis);
    if (value.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      return null;
    }
    return value;
  }

  Future<void> _writeActiveConfigId(String? id) async {
    final prefs = await _prefs();
    if (prefs == null) {
      return;
    }
    if (id == null) {
      await prefs.remove(_activeConfigPrefsKey);
    } else {
      await prefs.setString(_activeConfigPrefsKey, id);
    }
  }

  Future<void> _writeConnectedAt(DateTime? connectedAt) async {
    final prefs = await _prefs();
    if (prefs == null) {
      return;
    }
    if (connectedAt == null) {
      await prefs.remove(_connectedAtPrefsKey);
    } else {
      await prefs.setInt(
        _connectedAtPrefsKey,
        connectedAt.millisecondsSinceEpoch,
      );
    }
  }

  VpnConfig? _resolveConfig(String? id) {
    return ref.read(savedConfigsProvider.notifier).findById(id);
  }

  Future<bool> _isWifiAvailable() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet);
    } catch (_) {
      return true;
    }
  }

  Future<bool> _hasAnyNetwork() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((result) => result != ConnectivityResult.none);
    } catch (_) {
      return true;
    }
  }

  Future<void> connect(VpnConfig config, {bool isReconnect = false}) async {
    if (state.isBusy) {
      return;
    }
    if (state.status == VpnConnectionStatus.connected &&
        state.activeConfig?.id == config.id) {
      return;
    }
    if (!config.protocol.engineSupported) {
      state = VpnConnectionState(
        status: VpnConnectionStatus.error,
        activeConfig: config,
        errorCode: VpnEngineException.unsupportedProtocol,
      );
      return;
    }
    if (!validateConfig(config.content).isValid) {
      state = VpnConnectionState(
        status: VpnConnectionStatus.error,
        activeConfig: config,
        errorCode: VpnEngineException.invalidConfig,
      );
      return;
    }
    final settings = ref.read(vpnSettingsProvider);
    if (settings.wifiOnly && !await _isWifiAvailable()) {
      state = VpnConnectionState(
        status: VpnConnectionStatus.error,
        activeConfig: config,
        errorCode: VpnEngineException.wifiOnly,
      );
      return;
    }
    if (!await _hasAnyNetwork()) {
      state = VpnConnectionState(
        status: VpnConnectionStatus.error,
        activeConfig: config,
        errorCode: VpnEngineException.networkUnavailable,
      );
      return;
    }

    if (state.status == VpnConnectionStatus.connected) {
      await _disconnectInternal(notify: false, userInitiated: false);
      if (!ref.mounted) {
        return;
      }
    }

    _cancelReconnectTimer();
    _userInitiatedDisconnect = false;
    _connectCancelRequested = false;
    final generation = ++_connectGeneration;

    final excluded = settings.splitMode == SplitTunnelingMode.exclude
        ? settings.selectedApplications
        : const <String>[];
    final included = settings.splitMode == SplitTunnelingMode.include
        ? settings.selectedApplications
        : const <String>[];

    state = VpnConnectionState(
      status: VpnConnectionStatus.connecting,
      activeConfig: config,
      reconnectAttempt: isReconnect ? state.reconnectAttempt : 0,
    );
    try {
      await ref
          .read(vpnEngineProvider)
          .connect(
            config,
            excludedApplications: excluded,
            includedApplications: included,
            dnsProtection: settings.dnsProtectionEnabled,
            dnsServers: settings.dnsServersForEngine,
          )
          .timeout(Duration(seconds: settings.connectTimeoutSeconds));
      if (!ref.mounted || generation != _connectGeneration) {
        return;
      }
      if (_connectCancelRequested) {
        await ref.read(vpnEngineProvider).disconnect().catchError((_) {});
        if (!ref.mounted) {
          return;
        }
        state = VpnConnectionState(
          status: VpnConnectionStatus.disconnected,
          activeConfig: config,
        );
        return;
      }
      _activeConfigId = config.id;
      unawaited(_writeActiveConfigId(config.id));
      final connectedAt = DateTime.now();
      unawaited(_writeConnectedAt(connectedAt));
      state = VpnConnectionState(
        status: VpnConnectionStatus.connected,
        activeConfig: config,
        connectedAt: connectedAt,
      );
      _startStatsPolling();
      _notifyPush('connected', config);
    } on TimeoutException {
      if (!ref.mounted || generation != _connectGeneration) {
        return;
      }
      await ref.read(vpnEngineProvider).disconnect().catchError((_) {});
      if (!ref.mounted) {
        return;
      }
      if (_connectCancelRequested) {
        state = VpnConnectionState(
          status: VpnConnectionStatus.disconnected,
          activeConfig: config,
        );
        return;
      }
      await _handleConnectFailure(
        config,
        VpnEngineException.connectionTimeout,
        null,
      );
    } on VpnEngineException catch (error) {
      if (!ref.mounted || generation != _connectGeneration) {
        return;
      }
      if (_connectCancelRequested ||
          error.code == VpnEngineException.connectionCancelled) {
        state = VpnConnectionState(
          status: VpnConnectionStatus.disconnected,
          activeConfig: config,
        );
        return;
      }
      await _handleConnectFailure(config, error.code, error.details);
    } catch (error) {
      if (!ref.mounted || generation != _connectGeneration) {
        return;
      }
      if (_connectCancelRequested) {
        state = VpnConnectionState(
          status: VpnConnectionStatus.disconnected,
          activeConfig: config,
        );
        return;
      }
      await _handleConnectFailure(
        config,
        VpnEngineException.unknown,
        error.toString(),
      );
    }
  }

  Future<void> _handleConnectFailure(
    VpnConfig config,
    String code,
    String? details,
  ) async {
    final settings = ref.read(vpnSettingsProvider);
    final canRetry =
        settings.autoReconnectEnabled &&
        !_userInitiatedDisconnect &&
        !_connectCancelRequested &&
        code != VpnEngineException.vpnPermissionDenied &&
        code != VpnEngineException.invalidConfig &&
        code != VpnEngineException.unsupportedProtocol &&
        code != VpnEngineException.wifiOnly;
    if (canRetry &&
        state.reconnectAttempt < settings.autoReconnectMaxAttempts) {
      final nextAttempt = state.reconnectAttempt + 1;
      state = VpnConnectionState(
        status: VpnConnectionStatus.error,
        activeConfig: config,
        errorCode: code,
        errorDetails: details,
        reconnectAttempt: nextAttempt,
      );
      _scheduleReconnect(config, nextAttempt);
      return;
    }
    state = VpnConnectionState(
      status: VpnConnectionStatus.error,
      activeConfig: config,
      errorCode: code,
      errorDetails: details,
      reconnectAttempt: 0,
    );
  }

  void _scheduleReconnect(VpnConfig config, int attempt) {
    _reconnectTimer?.cancel();
    final delaySeconds = (attempt * 2).clamp(2, 10);
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      unawaited(_runScheduledReconnect(config));
    });
  }

  Future<void> _runScheduledReconnect(VpnConfig config) async {
    if (!ref.mounted || _userInitiatedDisconnect) {
      return;
    }
    final settings = ref.read(vpnSettingsProvider);
    if (!settings.autoReconnectEnabled) {
      return;
    }
    if (settings.wifiOnly && !await _isWifiAvailable()) {
      return;
    }
    if (state.isBusy || state.status == VpnConnectionStatus.connected) {
      return;
    }
    state = state.copyWith(
      status: VpnConnectionStatus.connecting,
      clearError: true,
    );
    await connect(config, isReconnect: true);
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  Future<void> cancelConnect() async {
    if (state.status != VpnConnectionStatus.connecting) {
      return;
    }
    _connectCancelRequested = true;
    _userInitiatedDisconnect = true;
    _cancelReconnectTimer();
    _connectGeneration++;
    try {
      await ref.read(vpnEngineProvider).disconnect();
    } catch (_) {}
    if (!ref.mounted) {
      return;
    }
    final config = state.activeConfig;
    state = VpnConnectionState(
      status: VpnConnectionStatus.disconnected,
      activeConfig: config,
    );
  }

  Future<void> disconnect() async {
    _userInitiatedDisconnect = true;
    _connectCancelRequested = true;
    _cancelReconnectTimer();
    if (state.status == VpnConnectionStatus.connecting) {
      await cancelConnect();
      return;
    }
    if (state.status != VpnConnectionStatus.connected) {
      state = state.copyWith(reconnectAttempt: 0);
      return;
    }
    await _disconnectInternal(notify: true, userInitiated: true);
  }

  Future<void> _disconnectInternal({
    required bool notify,
    bool userInitiated = false,
  }) async {
    final config = state.activeConfig;
    _stopStatsPolling();
    state = state.copyWith(
      status: VpnConnectionStatus.disconnecting,
      clearError: true,
      reconnectAttempt: 0,
    );
    try {
      await ref
          .read(vpnEngineProvider)
          .disconnect()
          .timeout(const Duration(minutes: 2));
      if (!ref.mounted) {
        return;
      }
      unawaited(_writeConnectedAt(null));
      state = VpnConnectionState(
        status: VpnConnectionStatus.disconnected,
        activeConfig: config,
      );
      if (notify) {
        _notifyPush('disconnected', config);
      }
    } on TimeoutException {
      if (!ref.mounted) {
        return;
      }
      state = VpnConnectionState(
        status: VpnConnectionStatus.error,
        activeConfig: config,
        errorCode: VpnEngineException.tunnelStartFailed,
      );
    } on VpnEngineException catch (error) {
      if (!ref.mounted) {
        return;
      }
      state = VpnConnectionState(
        status: VpnConnectionStatus.error,
        activeConfig: config,
        errorCode: error.code,
        errorDetails: error.details,
      );
    } catch (error) {
      if (!ref.mounted) {
        return;
      }
      state = VpnConnectionState(
        status: VpnConnectionStatus.error,
        activeConfig: config,
        errorCode: VpnEngineException.unknown,
        errorDetails: error.toString(),
      );
    }
  }

  Future<void> retry() async {
    final config = state.activeConfig;
    if (config == null || state.isBusy) {
      return;
    }
    _cancelReconnectTimer();
    _userInitiatedDisconnect = false;
    _connectCancelRequested = false;
    _stopStatsPolling();
    state = VpnConnectionState(activeConfig: config);
    await connect(config);
  }

  void selectConfig(VpnConfig config) {
    if (state.isBusy || state.status == VpnConnectionStatus.connected) {
      return;
    }
    _activeConfigId = config.id;
    unawaited(_writeActiveConfigId(config.id));
    _stopStatsPolling();
    state = VpnConnectionState(
      status: VpnConnectionStatus.disconnected,
      activeConfig: config,
    );
  }

  Future<bool> quickToggle() async {
    if (state.status == VpnConnectionStatus.connecting) {
      await cancelConnect();
      return true;
    }
    if (state.isBusy) {
      return true;
    }
    if (state.status == VpnConnectionStatus.connected) {
      await disconnect();
      return true;
    }
    final configs = ref.read(savedConfigsProvider);
    final config =
        state.activeConfig ??
        _resolveConfig(_activeConfigId) ??
        (configs.isEmpty ? null : configs.first);
    if (config == null) {
      return false;
    }
    state = state.copyWith(activeConfig: config);
    await connect(config);
    return true;
  }

  void _startStatsPolling() {
    _statsTimer ??= Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_syncStats());
    });
  }

  void _stopStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = null;
  }

  Future<void> _syncStats() async {
    if (!ref.mounted || state.status != VpnConnectionStatus.connected) {
      _stopStatsPolling();
      return;
    }
    final snapshot = await ref.read(vpnEngineProvider).getState();
    if (!ref.mounted ||
        !snapshot.isConnected ||
        state.status != VpnConnectionStatus.connected) {
      return;
    }
    state = state.copyWith(
      rxBytes: snapshot.rxBytes,
      txBytes: snapshot.txBytes,
      lastHandshakeMs: snapshot.lastHandshakeMs,
    );
  }

  void _onNativeState(VpnStateSnapshot snapshot) {
    if (!ref.mounted) {
      return;
    }
    if (snapshot.isConnected) {
      if (state.status == VpnConnectionStatus.connected) {
        return;
      }
      if (state.status == VpnConnectionStatus.disconnecting) {
        return;
      }
      final config = state.activeConfig ?? _resolveConfig(_activeConfigId);
      state = VpnConnectionState(
        status: VpnConnectionStatus.connected,
        activeConfig: config,
        connectedAt: state.connectedAt ?? DateTime.now(),
        rxBytes: snapshot.rxBytes,
        txBytes: snapshot.txBytes,
        lastHandshakeMs: snapshot.lastHandshakeMs,
      );
      _startStatsPolling();
      return;
    }
    if (state.status != VpnConnectionStatus.connected) {
      return;
    }
    _stopStatsPolling();
    final config = state.activeConfig;
    unawaited(_writeConnectedAt(null));
    final settings = ref.read(vpnSettingsProvider);
    final shouldReconnect =
        !_userInitiatedDisconnect &&
        settings.autoReconnectEnabled &&
        config != null;
    if (shouldReconnect) {
      final nextAttempt = 1;
      state = VpnConnectionState(
        status: VpnConnectionStatus.error,
        activeConfig: config,
        errorCode: VpnEngineException.tunnelStartFailed,
        reconnectAttempt: nextAttempt,
      );
      _scheduleReconnect(config, nextAttempt);
    } else {
      state = VpnConnectionState(
        status: VpnConnectionStatus.disconnected,
        activeConfig: config,
      );
    }
    _notifyPush('disconnected', config);
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    if (!ref.mounted) {
      return;
    }
    final settings = ref.read(vpnSettingsProvider);
    final hasNetwork = results.any(
      (result) => result != ConnectivityResult.none,
    );
    final hasWifi =
        results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet);

    if (settings.wifiOnly && !hasWifi) {
      if (state.status == VpnConnectionStatus.connecting) {
        unawaited(cancelConnect());
      } else if (state.status == VpnConnectionStatus.connected &&
          !_userInitiatedDisconnect) {
        unawaited(disconnect());
      }
      return;
    }

    if (!hasNetwork) {
      return;
    }

    if (settings.reconnectOnNetworkChange &&
        !_userInitiatedDisconnect &&
        state.status == VpnConnectionStatus.connected) {
      final config = state.activeConfig;
      if (config != null) {
        unawaited(_reconnectSameConfig(config));
      }
      return;
    }

    if (settings.autoReconnectEnabled &&
        !_userInitiatedDisconnect &&
        state.status == VpnConnectionStatus.error &&
        state.reconnectAttempt > 0) {
      final config = state.activeConfig;
      if (config != null &&
          state.reconnectAttempt < settings.autoReconnectMaxAttempts) {
        _cancelReconnectTimer();
        _scheduleReconnect(config, state.reconnectAttempt);
      }
    }
  }

  Future<void> _reconnectSameConfig(VpnConfig config) async {
    if (state.isBusy) {
      return;
    }
    await _disconnectInternal(notify: false, userInitiated: false);
    if (!ref.mounted || _userInitiatedDisconnect) {
      return;
    }
    await connect(config);
  }

  void _notifyPush(String type, VpnConfig? config) {
    if (!ref.read(pushNotificationsEnabledProvider)) {
      return;
    }
    final localizations = AppLocalizations(ref.read(localeProvider));
    final title = localizations.t(
      type == 'connected' ? 'connected' : 'disconnected',
    );
    final text = config == null
        ? null
        : '${config.name} · ${localizations.t(config.protocol.labelKey)}';
    unawaited(
      ref
          .read(pushNotificationServiceProvider)
          .notify(
            type,
            serverName: config?.name,
            protocol: config?.protocol.name,
            title: title,
            text: text,
            disconnectAction: localizations.t('disconnect'),
          ),
    );
  }
}

final connectionProvider =
    NotifierProvider<ConnectionNotifier, VpnConnectionState>(
      ConnectionNotifier.new,
    );
