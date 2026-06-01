import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tatuzin_admin_web/src/core/auth/admin_auth_storage.dart';
import 'package:tatuzin_admin_web/src/core/auth/admin_providers.dart';
import 'package:tatuzin_admin_web/src/core/models/admin_permissions_models.dart';
import 'package:tatuzin_admin_web/src/core/network/admin_api_client.dart';
import 'package:tatuzin_admin_web/src/core/network/admin_api_service.dart';
import 'package:tatuzin_admin_web/src/features/permissions/presentation/admin_permissions_page.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('/permissions renderiza catalogo e permissoes por admin', (
    tester,
  ) async {
    final service = _FakePermissionsApiService();

    await tester.pumpWidget(
      _testApp(
        service: service,
        initialLocation: '/permissions?adminUserId=admin-1',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Permissoes administrativas'), findsWidgets);
    expect(find.text('Catalogo de permissionKeys'), findsOneWidget);
    expect(find.text('support.session.revoke'), findsWidgets);
    expect(find.text('support-action'), findsNothing);
    expect(find.text('Support action'), findsOneWidget);
    expect(find.text('Alto'), findsOneWidget);
    expect(find.text('revoke_session'), findsOneWidget);
    expect(find.text('Dry-run'), findsOneWidget);
    expect(find.text('Motivo'), findsOneWidget);
    expect(find.text('Confirmacao'), findsOneWidget);
    expect(find.text('Auditoria'), findsOneWidget);
    expect(find.text('Permissoes ativas'), findsOneWidget);
    expect(find.text('admin-permissions.manage'), findsWidgets);
    expect(find.text('Ativa'), findsOneWidget);
    expect(
      find.text(
        'Bootstrap inicial permanece restrito ao backend/CLI controlado.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Use este painel apenas para permissoes administrativas. Acoes operacionais continuam bloqueadas nesta fase.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('permissionKeys do cliente nao concedem acesso'),
      findsOneWidget,
    );
    expect(
      find.text('isPlatformAdmin sozinho nao libera acoes sensiveis'),
      findsOneWidget,
    );
    expect(
      find.text('Grant/revoke exigem motivo, confirmacao e auditoria'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, 'Conceder permissao'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, 'Revogar'), findsOneWidget);
    expect(find.text('Executar dry-run'), findsNothing);
    expect(find.text('Bootstrap'), findsNothing);
    expect(find.text('Bloquear usuario'), findsNothing);
    expect(find.text('Forcar sync'), findsNothing);
    expect(service.catalogCalls, 1);
    expect(service.userPermissionCalls, 1);
    expect(service.lastAdminUserId, 'admin-1');
  });

  testWidgets('consulta permissoes por adminUserId informado', (tester) async {
    final service = _FakePermissionsApiService();

    await tester.pumpWidget(_testApp(service: service));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'admin-2');
    await tester.ensureVisible(find.text('Consultar'));
    await tester.tap(find.text('Consultar'));
    await tester.pumpAndSettle();

    expect(find.text('admin-2'), findsWidgets);
    expect(find.text('support.session.revoke'), findsWidgets);
    expect(service.lastAdminUserId, 'admin-2');
  });

  testWidgets('mostra estados vazios sem grant/revoke funcional', (
    tester,
  ) async {
    final service = _FakePermissionsApiService(empty: true);

    await tester.pumpWidget(
      _testApp(
        service: service,
        initialLocation: '/permissions?adminUserId=admin-empty',
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Nenhum permissionKey encontrado no catalogo.'),
      findsOneWidget,
    );
    expect(find.text('Admin sem permissoes ativas.'), findsOneWidget);
    expect(
      find.text(
        'Nenhuma permissao inativa retornada pelo backend para este admin.',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Conceder'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Revogar'), findsNothing);
  });

  testWidgets('mostra erros de catalogo e autorizacao de admin', (
    tester,
  ) async {
    final service = _FakePermissionsApiService(
      catalogError: true,
      userPermissionsError: true,
    );

    await tester.pumpWidget(
      _testApp(
        service: service,
        initialLocation: '/permissions?adminUserId=admin-denied',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Catalogo indisponivel'), findsOneWidget);
    expect(
      find.text('Sem permissao para consultar este admin'),
      findsOneWidget,
    );
    expect(find.textContaining('Sem permissao para permissoes'), findsWidgets);
  });

  testWidgets('grant exige motivo e confirmacao antes da chamada auditada', (
    tester,
  ) async {
    final service = _FakePermissionsApiService();

    await tester.pumpWidget(
      _testApp(
        service: service,
        initialLocation: '/permissions?adminUserId=admin-1',
      ),
    );
    await tester.pumpAndSettle();

    await _selectGrantPermission(tester, 'support.session.revoke');
    await tester.ensureVisible(find.text('Conceder permissao'));
    await tester.tap(find.text('Conceder permissao'));
    await tester.pumpAndSettle();

    expect(
      find.text('Informe um motivo com pelo menos 12 caracteres.'),
      findsOneWidget,
    );
    expect(service.grantCalls, 0);

    await tester.enterText(
      _textFieldWithLabel('Motivo da concessao'),
      'Concessao aprovada no chamado 123',
    );
    await tester.tap(find.text('Conceder permissao'));
    await tester.pumpAndSettle();

    expect(find.text('Confirmar concessao'), findsWidgets);
    expect(
      find.text(
        'Voce esta concedendo uma permissao administrativa sensivel. Esta acao sera auditada.',
      ),
      findsOneWidget,
    );
    expect(service.grantCalls, 0);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirmar concessao'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(service.grantCalls, 1);
    expect(service.lastMutationPermissionKey, 'support.session.revoke');
    expect(service.lastMutationReason, 'Concessao aprovada no chamado 123');
    expect(service.userPermissionCalls, 2);
    expect(find.textContaining('Acao auditada: audit-grant'), findsOneWidget);
  });

  testWidgets('revoke exige motivo e aparece apenas para permissao ativa', (
    tester,
  ) async {
    final service = _FakePermissionsApiService();

    await tester.pumpWidget(
      _testApp(
        service: service,
        initialLocation: '/permissions?adminUserId=admin-1',
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Revogar'));
    expect(find.widgetWithText(TextButton, 'Revogar'), findsOneWidget);
    await tester.tap(find.text('Revogar'));
    await tester.pumpAndSettle();

    expect(find.text('Confirmar revogacao'), findsWidgets);
    final confirmButton = find.widgetWithText(
      FilledButton,
      'Confirmar revogacao',
    );
    expect(tester.widget<FilledButton>(confirmButton).onPressed, isNull);

    await tester.enterText(
      _textFieldWithLabel('Motivo da revogacao'),
      'Revogacao aprovada no chamado 456',
    );
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(tester.widget<FilledButton>(confirmButton).onPressed, isNotNull);
    await tester.tap(confirmButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(service.revokeCalls, 1);
    expect(service.lastMutationPermissionKey, 'admin-permissions.manage');
    expect(service.lastMutationReason, 'Revogacao aprovada no chamado 456');
    expect(service.userPermissionCalls, 2);
    expect(find.textContaining('Acao auditada: audit-revoke'), findsOneWidget);
  });

  testWidgets('grant mostra erro seguro para permissionKey desconhecida', (
    tester,
  ) async {
    final service = _FakePermissionsApiService(
      mutationErrorCode: 'ADMIN_PERMISSION_UNSUPPORTED',
    );

    await tester.pumpWidget(
      _testApp(
        service: service,
        initialLocation: '/permissions?adminUserId=admin-1',
      ),
    );
    await tester.pumpAndSettle();

    await _completeGrant(tester);

    expect(
      find.text('PermissionKey desconhecida ou nao suportada pelo backend.'),
      findsOneWidget,
    );
    expect(find.textContaining('stack'), findsNothing);
    expect(find.textContaining('token'), findsNothing);
  });

  testWidgets('grant mostra erro seguro de autorizacao', (tester) async {
    final service = _FakePermissionsApiService(
      mutationErrorCode: 'ADMIN_PERMISSION_MANAGE_REQUIRED',
    );

    await tester.pumpWidget(
      _testApp(
        service: service,
        initialLocation: '/permissions?adminUserId=admin-1',
      ),
    );
    await tester.pumpAndSettle();

    await _completeGrant(tester);

    expect(
      find.text('Sem autorizacao para alterar esta permissao administrativa.'),
      findsOneWidget,
    );
  });

  test('AdminApiService chama endpoints grant e revoke corretos', () async {
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
          return http.Response(
            jsonEncode(<String, dynamic>{
              'ok': true,
              'code': request.url.path.endsWith('/grant')
                  ? 'ADMIN_PERMISSION_GRANTED'
                  : 'ADMIN_PERMISSION_REVOKED',
              'message': 'Operacao auditada.',
              'auditEventId': 'audit-http',
              'permission': null,
              'details': <String, dynamic>{'revokedCount': 1},
            }),
            200,
          );
        }),
      ),
      authStorage: storage,
    );

    await service.grantAdminPermission(
      adminUserId: 'admin-1',
      permissionKey: 'support.session.revoke',
      reason: 'Concessao aprovada no chamado',
    );
    await service.revokeAdminPermission(
      adminUserId: 'admin-1',
      permissionKey: 'support.session.revoke',
      reason: 'Revogacao aprovada no chamado',
    );

    expect(requests.map((request) => request.method), ['POST', 'POST']);
    expect(requests.map((request) => request.url.path), [
      '/api/admin/permissions/users/admin-1/grant',
      '/api/admin/permissions/users/admin-1/revoke',
    ]);
    expect(
      requests.map((request) => request.url.path.contains('support-actions')),
      [false, false],
    );
    expect(jsonDecode(requests.first.body), <String, dynamic>{
      'permissionKey': 'support.session.revoke',
      'reason': 'Concessao aprovada no chamado',
      'scope': 'platform',
      'scopeId': '*',
    });
  });
}

Finder _textFieldWithLabel(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );
}

Future<void> _selectGrantPermission(
  WidgetTester tester,
  String permissionKey,
) async {
  final dropdown = find.byType(DropdownButtonFormField<String>);
  await tester.ensureVisible(dropdown);
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(permissionKey).last);
  await tester.pumpAndSettle();
}

Future<void> _completeGrant(WidgetTester tester) async {
  await _selectGrantPermission(tester, 'support.session.revoke');
  await tester.enterText(
    _textFieldWithLabel('Motivo da concessao'),
    'Concessao aprovada no chamado 123',
  );
  await tester.ensureVisible(find.text('Conceder permissao'));
  await tester.tap(find.text('Conceder permissao'));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(Checkbox));
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, 'Confirmar concessao'));
  await tester.pumpAndSettle();
}

Widget _testApp({
  required AdminApiService service,
  String initialLocation = '/permissions',
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/permissions',
        builder: (context, state) => Scaffold(
          body: AdminPermissionsPage(
            initialAdminUserId: state.uri.queryParameters['adminUserId'],
          ),
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [adminApiServiceProvider.overrideWithValue(service)],
    child: MaterialApp.router(routerConfig: router),
  );
}

class _FakePermissionsApiService extends AdminApiService {
  _FakePermissionsApiService({
    this.empty = false,
    this.catalogError = false,
    this.userPermissionsError = false,
    this.mutationErrorCode,
  }) : super(
         apiClient: AdminApiClient(
           baseUrl: 'https://api.test/api',
           authStorage: AdminAuthStorage(),
           httpClient: MockClient((_) async => http.Response('{}', 200)),
         ),
         authStorage: AdminAuthStorage(),
       );

  final bool empty;
  final bool catalogError;
  final bool userPermissionsError;
  final String? mutationErrorCode;
  int catalogCalls = 0;
  int userPermissionCalls = 0;
  int grantCalls = 0;
  int revokeCalls = 0;
  String? lastAdminUserId;
  String? lastMutationPermissionKey;
  String? lastMutationReason;

  @override
  Future<AdminPermissionsCatalog> fetchAdminPermissionsCatalog() async {
    catalogCalls++;
    if (catalogError) {
      throw const AdminApiException(
        message: 'Catalogo indisponivel para teste',
        statusCode: 500,
      );
    }
    if (empty) {
      return const AdminPermissionsCatalog(items: []);
    }
    return const AdminPermissionsCatalog(
      items: [
        AdminPermissionDefinition(
          permissionKey: 'admin-permissions.manage',
          description: 'Gerencia permissoes administrativas',
          category: 'admin-permissions',
          riskLevel: 'critical',
          actionType: null,
          scopes: ['platform'],
          requiresDryRun: false,
          requiresReason: true,
          requiresExplicitConfirmation: true,
          requiresPersistentAudit: true,
        ),
        AdminPermissionDefinition(
          permissionKey: 'support.session.revoke',
          description: 'Permite preparar revogacao auditada de sessao.',
          category: 'support-action',
          riskLevel: 'high',
          actionType: 'revoke_session',
          scopes: ['platform', 'company', 'user', 'device'],
          requiresDryRun: true,
          requiresReason: true,
          requiresExplicitConfirmation: true,
          requiresPersistentAudit: true,
        ),
      ],
    );
  }

  @override
  Future<AdminUserPermissionsSnapshot> fetchAdminUserPermissions(
    String adminUserId,
  ) async {
    userPermissionCalls++;
    lastAdminUserId = adminUserId;
    if (userPermissionsError) {
      throw const AdminApiException(
        message: 'Sem permissao para permissoes do admin',
        statusCode: 403,
        code: 'ADMIN_PERMISSION_MANAGE_REQUIRED',
      );
    }
    if (empty) {
      return AdminUserPermissionsSnapshot(
        adminUserId: adminUserId,
        activePermissions: const [],
        inactivePermissions: const [],
        auditEventId: null,
      );
    }
    return AdminUserPermissionsSnapshot(
      adminUserId: adminUserId,
      activePermissions: [
        AdminUserPermission(
          id: 'perm-1',
          actorUserId: adminUserId,
          permissionKey: 'admin-permissions.manage',
          scope: 'platform',
          scopeId: '*',
          isActive: true,
          createdAt: DateTime.utc(2026, 5, 31, 18),
          updatedAt: DateTime.utc(2026, 5, 31, 18, 30),
          revokedAt: null,
        ),
      ],
      inactivePermissions: [
        AdminUserPermission(
          id: 'perm-2',
          actorUserId: adminUserId,
          permissionKey: 'support.session.revoke',
          scope: 'platform',
          scopeId: '*',
          isActive: false,
          createdAt: DateTime.utc(2026, 5, 30, 18),
          updatedAt: DateTime.utc(2026, 5, 31, 17),
          revokedAt: DateTime.utc(2026, 5, 31, 17),
        ),
      ],
      auditEventId: 'audit-1',
    );
  }

  @override
  Future<AdminPermissionMutationResult> grantAdminPermission({
    required String adminUserId,
    required String permissionKey,
    required String reason,
    String scope = 'platform',
    String scopeId = '*',
  }) async {
    grantCalls++;
    lastMutationPermissionKey = permissionKey;
    lastMutationReason = reason;
    _throwMutationErrorIfNeeded();
    return const AdminPermissionMutationResult(
      ok: true,
      code: 'ADMIN_PERMISSION_GRANTED',
      message: 'Permissao administrativa concedida.',
      auditEventId: 'audit-grant',
      permission: null,
      revokedCount: null,
    );
  }

  @override
  Future<AdminPermissionMutationResult> revokeAdminPermission({
    required String adminUserId,
    required String permissionKey,
    required String reason,
    String scope = 'platform',
    String scopeId = '*',
  }) async {
    revokeCalls++;
    lastMutationPermissionKey = permissionKey;
    lastMutationReason = reason;
    _throwMutationErrorIfNeeded();
    return const AdminPermissionMutationResult(
      ok: true,
      code: 'ADMIN_PERMISSION_REVOKED',
      message: 'Permissao administrativa revogada.',
      auditEventId: 'audit-revoke',
      permission: null,
      revokedCount: 1,
    );
  }

  void _throwMutationErrorIfNeeded() {
    final code = mutationErrorCode;
    if (code == null) {
      return;
    }
    throw AdminApiException(
      message: 'Mensagem backend segura para $code',
      statusCode: code == 'ADMIN_PERMISSION_MANAGE_REQUIRED' ? 403 : 422,
      code: code,
    );
  }
}
