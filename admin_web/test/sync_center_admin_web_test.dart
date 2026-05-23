import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/testing.dart';
import 'package:tatuzin_admin_web/src/core/auth/admin_auth_storage.dart';
import 'package:tatuzin_admin_web/src/core/auth/admin_providers.dart';
import 'package:tatuzin_admin_web/src/core/models/admin_models.dart';
import 'package:tatuzin_admin_web/src/core/models/admin_sync_center_models.dart';
import 'package:tatuzin_admin_web/src/core/network/admin_api_client.dart';
import 'package:tatuzin_admin_web/src/core/network/admin_api_service.dart';
import 'package:tatuzin_admin_web/src/features/sync_center/presentation/sync_center_pages.dart';

void main() {
  test('menu e router registram Sincronização sem owner_web', () {
    final shellSource = File(
      'lib/src/core/widgets/admin_shell_scaffold.dart',
    ).readAsStringSync();
    final routerSource = File(
      'lib/src/app/admin_web_router.dart',
    ).readAsStringSync();

    expect(shellSource, contains('Sincronização'));
    expect(routerSource, contains("path: '/sync'"));
    expect(routerSource, contains("path: '/sync/:companyId'"));
    expect(routerSource, contains("path: '/sync/:companyId/events/:eventId'"));
    expect(
      routerSource,
      contains("path: '/sync/:companyId/conflicts/:conflictId'"),
    );
    expect(routerSource, isNot(contains("path: '/owner'")));
  });

  test('AdminApiService exige reason e confirmationText antes da rede', () {
    final service = _baseService();

    expect(
      service.dryRunSyncEventReprocess(
        companyId: 'company-1',
        eventId: 'event-1',
        reason: '',
      ),
      throwsA(isA<AdminApiException>()),
    );
    expect(
      service.reprocessSyncEvent(
        companyId: 'company-1',
        eventId: 'event-1',
        reason: 'revisao',
        confirmationText: 'ERRADO',
      ),
      throwsA(isA<AdminApiException>()),
    );
    expect(
      service.archiveSyncConflict(
        companyId: 'company-1',
        conflictId: 'conflict-1',
        reason: 'revisao',
        confirmationText: '',
      ),
      throwsA(isA<AdminApiException>()),
    );
  });

  testWidgets('/sync lista empresas com problemas', (tester) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      _adminTestApp(
        service: _FakeSyncApiService(),
        child: const SyncCenterPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sincronização'), findsOneWidget);
    expect(find.text('café oliveira'), findsOneWidget);
    expect(find.text('Empresas com revisão'), findsOneWidget);
    expect(find.text('Conflitos abertos'), findsOneWidget);
    expect(find.text('Falhas'), findsWidgets);
    expect(find.text('Eventos pendentes'), findsOneWidget);
  });

  testWidgets('/sync/:companyId mostra resumo e abas', (tester) async {
    _setLargeViewport(tester);
    final service = _FakeSyncApiService();
    await tester.pumpWidget(
      _adminRouterTestApp(service: service, initialLocation: '/sync/company-1'),
    );
    await tester.pumpAndSettle();

    expect(find.text('café oliveira'), findsWidgets);
    expect(find.text('currentVersion'), findsOneWidget);
    expect(find.text('25'), findsWidgets);
    expect(find.text('Eventos'), findsOneWidget);
    expect(find.text('Conflitos'), findsWidgets);
    expect(find.text('Incidentes'), findsOneWidget);
    expect(find.text('Auditoria'), findsOneWidget);
  });

  testWidgets('tabela de eventos mostra ações e traduções seguras', (
    tester,
  ) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: _FakeSyncApiService(),
        initialLocation: '/sync/company-1',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ações'), findsWidgets);
    expect(find.text('Entidade'), findsWidgets);
    expect(find.text('Operação'), findsWidgets);
    expect(find.text('Módulo'), findsWidgets);
    expect(find.text('Baixa de estoque'), findsWidgets);
    expect(find.text('Sessão de caixa'), findsWidgets);
    expect(find.text('Perigoso'), findsWidgets);
    expect(find.text('Bloqueado por segurança'), findsWidgets);
    expect(find.text('Ver conflito'), findsOneWidget);
    expect(find.text('Dry-run'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Reprocessar'), findsOneWidget);

    final reprocessButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Reprocessar'),
    );
    expect(reprocessButton.enabled, isFalse);
    expect(find.textContaining('token-super-secreto'), findsNothing);
  });

  testWidgets(
    'cashSession reprocessável exige dry-run antes de write e recarrega',
    (tester) async {
      _setLargeViewport(tester);
      final service = _FakeSyncApiService();
      await tester.pumpWidget(
        _adminRouterTestApp(
          service: service,
          initialLocation: '/sync/company-1',
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dry-run'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'corrigir caixa');
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();

      expect(service.dryRunReprocessCalls, 1);
      expect(find.text('Resultado do dry-run'), findsOneWidget);
      expect(find.text('Pode executar'), findsOneWidget);
      expect(find.text('Sim'), findsOneWidget);

      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();

      final enabledReprocessButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Reprocessar'),
      );
      expect(enabledReprocessButton.enabled, isTrue);

      final reprocessFinder = find.widgetWithText(FilledButton, 'Reprocessar');
      await tester.ensureVisible(reprocessFinder);
      await tester.pumpAndSettle();
      await tester.tap(reprocessFinder);
      await tester.pumpAndSettle();
      expect(find.text('Motivo obrigatório'), findsOneWidget);
      expect(find.text('Texto de confirmação'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(0), 'corrigir caixa');
      await tester.enterText(find.byType(TextField).at(1), 'REPROCESSAR');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirmar'),
            )
            .enabled,
        isTrue,
      );
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();

      expect(service.reprocessCalls, 1);
      expect(service.lastReprocessReason, 'corrigir caixa');
      expect(service.fetchSummaryCalls, greaterThan(1));
      expect(service.fetchEventsCalls, greaterThan(1));
      expect(service.fetchConflictsCalls, greaterThan(1));
    },
  );

  testWidgets('tabela de conflitos permite dry-run antes de arquivar legado', (
    tester,
  ) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      _adminRouterTestApp(
        service: _FakeSyncApiService(),
        initialLocation: '/sync/company-1',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(Tab, 'Conflitos'));
    await tester.pumpAndSettle();

    expect(find.text('Arquivar legado'), findsWidgets);
    expect(find.text('Ajuste manual indisponível'), findsWidgets);
    final archiveButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Arquivar legado').first,
    );
    expect(archiveButton.enabled, isFalse);
  });

  testWidgets('conflito legado exibe classificação amigável e bloqueios', (
    tester,
  ) async {
    _setLargeViewport(tester);
    await tester.pumpWidget(
      _adminTestApp(
        service: _FakeSyncApiService(),
        child: const SyncConflictDetailPage(
          companyId: 'company-1',
          conflictId: 'conflict-legacy',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Evento legado'), findsWidgets);
    expect(
      find.text(
        'Evento antigo sem identificação remota segura. Não é recomendado reprocessar automaticamente. Revise estoque manualmente ou arquive como evento legado de teste.',
      ),
      findsWidgets,
    );
    expect(find.text('Dry-run arquivar'), findsOneWidget);
    expect(find.text('Arquivar legado'), findsOneWidget);
    expect(find.text('Payload preview'), findsOneWidget);
    expect(find.textContaining('productId: 5'), findsOneWidget);
    expect(find.textContaining('Bearer secret'), findsNothing);
    expect(find.textContaining('api-key-secret'), findsNothing);
  });

  testWidgets(
    'evento legado não mostra reprocessamento automático habilitado',
    (tester) async {
      _setLargeViewport(tester);
      await tester.pumpWidget(
        _adminTestApp(
          service: _FakeSyncApiService(),
          child: const SyncEventDetailPage(
            companyId: 'company-1',
            eventId: 'event-legacy',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Dry-run reprocessar'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Reprocessar'), findsNothing);
      expect(
        find.widgetWithText(OutlinedButton, 'Bloqueado por segurança'),
        findsOneWidget,
      );
      expect(find.text('Reprocessamento automático bloqueado'), findsOneWidget);
      expect(find.textContaining('token-super-secreto'), findsNothing);
      await tester.tap(find.text('Payload sanitizado avançado'));
      await tester.pumpAndSettle();
      expect(find.textContaining('[redacted]'), findsWidgets);
    },
  );

  testWidgets('modal de arquivamento exige reason e confirmationText', (
    tester,
  ) async {
    _setLargeViewport(tester);
    final service = _FakeSyncApiService();
    await tester.pumpWidget(
      _adminTestApp(
        service: service,
        child: const SyncConflictDetailPage(
          companyId: 'company-1',
          conflictId: 'conflict-legacy',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final disabledArchiveButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Arquivar legado'),
    );
    expect(disabledArchiveButton.enabled, isFalse);

    await tester.tap(find.text('Dry-run arquivar'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      'evento legado de teste',
    );
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(service.dryRunArchiveCalls, 1);
    expect(find.text('Resultado do dry-run'), findsOneWidget);
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Arquivar legado'));
    await tester.pumpAndSettle();

    expect(find.text('Digite ARQUIVAR para confirmar.'), findsOneWidget);
    expect(find.text('Motivo obrigatório'), findsOneWidget);
    expect(find.text('Texto de confirmação'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirmar'))
          .enabled,
      isFalse,
    );

    await tester.enterText(
      find.byType(TextField).at(0),
      'evento legado de teste',
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirmar'))
          .enabled,
      isFalse,
    );

    await tester.enterText(find.byType(TextField).at(1), 'ERRADO');
    await tester.pumpAndSettle();
    expect(
      find.text('Digite ARQUIVAR para liberar a confirmacao.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirmar'))
          .enabled,
      isFalse,
    );

    await tester.enterText(find.byType(TextField).at(1), 'ARQUIVAR');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirmar'))
          .enabled,
      isTrue,
    );

    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();

    expect(service.archiveCalls, 1);
    expect(service.lastArchiveReason, 'evento legado de teste');
  });

  testWidgets('dry-run bloqueado mostra motivo e nao libera arquivamento', (
    tester,
  ) async {
    _setLargeViewport(tester);
    final service = _FakeSyncApiService(archiveDryRunAllowed: false);
    await tester.pumpWidget(
      _adminTestApp(
        service: service,
        child: const SyncConflictDetailPage(
          companyId: 'company-1',
          conflictId: 'conflict-legacy',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dry-run arquivar'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      'avaliar conflito legado',
    );
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(find.text('Resultado do dry-run'), findsOneWidget);
    expect(find.text('Conflito bloqueado para arquivamento.'), findsWidgets);
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();

    final archiveButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Arquivar legado'),
    );
    expect(archiveButton.enabled, isFalse);
  });
}

AdminApiService _baseService() {
  final storage = AdminAuthStorage();
  return AdminApiService(
    apiClient: AdminApiClient(
      baseUrl: 'https://api.test/api',
      authStorage: storage,
      httpClient: MockClient((request) async {
        throw UnimplementedError(request.url.toString());
      }),
    ),
    authStorage: storage,
  );
}

void _setLargeViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(2400, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Widget _adminTestApp({
  required AdminApiService service,
  required Widget child,
}) {
  return ProviderScope(
    overrides: [adminApiServiceProvider.overrideWithValue(service)],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

Widget _adminRouterTestApp({
  required AdminApiService service,
  required String initialLocation,
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/sync',
        builder: (context, state) => const Scaffold(body: SyncCenterPage()),
      ),
      GoRoute(
        path: '/sync/:companyId',
        builder: (context, state) => Scaffold(
          body: SyncCompanyPage(
            companyId: state.pathParameters['companyId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/sync/:companyId/events/:eventId',
        builder: (context, state) => Scaffold(
          body: SyncEventDetailPage(
            companyId: state.pathParameters['companyId'] ?? '',
            eventId: state.pathParameters['eventId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/sync/:companyId/conflicts/:conflictId',
        builder: (context, state) => Scaffold(
          body: SyncConflictDetailPage(
            companyId: state.pathParameters['companyId'] ?? '',
            conflictId: state.pathParameters['conflictId'] ?? '',
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

class _FakeSyncApiService extends AdminApiService {
  _FakeSyncApiService({this.archiveDryRunAllowed = true})
    : super(
        apiClient: AdminApiClient(
          baseUrl: 'https://api.test/api',
          authStorage: AdminAuthStorage(),
          httpClient: MockClient((request) async {
            throw UnimplementedError(request.url.toString());
          }),
        ),
        authStorage: AdminAuthStorage(),
      );

  final bool archiveDryRunAllowed;

  int archiveCalls = 0;
  int dryRunArchiveCalls = 0;
  int dryRunReprocessCalls = 0;
  int reprocessCalls = 0;
  int fetchSummaryCalls = 0;
  int fetchEventsCalls = 0;
  int fetchConflictsCalls = 0;
  String? lastArchiveReason;
  String? lastReprocessReason;

  @override
  Future<AdminPaginatedResult<AdminSyncCenterCompany>>
  fetchSyncCenterCompanies({AdminSyncCenterCompaniesQuery? query}) async {
    return AdminPaginatedResult<AdminSyncCenterCompany>(
      items: [AdminSyncCenterCompany.fromMap(_companyMap())],
      pagination: const AdminPaginationMeta(
        page: 1,
        pageSize: 20,
        total: 1,
        count: 1,
        hasNext: false,
        hasPrevious: false,
      ),
      filters: const {},
      sort: const AdminSortMeta(by: 'companyName', direction: 'asc'),
    );
  }

  @override
  Future<AdminSyncCenterCompanySummary> fetchSyncCenterCompanySummary(
    String companyId,
  ) async {
    fetchSummaryCalls += 1;
    return AdminSyncCenterCompanySummary.fromMap({
      'company': {
        'companyId': companyId,
        'companyName': 'café oliveira',
        'plan': 'PRO',
      },
      'syncState': {'currentVersion': '25', 'serverFirstSnapshotVersion': '0'},
      'eventStatusCounts': {
        'accepted': 17,
        'duplicate': 3,
        'conflict': 8,
        'failed': 1,
        'pending': 0,
        'rejected': 0,
      },
      'entityOperationStatusCounts': [
        {
          'entity': 'stockDeduction',
          'operation': 'create',
          'status': 'conflict',
          'count': 8,
        },
        {
          'entity': 'cashSession',
          'operation': 'update',
          'status': 'failed',
          'count': 1,
        },
      ],
      'conflictCounts': [
        {
          'code': 'STOCK_VARIANT_NOT_FOUND',
          'entity': 'stockDeduction',
          'status': 'open',
          'count': 8,
        },
      ],
      'incidentCounts': const [],
      'latestEvents': [_legacyEventMap(), _cashEventMap()],
      'latestConflicts': [_legacyConflictMap()],
      'latestIncidents': [
        {
          'id': 'incident-1',
          'code': 'SYNC_MATERIALIZATION_FAILED',
          'message': 'Falha inesperada ao materializar evento operacional.',
          'severity': 'error',
          'createdAt': '2026-05-06T20:45:01.211999Z',
        },
      ],
      'recommendation':
          'Existem falhas e conflitos. Use dry-run antes de qualquer ação.',
      'requiresReview': true,
    });
  }

  @override
  Future<AdminPaginatedResult<AdminSyncCenterEvent>> fetchSyncCenterEvents({
    required AdminSyncCenterEventsQuery query,
  }) async {
    fetchEventsCalls += 1;
    return AdminPaginatedResult<AdminSyncCenterEvent>(
      items: [
        AdminSyncCenterEvent.fromMap(_legacyEventMap()),
        AdminSyncCenterEvent.fromMap(_cashEventMap()),
        AdminSyncCenterEvent.fromMap(_dangerousEventMap()),
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
    );
  }

  @override
  Future<AdminPaginatedResult<AdminSyncCenterConflict>>
  fetchSyncCenterConflicts({
    required AdminSyncCenterConflictsQuery query,
  }) async {
    fetchConflictsCalls += 1;
    return AdminPaginatedResult<AdminSyncCenterConflict>(
      items: [AdminSyncCenterConflict.fromMap(_legacyConflictMap())],
      pagination: const AdminPaginationMeta(
        page: 1,
        pageSize: 20,
        total: 1,
        count: 1,
        hasNext: false,
        hasPrevious: false,
      ),
      filters: const {},
      sort: const AdminSortMeta(by: 'createdAt', direction: 'desc'),
    );
  }

  @override
  Future<AdminSyncCenterEventDetail> fetchSyncCenterEventDetail({
    required String companyId,
    required String eventId,
  }) async {
    final event = eventId == 'event-cash' ? _cashEventMap() : _legacyEventMap();
    return AdminSyncCenterEventDetail.fromMap({
      'event': {
        ...event,
        'payload': {
          ...event['safePayloadPreview'] as Map<String, dynamic>,
          'token': '[redacted]',
        },
      },
      'conflict': eventId == 'event-cash' ? null : _legacyConflictMap(),
      'incidents': const [],
      'classification': event['classification'],
      'recommendedAction': event['recommendedAction'],
      'canReprocess': event['canReprocess'],
      'canArchive': event['canArchive'],
      'risks': ['Reprocessar pode alterar estoque remoto.'],
      'blockers': event['canReprocess'] == true
          ? const []
          : ['O payload usa id local em campo remoto.'],
      'message':
          'Evento antigo sem identificação remota segura. Não é recomendado reprocessar automaticamente. Revise estoque manualmente ou arquive como evento legado de teste.',
    });
  }

  @override
  Future<AdminSyncCenterConflictDetail> fetchSyncCenterConflictDetail({
    required String companyId,
    required String conflictId,
  }) async {
    return AdminSyncCenterConflictDetail.fromMap({
      'conflict': {
        ..._legacyConflictMap(),
        'payload': _legacyPayload(),
        'resolution': const {},
      },
      'event': {..._legacyEventMap(), 'payload': _legacyPayload()},
      'incidents': const [],
      'classification': 'IRRECOVERABLE_LEGACY_EVENT',
      'recommendedAction': 'ARCHIVE_LEGACY',
      'canReprocess': false,
      'canArchive': true,
      'canCreateManualStockAdjustment': false,
      'risks': ['Baixa automática poderia atingir produto errado.'],
      'blockers': ['O payload usa id local em campo remoto.'],
      'message':
          'Evento antigo sem identificação remota segura. Não é recomendado reprocessar automaticamente. Revise estoque manualmente ou arquive como evento legado de teste.',
    });
  }

  @override
  Future<AdminSyncCenterDryRunResult> dryRunSyncEventReprocess({
    required String companyId,
    required String eventId,
    required String reason,
  }) async {
    dryRunReprocessCalls += 1;
    if (eventId == 'event-cash') {
      return AdminSyncCenterDryRunResult.fromMap({
        'wouldReprocess': true,
        'classification': 'REPROCESSABLE',
        'expectedAction': 'REPROCESS',
        'blockers': const [],
        'risks': ['Atualiza sessão de caixa de forma idempotente.'],
        'message': 'Evento pode ser reprocessado com segurança.',
      });
    }
    return AdminSyncCenterDryRunResult.fromMap({
      'wouldReprocess': false,
      'classification': 'IRRECOVERABLE_LEGACY_EVENT',
      'blockers': ['Bloqueado por segurança.'],
      'risks': const [],
      'message': 'Dry-run concluído. Evento bloqueado.',
    });
  }

  @override
  Future<AdminSyncCenterActionResult> reprocessSyncEvent({
    required String companyId,
    required String eventId,
    required String reason,
    required String confirmationText,
  }) async {
    reprocessCalls += 1;
    lastReprocessReason = reason;
    return AdminSyncCenterActionResult.fromMap({
      'ok': true,
      'message': 'Evento reprocessado.',
    });
  }

  @override
  Future<AdminSyncCenterDryRunResult> dryRunSyncConflictArchive({
    required String companyId,
    required String conflictId,
    required String reason,
  }) async {
    dryRunArchiveCalls += 1;
    return AdminSyncCenterDryRunResult.fromMap({
      'wouldArchive': archiveDryRunAllowed,
      'classification': 'IRRECOVERABLE_LEGACY_EVENT',
      'expectedConfirmationText': 'ARQUIVAR',
      'blockers': archiveDryRunAllowed
          ? const []
          : const ['Conflito bloqueado para arquivamento.'],
      'risks': ['Nenhum dado operacional será alterado.'],
      'message': archiveDryRunAllowed
          ? 'Conflito pode ser arquivado com auditoria.'
          : 'Conflito bloqueado para arquivamento.',
    });
  }

  @override
  Future<AdminSyncCenterActionResult> archiveSyncConflict({
    required String companyId,
    required String conflictId,
    required String reason,
    required String confirmationText,
    String? note,
  }) async {
    archiveCalls += 1;
    lastArchiveReason = reason;
    return AdminSyncCenterActionResult.fromMap({
      'ok': true,
      'message': 'Conflito arquivado com auditoria.',
    });
  }
}

Map<String, dynamic> _companyMap() {
  return {
    'companyId': 'company-1',
    'companyName': 'café oliveira',
    'plan': 'PRO',
    'syncStatus': 'failed',
    'currentVersion': '25',
    'serverFirstSnapshotVersion': '0',
    'acceptedCount': 17,
    'duplicateCount': 3,
    'pendingCount': 0,
    'conflictCount': 8,
    'failedCount': 1,
    'openConflictCount': 8,
    'incidentCount': 1,
    'lastEventAt': '2026-05-06T20:45:01.211999Z',
    'lastIncidentAt': '2026-05-06T20:45:01.211999Z',
    'requiresReview': true,
  };
}

Map<String, dynamic> _legacyEventMap() {
  return {
    'id': 'event-legacy',
    'eventId': 'event-legacy-client',
    'feature': 'pdv',
    'entity': 'stockDeduction',
    'operation': 'create',
    'entityLocalId': '1778111101212016-10299ac7:5:0',
    'entityServerId': null,
    'status': 'conflict',
    'serverVersion': '25',
    'rejectionCode': 'STOCK_VARIANT_NOT_FOUND',
    'rejectionMessage':
        'Produto/variante remoto não encontrado para estoque operacional.',
    'occurredAt': '2026-05-06T20:45:01.211999Z',
    'createdAt': '2026-05-06T20:45:01.211999Z',
    'updatedAt': '2026-05-06T20:45:01.211999Z',
    'materializedAt': null,
    'relatedConflictId': 'conflict-legacy',
    'classification': 'IRRECOVERABLE_LEGACY_EVENT',
    'recommendedAction': 'ARCHIVE_LEGACY',
    'canReprocess': false,
    'canArchive': true,
    'safePayloadPreview': _legacyPayload(),
  };
}

Map<String, dynamic> _cashEventMap() {
  return {
    'id': 'event-cash',
    'eventId': 'event-cash-client',
    'feature': 'cash',
    'entity': 'cashSession',
    'operation': 'update',
    'entityLocalId': '1778110868189821-7df2cc20',
    'entityServerId': null,
    'status': 'failed',
    'serverVersion': null,
    'rejectionCode': 'SYNC_MATERIALIZATION_FAILED',
    'rejectionMessage': 'Falha inesperada.',
    'occurredAt': '2026-05-06T20:41:08.169407Z',
    'createdAt': '2026-05-06T20:41:08.169407Z',
    'updatedAt': '2026-05-06T20:41:08.169407Z',
    'materializedAt': null,
    'classification': 'REPROCESSABLE',
    'recommendedAction': 'REPROCESS',
    'canReprocess': true,
    'canArchive': false,
    'safePayloadPreview': {
      'uuid': '1778110868189821-7df2cc20',
      'status': 'aberto',
      'openedAt': '2026-05-06T20:41:08.169407',
      'expectedBalanceCents': 130400,
    },
  };
}

Map<String, dynamic> _dangerousEventMap() {
  return {
    'id': 'event-dangerous',
    'eventId': 'event-dangerous-client',
    'feature': 'pdv',
    'entity': 'unknownEntity',
    'operation': 'create',
    'entityLocalId': 'dangerous-local',
    'entityServerId': null,
    'status': 'failed',
    'serverVersion': null,
    'rejectionCode': 'SENSITIVE_PAYLOAD',
    'rejectionMessage': 'Payload sensível bloqueado.',
    'occurredAt': '2026-05-06T20:41:08.169407Z',
    'createdAt': '2026-05-06T20:41:08.169407Z',
    'updatedAt': '2026-05-06T20:41:08.169407Z',
    'materializedAt': null,
    'classification': 'DANGEROUS',
    'recommendedAction': 'CONTACT_SUPPORT',
    'canReprocess': false,
    'canArchive': false,
    'safePayloadPreview': {'status': '[redacted]'},
  };
}

Map<String, dynamic> _legacyConflictMap() {
  return {
    'conflictId': 'conflict-legacy',
    'syncEventId': 'event-legacy',
    'entity': 'stockDeduction',
    'entityLocalId': '1778111101212016-10299ac7:5:0',
    'entityServerId': null,
    'code': 'STOCK_VARIANT_NOT_FOUND',
    'message':
        'Produto/variante remoto não encontrado para estoque operacional.',
    'status': 'open',
    'createdAt': '2026-05-06T20:45:01.211999Z',
    'updatedAt': '2026-05-06T20:45:01.211999Z',
    'resolvedAt': null,
    'classification': 'IRRECOVERABLE_LEGACY_EVENT',
    'recommendedAction': 'ARCHIVE_LEGACY',
    'canReprocess': false,
    'canArchive': true,
    'canCreateManualStockAdjustment': false,
    'safePayloadPreview': _legacyPayload(),
  };
}

Map<String, dynamic> _legacyPayload() {
  return {
    'saleUuid': '1778111101212016-10299ac7',
    'saleLocalId': 23,
    'productId': 5,
    'productVariantId': null,
    'quantityDeltaMil': -21000,
    'stockBeforeMil': 200000,
    'stockAfterMil': 179000,
    'occurredAt': '2026-05-06T20:45:01.211999',
  };
}
