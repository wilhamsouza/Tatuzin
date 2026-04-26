import 'package:erp_pdv_app/app/core/network/endpoint_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EndpointConfig', () {
    test('fixa a API oficial em release e ignora override de build', () {
      final baseUrl = EndpointConfig.resolveBuildBaseUrl(
        isReleaseBuild: true,
        configuredBaseUrl: 'http://localhost:4000',
      );

      expect(baseUrl, EndpointConfig.productionResolvedBaseUrl);
      expect(EndpointConfig.productionApiUrl, 'https://api.tatuzin.com.br/api');
      expect(
        EndpointConfig(
          baseUrl: baseUrl,
          apiVersion: EndpointConfig.defaultApiVersion,
        ).uriFor('/health')?.toString(),
        'https://api.tatuzin.com.br/api/health',
      );
    });

    test('mantem o endpoint local no fallback de debug', () {
      final baseUrl = EndpointConfig.resolveBuildBaseUrl(isReleaseBuild: false);

      expect(baseUrl, EndpointConfig.localDevelopmentBaseUrl);
    });

    test('remove o prefixo /api de uma base ja configurada', () {
      final normalized = EndpointConfig.normalizeBaseUrl(
        'https://api.tatuzin.com.br/api/',
        apiVersion: EndpointConfig.defaultApiVersion,
      );

      expect(normalized, 'https://api.tatuzin.com.br');
    });

    test('monta a URL final com /api apenas uma vez', () {
      const config = EndpointConfig(
        baseUrl: 'https://api.tatuzin.com.br',
        apiVersion: EndpointConfig.defaultApiVersion,
      );

      expect(
        config.uriFor('/categories')?.toString(),
        'https://api.tatuzin.com.br/api/categories',
      );
    });

    test('detecta endpoints locais e de rede privada', () {
      expect(
        EndpointConfig.isLocalNetworkBaseUrl('http://localhost:4000'),
        isTrue,
      );
      expect(
        EndpointConfig.isLocalNetworkBaseUrl('http://10.0.2.2:4000'),
        isTrue,
      );
      expect(
        EndpointConfig.isLocalNetworkBaseUrl('http://192.168.0.15:4000'),
        isTrue,
      );
      expect(
        EndpointConfig.isLocalNetworkBaseUrl('https://api.tatuzin.com.br'),
        isFalse,
      );
    });
  });
}
