import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tatuzin_admin_web/src/core/auth/admin_auth_storage.dart';
import 'package:tatuzin_admin_web/src/core/auth/admin_providers.dart';
import 'package:tatuzin_admin_web/src/core/models/admin_support_action_models.dart';
import 'package:tatuzin_admin_web/src/core/network/admin_api_client.dart';
import 'package:tatuzin_admin_web/src/core/network/admin_api_service.dart';
import 'package:tatuzin_admin_web/src/core/widgets/admin_support_action_dry_run_panel.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('painel renderiza avisos e bloqueia motivo curto', (
    tester,
  ) async {
    final service = _FakeSupportActionApiService();

    await tester.pumpWidget(_testApp(service));

    expect(find.text('Simulacoes operacionais'), findsOneWidget);
    expect(
      find.text('Dry-run: nenhum dado real sera alterado.'),
      findsOneWidget,
    );
    expect(
      find.text('Execucao real ainda nao esta disponivel no Admin Web.'),
      findsOneWidget,
    );
    expect(
      find.text('PermissionKeys do cliente nao autorizam acoes.'),
      findsOneWidget,
    );
    expect(find.text('Executar agora'), findsNothing);
    expect(find.text('Confirmar execucao'), findsNothing);
    expect(find.text('Aplicar'), findsNothing);

    await tester.enterText(_textFieldWithLabel('sessionId'), 'session-1');
    await tester.enterText(_textFieldWithLabel('Motivo operacional'), 'curto');
    await _tapSimularDryRun(tester);
    await tester.pump();

    expect(
      find.text('Informe um motivo operacional com pelo menos 12 caracteres.'),
      findsOneWidget,
    );
    expect(service.calls, 0);
  });

  testWidgets('sucesso mostra impacto riscos entidades e auditoria preparada', (
    tester,
  ) async {
    final service = _FakeSupportActionApiService();

    await tester.pumpWidget(_testApp(service));
    await tester.enterText(_textFieldWithLabel('sessionId'), 'session-1');
    await tester.enterText(
      _textFieldWithLabel('Motivo operacional'),
      'Chamado de seguranca confirmado',
    );
    await _tapSimularDryRun(tester);
    await tester.pumpAndSettle();

    expect(service.calls, 1);
    expect(service.lastRequest?.actionType, 'revoke_session');
    expect(service.lastRequest?.companyId, 'company-1');
    expect(service.lastRequest?.targetType, 'session');
    expect(service.lastRequest?.targetId, 'session-1');
    expect(find.text('Pre-visualizacao de impacto'), findsOneWidget);
    expect(find.text('Sessao seria revogada em etapa futura.'), findsOneWidget);
    expect(
      find.text('- Usuario precisara autenticar novamente.'),
      findsOneWidget,
    );
    expect(find.text('- session: session-1'), findsOneWidget);
    expect(find.text('Auditoria preparada'), findsOneWidget);
    expect(find.text('audit-dry-run-1'), findsOneWidget);
    expect(find.text('support.session.revoke'), findsOneWidget);
  });

  testWidgets('erro de permissao aparece de forma segura', (tester) async {
    final service = _FakeSupportActionApiService(permissionDenied: true);

    await tester.pumpWidget(_testApp(service));
    await tester.enterText(_textFieldWithLabel('sessionId'), 'session-1');
    await tester.enterText(
      _textFieldWithLabel('Motivo operacional'),
      'Chamado de seguranca confirmado',
    );
    await _tapSimularDryRun(tester);
    await tester.pumpAndSettle();

    expect(
      find.text('Sem permissao persistida para simular esta acao operacional.'),
      findsOneWidget,
    );
    expect(find.textContaining('stack'), findsNothing);
    expect(find.textContaining('secret-token'), findsNothing);
  });

  test('service envia apenas payload seguro para endpoint dry-run', () async {
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
          return http.Response(jsonEncode(_successPayload()), 200);
        }),
      ),
      authStorage: storage,
    );

    await service.simulateSupportActionDryRun(
      request: const AdminSupportActionDryRunRequest(
        actionType: 'revoke_session',
        companyId: 'company-1',
        targetType: 'session',
        targetId: 'session-1',
        reason: 'Chamado de seguranca confirmado',
      ),
    );

    expect(requests, hasLength(1));
    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/api/admin/support-actions/dry-run');
    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body, <String, dynamic>{
      'actionType': 'revoke_session',
      'companyId': 'company-1',
      'targetType': 'session',
      'targetId': 'session-1',
      'reason': 'Chamado de seguranca confirmado',
      'dryRun': true,
    });
    expect(body.containsKey('permissionKeys'), isFalse);
    expect(body.containsKey('actorAdminId'), isFalse);
    expect(body['dryRun'], isTrue);
  });
}

Widget _testApp(AdminApiService service) {
  return ProviderScope(
    overrides: [adminApiServiceProvider.overrideWithValue(service)],
    child: const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AdminSupportActionDryRunPanel(companyId: 'company-1'),
        ),
      ),
    ),
  );
}

Finder _textFieldWithLabel(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );
}

Future<void> _tapSimularDryRun(WidgetTester tester) async {
  final button = find.text('Simular dry-run');
  await tester.ensureVisible(button);
  await tester.tap(button);
}

class _FakeSupportActionApiService extends AdminApiService {
  _FakeSupportActionApiService({this.permissionDenied = false})
    : super(
        apiClient: AdminApiClient(
          baseUrl: 'https://api.test/api',
          authStorage: AdminAuthStorage(),
          httpClient: MockClient((_) async => http.Response('{}', 200)),
        ),
        authStorage: AdminAuthStorage(),
      );

  final bool permissionDenied;
  int calls = 0;
  AdminSupportActionDryRunRequest? lastRequest;

  @override
  Future<AdminSupportActionDryRunResponse> simulateSupportActionDryRun({
    required AdminSupportActionDryRunRequest request,
  }) async {
    calls++;
    lastRequest = request;
    if (permissionDenied) {
      throw const AdminApiException(
        message: 'backend denied without raw payload',
        statusCode: 403,
        code: 'OPERATIONAL_ACTION_MISSING_PERMISSION',
      );
    }
    return AdminSupportActionDryRunResponse.fromMap(_successPayload());
  }
}

Map<String, dynamic> _successPayload() {
  return <String, dynamic>{
    'ok': true,
    'code': 'OPERATIONAL_ACTION_DRY_RUN_READY',
    'message': 'Dry-run preparado. Nenhum dado real foi alterado.',
    'action': <String, dynamic>{
      'actionType': 'revoke_session',
      'permissionKey': 'support.session.revoke',
      'companyId': 'company-1',
      'targetType': 'session',
      'targetId': 'session-1',
      'actorAdminId': 'admin-from-token',
      'reason': 'Chamado de seguranca confirmado',
      'dryRun': true,
      'confirmationRequired': true,
      'expectedImpact': <String, dynamic>{
        'summary': 'Sessao seria revogada em etapa futura.',
        'risks': <String>['Usuario precisara autenticar novamente.'],
        'affectedEntities': <Map<String, dynamic>>[
          <String, dynamic>{'type': 'session', 'id': 'session-1'},
          <String, dynamic>{
            'type': 'audit',
            'id': 'pending',
            'label': 'Evento de auditoria futuro',
          },
        ],
        'confirmationRequired': true,
      },
      'result': <String, dynamic>{
        'status': 'dry_run_ready',
        'code': 'OPERATIONAL_ACTION_DRY_RUN_READY',
        'message': 'Dry-run preparado. Nenhum dado real foi alterado.',
      },
      'auditRequired': true,
      'auditPrepared': true,
      'auditEventId': 'audit-dry-run-1',
      'auditDraft': <String, dynamic>{
        'dryRun': true,
        'confirmationRequired': true,
        'riskLevel': 'high',
        'createdAt': '2026-05-31T20:00:00.000Z',
      },
      'createdAt': '2026-05-31T20:00:00.000Z',
    },
  };
}
