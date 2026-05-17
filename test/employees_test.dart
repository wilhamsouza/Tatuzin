import 'package:erp_pdv_app/app/core/entitlements/feature_gate.dart';
import 'package:erp_pdv_app/app/core/entitlements/plan_entitlements.dart';
import 'package:erp_pdv_app/app/core/errors/app_exceptions.dart';
import 'package:erp_pdv_app/app/core/network/contracts/api_client_contract.dart';
import 'package:erp_pdv_app/app/core/session/app_session.dart';
import 'package:erp_pdv_app/app/core/session/app_user.dart';
import 'package:erp_pdv_app/app/core/session/auth_token_storage.dart';
import 'package:erp_pdv_app/app/core/session/company_context.dart';
import 'package:erp_pdv_app/app/core/session/session_provider.dart';
import 'package:erp_pdv_app/app/core/theme/app_theme.dart';
import 'package:erp_pdv_app/modules/funcionarios/data/employees_remote_data_source.dart';
import 'package:erp_pdv_app/modules/funcionarios/domain/employee_models.dart';
import 'package:erp_pdv_app/modules/funcionarios/presentation/pages/employees_page.dart';
import 'package:erp_pdv_app/modules/funcionarios/presentation/providers/employees_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('EmployeeProfile parseia campos ausentes sem token de convite', () {
    final employee = EmployeeProfile.fromMap(<String, dynamic>{
      'id': 'employee-1',
      'name': 'Caixa',
      'role': 'ALIEN',
      'status': 'MISSING',
      'permissions': <String>['employees.manage', 'unknown.permission'],
      'inviteExpiresAt': '2026-05-09T12:00:00.000Z',
      'inviteTokenHash': 'secret',
    });

    expect(employee.id, 'employee-1');
    expect(employee.role, EmployeeRole.unknown);
    expect(employee.status, EmployeeStatus.unknown);
    expect(employee.permissions, {EmployeePermission.employeesManage});
    expect(
      employee.inviteExpiresAt,
      DateTime.parse('2026-05-09T12:00:00.000Z'),
    );
  });

  test(
    'AppSession remove permissões efetivas quando employee está DISABLED',
    () {
      final session = _session(
        PlanEntitlements.pro,
        membershipPermissions: const {'employees.manage'},
        employee: const AppEmployeeContext(
          id: 'employee-1',
          role: 'MANAGER',
          status: 'DISABLED',
          permissions: {'employees.manage'},
        ),
      );

      expect(session.hasFeature(FeatureKey.employees), isTrue);
      expect(session.hasEffectivePermission('employees.manage'), isFalse);
    },
  );

  test('AppSession trata status desconhecido como sem permissões efetivas', () {
    final session = _session(
      PlanEntitlements.pro,
      membershipPermissions: const {'employees.manage'},
      employee: const AppEmployeeContext(
        id: 'employee-1',
        role: 'MANAGER',
        status: 'BROKEN',
        permissions: {'employees.manage'},
      ),
    );

    expect(session.hasFeature(FeatureKey.employees), isTrue);
    expect(session.hasEffectivePermission('employees.manage'), isFalse);
  });

  test('EmployeesRemoteDataSource chama endpoints e não envia OWNER', () async {
    final api = _RecordingApiClient();
    final dataSource = EmployeesRemoteDataSource(
      apiClient: api,
      tokenStorage: _TokenStorage(),
    );

    await dataSource.getEmployees(
      status: EmployeeStatus.active,
      role: EmployeeRole.cashier,
      search: 'caixa',
      page: 2,
      pageSize: 5,
    );
    await dataSource.getEmployee('employee 1');
    await dataSource.createEmployee(
      const EmployeeMutationInput(
        name: 'Caixa',
        role: EmployeeRole.cashier,
        permissions: {EmployeePermission.salesCreate},
      ),
    );
    await dataSource.updateEmployee(
      'employee 1',
      const EmployeeMutationInput(
        name: 'Caixa 2',
        role: EmployeeRole.seller,
        permissions: {EmployeePermission.salesCreate},
      ),
    );
    await dataSource.deleteEmployee('employee 1');
    await dataSource.inviteEmployee('employee 1');
    await dataSource.disableEmployee('employee 1');
    await dataSource.enableEmployee('employee 1');

    expect(api.calls.map((call) => call.method).toList(), [
      'GET',
      'GET',
      'POST',
      'PATCH',
      'DELETE',
      'POST',
      'POST',
      'POST',
    ]);
    expect(api.calls.map((call) => call.path).toList(), [
      '/employees',
      '/employees/employee%201',
      '/employees',
      '/employees/employee%201',
      '/employees/employee%201',
      '/employees/employee%201/invite',
      '/employees/employee%201/disable',
      '/employees/employee%201/enable',
    ]);
    expect(api.calls.first.queryParameters['status'], 'ACTIVE');
    expect(api.calls.first.queryParameters['role'], 'CASHIER');
    expect(api.calls[2].body?['role'], isNot('OWNER'));
    expect(api.calls[2].body?.containsKey('inviteTokenHash'), isFalse);

    expect(
      () => dataSource.createEmployee(
        const EmployeeMutationInput(
          name: 'Owner',
          role: EmployeeRole.owner,
          permissions: {EmployeePermission.employeesManage},
        ),
      ),
      throwsArgumentError,
    );
  });

  test(
    'EmployeesRemoteDataSource mapeia erros por code quando disponivel',
    () async {
      final featureDataSource = EmployeesRemoteDataSource(
        apiClient: _ThrowingApiClient(
          const NetworkRequestException(
            'Forbidden',
            cause: {'code': 'FEATURE_NOT_AVAILABLE'},
          ),
        ),
        tokenStorage: _TokenStorage(),
      );
      final permissionDataSource = EmployeesRemoteDataSource(
        apiClient: _ThrowingApiClient(
          const NetworkRequestException(
            'Forbidden',
            cause: {
              'body': {'code': 'EMPLOYEE_PERMISSION_DENIED'},
            },
          ),
        ),
        tokenStorage: _TokenStorage(),
      );
      final limitDataSource = EmployeesRemoteDataSource(
        apiClient: _ThrowingApiClient(
          const NetworkRequestException(
            'Conflict',
            cause: {'code': 'EMPLOYEE_LIMIT_REACHED'},
          ),
        ),
        tokenStorage: _TokenStorage(),
      );

      await expectLater(
        featureDataSource.getEmployees(),
        throwsA(
          isA<ValidationException>().having(
            (error) => error.message,
            'message',
            'Funcionários está disponível no plano PRO.',
          ),
        ),
      );
      await expectLater(
        permissionDataSource.getEmployees(),
        throwsA(
          isA<ValidationException>().having(
            (error) => error.message,
            'message',
            'Você não tem permissão para gerenciar funcionários.',
          ),
        ),
      );
      await expectLater(
        limitDataSource.getEmployees(),
        throwsA(
          isA<ValidationException>().having(
            (error) => error.message,
            'message',
            'Limite de funcionários atingido para o plano atual.',
          ),
        ),
      );
    },
  );

  testWidgets('FeatureGate bloqueia FREE mesmo com employees.manage', (
    tester,
  ) async {
    await _pumpFeatureGate(
      tester,
      session: _session(
        PlanEntitlements.free,
        membershipPermissions: const {'employees.manage'},
      ),
    );

    expect(find.text('Ver planos'), findsOneWidget);
    expect(find.text('Novo funcionário'), findsNothing);
  });

  testWidgets('FeatureGate bloqueia BASIC', (tester) async {
    await _pumpFeatureGate(
      tester,
      session: _session(
        PlanEntitlements.basic,
        membershipPermissions: const {'employees.manage'},
      ),
    );

    expect(find.text('Ver planos'), findsOneWidget);
    expect(find.text('Novo funcionário'), findsNothing);
  });

  testWidgets('PRO sem employees.manage mostra sem permissão', (tester) async {
    await _pumpEmployeesPage(
      tester,
      session: _session(PlanEntitlements.pro),
      dataSource: _FakeEmployeesRemoteDataSource(),
    );

    expect(find.text('Sem permissão'), findsOneWidget);
    expect(find.text('Novo funcionário'), findsNothing);
  });

  testWidgets('PRO renderiza lista e protege OWNER', (tester) async {
    await _pumpEmployeesPage(
      tester,
      session: _session(
        PlanEntitlements.pro,
        membershipPermissions: const {'employees.manage'},
        employee: const AppEmployeeContext(
          id: 'employee-owner',
          role: 'OWNER',
          status: 'ACTIVE',
          permissions: {'employees.manage'},
        ),
      ),
      dataSource: _FakeEmployeesRemoteDataSource(
        page: _page(<EmployeeProfile>[_owner, _cashier, _disabled]),
      ),
    );

    expect(find.text('Dono'), findsWidgets);
    expect(find.text('Protegido'), findsOneWidget);
    expect(find.text('Caixa Principal'), findsOneWidget);
    expect(find.text('Desativado'), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('Vendedor antigo'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();

    expect(find.text('Habilitar'), findsOneWidget);
  });

  testWidgets('convite não mostra token ou hash', (tester) async {
    final fakeDataSource = _FakeEmployeesRemoteDataSource(
      page: _page(<EmployeeProfile>[_invited]),
    );
    await _pumpEmployeesPage(
      tester,
      session: _session(
        PlanEntitlements.pro,
        membershipPermissions: const {'employees.manage'},
      ),
      dataSource: fakeDataSource,
    );

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gerar convite'));
    await tester.pumpAndSettle();

    expect(fakeDataSource.inviteCalls, ['employee-invited']);
    expect(find.textContaining('Convite gerado'), findsOneWidget);
    expect(find.textContaining('inviteTokenHash'), findsNothing);
    expect(find.textContaining('secret-token'), findsNothing);
  });
}

Future<void> _pumpFeatureGate(
  WidgetTester tester, {
  required AppSession session,
}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  container
      .read(appSessionProvider.notifier)
      .setAuthenticatedSession(
        scope: session.scope,
        user: session.user,
        company: session.company,
        clientInstanceId: session.clientInstanceId,
        membership: session.membership,
        employee: session.employee,
      );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const FeatureGate(
          feature: FeatureKey.employees,
          title: 'Funcionários',
          child: EmployeesPage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpEmployeesPage(
  WidgetTester tester, {
  required AppSession session,
  required _FakeEmployeesRemoteDataSource dataSource,
}) async {
  final container = ProviderContainer(
    overrides: [
      employeesRemoteDataSourceProvider.overrideWithValue(dataSource),
    ],
  );
  addTearDown(container.dispose);
  container
      .read(appSessionProvider.notifier)
      .setAuthenticatedSession(
        scope: session.scope,
        user: session.user,
        company: session.company,
        clientInstanceId: session.clientInstanceId,
        membership: session.membership,
        employee: session.employee,
      );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.light(), home: const EmployeesPage()),
    ),
  );
  await tester.pumpAndSettle();
}

EmployeesPageResult _page(List<EmployeeProfile> employees) {
  return EmployeesPageResult(
    items: employees,
    page: 1,
    pageSize: 20,
    total: employees.length,
    count: employees.length,
    hasNext: false,
    hasPrevious: false,
  );
}

AppSession _session(
  PlanEntitlements entitlements, {
  Set<String> membershipPermissions = const <String>{},
  AppEmployeeContext? employee,
}) {
  return AppSession(
    scope: SessionScope.authenticatedRemote,
    user: const AppUser(
      localId: null,
      remoteId: 'user-1',
      displayName: 'Owner',
      email: 'owner@tatuzin.test',
      roleLabel: 'Owner',
      kind: AppUserKind.remoteAuthenticated,
    ),
    company: CompanyContext(
      localId: null,
      remoteId: 'company-1',
      displayName: 'Cafe Oliveira',
      legalName: 'Cafe Oliveira LTDA',
      documentNumber: null,
      licensePlan: entitlements.plan.key,
      licenseStatus: 'active',
      syncEnabled: true,
      entitlements: entitlements,
    ),
    membership: AppMembershipContext(
      role: 'OWNER',
      permissions: membershipPermissions,
    ),
    employee: employee,
    startedAt: DateTime(2026, 5, 8),
    isOfflineFallback: false,
    clientInstanceId: 'device-1',
  );
}

const _owner = EmployeeProfile(
  id: 'employee-owner',
  name: 'Dono',
  role: EmployeeRole.owner,
  status: EmployeeStatus.active,
  permissions: {EmployeePermission.employeesManage},
  createdAt: null,
  updatedAt: null,
);

const _cashier = EmployeeProfile(
  id: 'employee-cashier',
  name: 'Caixa Principal',
  email: 'caixa@tatuzin.test',
  role: EmployeeRole.cashier,
  status: EmployeeStatus.active,
  permissions: {EmployeePermission.salesCreate},
  createdAt: null,
  updatedAt: null,
);

const _disabled = EmployeeProfile(
  id: 'employee-disabled',
  name: 'Vendedor antigo',
  role: EmployeeRole.seller,
  status: EmployeeStatus.disabled,
  permissions: {EmployeePermission.salesCreate},
  createdAt: null,
  updatedAt: null,
);

const _invited = EmployeeProfile(
  id: 'employee-invited',
  name: 'Vendedor convidado',
  email: 'convite@tatuzin.test',
  role: EmployeeRole.seller,
  status: EmployeeStatus.invited,
  permissions: {EmployeePermission.salesCreate},
  createdAt: null,
  updatedAt: null,
);

class _FakeEmployeesRemoteDataSource extends EmployeesRemoteDataSource {
  _FakeEmployeesRemoteDataSource({EmployeesPageResult? page})
    : page = page ?? _page(const <EmployeeProfile>[]),
      super(apiClient: _NoopApiClient(), tokenStorage: _TokenStorage());

  final EmployeesPageResult page;
  final inviteCalls = <String>[];

  @override
  Future<EmployeesPageResult> getEmployees({
    EmployeeStatus? status,
    EmployeeRole? role,
    String? search,
    int page = 1,
    int pageSize = 20,
  }) async {
    return this.page;
  }

  @override
  Future<EmployeeActionResult> inviteEmployee(String id) async {
    inviteCalls.add(id);
    return const EmployeeActionResult(
      employee: _invited,
      message:
          'Convite gerado. O envio automático de e-mail será implementado em etapa futura.',
    );
  }
}

class _RecordingApiClient implements ApiClientContract {
  final calls = <_ApiCall>[];

  @override
  Future<ApiResponse<void>> delete(
    String path, {
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async {
    calls.add(
      _ApiCall('DELETE', path, queryParameters: options.queryParameters),
    );
    return const ApiResponse<void>(
      statusCode: 200,
      data: null,
      headers: <String, String>{},
    );
  }

  @override
  Future<ApiResponse<Map<String, dynamic>>> getJson(
    String path, {
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async {
    calls.add(_ApiCall('GET', path, queryParameters: options.queryParameters));
    return ApiResponse<Map<String, dynamic>>(
      statusCode: 200,
      data: path == '/employees' ? _employeesPayload() : _employeePayload(),
      headers: const <String, String>{},
    );
  }

  @override
  Future<ApiResponse<Map<String, dynamic>>> patchJson(
    String path, {
    Map<String, dynamic>? body,
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async {
    calls.add(_ApiCall('PATCH', path, body: body));
    return ApiResponse<Map<String, dynamic>>(
      statusCode: 200,
      data: _employeePayload(),
      headers: const <String, String>{},
    );
  }

  @override
  Future<ApiResponse<Map<String, dynamic>>> postJson(
    String path, {
    Map<String, dynamic>? body,
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async {
    calls.add(_ApiCall('POST', path, body: body));
    return ApiResponse<Map<String, dynamic>>(
      statusCode: 200,
      data: path.endsWith('/invite') ? _invitePayload() : _employeePayload(),
      headers: const <String, String>{},
    );
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

class _ThrowingApiClient extends _NoopApiClient {
  _ThrowingApiClient(this.error);

  final NetworkRequestException error;

  @override
  Future<ApiResponse<Map<String, dynamic>>> getJson(
    String path, {
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async {
    throw error;
  }
}

class _NoopApiClient implements ApiClientContract {
  @override
  Future<ApiResponse<void>> delete(
    String path, {
    ApiRequestOptions options = const ApiRequestOptions(),
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ApiResponse<Map<String, dynamic>>> getJson(
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

class _TokenStorage implements AuthTokenStorage {
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
      clientInstanceId: 'device-1',
    );
  }

  @override
  Future<String?> readAccessToken() async => 'access-token';

  @override
  Future<AuthClientContext?> readClientContext() async =>
      const AuthClientContext(
        clientType: 'mobile_app',
        clientInstanceId: 'device-1',
      );

  @override
  Future<String?> readRefreshToken() async => 'refresh-token';

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {}
}

class _ApiCall {
  const _ApiCall(
    this.method,
    this.path, {
    this.body,
    this.queryParameters = const <String, Object?>{},
  });

  final String method;
  final String path;
  final Map<String, dynamic>? body;
  final Map<String, Object?> queryParameters;
}

Map<String, dynamic> _employeesPayload() {
  return <String, dynamic>{
    'items': <Map<String, dynamic>>[_employeeMap()],
    'page': 1,
    'pageSize': 20,
    'total': 1,
    'count': 1,
    'hasNext': false,
    'hasPrevious': false,
  };
}

Map<String, dynamic> _employeePayload() {
  return <String, dynamic>{'employee': _employeeMap()};
}

Map<String, dynamic> _invitePayload() {
  return <String, dynamic>{
    'employee': _employeeMap(status: 'INVITED'),
    'message':
        'Convite gerado. O envio automático de e-mail será implementado em etapa futura.',
  };
}

Map<String, dynamic> _employeeMap({String status = 'ACTIVE'}) {
  return <String, dynamic>{
    'id': 'employee-1',
    'name': 'Caixa',
    'email': 'caixa@tatuzin.test',
    'phone': '11999990000',
    'role': 'CASHIER',
    'status': status,
    'permissions': <String>['sales.create'],
    'createdAt': '2026-05-08T12:00:00.000Z',
    'updatedAt': '2026-05-08T12:00:00.000Z',
  };
}
