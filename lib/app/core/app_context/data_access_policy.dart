import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_data_mode.dart';
import '../config/app_environment.dart';

enum AppModule { pdv, erp, crm }

enum DataSourceStrategy { localFirst, serverFirst }

enum DataAccessStrategy { localOnly, localFirst, serverFirst, hybridReady }

DataSourceStrategy strategyForModule(AppModule module) {
  switch (module) {
    case AppModule.pdv:
      return DataSourceStrategy.localFirst;
    case AppModule.erp:
    case AppModule.crm:
      return DataSourceStrategy.serverFirst;
  }
}

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
          strategy: DataAccessStrategy.serverFirst,
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
      case DataAccessStrategy.serverFirst:
        return 'Server first';
      case DataAccessStrategy.hybridReady:
        return 'Hibrido pronto';
    }
  }

  DataSourceStrategy strategyFor(AppModule module) {
    if (!allowRemoteRead) {
      return DataSourceStrategy.localFirst;
    }
    return strategyForModule(module);
  }
}

final appDataAccessPolicyProvider = Provider<DataAccessPolicy>((ref) {
  final mode = ref.watch(appDataModeProvider);
  return DataAccessPolicy.fromMode(mode);
});
