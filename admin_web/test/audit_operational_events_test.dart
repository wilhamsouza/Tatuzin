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
import 'package:tatuzin_admin_web/src/features/audit/presentation/audit_page.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('auditoria destaca permissoes support-actions e revoke_session', (
    tester,
  ) async {
    final service = _FakeAuditApiService();

    await tester.pumpWidget(_testApp(service));
    await tester.pumpAndSettle();

    expect(find.text('Permissoes'), findsWidgets);
    expect(find.text('Support-actions'), findsWidgets);
    expect(find.text('Revoke session'), findsWidgets);
    expect(find.text('Permissao administrativa concedida'), findsOneWidget);
    expect(find.text('Dry-run de revoke_session'), findsOneWidget);
    expect(find.text('Uso da rota legada de sessao'), findsOneWidget);
    expect(
      find.text('revoke_session real depende do gate operacional'),
      findsOneWidget,
    );
    expect(find.textContaining('secret-token'), findsNothing);
    expect(find.textContaining('authorization'), findsNothing);
    expect(service.calls, 1);
  });
}

Widget _testApp(AdminApiService service) {
  return ProviderScope(
    overrides: [adminApiServiceProvider.overrideWithValue(service)],
    child: const MaterialApp(home: Scaffold(body: AuditPage())),
  );
}

class _FakeAuditApiService extends AdminApiService {
  _FakeAuditApiService()
    : super(
        apiClient: AdminApiClient(
          baseUrl: 'https://api.test/api',
          authStorage: AdminAuthStorage(),
          httpClient: MockClient((_) async => http.Response('{}', 200)),
        ),
        authStorage: AdminAuthStorage(),
      );

  int calls = 0;

  @override
  Future<AdminAuditLogPage> fetchAuditLogs({AdminAuditQuery? query}) async {
    calls++;
    return AdminAuditLogPage(
      items: [
        AdminAuditEntry(
          id: 'audit-1',
          source: 'admin',
          category: 'security',
          action: 'admin-permissions.grant',
          status: 'success',
          companyId: 'company-1',
          companyName: 'Tatuzin Demo',
          actorUserId: 'admin-1',
          actorName: 'Operador',
          targetType: 'adminUserPermission',
          targetId: 'perm-1',
          reason: 'Chamado aprovado',
          createdAt: DateTime.utc(2026, 6, 1, 10),
          metadata: const <String, dynamic>{
            'permissionKey': 'support.session.revoke',
          },
        ),
        AdminAuditEntry(
          id: 'audit-2',
          source: 'support_actions',
          category: 'session',
          action: 'support.revoke_session.dry_run.succeeded',
          status: 'success',
          companyId: 'company-1',
          companyName: 'Tatuzin Demo',
          actorUserId: 'admin-1',
          actorName: 'Operador',
          targetType: 'session',
          targetId: 'session-1',
          reason: 'Simulacao de impacto',
          createdAt: DateTime.utc(2026, 6, 1, 11),
        ),
        AdminAuditEntry(
          id: 'audit-3',
          source: 'admin',
          category: 'session',
          action: 'admin.sessions.legacy_revoke.used',
          status: 'info',
          companyId: 'company-1',
          companyName: 'Tatuzin Demo',
          actorUserId: 'admin-1',
          actorName: 'Operador',
          targetType: 'session',
          targetId: 'session-2',
          summary: 'legacy_route',
          createdAt: DateTime.utc(2026, 6, 1, 12),
        ),
      ],
      pagination: const AdminPaginationMeta(
        page: 1,
        pageSize: 20,
        total: 3,
        count: 3,
        hasNext: false,
        hasPrevious: false,
      ),
      filters: const {},
      sort: const AdminSortMeta(by: 'createdAt', direction: 'desc'),
      overview: const AdminAuditOverview(
        totalEvents: 3,
        countsByCategory: {'security': 1, 'session': 2},
        failures: 0,
        last7Days: 3,
      ),
    );
  }
}
