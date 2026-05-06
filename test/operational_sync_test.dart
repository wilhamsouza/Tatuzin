import 'package:erp_pdv_app/app/core/database/app_database.dart';
import 'package:erp_pdv_app/app/core/database/table_names.dart';
import 'package:erp_pdv_app/app/core/sync/app_snapshot_remote_datasource.dart';
import 'package:erp_pdv_app/app/core/sync/operational_sync_event.dart';
import 'package:erp_pdv_app/app/core/sync/operational_sync_policy.dart';
import 'package:erp_pdv_app/app/core/sync/operational_sync_queue_item.dart';
import 'package:erp_pdv_app/app/core/sync/operational_sync_queue_repository.dart';
import 'package:erp_pdv_app/app/core/sync/operational_sync_queue_status.dart';
import 'package:erp_pdv_app/app/core/sync/operational_sync_remote_datasource.dart';
import 'package:erp_pdv_app/app/core/sync/operational_sync_runner.dart';
import 'package:erp_pdv_app/app/core/sync/sqlite_operational_sync_queue_repository.dart';
import 'package:erp_pdv_app/app/core/sync/sync_queue_feature_summary.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _uuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('OperationalSyncPolicy', () {
    test('permite apenas entidades PDV local-first', () {
      expect(OperationalSyncPolicy.isLocalFirstEntity('sale'), isTrue);
      expect(OperationalSyncPolicy.isLocalFirstEntity('cashSession'), isTrue);

      for (final entity in <String>[
        'product',
        'customer',
        'supplier',
        'purchase',
        'cost',
        'report',
        'fiado',
      ]) {
        expect(
          OperationalSyncPolicy.isLocalFirstEntity(entity),
          isFalse,
          reason: '$entity nao deve entrar em SyncEvent operacional',
        );
      }
    });

    test('fila local bloqueia product customer supplier purchase', () async {
      final isolationKey =
          'operational-sync-policy-${DateTime.now().microsecondsSinceEpoch}';
      final appDatabase = AppDatabase.forIsolationKey(isolationKey);
      addTearDown(() async {
        await appDatabase.close();
        await AppDatabase.deleteDatabaseForIsolationKeyForTesting(isolationKey);
      });

      final database = await appDatabase.database;
      final repository = SqliteOperationalSyncQueueRepository(appDatabase);
      final acceptedSale = await repository.enqueue(
        database,
        event: _event(entity: 'sale', id: 'sale-1'),
      );
      final acceptedCashSession = await repository.enqueue(
        database,
        event: _event(entity: 'cashSession', id: 'cash-1'),
      );

      expect(acceptedSale, isTrue);
      expect(acceptedCashSession, isTrue);

      for (final entity in <String>[
        'product',
        'customer',
        'supplier',
        'purchase',
      ]) {
        final accepted = await repository.enqueue(
          database,
          event: _event(entity: entity, id: entity),
        );
        expect(accepted, isFalse);
      }

      final rows = await database.query(TableNames.operationalSyncEvents);
      expect(rows.map((row) => row['entity']), ['sale', 'cashSession']);
    });
  });

  group('OperationalSyncEvent', () {
    test('dois updates do mesmo pedido geram eventIds diferentes', () {
      final first = OperationalSyncEvent.buildEventId(
        entity: 'operationalOrder',
        operation: 'update',
        localIdentity: 'order-1',
      );
      final second = OperationalSyncEvent.buildEventId(
        entity: 'operationalOrder',
        operation: 'update',
        localIdentity: 'order-1',
      );

      expect(first, isNot(second));
      expect(first, matches(_uuidV4Pattern));
      expect(second, matches(_uuidV4Pattern));
    });

    test('dois cashMovement create diferentes nao colidem', () {
      final first = OperationalSyncEvent.buildEventId(
        entity: 'cashMovement',
        operation: 'create',
        localIdentity: 'cash-movement-1',
      );
      final second = OperationalSyncEvent.buildEventId(
        entity: 'cashMovement',
        operation: 'create',
        localIdentity: 'cash-movement-2',
      );

      expect(first, isNot(second));
      expect(first, matches(_uuidV4Pattern));
      expect(second, matches(_uuidV4Pattern));
    });

    test('payload inclui metadados de dominio para idempotencia', () {
      final event = _event(entity: 'sale', id: 'sale-1');

      expect(event.payloadWithSyncMetadata['_sync'], {
        'eventId': event.eventId,
        'entityLocalId': 'sale-1',
        'localSequence': event.occurredAt.microsecondsSinceEpoch,
        'idempotencyKey': event.eventId,
      });
    });
  });

  group('SqliteOperationalSyncQueueRepository', () {
    test(
      'sale/create reenviado com mesmo eventId continua idempotente',
      () async {
        final appDatabase = _newIsolatedDatabase('same-sale-event');
        addTearDown(() async => _disposeIsolatedDatabase(appDatabase));
        final database = await appDatabase.database;
        final repository = SqliteOperationalSyncQueueRepository(appDatabase);
        final event = _event(
          entity: 'sale',
          id: 'sale-1',
          eventId: 'sale-event-1',
        );

        final first = await repository.enqueue(database, event: event);
        final second = await repository.enqueue(database, event: event);

        final rows = await database.query(TableNames.operationalSyncEvents);
        expect(first, isTrue);
        expect(second, isFalse);
        expect(rows, hasLength(1));
        expect(rows.single['event_id'], 'sale-event-1');
      },
    );

    test(
      'update posterior da mesma entidade nao e ignorado como duplicado',
      () async {
        final appDatabase = _newIsolatedDatabase('order-updates');
        addTearDown(() async => _disposeIsolatedDatabase(appDatabase));
        final database = await appDatabase.database;
        final repository = SqliteOperationalSyncQueueRepository(appDatabase);
        final first = _event(
          entity: 'operationalOrder',
          id: 'order-1',
          operation: 'update',
        );
        final second = _event(
          entity: 'operationalOrder',
          id: 'order-1',
          operation: 'update',
        );

        expect(await repository.enqueue(database, event: first), isTrue);
        expect(await repository.enqueue(database, event: second), isTrue);

        final rows = await database.query(
          TableNames.operationalSyncEvents,
          orderBy: 'id ASC',
        );
        expect(rows, hasLength(2));
        expect(rows.first['entity_local_id'], 'order-1');
        expect(rows.last['entity_local_id'], 'order-1');
        expect(rows.first['event_id'], isNot(rows.last['event_id']));
      },
    );

    test('duplicate real continua preso por eventId unico', () async {
      final appDatabase = _newIsolatedDatabase('duplicate-event');
      addTearDown(() async => _disposeIsolatedDatabase(appDatabase));
      final database = await appDatabase.database;
      final repository = SqliteOperationalSyncQueueRepository(appDatabase);
      final original = _event(
        entity: 'cashMovement',
        id: 'cash-1',
        eventId: 'cash-movement-event-1',
      );
      final duplicate = _event(
        entity: 'cashMovement',
        id: 'cash-2',
        eventId: original.eventId,
      );

      expect(await repository.enqueue(database, event: original), isTrue);
      expect(await repository.enqueue(database, event: duplicate), isFalse);

      final rows = await database.query(TableNames.operationalSyncEvents);
      expect(rows, hasLength(1));
      expect(rows.single['entity_local_id'], 'cash-1');
    });

    test('recupera pushing antigo sem zerar attempts', () async {
      final now = DateTime(2026, 5, 5, 12);
      final appDatabase = _newIsolatedDatabase('stale-pushing');
      addTearDown(() async => _disposeIsolatedDatabase(appDatabase));
      final database = await appDatabase.database;
      final repository = SqliteOperationalSyncQueueRepository(appDatabase);
      final event = _event(entity: 'sale', id: 'sale-stale');

      await repository.enqueue(database, event: event);
      final pending = await repository.listPending(
        limit: 10,
        retryOnly: false,
        now: now,
      );
      await repository.markPushing(
        pending,
        startedAt: now.subtract(const Duration(minutes: 3)),
      );

      final recovered = await repository.recoverStalePushing(
        staleAfter: const Duration(minutes: 2),
        now: now,
      );
      final rows = await database.query(TableNames.operationalSyncEvents);
      final eligible = await repository.listPending(
        limit: 10,
        retryOnly: false,
        now: now,
      );

      expect(recovered, 1);
      expect(
        rows.single['status'],
        OperationalSyncQueueStatus.pending.storageValue,
      );
      expect(rows.single['attempt_count'], 1);
      expect(rows.single['pushing_started_at'], isNull);
      expect(rows.single['error_code'], 'SYNC_PUSH_STALE');
      expect(eligible.map((item) => item.event.eventId), [event.eventId]);
    });

    test('backoff nao ocupa limit e nao esconde eventos elegiveis', () async {
      final now = DateTime(2026, 5, 5, 12);
      final appDatabase = _newIsolatedDatabase('backoff-limit');
      addTearDown(() async => _disposeIsolatedDatabase(appDatabase));
      final database = await appDatabase.database;
      final repository = SqliteOperationalSyncQueueRepository(appDatabase);

      for (var index = 0; index < 150; index++) {
        await repository.enqueue(
          database,
          event: _event(entity: 'sale', id: 'sale-$index'),
        );
      }

      await database.update(
        TableNames.operationalSyncEvents,
        {
          'status': OperationalSyncQueueStatus.failed.storageValue,
          'next_retry_at': now
              .add(const Duration(minutes: 10))
              .toIso8601String(),
          'attempt_count': 1,
        },
        where: 'id <= ?',
        whereArgs: const <Object?>[100],
      );
      await database.update(
        TableNames.operationalSyncEvents,
        {
          'status': OperationalSyncQueueStatus.failed.storageValue,
          'next_retry_at': now
              .subtract(const Duration(seconds: 1))
              .toIso8601String(),
          'attempt_count': 1,
        },
        where: 'id > ?',
        whereArgs: const <Object?>[100],
      );

      final pending = await repository.listPending(
        limit: 20,
        retryOnly: false,
        now: now,
      );

      expect(pending, hasLength(20));
      expect(
        pending.every(
          (item) =>
              int.parse(item.event.entityLocalId!.replaceFirst('sale-', '')) >=
              100,
        ),
        isTrue,
      );
    });
  });

  group('OperationalSyncRunner', () {
    test('push trata accepted duplicate rejected e conflict', () async {
      final accepted = _event(entity: 'sale', id: 'accepted');
      final duplicate = _event(entity: 'cashSession', id: 'duplicate');
      final rejected = _event(entity: 'product', id: 'rejected');
      final conflict = _event(entity: 'sale', id: 'conflict');
      final queue = _MemoryOperationalSyncQueueRepository(
        events: <OperationalSyncEvent>[accepted, duplicate, rejected, conflict],
      );
      final remote = _FakeOperationalSyncRemoteDataSource(
        pushResponse: OperationalSyncPushResponse(
          currentServerVersion: '12',
          accepted: <OperationalSyncPushItemResult>[
            OperationalSyncPushItemResult(
              eventId: accepted.eventId,
              entity: 'sale',
              operation: 'create',
              serverVersion: '10',
            ),
          ],
          duplicates: <OperationalSyncPushItemResult>[
            OperationalSyncPushItemResult(
              eventId: duplicate.eventId,
              entity: 'cashSession',
              operation: 'create',
              serverVersion: '11',
            ),
          ],
          rejected: <OperationalSyncPushItemResult>[
            OperationalSyncPushItemResult(
              eventId: rejected.eventId,
              entity: 'product',
              operation: 'create',
              code: 'ENTITY_NOT_LOCAL_FIRST',
              message: 'server-first',
            ),
          ],
          conflicts: <OperationalSyncPushItemResult>[
            OperationalSyncPushItemResult(
              eventId: conflict.eventId,
              entity: 'sale',
              operation: 'create',
              serverVersion: '12',
              code: 'SALE_ALREADY_FINALIZED',
              message: 'conflito',
            ),
          ],
        ),
        conflicts: <OperationalSyncConflict>[
          OperationalSyncConflict(
            id: 'conflict-1',
            entity: 'sale',
            code: 'SALE_ALREADY_FINALIZED',
            message: 'conflito',
            status: 'OPEN',
            eventId: conflict.eventId,
          ),
        ],
      );
      const snapshot = _FakeAppSnapshotRemoteDataSource(version: '1');
      var snapshotChanges = 0;
      final runner = OperationalSyncRunner(
        queueRepository: queue,
        remoteDataSource: remote,
        snapshotRemoteDataSource: snapshot,
        shouldContinue: () => true,
        onCacheSnapshotChanged: () => snapshotChanges++,
      );

      final result = await runner.run(retryOnly: false);

      expect(result.processedCount, 4);
      expect(result.syncedCount, 2);
      expect(result.failedCount, 1);
      expect(result.conflictCount, 1);
      expect(queue.statusByEventId[accepted.eventId], 'accepted:10');
      expect(queue.statusByEventId[duplicate.eventId], 'duplicate:11');
      expect(
        queue.statusByEventId[rejected.eventId],
        'rejected:ENTITY_NOT_LOCAL_FIRST',
      );
      expect(queue.statusByEventId[conflict.eventId], 'conflict:conflict-1');
      expect(snapshotChanges, 1);
    });

    test('batch limita 100 eventos por push', () async {
      final queue = _MemoryOperationalSyncQueueRepository(
        events: List<OperationalSyncEvent>.generate(
          101,
          (index) => _event(entity: 'sale', id: 'sale-$index'),
        ),
      );
      final remote = _FakeOperationalSyncRemoteDataSource();
      final runner = OperationalSyncRunner(
        queueRepository: queue,
        remoteDataSource: remote,
        snapshotRemoteDataSource: const _FakeAppSnapshotRemoteDataSource(
          version: '0',
        ),
        shouldContinue: () => true,
        onCacheSnapshotChanged: () {},
      );

      await runner.run(retryOnly: false);

      expect(
        remote.lastPushedEvents.length,
        OperationalSyncRunner.maxEventsPerBatch,
      );
    });

    test('snapshot server-first atualiza cache quando versao muda', () async {
      final queue = _MemoryOperationalSyncQueueRepository();
      final runner = OperationalSyncRunner(
        queueRepository: queue,
        remoteDataSource: _FakeOperationalSyncRemoteDataSource(),
        snapshotRemoteDataSource: const _FakeAppSnapshotRemoteDataSource(
          version: '42',
        ),
        shouldContinue: () => true,
        onCacheSnapshotChanged: () => queue.cacheRefreshSignals++,
      );

      await runner.run(retryOnly: false);

      expect(queue.snapshotVersion, '42');
      expect(queue.cacheRefreshSignals, 1);
    });

    test('push ok com pull falhando registra estado parcial', () async {
      final event = _event(entity: 'sale', id: 'sale-pull-failed');
      final queue = _MemoryOperationalSyncQueueRepository(
        events: <OperationalSyncEvent>[event],
      );
      final runner = OperationalSyncRunner(
        queueRepository: queue,
        remoteDataSource: _FakeOperationalSyncRemoteDataSource(
          pushResponse: OperationalSyncPushResponse(
            currentServerVersion: '1',
            accepted: <OperationalSyncPushItemResult>[
              OperationalSyncPushItemResult(
                eventId: event.eventId,
                entity: 'sale',
                operation: 'create',
                serverVersion: '1',
              ),
            ],
            duplicates: const <OperationalSyncPushItemResult>[],
            rejected: const <OperationalSyncPushItemResult>[],
            conflicts: const <OperationalSyncPushItemResult>[],
          ),
          failPull: true,
        ),
        snapshotRemoteDataSource: const _FakeAppSnapshotRemoteDataSource(
          version: '0',
        ),
        shouldContinue: () => true,
        onCacheSnapshotChanged: () => queue.cacheRefreshSignals++,
      );

      final result = await runner.run(retryOnly: false);

      expect(result.syncedCount, 1);
      expect(result.failedCount, 0);
      expect(result.pullFailed, isTrue);
      expect(result.snapshotFailed, isFalse);
      expect(result.hasServerDataStale, isTrue);
      expect(queue.lastPullError, contains('pull offline'));
      expect(queue.lastSnapshotError, isNull);
      expect(queue.cacheRefreshSignals, 0);
    });

    test(
      'falha de snapshot nao bloqueia PDV e marca dados desatualizados',
      () async {
        final queue = _MemoryOperationalSyncQueueRepository();
        final runner = OperationalSyncRunner(
          queueRepository: queue,
          remoteDataSource: _FakeOperationalSyncRemoteDataSource(),
          snapshotRemoteDataSource: const _FakeAppSnapshotRemoteDataSource(
            version: '42',
            fail: true,
          ),
          shouldContinue: () => true,
          onCacheSnapshotChanged: () => queue.cacheRefreshSignals++,
        );

        final result = await runner.run(retryOnly: false);

        expect(result.processedCount, 0);
        expect(result.failedCount, 0);
        expect(result.pullFailed, isFalse);
        expect(result.snapshotFailed, isTrue);
        expect(result.hasServerDataStale, isTrue);
        expect(queue.lastPullError, isNull);
        expect(queue.lastSnapshotError, contains('snapshot offline'));
        expect(queue.cacheRefreshSignals, 0);
      },
    );
  });
}

final _isolationKeys = <AppDatabase, String>{};

AppDatabase _newIsolatedDatabase(String label) {
  final isolationKey =
      'operational-sync-$label-${DateTime.now().microsecondsSinceEpoch}';
  final appDatabase = AppDatabase.forIsolationKey(isolationKey);
  _isolationKeys[appDatabase] = isolationKey;
  return appDatabase;
}

Future<void> _disposeIsolatedDatabase(AppDatabase appDatabase) async {
  final isolationKey = _isolationKeys.remove(appDatabase);
  await appDatabase.close();
  if (isolationKey != null) {
    await AppDatabase.deleteDatabaseForIsolationKeyForTesting(isolationKey);
  }
}

OperationalSyncEvent _event({
  required String entity,
  required String id,
  String operation = 'create',
  String? eventId,
}) {
  return OperationalSyncEvent(
    eventId:
        eventId ??
        OperationalSyncEvent.buildEventId(
          entity: entity,
          operation: operation,
          localIdentity: id,
        ),
    feature: 'pdv',
    entity: entity,
    operation: operation,
    entityLocalId: id,
    occurredAt: DateTime(2026, 5, 5, 10),
    payload: <String, dynamic>{'id': id},
  );
}

class _MemoryOperationalSyncQueueRepository
    implements OperationalSyncQueueRepository {
  _MemoryOperationalSyncQueueRepository({
    List<OperationalSyncEvent> events = const <OperationalSyncEvent>[],
  }) : _items = [
         for (var i = 0; i < events.length; i++)
           OperationalSyncQueueItem(
             id: i + 1,
             event: events[i],
             status: OperationalSyncQueueStatus.pending,
             attemptCount: 0,
             createdAt: DateTime(2026, 5, 5, 10),
             updatedAt: DateTime(2026, 5, 5, 10),
           ),
       ];

  final List<OperationalSyncQueueItem> _items;
  final Map<String, String> statusByEventId = <String, String>{};
  String checkpoint = '0';
  String? snapshotVersion;
  String? lastPullError;
  String? lastSnapshotError;
  DateTime? lastPullSucceededAt;
  DateTime? lastSnapshotSucceededAt;
  int staleRecoveryCalls = 0;
  int cacheRefreshSignals = 0;

  @override
  Future<bool> enqueue(db, {required OperationalSyncEvent event}) async {
    throw UnimplementedError();
  }

  @override
  Future<List<OperationalSyncQueueItem>> listPending({
    required int limit,
    required bool retryOnly,
    bool ignoreRetryBackoff = false,
    DateTime? now,
  }) async {
    return _items.take(limit).toList(growable: false);
  }

  @override
  Future<void> markPushing(
    Iterable<OperationalSyncQueueItem> items, {
    required DateTime startedAt,
  }) async {}

  @override
  Future<void> markAccepted({
    required String eventId,
    required String? serverVersion,
    required DateTime processedAt,
  }) async {
    statusByEventId[eventId] = 'accepted:$serverVersion';
  }

  @override
  Future<void> markDuplicate({
    required String eventId,
    required String? serverVersion,
    required DateTime processedAt,
  }) async {
    statusByEventId[eventId] = 'duplicate:$serverVersion';
  }

  @override
  Future<void> markRejected({
    required String eventId,
    required String code,
    required String message,
    required DateTime processedAt,
  }) async {
    statusByEventId[eventId] = 'rejected:$code';
  }

  @override
  Future<void> markConflict({
    required String eventId,
    required String? serverVersion,
    required String code,
    required String message,
    required String? conflictId,
    required DateTime processedAt,
  }) async {
    statusByEventId[eventId] = 'conflict:$conflictId';
  }

  @override
  Future<void> markFailed(
    Iterable<OperationalSyncQueueItem> items, {
    required String message,
    required DateTime failedAt,
    required DateTime? nextRetryAt,
  }) async {
    for (final item in items) {
      statusByEventId[item.event.eventId] = 'failed';
    }
  }

  @override
  Future<int> recoverStalePushing({
    required Duration staleAfter,
    DateTime? now,
  }) async {
    staleRecoveryCalls++;
    return 0;
  }

  @override
  Future<String> readCheckpoint() async => checkpoint;

  @override
  Future<void> saveCheckpoint(String serverVersion) async {
    checkpoint = serverVersion;
  }

  @override
  Future<String?> readSnapshotVersion() async => snapshotVersion;

  @override
  Future<void> saveSnapshotVersion(String serverFirstSnapshotVersion) async {
    snapshotVersion = serverFirstSnapshotVersion;
  }

  @override
  Future<void> recordPullSucceeded({required DateTime completedAt}) async {
    lastPullSucceededAt = completedAt;
    lastPullError = null;
  }

  @override
  Future<void> recordPullFailed({
    required String message,
    required DateTime failedAt,
  }) async {
    lastPullError = message;
  }

  @override
  Future<void> recordSnapshotSucceeded({
    required String serverFirstSnapshotVersion,
    required DateTime completedAt,
  }) async {
    snapshotVersion = serverFirstSnapshotVersion;
    lastSnapshotSucceededAt = completedAt;
    lastSnapshotError = null;
  }

  @override
  Future<void> recordSnapshotFailed({
    required String message,
    required DateTime failedAt,
  }) async {
    lastSnapshotError = message;
  }

  @override
  Future<List<SyncQueueFeatureSummary>> listFeatureSummaries() async {
    return const <SyncQueueFeatureSummary>[];
  }
}

class _FakeOperationalSyncRemoteDataSource
    implements OperationalSyncRemoteDataSource {
  _FakeOperationalSyncRemoteDataSource({
    OperationalSyncPushResponse? pushResponse,
    this.conflicts = const <OperationalSyncConflict>[],
    this.failPull = false,
  }) : pushResponse =
           pushResponse ??
           const OperationalSyncPushResponse(
             currentServerVersion: '0',
             accepted: <OperationalSyncPushItemResult>[],
             duplicates: <OperationalSyncPushItemResult>[],
             rejected: <OperationalSyncPushItemResult>[],
             conflicts: <OperationalSyncPushItemResult>[],
           );

  final OperationalSyncPushResponse pushResponse;
  final List<OperationalSyncConflict> conflicts;
  final bool failPull;
  List<OperationalSyncEvent> lastPushedEvents = const <OperationalSyncEvent>[];

  @override
  Future<OperationalSyncPushResponse> pushEvents(
    List<OperationalSyncEvent> events, {
    String? lastKnownServerVersion,
  }) async {
    lastPushedEvents = events;
    return pushResponse;
  }

  @override
  Future<OperationalSyncPullResponse> pullChanges({
    required String sinceVersion,
    Iterable<String> features = const <String>[],
    int limit = 100,
  }) async {
    if (failPull) {
      throw StateError('pull offline');
    }
    return const OperationalSyncPullResponse(
      currentServerVersion: '0',
      nextSinceVersion: '0',
      hasMore: false,
      events: <OperationalSyncPulledEvent>[],
    );
  }

  @override
  Future<OperationalSyncStatusResponse> getStatus() async {
    return const OperationalSyncStatusResponse(
      companyId: 'company-1',
      deviceId: 'device-1',
      syncEnabled: true,
      currentServerVersion: '0',
      openConflictsCount: 0,
      deviceStatus: 'ACTIVE',
    );
  }

  @override
  Future<List<OperationalSyncConflict>> getConflicts() async => conflicts;

  @override
  Future<OperationalSyncConflict> resolveConflict(
    String conflictId,
    Map<String, dynamic> resolution,
  ) async {
    throw UnimplementedError();
  }
}

class _FakeAppSnapshotRemoteDataSource implements AppSnapshotRemoteDataSource {
  const _FakeAppSnapshotRemoteDataSource({
    required this.version,
    this.fail = false,
  });

  final String version;
  final bool fail;

  @override
  Future<AppSnapshotResponse> fetchSnapshot({
    Iterable<String> features = const <String>[],
  }) async {
    if (fail) {
      throw StateError('snapshot offline');
    }
    return AppSnapshotResponse(
      companyId: 'company-1',
      serverFirstSnapshotVersion: version,
      features: const <String, AppSnapshotFeature>{},
    );
  }
}
