import 'package:erp_pdv_app/app/core/app_context/app_operational_context.dart';
import 'package:erp_pdv_app/app/core/config/app_environment.dart';
import 'package:erp_pdv_app/app/core/errors/app_exceptions.dart';
import 'package:erp_pdv_app/app/core/network/contracts/api_client_contract.dart';
import 'package:erp_pdv_app/app/core/session/app_session.dart';
import 'package:erp_pdv_app/app/core/session/app_user.dart';
import 'package:erp_pdv_app/app/core/session/auth_token_storage.dart';
import 'package:erp_pdv_app/app/core/session/company_context.dart';
import 'package:erp_pdv_app/modules/relatorios/data/analytics_report_repository.dart';
import 'package:erp_pdv_app/modules/relatorios/data/real/real_analytics_reports_remote_datasource.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_data_origin_notice.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_filter.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_period.dart';
import 'package:flutter_test/flutter_test.dart';

import 'management_reports_server_first_test.dart' as reports_fakes;

void main() {
  test('datasource usa endpoint tenant de analytics sem companyId', () async {
    final apiClient = _RecordingApiClient();
    final datasource = RealAnalyticsReportsRemoteDatasource(
      apiClient: apiClient,
      tokenStorage: const _MemoryTokenStorage('access-token'),
      operationalContext: _remoteContext(),
    );

    await datasource.fetchSalesByDay(filter: _filter());
    await datasource.fetchSalesByProduct(filter: _filter(), limit: 5);
    await datasource.fetchSalesByCustomer(filter: _filter(), limit: 5);
    await datasource.fetchFinancialSummary(filter: _filter());

    expect(
      apiClient.paths,
      containsAll(<String>[
        '/analytics/reports/sales-by-day',
        '/analytics/reports/sales-by-product',
        '/analytics/reports/sales-by-customer',
        '/analytics/reports/financial-summary',
      ]),
    );
    expect(apiClient.paths.any((path) => path.contains('/admin/')), isFalse);
    expect(
      apiClient.queryParameters.any((query) => query.containsKey('companyId')),
      isFalse,
    );
  });

  test('resultado remoto recebe notice de dados atualizados', () async {
    final repository = AnalyticsReportRepository(
      remoteDatasource: reports_fakes.FakeAnalyticsRemoteDatasource(),
      localFallbackRepository: reports_fakes.FakeReportRepository(),
    );

    final result = await repository.fetchTopProductsResult(filter: _filter());

    expect(result.notice, isNotNull);
    expect(result.notice!.scope, ReportDataOriginScope.sales);
    expect(result.notice!.message, contains('nuvem'));
  });

  test('403, 404 e 501 caem para fallback local com notice', () async {
    for (final statusCode in <int>[403, 404, 501]) {
      final repository = AnalyticsReportRepository(
        remoteDatasource: reports_fakes.FakeAnalyticsRemoteDatasource(
          shouldFail: true,
          error: NetworkRequestException(
            'remote unavailable',
            cause: statusCode,
          ),
        ),
        localFallbackRepository: reports_fakes.FakeReportRepository(),
      );

      final result = await repository.fetchTopProductsResult(filter: _filter());

      expect(result.data.single.productName, 'Produto local');
      expect(result.notice, isNotNull);
      expect(
        result.notice!.message,
        anyOf(contains('cache'), contains('Endpoint')),
      );
    }
  });
}

ReportFilter _filter() {
  return ReportFilter.fromPeriod(
    ReportPeriod.monthly,
    reference: DateTime(2026, 4, 28),
  );
}

AppOperationalContext _remoteContext() {
  return AppOperationalContext(
    environment: AppEnvironment.remoteDefault(),
    session: AppSession(
      scope: SessionScope.authenticatedRemote,
      user: const AppUser(
        localId: 1,
        remoteId: 'user-1',
        displayName: 'Operador',
        email: 'operador@tatuzin.test',
        roleLabel: 'Operador',
        kind: AppUserKind.remoteAuthenticated,
      ),
      company: const CompanyContext(
        localId: 1,
        remoteId: '11111111-1111-4111-8111-111111111111',
        displayName: 'Tatuzin',
        legalName: 'Tatuzin',
        documentNumber: null,
        licensePlan: 'pro',
        licenseStatus: 'ACTIVE',
        syncEnabled: true,
      ),
      startedAt: DateTime(2026, 4, 28),
      isOfflineFallback: false,
    ),
  );
}

class _RecordingApiClient implements ApiClientContract {
  final paths = <String>[];
  final queryParameters = <Map<String, Object?>>[];

  @override
  Future<ApiResponse<Map<String, dynamic>>> getJson(
    String path, {
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async {
    paths.add(path);
    queryParameters.add(options.queryParameters);
    return ApiResponse<Map<String, dynamic>>(
      statusCode: 200,
      headers: const <String, String>{},
      data: _responseFor(path),
    );
  }

  Map<String, dynamic> _responseFor(String path) {
    if (path.endsWith('/sales-by-day')) {
      return {
        'series': [
          {
            'date': '2026-04-01',
            'salesCount': 1,
            'salesAmountCents': 1000,
            'salesCostCents': 400,
            'salesProfitCents': 600,
          },
        ],
      };
    }
    if (path.endsWith('/sales-by-product')) {
      return {
        'items': [
          {
            'productKey': 'product-1',
            'productId': 'product-1',
            'productName': 'Produto',
            'quantityMil': 1000,
            'salesCount': 1,
            'revenueCents': 1000,
            'costCents': 400,
            'profitCents': 600,
          },
        ],
      };
    }
    if (path.endsWith('/sales-by-customer')) {
      return {
        'items': [
          {
            'customerKey': 'customer-1',
            'customerId': 'customer-1',
            'customerName': 'Cliente',
            'salesCount': 1,
            'revenueCents': 1000,
            'costCents': 400,
            'profitCents': 600,
            'fiadoPaymentsCents': 0,
          },
        ],
      };
    }
    return {
      'summary': {
        'salesAmountCents': 1000,
        'salesCostCents': 400,
        'salesProfitCents': 600,
        'purchasesAmountCents': 0,
        'fiadoPaymentsAmountCents': 0,
        'cashNetCents': 1000,
        'financialAdjustmentsCents': 0,
        'operatingMarginBasisPoints': 6000,
      },
    };
  }

  @override
  Future<ApiResponse<void>> delete(
    String path, {
    ApiRequestOptions options = const ApiRequestOptions(),
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ApiResponse<Map<String, dynamic>>> patchJson(
    String path, {
    Map<String, dynamic>? body,
    ApiRequestOptions options = const ApiRequestOptions(),
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ApiResponse<Map<String, dynamic>>> postJson(
    String path, {
    Map<String, dynamic>? body,
    ApiRequestOptions options = const ApiRequestOptions(),
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ApiResponse<Map<String, dynamic>>> putJson(
    String path, {
    Map<String, dynamic>? body,
    ApiRequestOptions options = const ApiRequestOptions(),
  }) {
    throw UnimplementedError();
  }
}

class _MemoryTokenStorage implements AuthTokenStorage {
  const _MemoryTokenStorage(this.accessToken);

  final String accessToken;

  @override
  Future<void> clear() async {}

  @override
  Future<AuthClientContext> ensureClientContext({
    required String clientType,
    String? deviceLabel,
    String? platform,
    String? appVersion,
  }) async {
    return AuthClientContext(
      clientType: clientType,
      clientInstanceId: 'test-device',
      deviceLabel: deviceLabel,
      platform: platform,
      appVersion: appVersion,
    );
  }

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<AuthClientContext?> readClientContext() async => null;

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {}
}
