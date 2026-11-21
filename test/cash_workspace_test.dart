import 'package:tatuzin/modules/caixa/presentation/pages/cash_opening_page.dart';
import 'package:tatuzin/modules/caixa/domain/entities/cash_session.dart';
import 'package:tatuzin/modules/caixa/data/cash_database_support.dart';
import 'package:tatuzin/modules/caixa/presentation/pages/cash_count_page.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:tatuzin/app/routes/modules/cash_routes.dart';
import 'package:tatuzin/app/routes/route_names.dart';
import 'package:tatuzin/app/core/theme/app_theme.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tatuzin/app/core/database/app_database.dart';
import 'package:tatuzin/app/core/app_context/app_operational_context.dart';
import 'package:tatuzin/app/core/config/app_environment.dart';
import 'package:tatuzin/app/core/session/app_session.dart';
import 'package:tatuzin/app/core/sync/sqlite_operational_sync_queue_repository.dart';
import 'package:tatuzin/modules/caixa/data/sqlite_cash_repository.dart';
import 'package:tatuzin/modules/caixa/data/cash_workspace_store.dart';
import 'package:tatuzin/modules/caixa/domain/entities/cash_closure_preview.dart';

import 'package:tatuzin/modules/caixa/presentation/providers/cash_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUpAll(() async {
    final noto = FontLoader('NotoSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    await noto.load();
    final material = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await material.load();
  });
  late AppDatabase appDb;
  late SqliteCashRepository repository;
  setUp(() {
    appDb = AppDatabase.forIsolationKey(
      'cash-workspace-${DateTime.now().microsecondsSinceEpoch}',
    );
    repository = SqliteCashRepository(
      appDb,
      AppOperationalContext(
        environment: const AppEnvironment.localDefault(),
        session: AppSession.localDefault(),
      ),
    );
  });
  tearDown(() async {
    await appDb.close();
  });

  test(
    'blank is distinct from explicit zero and malformed values are rejected',
    () {
      expect(parseCashAmount(''), isNull);
      expect(parseCashAmount('0'), 0);
      expect(parseCashAmount('12,34'), 1234);
      expect(parseCashAmount('21474836,48'), isNull);
      expect(parseCashAmount('21474836,47'), 2147483647);
      for (final raw in ['-1', 'abc', '1,234', '1.2.3', '1e3']) {
        expect(parseCashAmount(raw), isNull);
      }
    },
  );
  test(
    'stale movement snapshot requires review; exact retry never closes next session',
    () async {
      final opened = await repository.openSession(initialFloatCents: 1000);
      final stale = await repository.prepareClosure(opened.uuid);
      final db = await appDb.database;
      await db.update(
        'caixa_sessoes',
        {'saldo_esperado_centavos': 1200},
        where: 'id = ?',
        whereArgs: [opened.id],
      );
      await expectLater(
        repository.commitClosure(preview: stale, countedBalanceCents: 1000),
        throwsA(anything),
      );
      final preview = await repository.prepareClosure(opened.uuid);
      await expectLater(
        repository.commitClosure(preview: preview, countedBalanceCents: 1000),
        throwsA(anything),
      );
      final closed = await repository.commitClosure(
        preview: preview,
        countedBalanceCents: 1000,
        reason: 'Falta de troco',
      );
      final next = await repository.openSession(initialFloatCents: 0);
      final retry = await repository.commitClosure(
        preview: preview,
        countedBalanceCents: 1000,
        reason: 'Falta de troco',
      );
      await db.update(
        'caixa_sessoes',
        {'saldo_esperado_centavos': 99999, 'diferenca_centavos': 123},
        where: 'id = ?',
        whereArgs: [opened.id],
      );
      final frozen = (await repository.listSessions()).firstWhere(
        (s) => s.uuid == opened.uuid,
      );
      expect(frozen.expectedBalanceCents, 1200);
      expect(frozen.differenceCents, -200);
      expect(retry.uuid, closed.uuid);
      expect((await repository.getCurrentSession())!.uuid, next.uuid);
      final items = await SqliteOperationalSyncQueueRepository(
        appDb,
      ).listPending(limit: 20, retryOnly: false, ignoreRetryBackoff: true);
      final closures = items.where(
        (e) =>
            e.event.entityLocalId == opened.uuid &&
            e.event.payload['closedAt'] != null,
      );
      expect(closures, hasLength(1));
      expect(
        (closures.single.event.payload['closingDetails'] as Map)['reason'],
        'Falta de troco',
      );
    },
  );
  test(
    'legacy opening closes with legacy wire fields and local frozen snapshot',
    () async {
      final opened = await repository.openSession(initialFloatCents: 100);
      final db = await appDb.database;
      await db.delete(
        'configuracoes',
        where: 'chave = ?',
        whereArgs: ['cash.opening:${opened.uuid}'],
      );
      // A legacy session already exists remotely; remove the artificial fixture's create event.
      await db.delete('operational_sync_events');
      final preview = await repository.prepareClosure(opened.uuid);
      expect(preview.session.blindClosureEnabled, isFalse);
      await repository.commitClosure(
        preview: preview,
        countedBalanceCents: 100,
      );
      final events = await SqliteOperationalSyncQueueRepository(
        appDb,
      ).listPending(limit: 20, retryOnly: false, ignoreRetryBackoff: true);
      final payload = events.single.event.payload;
      expect(payload.containsKey('openingDetails'), isFalse);
      expect(payload.containsKey('closingDetails'), isFalse);
      expect(payload['countedBalanceCents'], 100);
      expect(payload['status'], 'fechado');
      expect(
        (await CashWorkspaceStore.read(
          db,
          'cash.closing:${opened.uuid}',
        ))['expectedBalanceCents'],
        100,
      );
    },
  );

  test(
    'provisional auto opening syncs flag and confirms count exactly once',
    () async {
      final db = await appDb.database;
      await CashWorkspaceStore.write(db, 'cash.policy', {
        'cashBlindClosureEnabled': true,
        'cashPolicyRevision': 3,
      });
      await db.transaction(
        (txn) => CashDatabaseSupport.ensureOpenSession(
          txn,
          timestamp: DateTime.now(),
        ),
      );
      final provisional = (await repository.getCurrentSession())!;
      expect(provisional.awaitingInitialFloatConfirmation, isTrue);
      const count = CashCountResult(denominations: {1000: 2}, coinsCents: 50);
      final confirmed = await repository.confirmAutoOpenedSession(
        initialFloatCents: 2050,
        count: count,
      );
      expect(confirmed.awaitingInitialFloatConfirmation, isFalse);
      expect(confirmed.initialFloatCents, 2050);
      expect(confirmed.blindClosureEnabled, isTrue);
      await expectLater(
        repository.confirmAutoOpenedSession(initialFloatCents: 999),
        throwsA(anything),
      );
      expect((await repository.getCurrentSession())!.initialFloatCents, 2050);
      final opening = await CashWorkspaceStore.read(
        db,
        'cash.opening:${provisional.uuid}',
      );
      expect(opening['denominations'], [
        {'valueCents': 1000, 'quantity': 2},
      ]);
      expect(opening['coinsCents'], 50);
      expect(opening['policyRevision'], 3);
      final events = await SqliteOperationalSyncQueueRepository(
        appDb,
      ).listPending(limit: 20, retryOnly: false, ignoreRetryBackoff: true);
      final cashEvents = events
          .where((e) => e.event.entity == 'cashSession')
          .toList();
      expect(cashEvents, hasLength(2));
      expect(
        cashEvents.first.event.payload['awaitingInitialFloatConfirmation'],
        isTrue,
      );
      expect(
        (cashEvents.first.event.payload['openingDetails']
            as Map)['countedAmountCents'],
        0,
      );
      expect(
        cashEvents.last.event.payload['awaitingInitialFloatConfirmation'],
        isFalse,
      );
      expect(
        (cashEvents.last.event.payload['openingDetails']
            as Map)['countedAmountCents'],
        2050,
      );
    },
  );

  test(
    'outbox failure rolls back closure and draft; file reopen retries once',
    () async {
      final session = await repository.openSession(initialFloatCents: 0);
      final preview = await repository.prepareClosure(session.uuid);
      await repository.saveDraft('close:${session.uuid}', {'amount': '0'});
      final db = await appDb.database;
      await db.execute(
        "CREATE TRIGGER fail_closure BEFORE INSERT ON operational_sync_events WHEN NEW.operation = 'update' BEGIN SELECT RAISE(ABORT, 'injected outbox failure'); END",
      );
      await expectLater(
        repository.commitClosure(preview: preview, countedBalanceCents: 0),
        throwsA(anything),
      );
      expect((await repository.getCurrentSession())!.uuid, session.uuid);
      expect(
        (await CashWorkspaceStore.read(db, 'cash.closing:${session.uuid}')),
        isEmpty,
      );
      expect(
        (await repository.loadDraft('close:${session.uuid}'))['amount'],
        '0',
      );
      await db.execute('DROP TRIGGER fail_closure');
      await repository.commitClosure(preview: preview, countedBalanceCents: 0);
      final next = await repository.openSession(initialFloatCents: 100);
      await appDb.close();
      final recreated = SqliteCashRepository(
        appDb,
        AppOperationalContext(
          environment: const AppEnvironment.localDefault(),
          session: AppSession.localDefault(),
        ),
      );
      final retry = await recreated.commitClosure(
        preview: preview,
        countedBalanceCents: 0,
      );
      expect(retry.uuid, session.uuid);
      expect((await recreated.getCurrentSession())!.uuid, next.uuid);
      final events = await SqliteOperationalSyncQueueRepository(
        appDb,
      ).listPending(limit: 20, retryOnly: false, ignoreRetryBackoff: true);
      expect(
        events.where(
          (e) =>
              e.event.entityLocalId == session.uuid &&
              e.event.payload['closedAt'] != null,
        ),
        hasLength(1),
      );
    },
  );

  test(
    'policy snapshots remain frozen and drafts survive repository recreation',
    () async {
      final db = await appDb.database;
      await CashWorkspaceStore.write(db, 'cash.policy', {
        'cashBlindClosureEnabled': true,
        'cashPolicyRevision': 7,
      });
      final opened = await repository.openSession(initialFloatCents: 0);
      expect(opened.blindClosureEnabled, isTrue);
      await repository.saveDraft('close:${opened.uuid}', {
        'amount': '0',
        'reason': 'Contagem física',
      });
      await appDb.close();
      final recreated = SqliteCashRepository(
        appDb,
        AppOperationalContext(
          environment: const AppEnvironment.localDefault(),
          session: AppSession.localDefault(),
        ),
      );
      expect(
        (await recreated.loadDraft('close:${opened.uuid}'))['amount'],
        '0',
      );
      final reopenedDb = await appDb.database;
      await CashWorkspaceStore.write(reopenedDb, 'cash.policy', {
        'cashBlindClosureEnabled': false,
        'cashPolicyRevision': 8,
      });
      final preview = await recreated.prepareClosure(opened.uuid);
      expect(preview.session.blindClosureEnabled, isTrue);
      await expectLater(
        recreated.commitClosure(preview: preview, countedBalanceCents: 0),
        throwsA(anything),
      );
      await recreated.commitClosure(
        preview: preview,
        countedBalanceCents: 0,
        reason: 'Contagem física',
      );
      expect(await recreated.loadDraft('close:${opened.uuid}'), isEmpty);
      final saved = await CashWorkspaceStore.read(
        reopenedDb,
        'cash.closing:${opened.uuid}',
      );
      expect(saved['policyRevision'], 7);
      expect(jsonEncode(saved), contains('Contagem física'));
    },
  );

  testWidgets('auto-open close requires opening count then reviews real closure', (
    tester,
  ) async {
    final session = (await tester.runAsync(() async {
      final db = await appDb.database;
      await db.transaction(
        (txn) => CashDatabaseSupport.ensureOpenSession(
          txn,
          timestamp: DateTime.now(),
        ),
      );
      return (await repository.getCurrentSession())!;
    }))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localCashRepositoryProvider.overrideWithValue(repository),
          cashActionControllerProvider.overrideWith(
            () => _LocalConfirmController(repository),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CashOpeningPage(autoOpenedSession: session),
                  ),
                ),
                child: const Text('Caixa inicial'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Caixa inicial'));
    await tester.pumpAndSettle();
    await _flushCashIo(tester);
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
    await _flushCashIo(tester);
    await tester.ensureVisible(find.text('Conferir e fechar este caixa'));
    await tester.tap(find.text('Conferir e fechar este caixa'));
    await tester.pumpAndSettle();
    await _flushCashIo(tester);
    expect(
      find.text(
        'Confira o troco inicial antes de fechar. Informe o valor, inclusive quando for zero.',
      ),
      findsOneWidget,
    );
    expect(
      (await tester.runAsync(
        () => repository.getCurrentSession(),
      ))!.awaitingInitialFloatConfirmation,
      isTrue,
    );
    await tester.ensureVisible(find.byKey(const Key('cash-opening-amount')));
    await tester.runAsync(() async {
      await tester.enterText(
        find.byKey(const Key('cash-opening-amount')),
        '2,00',
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.ensureVisible(find.text('Conferir e fechar este caixa'));
    await tester.runAsync(() async {
      await tester.tap(find.text('Conferir e fechar este caixa'));
      await Future<void>.delayed(const Duration(milliseconds: 120));
    });
    await tester.pumpAndSettle();
    await _flushCashIo(tester);
    expect(find.text('Conferir e fechar caixa'), findsOneWidget);
    final confirmed = (await tester.runAsync(
      () => repository.getCurrentSession(),
    ))!;
    expect(confirmed.awaitingInitialFloatConfirmation, isFalse);
    expect(confirmed.initialFloatCents, 200);
    await tester.runAsync(() async {
      await tester.enterText(
        find.byKey(const Key('cash-counted-amount')),
        '2,00',
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('cash-close-footer')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    await _flushCashIo(tester);
    if (find.text('Fechar caixa').evaluate().isEmpty) {
      debugPrint(
        'Cash review debug: ${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).toList()}',
      );
    }
    expect(find.text('Fechar caixa'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('cash-close-footer')));
      await tester.tap(find.byKey(const Key('cash-close-footer')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    await _flushCashIo(tester);
    expect(find.text('Caixa fechado'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cash-close-footer')));
    await tester.pumpAndSettle();
    await _flushCashIo(tester);
    expect(find.text('Caixa inicial'), findsOneWidget);
    expect(await tester.runAsync(() => repository.getCurrentSession()), isNull);
  });

  testWidgets(
    'calculator preserves raw quantities after dismissal and returns typed total',
    (tester) async {
      Map<String, dynamic>? draft;
      CashCountResult? accepted;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  accepted = await Navigator.of(context).push<CashCountResult>(
                    MaterialPageRoute(
                      builder: (_) => CashCountPage(
                        initialDraft: draft,
                        onDraftChanged: (value) => draft = value,
                      ),
                    ),
                  );
                },
                child: const Text('Contar'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Contar'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '2');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect((draft!['quantities'] as Map)['20000'], '2');
      await tester.tap(find.text('Contar'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '2',
      );
      await tester.tap(find.text('Usar total na conferência'));
      await tester.pumpAndSettle();
      expect(accepted!.totalCents, 40000);
      expect(accepted!.denominations[20000], 2);
    },
  );

  for (final size in [const Size(360, 640), const Size(390, 800)]) {
    for (final scale in [1.0, 2.0]) {
      for (final brightness in Brightness.values) {
        testWidgets(
          'footer reachable $size font $scale $brightness with keyboard',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            tester.view.viewInsets = const FakeViewPadding(bottom: 280);
            tester.view.padding = const FakeViewPadding(bottom: 24);
            addTearDown(tester.view.reset);
            final session = (await tester.runAsync(
              () => repository.openSession(initialFloatCents: 12345),
            ))!;
            final router = GoRouter(
              initialLocation: '/test',
              routes: [
                GoRoute(
                  path: '/test',
                  builder: (_, __) => const SizedBox.shrink(),
                ),
                ...buildCashRoutes(),
              ],
            );
            addTearDown(router.dispose);
            router.pushNamed(AppRouteNames.cashClose, extra: session);
            await tester.pumpWidget(
              ProviderScope(
                overrides: [
                  localCashRepositoryProvider.overrideWithValue(repository),
                ],
                child: MaterialApp.router(
                  routerConfig: router,
                  theme: brightness == Brightness.dark
                      ? AppTheme.dark()
                      : AppTheme.light(),
                  builder: (context, child) => MediaQuery(
                    data: MediaQueryData(
                      size: size,
                      viewInsets: const EdgeInsets.only(bottom: 280),
                      padding: const EdgeInsets.only(bottom: 24),
                      textScaler: TextScaler.linear(scale),
                    ),
                    child: RepaintBoundary(
                      key: const Key('cash-capture'),
                      child: child!,
                    ),
                  ),
                ),
              ),
            );
            await tester.runAsync(() async {
              await Future<void>.delayed(const Duration(milliseconds: 30));
            });
            await tester.pumpAndSettle();
            final footer = find.byKey(const Key('cash-close-footer'));
            final rect = tester.getRect(footer);
            expect(rect.height, greaterThanOrEqualTo(48));
            expect(rect.bottom, lessThanOrEqualTo(size.height - 280));
            expect(rect.top, greaterThanOrEqualTo(0));
            expect(tester.takeException(), isNull);
            await tester.runAsync(() async {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const Key('cash-capture')),
              );
              final screenshot = await boundary.toImage(pixelRatio: 1);
              final png = await screenshot.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                'build/cash-workspace/close-${size.width.toInt()}-font${scale.toInt()}-${brightness.name}.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(png!.buffer.asUint8List());
              screenshot.dispose();
            });
            await tester.tap(footer);
            await tester.pump();
            expect(
              find.text(
                'Informe o total contado. Use 0 para caixa sem dinheiro.',
              ),
              findsOneWidget,
            );
          },
        );
      }
    }
  }
}

class _LocalConfirmController extends CashActionController {
  _LocalConfirmController(this.repository);
  final SqliteCashRepository repository;
  @override
  Future<CashSession> confirmAutoOpenedSession({
    required int initialFloatCents,
    CashCountResult? count,
  }) => repository.confirmAutoOpenedSession(
    initialFloatCents: initialFloatCents,
    count: count,
  );
}

Future<void> _flushCashIo(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
  }
}
