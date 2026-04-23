import 'package:erp_pdv_app/app/core/config/app_data_mode.dart';
import 'package:erp_pdv_app/app/core/config/app_environment.dart';
import 'package:erp_pdv_app/app/core/network/endpoint_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('AppEnvironmentStorage', () {
    test(
      'mantem o endpoint remoto default quando nao existe override salvo',
      () async {
        final environment = await AppEnvironmentStorage.load();

        expect(environment.dataMode, AppDataMode.futureRemoteReady);
        expect(
          environment.endpointConfig.baseUrl,
          EndpointConfig.remoteDefault().baseUrl,
        );
        expect(
          environment.endpointConfig.apiVersion,
          EndpointConfig.defaultApiVersion,
        );
      },
    );

    test('normaliza override salvo sem duplicar /api', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'app.environment.data_mode': AppDataMode.futureRemoteReady.name,
        'app.environment.endpoint_base_url': 'https://api.tatuzin.com.br/api/',
      });

      final environment = await AppEnvironmentStorage.load();

      expect(environment.endpointConfig.baseUrl, 'https://api.tatuzin.com.br');
      expect(
        environment.endpointConfig.uriFor('/health')?.toString(),
        'https://api.tatuzin.com.br/api/health',
      );
    });
  });
}
