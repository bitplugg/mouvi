import 'dart:async';

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
    );
  }
}

class ConnectionNotifier extends Notifier<VpnConnectionState> {
  static const String _activeConfigPrefsKey = 'mouvi.active_config_id';
  static const String _connectedAtPrefsKey = 'mouvi.connected_at_ms';

  StreamSubscription<VpnStateSnapshot>? _nativeSubscription;
  Timer? _statsTimer;
  String? _activeConfigId;
  bool _autoConnectTried = false;
  bool _autoConnectInFlight = false;

  @override
  VpnConnectionState build() {
    ref.onDispose(() {
      _statsTimer?.cancel();
      _statsTimer = null;
      unawaited(_nativeSubscription?.cancel());
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

  /// Автоподключение при запуске.
  ///
  /// Срабатывает один раз за процесс и только если разрешение VPN уже
  /// выдано: иначе приложение неожиданно показывало бы системный диалог.
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
      // Конфиги ещё загружаются — попробуем после обновления списка.
      return;
    }
    if (!config.protocol.engineSupported) {
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
      // Пользователь уже выбрал сервер, пока шло восстановление.
      return;
    }
    _activeConfigId = storedId;
    final config = _resolveConfig(storedId);
    if (snapshot.isConnected) {
      state = VpnConnectionState(
        status: VpnConnectionStatus.connected,
        activeConfig: config,
        // После пересоздания Activity туннель остаётся поднятым, поэтому
        // берём сохранённое время старта, чтобы uptime не сбрасывался.
        connectedAt: storedConnectedAt ?? DateTime.now(),
        rxBytes: snapshot.rxBytes,
        txBytes: snapshot.txBytes,
        lastHandshakeMs: snapshot.lastHandshakeMs,
      );
      _startStatsPolling();
    } else if (config != null) {
      // Туннель не поднят, но последний выбранный сервер сохраняем.
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
    // Отбрасываем явно некорректное время (например, часы перевели назад).
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

  /// Подключиться к выбранному серверу.
  ///
  /// Повторные нажатия во время подключения/отключения игнорируются.
  Future<void> connect(VpnConfig config) async {
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
    // Конфиг мог быть сохранён до ужесточения проверок или изменён вручную.
    // Не отдаём заведомо нерабочий конфиг нативному движку.
    if (!validateConfig(config.content).isValid) {
      state = VpnConnectionState(
        status: VpnConnectionStatus.error,
        activeConfig: config,
        errorCode: VpnEngineException.invalidConfig,
      );
      return;
    }
    if (state.status == VpnConnectionStatus.connected) {
      await _disconnectInternal(notify: false);
      if (!ref.mounted) {
        return;
      }
    }

    final settings = ref.read(vpnSettingsProvider);
    final excluded = settings.splitMode == SplitTunnelingMode.exclude
        ? settings.selectedApplications
        : const <String>[];
    final included = settings.splitMode == SplitTunnelingMode.include
        ? settings.selectedApplications
        : const <String>[];
    state = VpnConnectionState(
      status: VpnConnectionStatus.connecting,
      activeConfig: config,
    );
    try {
      await ref
          .read(vpnEngineProvider)
          .connect(
            config,
            excludedApplications: excluded,
            includedApplications: included,
            dnsProtection: settings.dnsProtectionEnabled,
          )
          .timeout(const Duration(minutes: 2));
      if (!ref.mounted) {
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

  Future<void> disconnect() async {
    if (state.status != VpnConnectionStatus.connected) {
      return;
    }
    await _disconnectInternal(notify: true);
  }

  Future<void> _disconnectInternal({required bool notify}) async {
    final config = state.activeConfig;
    _stopStatsPolling();
    state = state.copyWith(
      status: VpnConnectionStatus.disconnecting,
      clearError: true,
    );
    try {
      await ref
          .read(vpnEngineProvider)
          .disconnect()
          .timeout(const Duration(minutes: 2));
      if (!ref.mounted) {
        return;
      }
      // Последний выбранный сервер оставляем, чтобы после перезапуска
      // приложения он был выбран снова; сбрасываем только время старта.
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

  /// Повторить подключение после ошибки.
  Future<void> retry() async {
    final config = state.activeConfig;
    if (config == null || state.isBusy) {
      return;
    }
    _stopStatsPolling();
    state = const VpnConnectionState();
    await connect(config);
  }

  /// Выбрать сервер без подключения (например, из списка).
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

  /// Обработать открытие приложения из плитки Quick Settings.
  ///
  /// Возвращает `false`, если подключаться не к чему: вызывающая сторона
  /// может показать список серверов.
  Future<bool> quickToggle() async {
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

  /// Периодически обновлять статистику туннеля.
  ///
  /// Нативный слой присылает события только при смене состояния, а трафик
  /// и время рукопожатия меняются постоянно. Опрос идёт только пока
  /// туннель поднят и прекращается при отключении/ошибке.
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

  /// Реакция на реальные события из нативного слоя.
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
    // Туннель опущен. Пока идёт наш собственный connect/disconnect,
    // итоговое состояние выставит соответствующий вызов.
    if (state.status != VpnConnectionStatus.connected) {
      return;
    }
    _stopStatsPolling();
    final config = state.activeConfig;
    unawaited(_writeConnectedAt(null));
    state = VpnConnectionState(
      status: VpnConnectionStatus.disconnected,
      activeConfig: config,
    );
    _notifyPush('disconnected', config);
  }

  void _notifyPush(String type, VpnConfig? config) {
    if (!ref.read(pushNotificationsEnabledProvider)) {
      return;
    }
    // Локальные уведомления локализуем так же, как интерфейс приложения,
    // чтобы язык не зависел от системного.
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
