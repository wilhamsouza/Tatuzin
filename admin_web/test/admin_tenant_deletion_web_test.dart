import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tatuzin_admin_web/src/core/auth/admin_auth_storage.dart';
import 'package:tatuzin_admin_web/src/core/auth/admin_providers.dart';
import 'package:tatuzin_admin_web/src/core/models/admin_permissions_models.dart';
import 'package:tatuzin_admin_web/src/core/models/admin_tenant_deletion_models.dart';
import 'package:tatuzin_admin_web/src/core/network/admin_api_client.dart';
import 'package:tatuzin_admin_web/src/core/network/admin_api_service.dart';
import 'package:tatuzin_admin_web/src/features/tenant_deletion/presentation/tenant_deletion_page.dart';

const _requestId = '11111111-1111-4111-8111-111111111111';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'AdminApiService lista, registra e gera dry-run sem payload inseguro',
    () async {
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
        requestId: _requestId,
        reason: 'Inventario solicitado para triagem segura',
      );

      expect(snapshot.items.single.requestId, _requestId);
      expect(snapshot.items.single.identityStatus, 'NOT_STARTED');
      expect(snapshot.items.single.source, 'web');
      expect(created.request?.status, 'REQUESTED');
      expect(dryRun.dryRun.persistenceMode, 'tenant_deletion_request');
      expect(requests.map((request) => request.method), [
        'GET',
        'POST',
        'POST',
      ]);
      expect(requests.map((request) => request.url.path), [
        '/api/admin/tenant-deletion/requests',
        '/api/admin/tenant-deletion/requests',
        '/api/admin/tenant-deletion/companies/company-1/dry-run',
      ]);
      expect(requests.first.url.queryParameters, <String, String>{
        'companyId': 'company-1',
        'status': 'REQUESTED',
      });

      final createBody = jsonDecode(requests[1].body) as Map<String, dynamic>;
      expect(createBody['companyId'], 'company-1');
      expect(
        createBody['reason'],
        'Solicitacao recebida pelo formulario publico',
      );
      expect(createBody['requesterEmail'], 'titular@example.com');
      expect(createBody.containsKey('actorAdminId'), isFalse);
      expect(createBody.containsKey('permissionKeys'), isFalse);

      final dryRunBody = jsonDecode(requests[2].body) as Map<String, dynamic>;
      expect(dryRunBody, <String, dynamic>{
        'reason': 'Inventario solicitado para triagem segura',
        'requestId': _requestId,
      });
      expect(dryRunBody.containsKey('actorAdminId'), isFalse);
      expect(dryRunBody.containsKey('permissionKeys'), isFalse);
    },
  );

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
      service.dryRunTenantDeletion(
        companyId: 'company-1',
        requestId: _requestId,
        reason: 'curto',
      ),
      throwsA(isA<AdminApiException>()),
    );
    expect(requests, isEmpty);
  });

  test(
    'API envia quarentena e cancelamento sem campos administrativos',
    () async {
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
            return http.Response(jsonEncode(_createPayload()), 200);
          }),
        ),
        authStorage: storage,
      );

      await service.quarantineTenantDeletion(
        companyId: 'company-1',
        requestId: _requestId,
        reason: 'Quarentena aprovada apos analise operacional',
        confirmation: 'QUARENTENA',
      );
      await service.cancelTenantDeletion(
        companyId: 'company-1',
        requestId: _requestId,
        reason: 'Solicitacao retirada pelo titular validado',
      );

      expect(requests.map((request) => request.url.path), [
        '/api/admin/tenant-deletion/requests/$_requestId/quarantine',
        '/api/admin/tenant-deletion/requests/$_requestId/cancel',
      ]);
      final quarantineBody =
          jsonDecode(requests.first.body) as Map<String, dynamic>;
      expect(quarantineBody['confirmation'], 'QUARENTENA');
      expect(quarantineBody.containsKey('actorAdminId'), isFalse);
      expect(quarantineBody.containsKey('permissionKeys'), isFalse);
      final cancelBody = jsonDecode(requests.last.body) as Map<String, dynamic>;
      expect(cancelBody.containsKey('confirmation'), isFalse);
    },
  );

  testWidgets('tela deixa claro que o workflow e dedicado e nao destrutivo', (
    tester,
  ) async {
    final service = _FakeTenantDeletionApiService();

    await tester.pumpWidget(_testApp(service));
    await tester.pumpAndSettle();

    expect(find.text('Registrar solicitacao'), findsNWidgets(2));
    expect(find.text('Inventario dry-run'), findsOneWidget);
    expect(find.textContaining('Workflow seguro'), findsOneWidget);
    expect(
      find.textContaining('execucao final continuam indisponiveis'),
      findsOneWidget,
    );
    expect(find.text('Excluir empresa'), findsNothing);
    expect(find.text('Executar exclusao'), findsNothing);
  });

  testWidgets('quarentena exige permissao, motivo e confirmacao explicita', (
    tester,
  ) async {
    final service = _FakeTenantDeletionApiService(
      requestStatus: 'DRY_RUN_READY',
    );

    await tester.pumpWidget(
      _testApp(
        service,
        permissions: _permissions('tenant.deletion.quarantine'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Colocar em quarentena'), findsOneWidget);
    await tester.ensureVisible(find.text('Colocar em quarentena'));
    await tester.tap(find.text('Colocar em quarentena'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Os dados permanecem preservados'),
      findsOneWidget,
    );
    await tester.enterText(
      _textFieldWithLabel('Motivo obrigatorio'),
      'Quarentena aprovada apos analise operacional',
    );
    await tester.enterText(
      _textFieldWithLabel('Confirmacao explicita'),
      'QUARENTENA',
    );
    final confirmButton = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'Colocar em quarentena'),
    );
    await tester.tap(confirmButton);
    await tester.pumpAndSettle();

    expect(service.quarantineCalls, 1);
    expect(service.lastConfirmation, 'QUARENTENA');
    expect(
      find.textContaining('Quarentena operacional registrada'),
      findsOneWidget,
    );
  });

  testWidgets('cancelamento de quarentena preserva aviso de novo login', (
    tester,
  ) async {
    final service = _FakeTenantDeletionApiService(
      requestStatus: 'FUTURE_PENDING_DELETION',
    );

    await tester.pumpWidget(
      _testApp(service, permissions: _permissions('tenant.deletion.cancel')),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Cancelar quarentena'));
    await tester.tap(find.text('Cancelar quarentena'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('sessoes revogadas nao serao reativadas'),
      findsOneWidget,
    );
    await tester.enterText(
      _textFieldWithLabel('Motivo obrigatorio'),
      'Solicitacao retirada pelo titular validado',
    );
    await tester.enterText(
      _textFieldWithLabel('Confirmacao explicita'),
      'CANCELAR QUARENTENA',
    );
    final confirmButton = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'Cancelar quarentena'),
    );
    await tester.tap(confirmButton);
    await tester.pumpAndSettle();

    expect(service.cancelCalls, 1);
  });

  testWidgets('tela registra solicitacao e persiste snapshot dry-run', (
    tester,
  ) async {
    final service = _FakeTenantDeletionApiService();

    await tester.pumpWidget(_testApp(service));
    await tester.pumpAndSettle();

    await tester.enterText(_textFieldWithLabel('companyId').first, 'company-1');
    await tester.enterText(
      _textFieldWithLabel('Motivo do registro'),
      'Solicitacao validada pelo atendimento',
    );
    final createButton = find.byIcon(Icons.playlist_add_check_rounded);
    await tester.ensureVisible(createButton);
    await tester.tap(createButton);
    await tester.pumpAndSettle();

    expect(service.createCalls, 1);
    expect(service.lastCreatedCompanyId, 'company-1');
    expect(find.textContaining('Solicitacao registrada:'), findsOneWidget);

    await tester.enterText(_textFieldWithLabel('companyId').last, 'company-1');
    await tester.enterText(_textFieldWithLabel('requestId'), _requestId);
    await tester.enterText(
      _textFieldWithLabel('Motivo do dry-run'),
      'Inventario solicitado para triagem segura',
    );
    await tester.ensureVisible(find.text('Gerar dry-run'));
    await tester.tap(find.text('Gerar dry-run'));
    await tester.pumpAndSettle();

    expect(service.dryRunCalls, 1);
    expect(service.lastDryRunRequestId, _requestId);
    expect(find.text('Resultado do dry-run'), findsOneWidget);
    expect(find.text('Modo: tenant_deletion_request'), findsOneWidget);
    expect(find.text('Bloqueadores: 1'), findsOneWidget);
  });
}

Widget _testApp(
  AdminApiService service, {
  AdminUserPermissionsSnapshot? permissions,
}) {
  return ProviderScope(
    overrides: [
      adminApiServiceProvider.overrideWithValue(service),
      if (permissions != null)
        adminCurrentUserPermissionsProvider.overrideWith(
          (ref) async => permissions,
        ),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: Padding(padding: EdgeInsets.all(16), child: TenantDeletionPage()),
      ),
    ),
  );
}

Finder _textFieldWithLabel(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );
}

class _FakeTenantDeletionApiService extends AdminApiService {
  _FakeTenantDeletionApiService({this.requestStatus = 'REQUESTED'})
    : super(
        apiClient: AdminApiClient(
          baseUrl: 'https://api.test/api',
          authStorage: AdminAuthStorage(),
          httpClient: MockClient((_) async => http.Response('{}', 200)),
        ),
        authStorage: AdminAuthStorage(),
      );

  final String requestStatus;
  int createCalls = 0;
  int dryRunCalls = 0;
  int quarantineCalls = 0;
  int cancelCalls = 0;
  String? lastCreatedCompanyId;
  String? lastDryRunRequestId;
  String? lastConfirmation;

  @override
  Future<AdminTenantDeletionRequestsSnapshot> fetchTenantDeletionRequests({
    AdminTenantDeletionQuery query = const AdminTenantDeletionQuery(),
  }) async {
    return AdminTenantDeletionRequestsSnapshot.fromMap(
      _requestsPayload(status: requestStatus),
    );
  }

  @override
  Future<AdminTenantDeletionMutationResult> createTenantDeletionRequest({
    required String companyId,
    required String reason,
    String? requesterName,
    String? requesterEmail,
    String? requesterChannel,
  }) async {
    createCalls++;
    lastCreatedCompanyId = companyId;
    return AdminTenantDeletionMutationResult.fromMap(_createPayload());
  }

  @override
  Future<AdminTenantDeletionDryRunResponse> dryRunTenantDeletion({
    required String companyId,
    required String requestId,
    required String reason,
  }) async {
    dryRunCalls++;
    lastDryRunRequestId = requestId;
    return AdminTenantDeletionDryRunResponse.fromMap(_dryRunPayload());
  }

  @override
  Future<AdminTenantDeletionMutationResult> quarantineTenantDeletion({
    required String companyId,
    required String requestId,
    required String reason,
    required String confirmation,
  }) async {
    quarantineCalls++;
    lastConfirmation = confirmation;
    return AdminTenantDeletionMutationResult.fromMap(
      _createPayload(status: 'FUTURE_PENDING_DELETION'),
    );
  }

  @override
  Future<AdminTenantDeletionMutationResult> cancelTenantDeletion({
    required String companyId,
    required String requestId,
    required String reason,
  }) async {
    cancelCalls++;
    return AdminTenantDeletionMutationResult.fromMap(
      _createPayload(status: 'CANCELLED'),
    );
  }
}

Map<String, dynamic> _requestsPayload({String status = 'REQUESTED'}) {
  return <String, dynamic>{
    'ok': true,
    'code': 'TENANT_DELETION_REQUEST_LISTED',
    'message': 'Solicitacoes listadas.',
    'auditEventId': null,
    'requests': <Map<String, dynamic>>[_requestPayload(status: status)],
  };
}

Map<String, dynamic> _createPayload({String status = 'REQUESTED'}) {
  return <String, dynamic>{
    'ok': true,
    'code': 'TENANT_DELETION_REQUEST_RECORDED',
    'message': 'Solicitacao registrada.',
    'auditEventId': 'audit-1',
    'request': _requestPayload(status: status),
  };
}

Map<String, dynamic> _requestPayload({String status = 'REQUESTED'}) {
  return <String, dynamic>{
    'requestId': _requestId,
    'company': _companyPayload(),
    'status': status,
    'identityStatus': status == 'REQUESTED' ? 'NOT_STARTED' : 'VERIFIED',
    'source': 'web',
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
    'dryRunSummary': status == 'REQUESTED'
        ? null
        : <String, dynamic>{'categories': 10, 'blockers': 2},
  };
}

AdminUserPermissionsSnapshot _permissions(String permissionKey) {
  return AdminUserPermissionsSnapshot(
    adminUserId: 'admin-1',
    activePermissions: <AdminUserPermission>[
      AdminUserPermission(
        id: 'permission-1',
        actorUserId: 'admin-1',
        permissionKey: permissionKey,
        scope: 'platform',
        scopeId: '*',
        isActive: true,
        createdAt: DateTime.utc(2026, 6, 10),
        updatedAt: DateTime.utc(2026, 6, 10),
        revokedAt: null,
      ),
    ],
    inactivePermissions: const <AdminUserPermission>[],
    auditEventId: 'permission-audit',
  );
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
      'persistenceMode': 'tenant_deletion_request',
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
