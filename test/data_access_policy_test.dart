import 'package:erp_pdv_app/app/core/app_context/data_access_policy.dart';
import 'package:erp_pdv_app/app/core/config/app_data_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('module strategies match current Tatuzin architecture', () {
    expect(strategyForModule(AppModule.pdv), DataSourceStrategy.localFirst);
    expect(strategyForModule(AppModule.erp), DataSourceStrategy.serverFirst);
    expect(strategyForModule(AppModule.crm), DataSourceStrategy.serverFirst);
  });

  test('remote ready mode no longer keeps local as global source of truth', () {
    expect(AppDataMode.localOnly.keepsLocalAsSourceOfTruth, isTrue);
    expect(AppDataMode.futureRemoteReady.keepsLocalAsSourceOfTruth, isFalse);
    expect(AppDataMode.futureHybridReady.keepsLocalAsSourceOfTruth, isFalse);
  });
}
