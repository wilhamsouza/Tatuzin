import 'package:erp_pdv_app/app/core/app_context/record_identity.dart';
import 'package:erp_pdv_app/app/core/database/app_database.dart';
import 'package:erp_pdv_app/app/core/database/table_names.dart';
import 'package:erp_pdv_app/app/core/sync/sqlite_sync_metadata_repository.dart';
import 'package:erp_pdv_app/app/core/sync/sync_feature_keys.dart';
import 'package:erp_pdv_app/modules/produtos/data/models/remote_product_record.dart';
import 'package:erp_pdv_app/modules/produtos/data/sqlite_product_repository.dart';
import 'package:erp_pdv_app/modules/produtos/domain/entities/product.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'upsert remoto de produto resolve categoria dentro da transacao',
    () async {
      final isolationKey =
          'remote:product-upsert-${DateTime.now().microsecondsSinceEpoch}';
      final appDatabase = AppDatabase.forIsolationKey(isolationKey);
      addTearDown(() async {
        await appDatabase.close();
        await AppDatabase.deleteDatabaseForIsolationKeyForTesting(isolationKey);
      });

      final database = await appDatabase.database;
      final now = DateTime.now();
      final categoryId = await database.insert(TableNames.categorias, {
        'uuid': 'cat-local',
        'nome': 'Bebidas',
        'descricao': null,
        'ativo': 1,
        'criado_em': now.toIso8601String(),
        'atualizado_em': now.toIso8601String(),
        'deletado_em': null,
      });
      await SqliteSyncMetadataRepository(appDatabase).markSynced(
        database,
        featureKey: SyncFeatureKeys.categories,
        localId: categoryId,
        localUuid: 'cat-local',
        remoteId: 'cat-remote',
        origin: RecordOrigin.remote,
        createdAt: now,
        updatedAt: now,
        syncedAt: now,
      );

      final repository = SqliteProductRepository(appDatabase);
      await repository
          .upsertFromRemote(
            RemoteProductRecord(
              remoteId: 'prod-remote',
              localUuid: 'prod-local',
              remoteCategoryId: 'cat-remote',
              name: 'Cafe coado',
              description: null,
              barcode: null,
              productType: 'unidade',
              niche: ProductNiches.food,
              catalogType: ProductCatalogTypes.simple,
              modelName: null,
              variantLabel: null,
              unitMeasure: 'un',
              costCents: 100,
              manualCostCents: 100,
              costSource: ProductCostSource.manual,
              variableCostSnapshotCents: null,
              estimatedGrossMarginCents: null,
              estimatedGrossMarginPercentBasisPoints: null,
              lastCostUpdatedAt: null,
              salePriceCents: 300,
              stockMil: 2000,
              isActive: true,
              createdAt: now,
              updatedAt: now,
              deletedAt: null,
            ),
          )
          .timeout(const Duration(seconds: 3));

      final rows = await database.query(
        TableNames.produtos,
        columns: const ['nome', 'categoria_id'],
        where: 'uuid = ?',
        whereArgs: const ['prod-local'],
        limit: 1,
      );

      expect(rows, hasLength(1));
      expect(rows.single['nome'], 'Cafe coado');
      expect(rows.single['categoria_id'], categoryId);
    },
  );
}
