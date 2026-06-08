import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tatuzin_admin_web/src/core/auth/admin_auth_storage.dart';
import 'package:tatuzin_admin_web/src/core/models/admin_tenant_deletion_models.dart';
import 'package:tatuzin_admin_web/src/core/network/admin_api_client.dart';
import 'package:tatuzin_admin_web/src/core/network/admin_api_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('AdminApiService lista, registra e gera dry-run sem payload inseguro', () async {
    final requests = <http.Request>[];
    final storage = AdminAuthStorage();
    await storage.saveTokens(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
    );
    final service = AdminApiService(
      apiClient: AdminApiClient(
        baseUrl: 'https://api.test/api',
        authStorage: storage,
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.method == 'GET') {
            return http.Response(jsonEncode(_requestsPayload()), 200);
          }
          if (request.url.path.endsWith('/requests')) {
            return http.Response(jsonEncode(_createPayload()), 200);
          }
          return http.Response(jsonEncode(_dryRunPayload()), 200);
        }),
      ),
      authStorage: storage,
    );

    final snapshot = await service.fetchTenantDeletionRequests(
      query: const AdminTenantDeletionQuery(
        companyId: 'company-1',
        status: 'REQUESTED',
      ),
    );
    final created = await service.createTenantDeletionRequest(
      companyId: 'company-1',
      reason: 'Solicitacao recebida pelo formulario publico',
      requesterEmail: 'titular@example.com',
      requesterChannel: 'web',
    );
    final dryRun = await service.dryRunTenantDeletion(
      companyId: 'company-1',
      requestId: 'tdr_1',
      reason: 'Inventario solicitado para triagem segura',
    );

    expect(snapshot.items.single.requestId, 'tdr_1');
    expect(created.request?.status, 'REQUESTED');
    expect(dryRun.dryRun.persistenceMode, 'admin_audit_log_foundation');
    expect(requests.map((request) => request.method), ['GET', 'POST', 'POST']);
    expect(requests.map((request) => request.url.path), [
      '/api/admin/tenant-deletion/requests',
      '/api/admin/tenant-deletion/requests',
      '/api/admin/tenant-deletion/companies/company-1/dry-run',
    ]);
    expect(requests.first.url.queryParameters, <String, String>{
      'companyId': 'company-1',
      'status': 'REQUESTED',
    });

    final createBody =
        jsonDecode(requests[1].body) as Map<String, dynamic>;
    expect(createBody['companyId'], 'company-1');
    expect(createBody['reason'], 'Solicitacao recebida pelo formulario publico');
    expect(createBody['requesterEmail'], 'titular@example.com');
    expect(createBody.containsKey('actorAdminId'), isFalse);
    expect(createBody.containsKey('permissionKeys'), isFalse);

    final dryRunBody =
        jsonDecode(requests[2].body) as Map<String, dynamic>;
    expect(dryRunBody, <String, dynamic>{
      'reason': 'Inventario solicitado para triagem segura',
      'requestId': 'tdr_1',
    });
    expect(dryRunBody.containsKey('actorAdminId'), isFalse);
    expect(dryRunBody.containsKey('permissionKeys'), isFalse);
  });

  test('dry-run exige motivo minimo antes da chamada HTTP', () async {
    final requests = <http.Request>[];
    final storage = AdminAuthStorage();
    await storage.saveTokens(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
    );
    final service = AdminApiService(
      apiClient: AdminApiClient(
        baseUrl: 'https://api.test/api',
        authStorage: storage,
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response('{}', 200);
        }),
      ),
      authStorage: storage,
    );

    await expectLater(
      service.dryRunTenantDeletion(companyId: 'company-1', reason: 'curto'),
      throwsA(isA<AdminApiException>()),
    );
    expect(requests, isEmpty);
  });
}

Map<String, dynamic> _requestsPayload() {
  return <String, dynamic>{
    'ok': true,
    'code': 'TENANT_DELETION_REQUEST_LISTED',
    'message': 'Solicitacoes listadas.',
    'auditEventId': null,
    'requests': <Map<String, dynamic>>[_requestPayload()],
  };
}

Map<String, dynamic> _createPayload() {
  return <String, dynamic>{
    'ok': true,
    'code': 'TENANT_DELETION_REQUEST_RECORDED',
    'message': 'Solicitacao registrada.',
    'auditEventId': 'audit-1',
    'request': _requestPayload(),
  };
}

Map<String, dynamic> _requestPayload() {
  return <String, dynamic>{
    'requestId': 'tdr_1',
    'company': _companyPayload(),
    'status': 'REQUESTED',
    'createdAt': '2026-06-07T12:00:00.000Z',
    'updatedAt': '2026-06-07T12:00:00.000Z',
    'latestAuditEventId': 'audit-1',
    'latestAction': 'tenant.deletion.requested',
    'reason': 'Solicitacao recebida pelo formulario publico',
    'requester': <String, dynamic>{
      'name': null,
      'email': 'titular@example.com',
      'channel': 'web',
    },
    'dryRunSummary': null,
  };
}

Map<String, dynamic> _dryRunPayload() {
  return <String, dynamic>{
    'ok': true,
    'code': 'TENANT_DELETION_DRY_RUN_READY',
    'message': 'Dry-run gerado.',
    'auditEventId': 'audit-dry-run',
    'dryRun': <String, dynamic>{
      'company': _companyPayload(),
      'generatedAt': '2026-06-07T12:00:00.000Z',
      'dryRun': true,
      'persistenceMode': 'admin_audit_log_foundation',
      'categories': <Map<String, dynamic>>[
        <String, dynamic>{
          'key': 'billing',
          'label': 'Billing',
          'count': 2,
          'recommendedHandling': 'retain_justified',
          'retentionReason': 'retencao legal',
        },
      ],
      'blockers': <Map<String, dynamic>>[
        <String, dynamic>{
          'key': 'company_physical_delete_forbidden',
          'severity': 'blocking',
          'message': 'Company nao deve ser excluida fisicamente.',
        },
      ],
      'notes': <String>['Nenhuma exclusao real foi executada.'],
    },
  };
}

Map<String, dynamic> _companyPayload() {
  return <String, dynamic>{
    'id': 'company-1',
    'name': 'Tatuzin Loja',
    'legalName': 'Tatuzin Loja LTDA',
    'slug': 'tatuzin-loja',
    'documentNumber': null,
    'isActive': true,
    'license': <String, dynamic>{
      'status': 'active',
      'plan': 'PRO',
      'syncEnabled': true,
      'billingProvider': 'mercado_pago',
      'hasProviderSubscription': true,
      'cancelAtPeriodEnd': false,
      'billingSubscriptionStatus': 'active',
    },
  };
}
