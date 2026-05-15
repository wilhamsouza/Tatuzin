import 'package:erp_pdv_app/app/core/database/app_database.dart';
import 'package:erp_pdv_app/app/core/database/table_names.dart';
import 'package:erp_pdv_app/app/core/sync/app_snapshot_hydrator.dart';
import 'package:erp_pdv_app/app/core/sync/app_snapshot_remote_datasource.dart';
import 'package:erp_pdv_app/app/core/sync/operational_sync_event.dart';
import 'package:erp_pdv_app/app/core/sync/operational_sync_policy.dart';
import 'package:erp_pdv_app/app/core/sync/operational_sync_projection_applier.dart';
import 'package:erp_pdv_app/app/core/sync/operational_sync_queue_item.dart';
import 'package:erp_pdv_app/app/core/sync/operational_sync_queue_repository.dart';
import 'package:erp_pdv_app/app/core/sync/operational_sync_queue_status.dart';
import 'package:erp_pdv_app/app/core/sync/operational_sync_remote_datasource.dart';
import 'package:erp_pdv_app/app/core/sync/operational_sync_runner.dart';
import 'package:erp_pdv_app/app/core/sync/sqlite_operational_sync_queue_repository.dart';
import 'package:erp_pdv_app/app/core/sync/sync_feature_keys.dart';
import 'package:erp_pdv_app/app/core/sync/sync_queue_feature_summary.dart';
import 'package:erp_pdv_app/modules/categorias/data/sqlite_category_repository.dart';
import 'package:erp_pdv_app/modules/caixa/data/sqlite_cash_repository.dart';
import 'package:erp_pdv_app/modules/clientes/data/sqlite_client_repository.dart';
import 'package:erp_pdv_app/app/core/app_context/app_operational_context.dart';
import 'package:erp_pdv_app/app/core/config/app_environment.dart';
import 'package:erp_pdv_app/modules/dashboard/data/sqlite_operational_dashboard_repository.dart';
import 'package:erp_pdv_app/modules/fornecedores/data/sqlite_supplier_repository.dart';
import 'package:erp_pdv_app/modules/produtos/data/sqlite_product_repository.dart';
import 'package:erp_pdv_app/app/core/session/app_session.dart';
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

    test(
      'app limpo hidrata catalogo via snapshot antes de aplicar pull operacional',
      () async {
        final appDatabase = _newIsolatedDatabase('initial-hydration');
        addTearDown(() => _disposeIsolatedDatabase(appDatabase));
        final db = await appDatabase.database;
        final queue = SqliteOperationalSyncQueueRepository(appDatabase);
        final categoryRepository = SqliteCategoryRepository(appDatabase);
        final productRepository = SqliteProductRepository(
          appDatabase,
          categoryRepository: categoryRepository,
        );
        final soldAt = DateTime.now().toIso8601String();
        final runner = OperationalSyncRunner(
          queueRepository: queue,
          remoteDataSource: _FakeOperationalSyncRemoteDataSource(
            pullResponse: OperationalSyncPullResponse(
              currentServerVersion: '2',
              nextSinceVersion: '2',
              hasMore: false,
              usesProjectionContract: true,
              events: <OperationalSyncPulledEvent>[
                _pulledChange(
                  entity: 'sale',
                  eventId: 'sale-device-a',
                  serverVersion: '1',
                  projection: <String, dynamic>{
                    'companyId': 'company-1',
                    'entityServerId': 'sale-server-1',
                    'id': 'sale-server-1',
                    'localUuid': 'sale-local-a',
                    'status': 'active',
                    'total': <String, dynamic>{
                      'totalAmountCents': 2400,
                      'totalCostCents': 900,
                    },
                    'receiptNumber': 'R-001',
                    'soldAt': soldAt,
                    'createdAt': soldAt,
                  },
                ),
                _pulledChange(
                  entity: 'saleItem',
                  eventId: 'sale-item-device-a',
                  serverVersion: '2',
                  projection: <String, dynamic>{
                    'companyId': 'company-1',
                    'entityServerId': 'sale-item-server-1',
                    'id': 'sale-item-server-1',
                    'saleId': 'sale-server-1',
                    'productId': 'product-server-1',
                    'description': 'Cafe coado',
                    'quantityMil': 1000,
                    'totals': <String, dynamic>{
                      'unitPriceCents': 2400,
                      'totalPriceCents': 2400,
                      'totalCostCents': 900,
                    },
                  },
                ),
              ],
            ),
          ),
          projectionApplier: SqliteOperationalSyncProjectionApplier(
            appDatabase: appDatabase,
            companyRemoteId: 'company-1',
          ),
          snapshotHydrator: SqliteAppSnapshotHydrator(
            categoryRepository: categoryRepository,
            supplierRepository: SqliteSupplierRepository(appDatabase),
            clientRepository: SqliteClientRepository(appDatabase),
            productRepository: productRepository,
            cashRepository: SqliteCashRepository(
              appDatabase,
              AppOperationalContext(
                environment: const AppEnvironment.localDefault(),
                session: AppSession.localDefault(),
              ),
            ),
          ),
          snapshotRemoteDataSource: _FakeAppSnapshotRemoteDataSource(
            version: '42',
            features: <String, AppSnapshotFeature>{
              SyncFeatureKeys.categories: AppSnapshotFeature(
                feature: SyncFeatureKeys.categories,
                mode: 'server_first_cache',
                count: 1,
                items: <Map<String, dynamic>>[
                  _categorySnapshotItem(
                    id: 'category-server-1',
                    name: 'Bebidas',
                  ),
                ],
              ),
              SyncFeatureKeys.products: AppSnapshotFeature(
                feature: SyncFeatureKeys.products,
                mode: 'server_first_cache',
                count: 1,
                items: <Map<String, dynamic>>[
                  _productSnapshotItem(
                    id: 'product-server-1',
                    categoryId: 'category-server-1',
                  ),
                ],
              ),
            },
          ),
          shouldContinue: () => true,
          onCacheSnapshotChanged: () {},
        );

        final result = await runner.run(retryOnly: false);

        final products = await db.query(TableNames.produtos);
        final productSync = await db.query(
          TableNames.syncRegistros,
          where: 'feature_key = ? AND remote_id = ?',
          whereArgs: const <Object?>[
            SyncFeatureKeys.products,
            'product-server-1',
          ],
        );
        final sales = await db.query(TableNames.vendas);
        final saleItems = await db.query(TableNames.itensVenda);
        final dashboard = await SqliteOperationalDashboardRepository(
          appDatabase,
        ).fetchSnapshot();

        expect(result.snapshotFailed, isFalse);
        expect(result.pullFailed, isFalse);
        expect(products, hasLength(1));
        expect(productSync, hasLength(1));
        expect(sales, hasLength(1));
        expect(saleItems, hasLength(1));
        expect(dashboard.soldTodayCents, 2400);
      },
    );

    test(
      'hidratacao de snapshot repetida preserva identidades e variantes',
      () async {
        final appDatabase = _newIsolatedDatabase('snapshot-idempotent');
        addTearDown(() => _disposeIsolatedDatabase(appDatabase));
        final db = await appDatabase.database;
        final categoryRepository = SqliteCategoryRepository(appDatabase);
        final productRepository = SqliteProductRepository(
          appDatabase,
          categoryRepository: categoryRepository,
        );
        final cashRepository = SqliteCashRepository(
          appDatabase,
          AppOperationalContext(
            environment: const AppEnvironment.localDefault(),
            session: AppSession.localDefault(),
          ),
        );
        final hydrator = SqliteAppSnapshotHydrator(
          categoryRepository: categoryRepository,
          supplierRepository: SqliteSupplierRepository(appDatabase),
          clientRepository: SqliteClientRepository(appDatabase),
          productRepository: productRepository,
          cashRepository: SqliteCashRepository(
            appDatabase,
            AppOperationalContext(
              environment: const AppEnvironment.localDefault(),
              session: AppSession.localDefault(),
            ),
          ),
        );
        final snapshot = AppSnapshotResponse(
          companyId: 'company-1',
          serverFirstSnapshotVersion: '42',
          features: <String, AppSnapshotFeature>{
            SyncFeatureKeys.categories: AppSnapshotFeature(
              feature: SyncFeatureKeys.categories,
              mode: 'server_first_cache',
              count: 1,
              items: <Map<String, dynamic>>[
                _categorySnapshotItem(id: 'category-server-1', name: 'Bebidas'),
              ],
            ),
            SyncFeatureKeys.suppliers: AppSnapshotFeature(
              feature: SyncFeatureKeys.suppliers,
              mode: 'server_first_cache',
              count: 1,
              items: <Map<String, dynamic>>[
                _supplierSnapshotItem(id: 'supplier-server-1'),
              ],
            ),
            SyncFeatureKeys.customers: AppSnapshotFeature(
              feature: SyncFeatureKeys.customers,
              mode: 'server_first_cache',
              count: 1,
              items: <Map<String, dynamic>>[
                _customerSnapshotItem(id: 'customer-server-1'),
              ],
            ),
            SyncFeatureKeys.products: AppSnapshotFeature(
              feature: SyncFeatureKeys.products,
              mode: 'server_first_cache',
              count: 1,
              items: <Map<String, dynamic>>[
                _productSnapshotItem(
                  id: 'product-server-1',
                  categoryId: 'category-server-1',
                  variants: <Map<String, dynamic>>[
                    _productVariantSnapshotItem(id: 'variant-server-1'),
                  ],
                ),
              ],
            ),
            SyncFeatureKeys.cashSessions: AppSnapshotFeature(
              feature: SyncFeatureKeys.cashSessions,
              mode: 'server_first_cache',
              count: 1,
              items: <Map<String, dynamic>>[
                _cashSessionSnapshotItem(id: 'cash-session-server-1'),
              ],
            ),
            SyncFeatureKeys.cashMovements: AppSnapshotFeature(
              feature: SyncFeatureKeys.cashMovements,
              mode: 'server_first_cache',
              count: 1,
              items: <Map<String, dynamic>>[
                _cashMovementSnapshotItem(
                  id: 'cash-movement-server-1',
                  cashSessionId: 'cash-session-server-1',
                ),
              ],
            ),
          },
        );

        await hydrator.hydrate(snapshot);
        await hydrator.hydrate(snapshot);

        final categories = await db.query(TableNames.categorias);
        final suppliers = await db.query(TableNames.fornecedores);
        final customers = await db.query(TableNames.clientes);
        final products = await db.query(TableNames.produtos);
        final variants = await db.query(TableNames.produtoVariantes);
        final cashSessions = await db.query(TableNames.caixaSessoes);
        final cashMovements = await db.query(TableNames.caixaMovimentos);
        final hydratedSessions = await cashRepository.listSessions();
        final hydratedDetail = await cashRepository.fetchSessionDetail(
          hydratedSessions.single.id,
        );
        final productSync = await db.query(
          TableNames.syncRegistros,
          where: 'feature_key = ? AND remote_id = ?',
          whereArgs: const <Object?>[
            SyncFeatureKeys.products,
            'product-server-1',
          ],
        );

        expect(categories, hasLength(1));
        expect(suppliers, hasLength(1));
        expect(customers, hasLength(1));
        expect(products, hasLength(1));
        expect(products.single['estoque_mil'], 12000);
        expect(cashSessions, hasLength(1));
        expect(cashSessions.single['saldo_final_centavos'], 8200);
        expect(hydratedSessions.single.operatorName, 'Operadora remota');
        expect(hydratedSessions.single.notes, 'Sessao restaurada');
        expect(cashMovements, hasLength(1));
        expect(cashMovements.single['valor_centavos'], 3200);
        expect(cashMovements.single['referencia_tipo'], 'venda');
        expect(cashMovements.single['referencia_id'], 'sale-server-1');
        expect(
          hydratedDetail.movements.single.referenceLabel,
          'VENDA #sale-server-1',
        );
        expect(
          hydratedDetail.movements.single.movement.referenceId,
          'sale-server-1',
        );
        expect(productSync, hasLength(1));
        expect(variants, hasLength(1));
        expect(variants.single['remote_id'], 'variant-server-1');
        expect(variants.single['estoque_mil'], 12000);
      },
    );

    test(
      'pull prefere changes com projection e avanca checkpoint apos aplicar',
      () async {
        final queue = _MemoryOperationalSyncQueueRepository();
        final applier = _MemoryOperationalSyncProjectionApplier();
        final runner = OperationalSyncRunner(
          queueRepository: queue,
          remoteDataSource: _FakeOperationalSyncRemoteDataSource(
            pullResponse: OperationalSyncPullResponse(
              currentServerVersion: '2',
              nextSinceVersion: '2',
              hasMore: false,
              usesProjectionContract: true,
              events: <OperationalSyncPulledEvent>[
                _pulledChange(
                  entity: 'sale',
                  eventId: 'sale-from-device-a',
                  serverVersion: '2',
                  projection: <String, dynamic>{
                    'entityServerId': 'sale-server-1',
                    'id': 'sale-server-1',
                    'localUuid': 'sale-local-a',
                  },
                ),
              ],
            ),
          ),
          projectionApplier: applier,
          snapshotRemoteDataSource: const _FakeAppSnapshotRemoteDataSource(
            version: '0',
          ),
          shouldContinue: () => true,
          onCacheSnapshotChanged: () {},
        );

        final result = await runner.run(retryOnly: false);

        expect(result.pullFailed, isFalse);
        expect(queue.checkpoint, '2');
        expect(applier.applied.map((change) => change.eventId), [
          'sale-from-device-a',
        ]);
      },
    );

    test(
      'pull com duas paginas aplica ambas e avanca checkpoint final',
      () async {
        final queue = _MemoryOperationalSyncQueueRepository();
        final applier = _MemoryOperationalSyncProjectionApplier();
        final remote = _FakeOperationalSyncRemoteDataSource(
          statusServerVersion: '2',
          pullResponses: <OperationalSyncPullResponse>[
            OperationalSyncPullResponse(
              currentServerVersion: '2',
              nextSinceVersion: '1',
              hasMore: true,
              usesProjectionContract: true,
              events: <OperationalSyncPulledEvent>[
                _pulledChange(
                  entity: 'sale',
                  eventId: 'sale-page-1',
                  serverVersion: '1',
                  projection: <String, dynamic>{
                    'entityServerId': 'sale-server-1',
                    'id': 'sale-server-1',
                    'localUuid': 'sale-local-page-1',
                  },
                ),
              ],
            ),
            OperationalSyncPullResponse(
              currentServerVersion: '2',
              nextSinceVersion: '2',
              hasMore: false,
              usesProjectionContract: true,
              events: <OperationalSyncPulledEvent>[
                _pulledChange(
                  entity: 'cashSession',
                  eventId: 'cash-page-2',
                  serverVersion: '2',
                  projection: <String, dynamic>{
                    'entityServerId': 'cash-server-2',
                    'id': 'cash-server-2',
                    'localUuid': 'cash-local-page-2',
                  },
                ),
              ],
            ),
          ],
        );
        final runner = OperationalSyncRunner(
          queueRepository: queue,
          remoteDataSource: remote,
          projectionApplier: applier,
          snapshotRemoteDataSource: const _FakeAppSnapshotRemoteDataSource(
            version: '0',
          ),
          shouldContinue: () => true,
          onCacheSnapshotChanged: () {},
        );

        final result = await runner.run(retryOnly: false);

        expect(result.pullFailed, isFalse);
        expect(queue.checkpoint, '2');
        expect(remote.pulledSinceVersions, ['0', '1']);
        expect(applier.applied.map((change) => change.eventId), [
          'sale-page-1',
          'cash-page-2',
        ]);
      },
    );

    test('pull legado sem changes continua compativel', () async {
      final queue = _MemoryOperationalSyncQueueRepository();
      final applier = _MemoryOperationalSyncProjectionApplier();
      final runner = OperationalSyncRunner(
        queueRepository: queue,
        remoteDataSource: _FakeOperationalSyncRemoteDataSource(
          pullResponse: OperationalSyncPullResponse(
            currentServerVersion: '4',
            nextSinceVersion: '4',
            hasMore: false,
            events: <OperationalSyncPulledEvent>[
              _pulledChange(
                entity: 'sale',
                eventId: 'legacy-sale-event',
                serverVersion: '4',
              ),
            ],
          ),
        ),
        projectionApplier: applier,
        snapshotRemoteDataSource: const _FakeAppSnapshotRemoteDataSource(
          version: '0',
        ),
        shouldContinue: () => true,
        onCacheSnapshotChanged: () {},
      );

      final result = await runner.run(retryOnly: false);

      expect(result.pullFailed, isFalse);
      expect(queue.checkpoint, '4');
      expect(applier.applied, isEmpty);
    });

    test(
      'projection null com warning nao avanca checkpoint inseguro',
      () async {
        final queue = _MemoryOperationalSyncQueueRepository();
        final runner = OperationalSyncRunner(
          queueRepository: queue,
          remoteDataSource: _FakeOperationalSyncRemoteDataSource(
            pullResponse: OperationalSyncPullResponse(
              currentServerVersion: '5',
              nextSinceVersion: '5',
              hasMore: false,
              usesProjectionContract: true,
              events: <OperationalSyncPulledEvent>[
                _pulledChange(
                  entity: 'sale',
                  eventId: 'sale-warning',
                  serverVersion: '5',
                  projectionWarning: 'PROJECTION_NOT_FOUND',
                ),
              ],
            ),
          ),
          snapshotRemoteDataSource: const _FakeAppSnapshotRemoteDataSource(
            version: '0',
          ),
          shouldContinue: () => true,
          onCacheSnapshotChanged: () {},
        );

        final result = await runner.run(retryOnly: false);

        expect(result.pullFailed, isTrue);
        expect(queue.checkpoint, '0');
        expect(queue.lastPullError, contains('Dados parcialmente atualizados'));
      },
    );

    test(
      'product vindo por engano no pull e ignorado sem aplicar projection',
      () async {
        final queue = _MemoryOperationalSyncQueueRepository();
        final applier = _MemoryOperationalSyncProjectionApplier();
        final runner = OperationalSyncRunner(
          queueRepository: queue,
          remoteDataSource: _FakeOperationalSyncRemoteDataSource(
            pullResponse: OperationalSyncPullResponse(
              currentServerVersion: '6',
              nextSinceVersion: '6',
              hasMore: false,
              usesProjectionContract: true,
              events: <OperationalSyncPulledEvent>[
                _pulledChange(
                  entity: 'product',
                  eventId: 'server-first-product',
                  serverVersion: '6',
                  projection: <String, dynamic>{'id': 'product-server-1'},
                ),
                _pulledChange(
                  entity: 'customer',
                  eventId: 'server-first-customer',
                  serverVersion: '7',
                  projection: <String, dynamic>{'id': 'customer-server-1'},
                ),
              ],
            ),
          ),
          projectionApplier: applier,
          snapshotRemoteDataSource: const _FakeAppSnapshotRemoteDataSource(
            version: '0',
          ),
          shouldContinue: () => true,
          onCacheSnapshotChanged: () {},
        );

        final result = await runner.run(retryOnly: false);

        expect(result.pullFailed, isFalse);
        expect(queue.checkpoint, '7');
        expect(applier.applied, isEmpty);
      },
    );

    test(
      'pull paginado nao salta checkpoint para status antes de aplicar tudo',
      () async {
        final queue = _MemoryOperationalSyncQueueRepository();
        final applier = _MemoryOperationalSyncProjectionApplier();
        final runner = OperationalSyncRunner(
          queueRepository: queue,
          remoteDataSource: _FakeOperationalSyncRemoteDataSource(
            statusServerVersion: '10',
            pullResponse: OperationalSyncPullResponse(
              currentServerVersion: '10',
              nextSinceVersion: '2',
              hasMore: true,
              usesProjectionContract: true,
              events: <OperationalSyncPulledEvent>[
                _pulledChange(
                  entity: 'sale',
                  eventId: 'sale-page-1',
                  serverVersion: '2',
                  projection: <String, dynamic>{
                    'entityServerId': 'sale-server-2',
                    'id': 'sale-server-2',
                    'localUuid': 'sale-local-page-1',
                  },
                ),
              ],
            ),
          ),
          projectionApplier: applier,
          snapshotRemoteDataSource: const _FakeAppSnapshotRemoteDataSource(
            version: '0',
          ),
          shouldContinue: () => true,
          onCacheSnapshotChanged: () {},
        );

        final result = await runner.run(retryOnly: false);

        expect(result.pullFailed, isFalse);
        expect(queue.checkpoint, '2');
        expect(applier.applied.single.eventId, 'sale-page-1');
      },
    );

    test('falha na segunda pagina mantem checkpoint da primeira', () async {
      final queue = _MemoryOperationalSyncQueueRepository();
      final applier = _MemoryOperationalSyncProjectionApplier(
        failOnEventIds: const <String>{'sale-second-page-fails'},
      );
      final runner = OperationalSyncRunner(
        queueRepository: queue,
        remoteDataSource: _FakeOperationalSyncRemoteDataSource(
          pullResponses: <OperationalSyncPullResponse>[
            OperationalSyncPullResponse(
              currentServerVersion: '2',
              nextSinceVersion: '1',
              hasMore: true,
              usesProjectionContract: true,
              events: <OperationalSyncPulledEvent>[
                _pulledChange(
                  entity: 'sale',
                  eventId: 'sale-first-page-before-failure',
                  serverVersion: '1',
                  projection: <String, dynamic>{
                    'entityServerId': 'sale-server-1',
                    'id': 'sale-server-1',
                    'localUuid': 'sale-local-1',
                  },
                ),
              ],
            ),
            OperationalSyncPullResponse(
              currentServerVersion: '2',
              nextSinceVersion: '2',
              hasMore: false,
              usesProjectionContract: true,
              events: <OperationalSyncPulledEvent>[
                _pulledChange(
                  entity: 'sale',
                  eventId: 'sale-second-page-fails',
                  serverVersion: '2',
                  projection: <String, dynamic>{
                    'entityServerId': 'sale-server-2',
                    'id': 'sale-server-2',
                    'localUuid': 'sale-local-2',
                  },
                ),
              ],
            ),
          ],
        ),
        projectionApplier: applier,
        snapshotRemoteDataSource: const _FakeAppSnapshotRemoteDataSource(
          version: '0',
        ),
        shouldContinue: () => true,
        onCacheSnapshotChanged: () {},
      );

      final result = await runner.run(retryOnly: false);

      expect(result.pullFailed, isTrue);
      expect(queue.checkpoint, '1');
      expect(queue.lastPullError, contains('projection failed'));
      expect(applier.applied.single.eventId, 'sale-first-page-before-failure');
    });

    test('hasMore true sem changes nao gera loop infinito', () async {
      final queue = _MemoryOperationalSyncQueueRepository();
      final remote = _FakeOperationalSyncRemoteDataSource(
        statusServerVersion: '10',
        pullResponse: const OperationalSyncPullResponse(
          currentServerVersion: '10',
          nextSinceVersion: '0',
          hasMore: true,
          usesProjectionContract: true,
          events: <OperationalSyncPulledEvent>[],
        ),
      );
      final runner = OperationalSyncRunner(
        queueRepository: queue,
        remoteDataSource: remote,
        snapshotRemoteDataSource: const _FakeAppSnapshotRemoteDataSource(
          version: '0',
        ),
        shouldContinue: () => true,
        onCacheSnapshotChanged: () {},
      );

      final result = await runner.run(retryOnly: false);

      expect(result.pullFailed, isFalse);
      expect(remote.pullCallCount, 1);
      expect(queue.checkpoint, '0');
      expect(queue.lastPullError, isNull);
    });

    test('serverVersion sem avanco nao gera loop infinito', () async {
      final queue = _MemoryOperationalSyncQueueRepository();
      final applier = _MemoryOperationalSyncProjectionApplier();
      final remote = _FakeOperationalSyncRemoteDataSource(
        pullResponses: <OperationalSyncPullResponse>[
          OperationalSyncPullResponse(
            currentServerVersion: '1',
            nextSinceVersion: '1',
            hasMore: true,
            usesProjectionContract: true,
            events: <OperationalSyncPulledEvent>[
              _pulledChange(
                entity: 'sale',
                eventId: 'sale-first-advancing-page',
                serverVersion: '1',
                projection: <String, dynamic>{
                  'entityServerId': 'sale-server-1',
                  'id': 'sale-server-1',
                  'localUuid': 'sale-local-1',
                },
              ),
            ],
          ),
          OperationalSyncPullResponse(
            currentServerVersion: '1',
            nextSinceVersion: '1',
            hasMore: true,
            usesProjectionContract: true,
            events: <OperationalSyncPulledEvent>[
              _pulledChange(
                entity: 'sale',
                eventId: 'sale-repeated-version',
                serverVersion: '1',
                projection: <String, dynamic>{
                  'entityServerId': 'sale-server-repeated',
                  'id': 'sale-server-repeated',
                  'localUuid': 'sale-local-repeated',
                },
              ),
            ],
          ),
        ],
      );
      final runner = OperationalSyncRunner(
        queueRepository: queue,
        remoteDataSource: remote,
        projectionApplier: applier,
        snapshotRemoteDataSource: const _FakeAppSnapshotRemoteDataSource(
          version: '0',
        ),
        shouldContinue: () => true,
        onCacheSnapshotChanged: () {},
      );

      final result = await runner.run(retryOnly: false);

      expect(result.pullFailed, isFalse);
      expect(remote.pullCallCount, 2);
      expect(queue.checkpoint, '1');
      expect(applier.applied.map((change) => change.eventId), [
        'sale-first-advancing-page',
      ]);
    });

    test('limite de paginas para rodada nao vira erro fatal', () async {
      final queue = _MemoryOperationalSyncQueueRepository();
      final applier = _MemoryOperationalSyncProjectionApplier();
      final remote = _FakeOperationalSyncRemoteDataSource(
        pullResponses: <OperationalSyncPullResponse>[
          for (
            var version = 1;
            version <= OperationalSyncRunner.maxPullPagesPerRun + 1;
            version++
          )
            OperationalSyncPullResponse(
              currentServerVersion: '20',
              nextSinceVersion: '$version',
              hasMore: true,
              usesProjectionContract: true,
              events: <OperationalSyncPulledEvent>[
                _pulledChange(
                  entity: 'sale',
                  eventId: 'sale-page-limit-$version',
                  serverVersion: '$version',
                  projection: <String, dynamic>{
                    'entityServerId': 'sale-server-$version',
                    'id': 'sale-server-$version',
                    'localUuid': 'sale-local-$version',
                  },
                ),
              ],
            ),
        ],
      );
      final runner = OperationalSyncRunner(
        queueRepository: queue,
        remoteDataSource: remote,
        projectionApplier: applier,
        snapshotRemoteDataSource: const _FakeAppSnapshotRemoteDataSource(
          version: '0',
        ),
        shouldContinue: () => true,
        onCacheSnapshotChanged: () {},
      );

      final result = await runner.run(retryOnly: false);

      expect(result.pullFailed, isFalse);
      expect(remote.pullCallCount, OperationalSyncRunner.maxPullPagesPerRun);
      expect(queue.checkpoint, '${OperationalSyncRunner.maxPullPagesPerRun}');
      expect(
        applier.applied,
        hasLength(OperationalSyncRunner.maxPullPagesPerRun),
      );
      expect(queue.lastPullError, isNull);
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

OperationalSyncPulledEvent _pulledChange({
  required String entity,
  required String eventId,
  required String serverVersion,
  Map<String, dynamic>? projection,
  String? projectionWarning,
}) {
  return OperationalSyncPulledEvent(
    eventId: eventId,
    feature: 'pdv',
    entity: entity,
    operation: 'create',
    entityLocalId: '$eventId-local',
    entityServerId: projection?['entityServerId'] as String?,
    occurredAt: DateTime(2026, 5, 5, 10),
    payload: <String, dynamic>{'id': eventId},
    serverVersion: serverVersion,
    materializedAt: DateTime(2026, 5, 5, 10, 1),
    projection: projection,
    projectionWarning: projectionWarning,
  );
}

Map<String, dynamic> _categorySnapshotItem({
  required String id,
  required String name,
}) {
  const now = '2026-05-05T08:00:00.000Z';
  return <String, dynamic>{
    'id': id,
    'companyId': 'company-1',
    'localUuid': id,
    'name': name,
    'description': null,
    'isActive': true,
    'deletedAt': null,
    'createdAt': now,
    'updatedAt': now,
  };
}

Map<String, dynamic> _productSnapshotItem({
  required String id,
  required String categoryId,
  List<Map<String, dynamic>> variants = const <Map<String, dynamic>>[],
}) {
  const now = '2026-05-05T08:00:00.000Z';
  return <String, dynamic>{
    'id': id,
    'companyId': 'company-1',
    'localUuid': id,
    'categoryId': categoryId,
    'name': 'Cafe coado',
    'description': null,
    'barcode': null,
    'productType': 'unidade',
    'niche': 'alimentacao',
    'catalogType': 'simple',
    'modelName': null,
    'variantLabel': null,
    'unitMeasure': 'un',
    'costPriceCents': 900,
    'manualCostCents': 900,
    'costSource': 'manual',
    'variableCostSnapshotCents': null,
    'estimatedGrossMarginCents': null,
    'estimatedGrossMarginPercentBasisPoints': null,
    'lastCostUpdatedAt': null,
    'salePriceCents': 2400,
    'stockMil': 12000,
    'variants': variants,
    'modifierGroups': const <Map<String, dynamic>>[],
    'isActive': true,
    'deletedAt': null,
    'createdAt': now,
    'updatedAt': now,
  };
}

Map<String, dynamic> _productVariantSnapshotItem({required String id}) {
  const now = '2026-05-05T08:00:00.000Z';
  return <String, dynamic>{
    'id': id,
    'sku': 'CAFE-001',
    'colorLabel': 'Unica',
    'sizeLabel': 'P',
    'priceAdditionalCents': 0,
    'stockMil': 12000,
    'sortOrder': 0,
    'isActive': true,
    'createdAt': now,
    'updatedAt': now,
  };
}

Map<String, dynamic> _supplierSnapshotItem({required String id}) {
  const now = '2026-05-05T08:00:00.000Z';
  return <String, dynamic>{
    'id': id,
    'companyId': 'company-1',
    'localUuid': id,
    'name': 'Fornecedor Cafe',
    'tradeName': null,
    'phone': null,
    'email': null,
    'address': null,
    'document': null,
    'contactPerson': null,
    'notes': null,
    'isActive': true,
    'deletedAt': null,
    'createdAt': now,
    'updatedAt': now,
  };
}

Map<String, dynamic> _customerSnapshotItem({required String id}) {
  const now = '2026-05-05T08:00:00.000Z';
  return <String, dynamic>{
    'id': id,
    'companyId': 'company-1',
    'localUuid': id,
    'name': 'Cliente Cafe',
    'phone': null,
    'address': null,
    'notes': null,
    'isActive': true,
    'deletedAt': null,
    'createdAt': now,
    'updatedAt': now,
  };
}

Map<String, dynamic> _cashSessionSnapshotItem({required String id}) {
  return <String, dynamic>{
    'id': id,
    'companyId': 'company-1',
    'localUuid': id,
    'operatorName': 'Operadora remota',
    'status': 'closed',
    'openedAt': '2026-05-05T08:00:00.000Z',
    'closedAt': '2026-05-05T18:00:00.000Z',
    'openingBalanceCents': 5000,
    'closingBalanceCents': 8200,
    'expectedBalanceCents': 8200,
    'notes': 'Sessao restaurada',
    'createdAt': '2026-05-05T08:00:00.000Z',
    'updatedAt': '2026-05-05T18:00:00.000Z',
  };
}

Map<String, dynamic> _cashMovementSnapshotItem({
  required String id,
  required String cashSessionId,
}) {
  return <String, dynamic>{
    'id': id,
    'companyId': 'company-1',
    'cashSessionId': cashSessionId,
    'localUuid': id,
    'eventType': 'venda',
    'amountCents': 3200,
    'paymentMethod': 'dinheiro',
    'referenceType': 'venda',
    'referenceId': 'sale-server-1',
    'notes': 'Venda restaurada',
    'createdAt': '2026-05-05T12:00:00.000Z',
    'updatedAt': '2026-05-05T12:00:00.000Z',
  };
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

class _MemoryOperationalSyncProjectionApplier
    implements OperationalSyncProjectionApplier {
  _MemoryOperationalSyncProjectionApplier({
    this.failOnEventIds = const <String>{},
  });

  final Set<String> failOnEventIds;
  final applied = <OperationalSyncPulledEvent>[];

  @override
  Future<void> apply(OperationalSyncPulledEvent change) async {
    if (failOnEventIds.contains(change.eventId)) {
      throw StateError('projection failed for ${change.eventId}');
    }
    applied.add(change);
  }
}

class _FakeOperationalSyncRemoteDataSource
    implements OperationalSyncRemoteDataSource {
  _FakeOperationalSyncRemoteDataSource({
    OperationalSyncPushResponse? pushResponse,
    OperationalSyncPullResponse? pullResponse,
    List<OperationalSyncPullResponse>? pullResponses,
    this.statusServerVersion = '0',
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
           ),
       pullResponses =
           pullResponses ??
           <OperationalSyncPullResponse>[
             pullResponse ??
                 const OperationalSyncPullResponse(
                   currentServerVersion: '0',
                   nextSinceVersion: '0',
                   hasMore: false,
                   events: <OperationalSyncPulledEvent>[],
                 ),
           ];

  final OperationalSyncPushResponse pushResponse;
  final List<OperationalSyncPullResponse> pullResponses;
  final String statusServerVersion;
  final List<OperationalSyncConflict> conflicts;
  final bool failPull;
  List<OperationalSyncEvent> lastPushedEvents = const <OperationalSyncEvent>[];
  final pulledSinceVersions = <String>[];
  int _pullCallCount = 0;

  int get pullCallCount => _pullCallCount;

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
    _pullCallCount++;
    pulledSinceVersions.add(sinceVersion);
    if (failPull) {
      throw StateError('pull offline');
    }
    final index = _pullCallCount - 1;
    if (index < pullResponses.length) {
      return pullResponses[index];
    }
    return pullResponses.last;
  }

  @override
  Future<OperationalSyncStatusResponse> getStatus() async {
    return OperationalSyncStatusResponse(
      companyId: 'company-1',
      deviceId: 'device-1',
      syncEnabled: true,
      currentServerVersion: statusServerVersion,
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
    this.features = const <String, AppSnapshotFeature>{},
    this.fail = false,
  });

  final String version;
  final Map<String, AppSnapshotFeature> features;
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
      features: this.features,
    );
  }
}
