import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mouvi/core/services/update_service.dart';

enum UpdateCheckStatus { idle, checking, upToDate, updateAvailable, error }

class UpdateState {
  const UpdateState({
    this.status = UpdateCheckStatus.idle,
    this.info,
    this.errorCode,
  });

  final UpdateCheckStatus status;
  final AppUpdateInfo? info;
  final String? errorCode;

  UpdateState copyWith({
    UpdateCheckStatus? status,
    AppUpdateInfo? info,
    bool clearInfo = false,
    String? errorCode,
    bool clearError = false,
  }) {
    return UpdateState(
      status: status ?? this.status,
      info: clearInfo ? null : (info ?? this.info),
      errorCode: clearError ? null : (errorCode ?? this.errorCode),
    );
  }
}

class UpdateNotifier extends Notifier<UpdateState> {
  @override
  UpdateState build() => const UpdateState();

  Future<void> check() async {
    if (state.status == UpdateCheckStatus.checking) {
      return;
    }
    state = state.copyWith(
      status: UpdateCheckStatus.checking,
      clearError: true,
    );
    try {
      final info = await ref.read(updateServiceProvider).checkForUpdates();
      state = UpdateState(
        status: info.hasUpdate
            ? UpdateCheckStatus.updateAvailable
            : UpdateCheckStatus.upToDate,
        info: info,
      );
    } on UpdateCheckException catch (e) {
      state = UpdateState(
        status: UpdateCheckStatus.error,
        errorCode: e.code,
        info: state.info,
      );
    } catch (_) {
      state = UpdateState(
        status: UpdateCheckStatus.error,
        errorCode: 'unknown',
        info: state.info,
      );
    }
  }

  void reset() {
    state = const UpdateState();
  }
}

final updateProvider = NotifierProvider<UpdateNotifier, UpdateState>(
  UpdateNotifier.new,
);
