import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_data_mode.dart';
import '../config/app_environment.dart';

enum DataAccessStrategy { localOnly, localFirst, hybridReady }

class DataAccessPolicy {
  const DataAccessPolicy({
    required this.mode,
    required this.strategy,
    required this.allowRemoteRead,
    required this.allowRemoteWrite,
  });

  factory DataAccessPolicy.fromMode(AppDataMode mode) {
    switch (mode) {
      case AppDataMode.localOnly:
        return const DataAccessPolicy(
          mode: AppDataMode.localOnly,
          strategy: DataAccessStrategy.localOnly,
          allowRemoteRead: false,
          allowRemoteWrite: false,
        );
      case AppDataMode.futureRemoteReady:
        return const DataAccessPolicy(
          mode: AppDataMode.futureRemoteReady,
          strategy: DataAccessStrategy.localFirst,
          allowRemoteRead: true,
          allowRemoteWrite: false,
        );
      case AppDataMode.futureHybridReady:
        return const DataAccessPolicy(
          mode: AppDataMode.futureHybridReady,
          strategy: DataAccessStrategy.hybridReady,
          allowRemoteRead: true,
          allowRemoteWrite: true,
        );
    }
  }

  final AppDataMode mode;
  final DataAccessStrategy strategy;
  final bool allowRemoteRead;
  final bool allowRemoteWrite;

  String get strategyLabel {
    switch (strategy) {
      case DataAccessStrategy.localOnly:
        return 'Somente local';
      case DataAccessStrategy.localFirst:
        return 'Local first';
      case DataAccessStrategy.hybridReady:
        return 'Hibrido pronto';
    }
  }
}

final appDataAccessPolicyProvider = Provider<DataAccessPolicy>((ref) {
  final mode = ref.watch(appDataModeProvider);
  return DataAccessPolicy.fromMode(mode);
});
