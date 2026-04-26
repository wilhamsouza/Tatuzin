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

    test(
      'ignora override legado salvo quando o build trava o endpoint',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'app.environment.data_mode': AppDataMode.futureRemoteReady.name,
          'app.environment.endpoint_base_url': 'http://192.168.0.15:4000/api',
          'app.environment.endpoint_api_version': 'v9',
        });

        final productionEnvironment = await AppEnvironmentStorage.load(
          allowTechnicalEndpointOverride: false,
          remoteDefaultEndpoint: EndpointConfig(
            baseUrl: EndpointConfig.resolveBuildBaseUrl(isReleaseBuild: true),
            apiVersion: EndpointConfig.defaultApiVersion,
          ),
        );
        final preferences = await SharedPreferences.getInstance();

        expect(
          productionEnvironment.endpointConfig.uriFor('/health')?.toString(),
          'https://api.tatuzin.com.br/api/health',
        );
        expect(
          productionEnvironment.endpointConfig.isOfficialProductionEndpoint,
          isTrue,
        );
        expect(
          preferences.containsKey('app.environment.endpoint_base_url'),
          isFalse,
        );
        expect(
          preferences.containsKey('app.environment.endpoint_api_version'),
          isFalse,
        );
      },
    );

    test(
      'nao persiste override tecnico quando o build nao permite editar endpoint',
      () async {
        final environment = AppEnvironment.remoteDefault().copyWith(
          endpointConfig: EndpointConfig.remoteDefault().copyWith(
            baseUrl: 'http://10.0.2.2:4000',
          ),
        );

        await AppEnvironmentStorage.save(
          environment,
          allowTechnicalEndpointOverride: false,
        );

        final preferences = await SharedPreferences.getInstance();
        expect(
          preferences.getString('app.environment.data_mode'),
          AppDataMode.futureRemoteReady.name,
        );
        expect(
          preferences.containsKey('app.environment.endpoint_base_url'),
          isFalse,
        );
        expect(
          preferences.containsKey('app.environment.endpoint_api_version'),
          isFalse,
        );
      },
    );
  });
}
