import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mouvi/core/models/vpn_config.dart';

class SavedConfigsNotifier extends Notifier<List<VpnConfig>> {
  @override
  List<VpnConfig> build() => const [];

  void addConfig(VpnConfig config) {
    state = [...state, config];
  }

  void removeConfig(String id) {
    state = state.where((config) => config.id != id).toList();
  }
}

final savedConfigsProvider = NotifierProvider<SavedConfigsNotifier, List<VpnConfig>>(SavedConfigsNotifier.new);
