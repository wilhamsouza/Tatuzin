import 'fixtures/cash_workspace_fixture.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tatuzin_owner_web/src/core/auth/owner_auth_storage.dart';
import 'package:tatuzin_owner_web/src/core/auth/owner_providers.dart';
import 'package:tatuzin_owner_web/src/core/models/owner_models.dart';
import 'package:tatuzin_owner_web/src/core/network/owner_api_client.dart';
import 'package:tatuzin_owner_web/src/core/network/owner_api_service.dart';
import 'package:tatuzin_owner_web/src/features/company/presentation/owner_cash_policy_card.dart';
import 'package:tatuzin_owner_web/src/features/reports/presentation/owner_cash_report_page.dart';
import 'package:tatuzin_owner_web/src/theme/owner_theme.dart';

final session = <String, dynamic>{
  'id': 'cash-1',
  'shortId': 'CX-001',
  'openedAt': '2026-11-19T08:00:00Z',
  'closedAt': '2026-11-19T18:00:00Z',
  'employee': {'name': 'Ana Caixa'},
  'status': 'closed',
  'statusLabel': 'Fechado',
  'totalSoldCents': 15000,
  'differenceCents': -500,
  'salesCount': 3,
};
OwnerCashSessionsReport report() => OwnerCashSessionsReport.fromMap({
  'summary': {
    'openSessions': 23,
    'closedSessions': 43,
    'totalSessions': 66,
    'sessionsWithDifference': 7,
    'totalDifferenceCents': -2500,
    'receiptBreakdownAvailable': false,
    'totalSoldCents': 450000,
    'salesCount': 75,
  },
  'items': {
    'items': [session],
    'page': 1,
    'pageSize': 20,
    'total': 66,
  },
});
OwnerCashSessionDetail detail({
  bool legacy = false,
  bool canReview = true,
  bool openingPending = false,
}) => OwnerCashSessionDetail.fromMap({
  'session': session,
  'employee': {'name': 'Ana Caixa'},
  'device': {'name': 'Balcão principal'},
  'openingAwaitingConfirmation': openingPending,
  'values': {
    'openingBalanceCents': 10000,
    'expectedBalanceCents': 20000,
    'closingBalanceCents': 19500,
    'differenceCents': -500,
  },
  if (!legacy)
    'openingDetails': {
      'version': 2,
      'countedAmountCents': 10000,
      'policyRevision': 3,
    },
  if (!legacy)
    'closingDetails': {
      'version': 2,
      'expectedBalanceCents': 20000,
      'countedBalanceCents': 19500,
      'differenceCents': -500,
      'reason': 'Diferença na contagem',
      'denominations': [
        {'valueCents': 5000, 'quantity': 3},
      ],
      'coinsCents': 4500,
      'blindClosureEnabled': true,
      'policyRevision': 3,
    },
  'hasLateMovements': true,
  'canReview': canReview,
  'divergenceReview': {'revision': 2, 'status': 'PENDING'},
  'divergenceReviewHistory': [
    {
      'revision': 2,
      'status': 'PENDING',
      'justification': 'Segunda conferência solicitada',
      'authorName': 'Gerente',
      'createdAt': '2026-11-20T09:00:00Z',
    },
  ],
  'sales': {
    'items': [
      {
        'id': 'sale-1',
        'shortId': 'V-001',
        'soldAt': '2026-11-19T09:00:00Z',
        'paymentMethod': 'Dinheiro',
        'statusLabel': 'Ativa',
        'totalAmountCents': 15000,
      },
    ],
    'total': 3,
  },
  'movements': [
    {
      'title': 'Sangria',
      'amountCents': -1000,
      'paymentMethod': 'Dinheiro',
      'notes': 'Recolhimento do turno',
      'createdAt': '2026-11-19T12:00:00Z',
    },
  ],
});

class RecordingService extends OwnerApiService {
  RecordingService()
    : super(
        apiClient: OwnerApiClient(
          baseUrl: 'http://localhost',
          authStorage: OwnerAuthStorage(),
        ),
        authStorage: OwnerAuthStorage(),
      );
  final reviews = <Map<String, dynamic>>[];
  final policies = <bool>[];
  int? failure;
  @override
  Future<Map<String, dynamic>> reviewCashDivergence({
    required String cashSessionId,
    required Map<String, dynamic> body,
  }) async {
    reviews.add(Map.of(body));
    if (failure != null) {
      throw OwnerApiException(
        message: 'Falha ao confirmar.',
        statusCode: failure,
      );
    }
    return {};
  }

  @override
  Future<void> updateCashPolicy({required bool blindClosureEnabled}) async {
    policies.add(blindClosureEnabled);
  }
}

ProviderContainer container({
  OwnerCashSessionDetail? data,
  RecordingService? service,
  Future<OwnerCashSessionsReport> Function()? load,
}) => ProviderContainer(
  overrides: [
    ownerCashWorkspaceProvider.overrideWith(
      (ref) async => OwnerCashWorkspace.fromMap(cashWorkspacePayload()),
    ),
    ownerCashSessionsProvider.overrideWith(
      (ref) => load?.call() ?? Future.value(report()),
    ),
    ownerCashSessionDetailProvider.overrideWith(
      (ref, id) async => data ?? detail(),
    ),
    ownerSelectedCashSessionIdProvider.overrideWith((ref) => 'cash-1'),
    if (service != null) ownerApiServiceProvider.overrideWithValue(service),
  ],
);
Widget app(
  ProviderContainer c, {
  Widget child = const OwnerCashReportPage(),
  GlobalKey? capture,
}) => UncontrolledProviderScope(
  container: c,
  child: MaterialApp(
    theme: OwnerTheme.light(),
    home: Scaffold(
      body: RepaintBoundary(
        key: capture,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    ),
  ),
);
void main() {
  test('cash HTTP contracts use existing authorized owner endpoints', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = OwnerAuthStorage();
    await storage.saveTokens(
      accessToken: 'local-test-token',
      refreshToken: 'local-refresh',
    );
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(
        '{}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final service = OwnerApiService(
      apiClient: OwnerApiClient(
        baseUrl: 'http://localhost/api',
        authStorage: storage,
        httpClient: client,
      ),
      authStorage: storage,
    );
    await service.updateCashPolicy(blindClosureEnabled: true);
    expect(requests[0].method, 'PATCH');
    expect(requests[0].url.path, '/api/owner/receipt-settings');
    expect(jsonDecode(requests[0].body), {'cashBlindClosureEnabled': true});
    expect(requests[0].headers['Authorization'], 'Bearer local-test-token');
    final audit = {
      'requestId': 'a4ba8501-e90b-4ab6-8e3f-f16acf38c2b7',
      'expectedRevision': 2,
      'status': 'REVIEWED',
      'justification': 'Conferido com o operador',
    };
    await service.reviewCashDivergence(cashSessionId: 'cash-1', body: audit);
    expect(requests[1].method, 'POST');
    expect(
      requests[1].url.path,
      '/api/owner/reports/cash-sessions/cash-1/divergence-review',
    );
    expect(jsonDecode(requests[1].body), audit);
    await service.getCashWorkspace();
    expect(requests[2].method, 'GET');
    expect(requests[2].url.path, '/api/owner/reports/cash-workspace');
    expect(requests[2].headers['Authorization'], 'Bearer local-test-token');
  });

  test(
    'cash receipt parsing uses reconciled amount and server availability',
    () {
      final parsed = OwnerCashSessionsSummary.fromMap({
        'receiptBreakdownAvailable': true,
        'byPaymentMethod': [
          {'key': 'pix', 'label': 'Pix', 'amountCents': 9876},
        ],
      });
      expect(parsed.receiptBreakdownAvailable, true);
      expect(parsed.byPaymentMethod.single.totalAmountCents, 9876);
      expect(OwnerCashSessionsSummary.fromMap({}).openSessions, isNull);
    },
  );

  for (final width in [360.0, 390.0, 768.0, 1280.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('cash reflows $width font $scale', (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await (FontLoader('NotoSans')
              ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
              ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf')))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        final c = container();
        addTearDown(c.dispose);
        final capture = GlobalKey();
        await tester.pumpWidget(app(c, capture: capture));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('23'), findsOneWidget);
        expect(find.text('43'), findsOneWidget);
        expect(
          find.textContaining('Recebimentos por forma indisponíveis'),
          findsOneWidget,
        );
        expect(find.textContaining('Política 3'), findsNWidgets(2));
        await tester.ensureVisible(find.text('Fechamento original'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        {
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            await Directory('build/cash-review').create(recursive: true);
            await File(
              'build/cash-review/cash-${width.toInt()}-scale-${scale.toInt()}.png',
            ).writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
  }
  testWidgets('opening uses actual API amount', (tester) async {
    final c = container(data: detail());
    addTearDown(c.dispose);
    await tester.pumpWidget(app(c));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Contagem na abertura: R\$ 100,00'),
      findsOneWidget,
    );
  });

  testWidgets('provisional opening does not claim a confirmed money count', (
    tester,
  ) async {
    final c = container(data: detail(openingPending: true));
    addTearDown(c.dispose);
    await tester.pumpWidget(app(c));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Abertura aguardando conferência'),
      findsOneWidget,
    );
    expect(find.textContaining('Contagem na abertura:'), findsNothing);
  });

  testWidgets(
    'employee cash keeps pending counts distinct and shows participant acknowledgements',
    (tester) async {
      final c = container();
      addTearDown(c.dispose);
      await tester.pumpWidget(app(c));
      await tester.pumpAndSettle();
      expect(find.text('Caixa geral da empresa'), findsOneWidget);
      expect(find.text('Aguardando sincronização'), findsOneWidget);
      expect(find.text('Revisão necessária no aplicativo'), findsOneWidget);
      await tester.ensureVisible(find.text('Bia Atendimento'));
      await tester.tap(find.text('Bia Atendimento'));
      await tester.pumpAndSettle();
      expect(
        find.text('Declarado • conferência pendente: R\$ 190,00'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Tablet da Bia\nEnvio confirmado'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Caixa lateral\nAguardando envio'),
        findsOneWidget,
      );
      expect(find.text('Diferença confirmada: R\$ 0,00'), findsNothing);
      await tester.ensureVisible(
        find.text('Consultar sessão e histórico').first,
      );
      await tester.tap(find.text('Consultar sessão e histórico').first);
      await tester.pumpAndSettle();
      expect(c.read(ownerSelectedCashSessionIdProvider), 'cash-pending');
      expect(
        find.textContaining('O fechamento não está confirmado.'),
        findsOneWidget,
      );
      expect(find.text('Conferir divergência'), findsNothing);
    },
  );

  test(
    'workspace preserves backend summary and individual amount visibility independent of audit permission',
    () {
      final payload = cashWorkspacePayload();
      payload['summary'] = {
        ...payload['summary'] as Map<String, dynamic>,
        'openEmployees': 73,
      };
      final workspace = OwnerCashWorkspace.fromMap(payload);
      expect(workspace.summary.openEmployees, 73);
      expect(workspace.employees.first.canReview, false);
      expect(workspace.employees.first.expectedBalanceCents, 25000);
      expect(workspace.employees[1].isPending, true);
      expect(workspace.employees[1].differenceCents, isNull);
      expect(workspace.employees.last.detailSessionId, 'cash-closed');
      expect(
        OwnerCashWorkspace.fromMap({}).summary.totalExpectedBalanceCents,
        isNull,
      );
    },
  );

  testWidgets(
    'V3 sale operation gate directs to employee app and preserves read-only receipt',
    (tester) async {
      final original = detail();
      final v3sale = OwnerCashSessionSale.fromMap({
        'id': 'sale-v3',
        'shortId': 'V-3',
        'canCancel': false,
        'canReturn': false,
        'actionUnavailableReason': 'CASH_V3_REFUND_REQUIRES_OPERATOR_APP',
      });
      final c = container(
        data: OwnerCashSessionDetail(
          session: original.session,
          employee: original.employee,
          values: original.values,
          movements: original.movements,
          sales: OwnerCashSessionSalesPage(items: [v3sale], total: 1),
        ),
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(app(c));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Venda V-3'));
      await tester.tap(find.text('Venda V-3'));
      await tester.pumpAndSettle();
      expect(
        find.text('Faça a operação no app com funcionário autorizado.'),
        findsOneWidget,
      );
      expect(find.text('Ver comprovante'), findsOneWidget);
      expect(find.text('Cancelar venda'), findsNothing);
      expect(find.text('Registrar troca/devolucao'), findsNothing);
    },
  );

  testWidgets('legacy count and review stay unavailable', (tester) async {
    final c = container(data: detail(legacy: true));
    addTearDown(c.dispose);
    await tester.pumpWidget(app(c));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Detalhamento de contagem não disponível'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Conferência gerencial não disponível'),
      findsOneWidget,
    );
    expect(find.text('Pendente de conferência'), findsNothing);
    expect(find.text('Conferir divergência'), findsNothing);
  });
  testWidgets('server denies review controls', (tester) async {
    final c = container(data: detail(canReview: false));
    addTearDown(c.dispose);
    await tester.pumpWidget(app(c));
    await tester.pumpAndSettle();
    expect(find.text('Conferir divergência'), findsNothing);
  });
  testWidgets('audit validates reason and retains UUID on retry', (
    tester,
  ) async {
    final service = RecordingService()..failure = 503;
    final c = container(service: service);
    addTearDown(c.dispose);
    await tester.pumpWidget(app(c));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Conferir divergência'));
    await tester.tap(find.text('Conferir divergência'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar registro'));
    await tester.pumpAndSettle();
    expect(service.reviews, isEmpty);
    await tester.enterText(
      find.byType(TextField).last,
      'Conferência com o operador.',
    );
    await tester.tap(find.text('Confirmar registro'));
    await tester.pumpAndSettle();
    expect(service.reviews.single['expectedRevision'], 2);
    expect(service.reviews.single['status'], 'REVIEWED');
    expect(
      service.reviews.single['requestId'],
      matches(
        RegExp(
          r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
        ),
      ),
    );
    service.failure = null;
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(service.reviews[1], service.reviews[0]);
  });
  testWidgets('audit conflict requires explicit reload', (tester) async {
    final service = RecordingService()..failure = 409;
    final c = container(service: service);
    addTearDown(c.dispose);
    await tester.pumpWidget(app(c));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Conferir divergência'));
    await tester.tap(find.text('Conferir divergência'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      'Conferência realizada.',
    );
    await tester.tap(find.text('Confirmar registro'));
    await tester.pumpAndSettle();
    expect(find.text('Recarregar conferência'), findsOneWidget);
    expect(service.reviews, hasLength(1));
    await tester.tap(find.text('Recarregar conferência'));
    await tester.pumpAndSettle();
    expect(service.reviews, hasLength(1));
  });
  testWidgets('cash URL restores filters page and selection', (tester) async {
    final c = container();
    addTearDown(c.dispose);
    final router = GoRouter(
      initialLocation:
          '/reports/cash?startDate=2026-11-01&endDate=2026-11-20&status=with_difference&search=Ana&page=2&session=cash-1',
      routes: [
        GoRoute(
          path: '/reports/cash',
          builder: (context, state) => Scaffold(
            body: SingleChildScrollView(
              child: OwnerCashReportPage(query: state.uri.queryParameters),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(c.read(ownerCashSessionsPageProvider), 2);
    expect(c.read(ownerCashSessionsStatusProvider), 'with_difference');
    expect(c.read(ownerCashSessionsSearchProvider), 'Ana');
    expect(c.read(ownerReportStartDateProvider), '2026-11-01');
    await tester.ensureVisible(find.text('Próxima'));
    await tester.tap(find.text('Próxima'));
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.queryParameters['search'],
      'Ana',
    );
    router.go('/reports/cash?status=open&page=1');
    await tester.pumpAndSettle();
    expect(c.read(ownerSelectedCashSessionIdProvider), isNull);
    expect(c.read(ownerCashSessionsStatusProvider), 'open');
  });
  testWidgets('policy requires server permission and confirmation', (
    tester,
  ) async {
    final service = RecordingService();
    final c = container(service: service);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      app(
        c,
        child: OwnerCashPolicyCard(company: OwnerCompanySummary.fromMap({})),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );
    await tester.pumpWidget(
      app(
        c,
        child: OwnerCashPolicyCard(
          company: OwnerCompanySummary.fromMap({'canManageCashPolicy': true}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(service.policies, isEmpty);
    await tester.tap(find.text('Confirmar alteração'));
    await tester.pumpAndSettle();
    expect(service.policies, [true]);
  });
  testWidgets('loading empty permission error states', (tester) async {
    final pending = Completer<OwnerCashSessionsReport>();
    final c = container(load: () => pending.future);
    addTearDown(c.dispose);
    await tester.pumpWidget(app(c));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    pending.complete(OwnerCashSessionsReport.fromMap({}));
    await tester.pumpAndSettle();
    expect(find.text('Nenhum caixa encontrado'), findsOneWidget);
    final denied = container(
      load: () async => throw const OwnerApiException(
        message: 'Sem permissão para relatórios.',
        statusCode: 403,
      ),
    );
    addTearDown(denied.dispose);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(denied));
    await tester.pumpAndSettle();
    expect(
      find.text('Você não tem permissão para acessar este painel.'),
      findsOneWidget,
    );
  });
}
