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
import 'package:erp_pdv_app/modules/funcionarios/presentation/pages/employee_activity_page.dart';
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
    await dataSource.generateTemporaryPassword('employee 1');
    await dataSource.disableEmployee('employee 1');
    await dataSource.enableEmployee('employee 1');
    final activityPeriod = EmployeeActivityPeriod(
      label: 'Hoje',
      from: DateTime(2026, 5, 20),
      to: DateTime(2026, 5, 20),
    );
    await dataSource.getEmployeeActivitySummary(period: activityPeriod);
    await dataSource.getEmployeeActivityDetail(
      'employee 1',
      period: activityPeriod,
    );

    expect(api.calls.map((call) => call.method).toList(), [
      'GET',
      'GET',
      'POST',
      'PATCH',
      'DELETE',
      'POST',
      'POST',
      'POST',
      'POST',
      'GET',
      'GET',
    ]);
    expect(api.calls.map((call) => call.path).toList(), [
      '/employees',
      '/employees/employee%201',
      '/employees',
      '/employees/employee%201',
      '/employees/employee%201',
      '/employees/employee%201/invite',
      '/employees/employee%201/access/temporary-password',
      '/employees/employee%201/disable',
      '/employees/employee%201/enable',
      '/employees/activity/summary',
      '/employees/employee%201/activity',
    ]);
    expect(api.calls.first.queryParameters['status'], 'ACTIVE');
    expect(api.calls.first.queryParameters['role'], 'CASHIER');
    expect(api.calls[9].queryParameters['from'], '2026-05-20');
    expect(api.calls[10].queryParameters['to'], '2026-05-20');
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
    expect(find.text('Acesso ativo'), findsOneWidget);
    expect(find.text('Ver atividade da equipe'), findsOneWidget);
    expect(find.text('Ver atividade'), findsWidgets);
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
    expect(find.text('Redefinir senha'), findsNothing);
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
    await tester.tap(find.text('Gerar senha temporária'));
    await tester.pumpAndSettle();

    expect(fakeDataSource.temporaryPasswordCalls, ['employee-invited']);
    expect(find.text('Acesso do funcionário'), findsOneWidget);
    expect(find.text('Temp123456'), findsOneWidget);
    expect(
      find.textContaining('Essa senha aparece apenas agora'),
      findsOneWidget,
    );
    expect(find.textContaining('hash'), findsNothing);

    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();
    expect(find.text('Temp123456'), findsNothing);
  });

  testWidgets('Atividade dos funcionários renderiza KPIs e estado parcial', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpEmployeeActivityPage(
      tester,
      session: _session(
        PlanEntitlements.pro,
        membershipPermissions: const {'reports.advanced'},
        employee: const AppEmployeeContext(
          id: 'employee-owner',
          role: 'OWNER',
          status: 'ACTIVE',
          permissions: {'reports.advanced'},
        ),
      ),
      dataSource: _FakeEmployeesRemoteDataSource(),
    );

    expect(find.text('Atividade dos funcionários'), findsWidgets);
    expect(find.text('Funcionários ativos'), findsOneWidget);
    expect(find.text('Total vendido'), findsOneWidget);
    expect(find.text('R\$ 125,00'), findsAtLeastNWidgets(1));
    expect(find.text('Dados parcialmente rastreados'), findsOneWidget);
  });

  testWidgets('Atividade dos funcionários mostra estado vazio', (tester) async {
    await _pumpEmployeeActivityPage(
      tester,
      session: _session(
        PlanEntitlements.pro,
        membershipPermissions: const {'reports.advanced'},
      ),
      dataSource: _FakeEmployeesRemoteDataSource(
        activitySummaryPayload: _emptyEmployeeActivitySummaryPayload(),
      ),
    );

    expect(find.text('Nenhuma atividade encontrada'), findsOneWidget);
    expect(
      find.text('Nenhuma atividade encontrada neste período.'),
      findsOneWidget,
    );
  });

  testWidgets('Filtro de período recarrega atividade', (tester) async {
    final dataSource = _FakeEmployeesRemoteDataSource();
    await _pumpEmployeeActivityPage(
      tester,
      session: _session(
        PlanEntitlements.pro,
        membershipPermissions: const {'reports.advanced'},
      ),
      dataSource: dataSource,
    );

    await tester.tap(find.text('Ontem'));
    await tester.pumpAndSettle();

    expect(dataSource.summaryPeriods.map((period) => period.label), [
      'Hoje',
      'Ontem',
    ]);
  });

  testWidgets('Atividade do funcionário renderiza timeline', (tester) async {
    await _pumpEmployeeActivityDetailPage(
      tester,
      session: _session(
        PlanEntitlements.pro,
        membershipPermissions: const {'reports.advanced'},
      ),
      dataSource: _FakeEmployeesRemoteDataSource(),
    );

    expect(find.text('Caixa Principal'), findsOneWidget);
    expect(find.text('Linha do tempo'), findsOneWidget);
    expect(find.text('Venda realizada'), findsOneWidget);
    expect(find.text('Venda 123'), findsOneWidget);
  });

  testWidgets('Timeline da atividade abre resumo seguro ao tocar', (
    tester,
  ) async {
    await _pumpEmployeeActivityDetailPage(
      tester,
      session: _session(
        PlanEntitlements.pro,
        membershipPermissions: const {'reports.advanced'},
      ),
      dataSource: _FakeEmployeesRemoteDataSource(),
    );

    await tester.ensureVisible(find.text('Venda realizada'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Venda realizada'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Detalhes completos ainda nao estao disponiveis para esta acao.',
      ),
      findsOneWidget,
    );
    expect(find.text('Valor'), findsOneWidget);
    expect(find.text('R\$ 125,00'), findsWidgets);
  });

  testWidgets('Atividade dos funcionários mostra sem permissão', (
    tester,
  ) async {
    await _pumpEmployeeActivityPage(
      tester,
      session: _session(PlanEntitlements.pro, membershipRole: 'OPERATOR'),
      dataSource: _FakeEmployeesRemoteDataSource(),
    );

    expect(
      find.text('Você não tem permissão para ver atividade de funcionários.'),
      findsOneWidget,
    );
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

Future<void> _pumpEmployeeActivityPage(
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
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const EmployeeActivityPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpEmployeeActivityDetailPage(
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
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const EmployeeActivityDetailPage(employeeId: 'employee-cashier'),
      ),
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
  String membershipRole = 'OWNER',
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
      role: membershipRole,
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
  accessStatus: EmployeeAccessStatus.active,
  createdAt: null,
  updatedAt: null,
);

const _cashierWithTemporaryPassword = EmployeeProfile(
  id: 'employee-cashier',
  name: 'Caixa Principal',
  email: 'caixa@tatuzin.test',
  role: EmployeeRole.cashier,
  status: EmployeeStatus.active,
  permissions: {EmployeePermission.salesCreate},
  accessStatus: EmployeeAccessStatus.temporaryPasswordPending,
  createdAt: null,
  updatedAt: null,
);

const _disabled = EmployeeProfile(
  id: 'employee-disabled',
  name: 'Vendedor antigo',
  role: EmployeeRole.seller,
  status: EmployeeStatus.disabled,
  permissions: {EmployeePermission.salesCreate},
  accessStatus: EmployeeAccessStatus.disabled,
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
  accessStatus: EmployeeAccessStatus.noAccess,
  createdAt: null,
  updatedAt: null,
);

class _FakeEmployeesRemoteDataSource extends EmployeesRemoteDataSource {
  _FakeEmployeesRemoteDataSource({
    EmployeesPageResult? page,
    Map<String, dynamic>? activitySummaryPayload,
    Map<String, dynamic>? activityDetailPayload,
  }) : page = page ?? _page(const <EmployeeProfile>[]),
       activitySummaryPayload =
           activitySummaryPayload ?? _employeeActivitySummaryPayload(),
       activityDetailPayload =
           activityDetailPayload ?? _employeeActivityDetailPayload(),
       super(apiClient: _NoopApiClient(), tokenStorage: _TokenStorage());

  final EmployeesPageResult page;
  final Map<String, dynamic> activitySummaryPayload;
  final Map<String, dynamic> activityDetailPayload;
  final inviteCalls = <String>[];
  final temporaryPasswordCalls = <String>[];
  final summaryPeriods = <EmployeeActivityPeriod>[];

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

  @override
  Future<EmployeeTemporaryPasswordResult> generateTemporaryPassword(
    String id,
  ) async {
    temporaryPasswordCalls.add(id);
    return const EmployeeTemporaryPasswordResult(
      employee: _cashierWithTemporaryPassword,
      login: 'caixa@tatuzin.test',
      temporaryPassword: 'Temp123456',
      temporaryPasswordExpiresAt: null,
      message: 'Senha temporária gerada.',
    );
  }

  @override
  Future<EmployeeActivitySummary> getEmployeeActivitySummary({
    required EmployeeActivityPeriod period,
  }) async {
    summaryPeriods.add(period);
    return EmployeeActivitySummary.fromMap(activitySummaryPayload);
  }

  @override
  Future<EmployeeActivityDetail> getEmployeeActivityDetail(
    String id, {
    required EmployeeActivityPeriod period,
  }) async {
    return EmployeeActivityDetail.fromMap(activityDetailPayload);
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
      data: path == '/employees'
          ? _employeesPayload()
          : path == '/employees/activity/summary'
          ? _employeeActivitySummaryPayload()
          : path.endsWith('/activity')
          ? _employeeActivityDetailPayload()
          : _employeePayload(),
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
      data: path.endsWith('/invite')
          ? _invitePayload()
          : path.endsWith('/access/temporary-password')
          ? _temporaryPasswordPayload()
          : _employeePayload(),
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

Map<String, dynamic> _temporaryPasswordPayload() {
  return <String, dynamic>{
    'employee': _employeeMap(accessStatus: 'TEMPORARY_PASSWORD_PENDING'),
    'login': 'caixa@tatuzin.test',
    'temporaryPassword': 'Temp123456',
    'temporaryPasswordExpiresAt': '2026-05-27T12:00:00.000Z',
    'message': 'Senha temporária gerada.',
  };
}

Map<String, dynamic> _employeeActivitySummaryPayload() {
  return <String, dynamic>{
    'totalEmployees': 1,
    'activeEmployees': 1,
    'employeesWithActivity': 1,
    'totalSalesCount': 1,
    'totalSalesAmountCents': 12500,
    'totalDiscountAmountCents': 500,
    'totalCanceledCount': 0,
    'totalStockAdjustments': 1,
    'rows': <Map<String, dynamic>>[
      <String, dynamic>{
        'employeeId': 'employee-cashier',
        'name': 'Caixa Principal',
        'role': 'CASHIER',
        'status': 'ACTIVE',
        'salesCount': 1,
        'salesAmountCents': 12500,
        'discountAmountCents': 500,
        'canceledSalesCount': 0,
        'stockAdjustmentsCount': 1,
        'cashActionsCount': 2,
        'lastActivityAt': '2026-05-20T18:00:00.000Z',
      },
    ],
    'tracking': <String, dynamic>{
      'partial': true,
      'notes': <String>[
        'Algumas ações antigas podem aparecer sem responsável.',
      ],
    },
  };
}

Map<String, dynamic> _emptyEmployeeActivitySummaryPayload() {
  return <String, dynamic>{
    'totalEmployees': 1,
    'activeEmployees': 1,
    'employeesWithActivity': 0,
    'totalSalesCount': 0,
    'totalSalesAmountCents': 0,
    'totalDiscountAmountCents': 0,
    'totalCanceledCount': 0,
    'totalStockAdjustments': 0,
    'rows': <Map<String, dynamic>>[],
    'tracking': <String, dynamic>{
      'partial': true,
      'notes': <String>[
        'Algumas ações antigas podem aparecer sem responsável.',
      ],
    },
  };
}

Map<String, dynamic> _employeeActivityDetailPayload() {
  return <String, dynamic>{
    'employee': <String, dynamic>{
      'id': 'employee-cashier',
      'name': 'Caixa Principal',
      'role': 'CASHIER',
      'status': 'ACTIVE',
    },
    'summary': <String, dynamic>{
      'salesCount': 1,
      'salesAmountCents': 12500,
      'discountAmountCents': 500,
      'canceledSalesCount': 0,
      'stockAdjustmentsCount': 1,
      'cashActionsCount': 2,
      'lastActivityAt': '2026-05-20T18:00:00.000Z',
    },
    'timeline': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'sale:1',
        'occurredAt': '2026-05-20T12:00:00.000Z',
        'type': 'SALE',
        'title': 'Venda realizada',
        'description': 'Venda 123',
        'amountCents': 12500,
      },
    ],
    'tracking': <String, dynamic>{
      'partial': true,
      'notes': <String>[
        'Algumas ações antigas podem aparecer sem responsável.',
      ],
    },
  };
}

Map<String, dynamic> _employeeMap({
  String status = 'ACTIVE',
  String accessStatus = 'ACTIVE',
}) {
  return <String, dynamic>{
    'id': 'employee-1',
    'name': 'Caixa',
    'email': 'caixa@tatuzin.test',
    'phone': '11999990000',
    'role': 'CASHIER',
    'status': status,
    'accessStatus': accessStatus,
    'permissions': <String>['sales.create'],
    'createdAt': '2026-05-08T12:00:00.000Z',
    'updatedAt': '2026-05-08T12:00:00.000Z',
  };
}
