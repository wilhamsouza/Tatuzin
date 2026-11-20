import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tatuzin/app/core/database/app_database.dart';
import 'package:tatuzin/app/core/database/table_names.dart';
import 'package:tatuzin/app/core/errors/app_exceptions.dart';
import 'package:tatuzin/app/core/sync/operational_sync_event.dart';
import 'package:tatuzin/app/core/sync/sqlite_operational_sync_queue_repository.dart';
import 'package:tatuzin/modules/produtos/data/models/remote_product_record.dart';
import 'package:tatuzin/modules/produtos/data/sqlite_product_repository.dart';
import 'package:tatuzin/modules/produtos/domain/entities/product.dart';

RemoteProductRecord _remote({
  int revision = 1,
  int stock = 9000,
  bool variant = false,
  String sku = 'CAM-P',
  String name = 'Camisa',
}) => RemoteProductRecord.fromJson({
  'id': 'remote-product',
  'localUuid': 'local-product',
  'name': name,
  'catalogRevision': revision,
  'niche': 'moda',
  'catalogType': variant ? 'variant' : 'simple',
  'modelName': variant ? 'Camisa' : null,
  'variantLabel': variant ? 'Cor/tamanho' : null,
  'stockMil': stock,
  'isActive': true,
  'costPriceCents': 200,
  'salePriceCents': 500,
  'createdAt': '2026-01-01T00:00:00Z',
  'updatedAt': '2026-01-0${revision + 1}T00:00:00Z',
  'variants': variant
      ? [
          {
            'id': 'remote-variant',
            'sku': sku,
            'colorLabel': 'Azul',
            'sizeLabel': 'P',
            'stockMil': stock,
            'isActive': true,
          },
        ]
      : [],
});
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late AppDatabase app;
  late String isolationKey;
  late SqliteProductRepository repository;
  late Database db;
  setUp(() async {
    isolationKey =
        'remote:stock-consistency-${DateTime.now().microsecondsSinceEpoch}';
    app = AppDatabase.forIsolationKey(isolationKey);
    db = await app.database;
    repository = SqliteProductRepository(app);
  });
  tearDown(() async {
    await app.close();
    await AppDatabase.deleteDatabaseForIsolationKeyForTesting(isolationKey);
  });
  for (final status in [
    'pending',
    'pushing',
    'failed',
    'rejected',
    'conflict',
  ]) {
    test(
      'snapshot e retorno de cadastro preservam saldo local com evento $status',
      () async {
        await repository.upsertFromRemote(_remote(variant: true));
        final product = (await repository.findByRemoteId('remote-product'))!;
        await db.update(
          TableNames.produtos,
          {'estoque_mil': 7000},
          where: 'id = ?',
          whereArgs: [product.id],
        );
        await db.update(
          TableNames.produtoVariantes,
          {'estoque_mil': 7000},
          where: 'produto_id = ?',
          whereArgs: [product.id],
        );
        final queue = SqliteOperationalSyncQueueRepository(app);
        await queue.enqueue(
          db,
          event: OperationalSyncEvent(
            eventId: 'test-event',
            feature: 'pdv',
            entity: 'sale',
            operation: 'create',
            occurredAt: DateTime.now(),
            payload: const {},
          ),
        );
        await db.update(
          TableNames.operationalSyncEvents,
          {'status': status},
          where: 'event_id = ?',
          whereArgs: ['test-event'],
        );
        await repository.upsertFromRemote(
          _remote(revision: 2, stock: 9000, variant: true),
        );
        var updated = (await repository.findByRemoteId('remote-product'))!;
        expect(updated.stockMil, 7000);
        expect(updated.variants.single.stockMil, 7000);
        await repository.applyPushResult(
          product: updated,
          remote: _remote(revision: 3, stock: 9000, variant: true),
        );
        updated = (await repository.findByRemoteId('remote-product'))!;
        expect(updated.stockMil, 7000);
        expect(updated.variants.single.stockMil, 7000);
        expect(updated.catalogRevision, 3);
      },
    );
  }
  test(
    'evento confirmado permite atualizar snapshot sem segunda baixa',
    () async {
      await repository.upsertFromRemote(_remote());
      final queue = SqliteOperationalSyncQueueRepository(app);
      await queue.enqueue(
        db,
        event: OperationalSyncEvent(
          eventId: 'confirmed',
          feature: 'pdv',
          entity: 'sale',
          operation: 'create',
          occurredAt: DateTime.now(),
          payload: const {},
        ),
      );
      await queue.markAccepted(
        eventId: 'confirmed',
        serverVersion: '1',
        processedAt: DateTime.now(),
      );
      await repository.upsertFromRemote(_remote(revision: 2, stock: 7000));
      expect(
        (await repository.findByRemoteId('remote-product'))!.stockMil,
        7000,
      );
    },
  );
  test(
    'editar metadados não altera quantidade e revisão antiga é recusada',
    () async {
      await repository.upsertFromRemote(_remote(revision: 2, stock: 5000));
      final product = (await repository.findByRemoteId('remote-product'))!;
      const stale = ProductInput(
        expectedCatalogRevision: 1,
        name: 'Nome antigo',
        unitMeasure: 'un',
        costCents: 100,
        salePriceCents: 600,
        stockMil: 99000,
      );
      await expectLater(
        repository.update(product.id, stale),
        throwsA(isA<ValidationException>()),
      );
      await repository.update(
        product.id,
        const ProductInput(
          expectedCatalogRevision: 2,
          name: 'Novo nome',
          unitMeasure: 'un',
          costCents: 100,
          salePriceCents: 600,
          stockMil: 99000,
        ),
      );
      final updated = (await repository.findByRemoteId('remote-product'))!;
      expect(updated.name, 'Novo nome');
      expect(updated.stockMil, 5000);
    },
  );
  test(
    'variação mantém ID ao mudar SKU e não é apagada quando removida do catálogo',
    () async {
      await repository.upsertFromRemote(_remote(variant: true));
      final before = (await repository.findByRemoteId('remote-product'))!;
      final originalId = before.variants.single.id;
      await repository.upsertFromRemote(
        _remote(revision: 2, variant: true, sku: 'NOVO-P'),
      );
      final after = (await repository.findByRemoteId('remote-product'))!;
      expect(after.variants.single.id, originalId);
      expect(after.variants.single.sku, 'NOVO-P');
      await repository.upsertFromRemote(_remote(revision: 3, variant: false));
      final row = (await db.query(
        TableNames.produtoVariantes,
        where: 'id = ?',
        whereArgs: [originalId],
      )).single;
      expect(row['ativo'], 0);
    },
  );
  test('corpo do catálogo envia revisão e identidade, separado de estoque', () {
    final body = _remote(revision: 3, variant: true).toUpsertBody();
    expect(body['metadataOnly'], isTrue);
    expect(body['expectedCatalogRevision'], 3);
    expect((body['variants'] as List).single['id'], 'remote-variant');
  });
}
