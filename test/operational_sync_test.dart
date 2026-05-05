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

  group('OperationalSyncRunner', () {
    test('push trata accepted duplicate rejected e conflict', () async {
      final queue = _MemoryOperationalSyncQueueRepository(
        events: <OperationalSyncEvent>[
          _event(entity: 'sale', id: 'accepted'),
          _event(entity: 'cashSession', id: 'duplicate'),
          _event(entity: 'product', id: 'rejected'),
          _event(entity: 'sale', id: 'conflict'),
        ],
      );
      final remote = _FakeOperationalSyncRemoteDataSource(
        pushResponse: const OperationalSyncPushResponse(
          currentServerVersion: '12',
          accepted: <OperationalSyncPushItemResult>[
            OperationalSyncPushItemResult(
              eventId: 'sale:create:accepted',
              entity: 'sale',
              operation: 'create',
              serverVersion: '10',
            ),
          ],
          duplicates: <OperationalSyncPushItemResult>[
            OperationalSyncPushItemResult(
              eventId: 'cashSession:create:duplicate',
              entity: 'cashSession',
              operation: 'create',
              serverVersion: '11',
            ),
          ],
          rejected: <OperationalSyncPushItemResult>[
            OperationalSyncPushItemResult(
              eventId: 'product:create:rejected',
              entity: 'product',
              operation: 'create',
              code: 'ENTITY_NOT_LOCAL_FIRST',
              message: 'server-first',
            ),
          ],
          conflicts: <OperationalSyncPushItemResult>[
            OperationalSyncPushItemResult(
              eventId: 'sale:create:conflict',
              entity: 'sale',
              operation: 'create',
              serverVersion: '12',
              code: 'SALE_ALREADY_FINALIZED',
              message: 'conflito',
            ),
          ],
        ),
        conflicts: const <OperationalSyncConflict>[
          OperationalSyncConflict(
            id: 'conflict-1',
            entity: 'sale',
            code: 'SALE_ALREADY_FINALIZED',
            message: 'conflito',
            status: 'OPEN',
            eventId: 'sale:create:conflict',
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
      expect(queue.statusByEventId['sale:create:accepted'], 'accepted:10');
      expect(
        queue.statusByEventId['cashSession:create:duplicate'],
        'duplicate:11',
      );
      expect(
        queue.statusByEventId['product:create:rejected'],
        'rejected:ENTITY_NOT_LOCAL_FIRST',
      );
      expect(
        queue.statusByEventId['sale:create:conflict'],
        'conflict:conflict-1',
      );
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
  });
}

OperationalSyncEvent _event({required String entity, required String id}) {
  return OperationalSyncEvent(
    eventId: OperationalSyncEvent.buildEventId(
      entity: entity,
      operation: 'create',
      localIdentity: id,
    ),
    feature: 'pdv',
    entity: entity,
    operation: 'create',
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
  Future<List<SyncQueueFeatureSummary>> listFeatureSummaries() async {
    return const <SyncQueueFeatureSummary>[];
  }
}

class _FakeOperationalSyncRemoteDataSource
    implements OperationalSyncRemoteDataSource {
  _FakeOperationalSyncRemoteDataSource({
    OperationalSyncPushResponse? pushResponse,
    this.conflicts = const <OperationalSyncConflict>[],
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
  const _FakeAppSnapshotRemoteDataSource({required this.version});

  final String version;

  @override
  Future<AppSnapshotResponse> fetchSnapshot({
    Iterable<String> features = const <String>[],
  }) async {
    return AppSnapshotResponse(
      companyId: 'company-1',
      serverFirstSnapshotVersion: version,
      features: const <String, AppSnapshotFeature>{},
    );
  }
}
