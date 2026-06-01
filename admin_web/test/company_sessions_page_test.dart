import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tatuzin_admin_web/src/core/auth/admin_auth_storage.dart';
import 'package:tatuzin_admin_web/src/core/auth/admin_providers.dart';
import 'package:tatuzin_admin_web/src/core/models/admin_models.dart';
import 'package:tatuzin_admin_web/src/core/network/admin_api_client.dart';
import 'package:tatuzin_admin_web/src/core/network/admin_api_service.dart';
import 'package:tatuzin_admin_web/src/features/companies/presentation/company_sessions_page.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('renderiza console operacional read-only de sessoes', (
    tester,
  ) async {
    final service = _FakeSessionsApiService();

    await tester.pumpWidget(_testApp(service));
    await tester.pumpAndSettle();

    expect(find.text('Sessoes da empresa'), findsWidgets);
    expect(find.text('Somente leitura'), findsOneWidget);
    expect(
      find.text('Dry-run disponivel na Central de suporte'),
      findsOneWidget,
    );
    expect(find.text('Execucao real indisponivel'), findsOneWidget);
    expect(find.text('Gate operacional em observacao'), findsOneWidget);
    expect(find.text('Resumo operacional de sessoes'), findsOneWidget);
    expect(find.text('session-1'), findsOneWidget);
    expect(find.text('session-2'), findsOneWidget);
    expect(find.text('Alice Admin'), findsOneWidget);
    expect(find.text('PDV Android'), findsOneWidget);
    expect(find.text('Tatuzin Demo'), findsWidgets);
    expect(find.text('Mobile app'), findsOneWidget);
    expect(find.text('Ativa'), findsOneWidget);
    expect(find.text('Revogada'), findsOneWidget);
    expect(find.text('Auditoria'), findsWidgets);
    expect(find.text('Suporte'), findsWidgets);
    expect(find.text('Dispositivos'), findsOneWidget);
    expect(find.text('Usuarios'), findsOneWidget);
    expect(find.text('Permissoes'), findsOneWidget);
    expect(find.text('Executar revogacao'), findsNothing);
    expect(find.text('Revogar sessao agora'), findsNothing);
    expect(find.text('Confirmar execucao'), findsNothing);
    expect(find.text('Aplicar acao'), findsNothing);
    expect(find.text('Bloquear usuario'), findsNothing);
    expect(find.text('Forcar sync'), findsNothing);
    expect(find.text('Resolver conflito'), findsNothing);
    expect(find.text('Enviar push'), findsNothing);
    expect(service.calls, 1);
    expect(service.lastCompanyId, 'company-1');
  });

  testWidgets('mostra estado vazio claro para empresa sem sessoes', (
    tester,
  ) async {
    final service = _FakeSessionsApiService(empty: true);

    await tester.pumpWidget(_testApp(service));
    await tester.pumpAndSettle();

    expect(find.text('Nenhuma sessao registrada'), findsOneWidget);
    expect(
      find.textContaining('as sessoes aparecerao aqui com usuario'),
      findsOneWidget,
    );
  });

  testWidgets('mostra erro seguro de carregamento de sessoes', (tester) async {
    final service = _FakeSessionsApiService(error: true);

    await tester.pumpWidget(_testApp(service));
    await tester.pumpAndSettle();

    expect(find.text('Sessoes indisponiveis'), findsOneWidget);
    expect(find.textContaining('Falha controlada'), findsOneWidget);
    expect(find.textContaining('authorization'), findsNothing);
    expect(find.text('Tentar novamente'), findsOneWidget);
  });
}

Widget _testApp(AdminApiService service) {
  return ProviderScope(
    overrides: [adminApiServiceProvider.overrideWithValue(service)],
    child: const MaterialApp(
      home: Scaffold(body: CompanySessionsPage(companyId: 'company-1')),
    ),
  );
}

class _FakeSessionsApiService extends AdminApiService {
  _FakeSessionsApiService({this.empty = false, this.error = false})
    : super(
        apiClient: AdminApiClient(
          baseUrl: 'https://api.test/api',
          authStorage: AdminAuthStorage(),
          httpClient: MockClient((_) async => http.Response('{}', 200)),
        ),
        authStorage: AdminAuthStorage(),
      );

  final bool empty;
  final bool error;
  int calls = 0;
  String? lastCompanyId;

  @override
  Future<List<AdminDeviceSession>> fetchCompanySessions(
    String companyId,
  ) async {
    calls++;
    lastCompanyId = companyId;
    if (error) {
      throw Exception('Falha controlada sem payload sensivel');
    }
    if (empty) {
      return const [];
    }
    return [
      AdminDeviceSession(
        id: 'session-1',
        userId: 'user-1',
        userName: 'Alice Admin',
        userEmail: 'alice@example.test',
        companyId: companyId,
        companyName: 'Tatuzin Demo',
        membershipId: 'member-1',
        membershipRole: 'owner',
        clientType: 'MOBILE_APP',
        clientInstanceId: 'device-instance-1',
        deviceLabel: 'PDV Android',
        platform: 'android',
        appVersion: '1.2.3',
        status: 'active',
        createdAt: DateTime.utc(2026, 5, 31, 10),
        lastSeenAt: DateTime.utc(2026, 5, 31, 11),
        lastRefreshedAt: DateTime.utc(2026, 5, 31, 11, 5),
        refreshTokenExpiresAt: DateTime.utc(2026, 7),
        revokedAt: null,
        revokedReason: null,
      ),
      AdminDeviceSession(
        id: 'session-2',
        userId: '',
        userName: '',
        userEmail: '',
        companyId: companyId,
        companyName: 'Tatuzin Demo',
        membershipId: '',
        membershipRole: '',
        clientType: 'ADMIN_WEB',
        clientInstanceId: '',
        deviceLabel: null,
        platform: null,
        appVersion: null,
        status: 'revoked',
        createdAt: DateTime.utc(2026, 5, 30, 10),
        lastSeenAt: null,
        lastRefreshedAt: null,
        refreshTokenExpiresAt: null,
        revokedAt: DateTime.utc(2026, 5, 30, 11),
        revokedReason: 'Chamado auditado',
      ),
    ];
  }
}
