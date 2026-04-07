import 'package:sqflite/sqflite.dart';

import '../app_context/record_identity.dart';
import '../database/app_database.dart';
import '../database/table_names.dart';
import 'sqlite_sync_metadata_repository.dart';
import 'sync_feature_keys.dart';
import 'sync_feature_summary.dart';
import 'sync_metadata.dart';
import 'sync_readiness_repository.dart';
import 'sync_status.dart';

class SqliteSyncReadinessRepository implements SyncReadinessRepository {
  SqliteSyncReadinessRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<List<SyncFeatureSummary>> listFeatureSummaries() async {
    final database = await _appDatabase.database;
    final metadataRepository = SqliteSyncMetadataRepository(_appDatabase);

    final salesMetadata = await metadataRepository.listByFeature(
      SyncFeatureKeys.sales,
    );
    final saleCancellationMetadata = await metadataRepository.listByFeature(
      SyncFeatureKeys.saleCancellations,
    );
    final fiadoPaymentMetadata = await metadataRepository.listByFeature(
      SyncFeatureKeys.fiadoPayments,
    );
    final financialEventMetadata = <SyncMetadata>[
      ...saleCancellationMetadata,
      ...fiadoPaymentMetadata,
    ];
    final cashEventMetadata = await metadataRepository.listByFeature(
      SyncFeatureKeys.cashEvents,
    );

    final fiadoMetadata = await _loadMetadata(
      database,
      sql:
          '''
        SELECT
          id,
          uuid,
          criado_em AS created_at,
          atualizado_em AS updated_at
        FROM ${TableNames.fiado}
      ''',
      featureKey: SyncFeatureKeys.fiado,
    );

    final cashMetadata = await _loadMetadata(
      database,
      sql:
          '''
        SELECT
          id,
          uuid,
          criado_em AS created_at,
          criado_em AS updated_at
        FROM ${TableNames.caixaMovimentos}
      ''',
      featureKey: SyncFeatureKeys.cashMovements,
    );

    final categoryMetadata = await metadataRepository.listByFeature(
      SyncFeatureKeys.categories,
    );
    final productMetadata = await metadataRepository.listByFeature(
      SyncFeatureKeys.products,
    );
    final customerMetadata = await metadataRepository.listByFeature(
      SyncFeatureKeys.customers,
    );
    final supplierMetadata = await metadataRepository.listByFeature(
      SyncFeatureKeys.suppliers,
    );
    final purchaseMetadata = await metadataRepository.listByFeature(
      SyncFeatureKeys.purchases,
    );

    return <SyncFeatureSummary>[
      SyncFeatureSummary.fromMetadata(
        featureKey: SyncFeatureKeys.categories,
        displayName: 'Categorias',
        metadata: categoryMetadata,
      ),
      SyncFeatureSummary.fromMetadata(
        featureKey: SyncFeatureKeys.products,
        displayName: 'Produtos',
        metadata: productMetadata,
      ),
      SyncFeatureSummary.fromMetadata(
        featureKey: SyncFeatureKeys.customers,
        displayName: 'Clientes',
        metadata: customerMetadata,
      ),
      SyncFeatureSummary.fromMetadata(
        featureKey: SyncFeatureKeys.suppliers,
        displayName: 'Fornecedores',
        metadata: supplierMetadata,
      ),
      SyncFeatureSummary.fromMetadata(
        featureKey: SyncFeatureKeys.purchases,
        displayName: 'Compras',
        metadata: purchaseMetadata,
      ),
      SyncFeatureSummary.fromMetadata(
        featureKey: SyncFeatureKeys.sales,
        displayName: 'Vendas',
        metadata: salesMetadata,
      ),
      SyncFeatureSummary.fromMetadata(
        featureKey: SyncFeatureKeys.financialEvents,
        displayName: 'Eventos financeiros',
        metadata: financialEventMetadata,
      ),
      SyncFeatureSummary.fromMetadata(
        featureKey: SyncFeatureKeys.cashEvents,
        displayName: 'Eventos de caixa',
        metadata: cashEventMetadata,
      ),
      SyncFeatureSummary.fromMetadata(
        featureKey: SyncFeatureKeys.fiado,
        displayName: 'Fiado',
        metadata: fiadoMetadata,
      ),
      SyncFeatureSummary.fromMetadata(
        featureKey: SyncFeatureKeys.cashMovements,
        displayName: 'Movimentos de caixa',
        metadata: cashMetadata,
      ),
    ];
  }

  Future<List<SyncMetadata>> _loadMetadata(
    DatabaseExecutor database, {
    required String sql,
    required String featureKey,
  }) async {
    final rows = await database.rawQuery(sql);
    return <SyncMetadata>[
      for (final row in rows)
        SyncMetadata(
          featureKey: featureKey,
          identity: RecordIdentity.local(
            localId: row['id'] as int?,
            localUuid: row['uuid'] as String?,
          ),
          status: SyncStatus.localOnly,
          createdAt: DateTime.parse(row['created_at'] as String),
          updatedAt: DateTime.parse(row['updated_at'] as String),
          lastSyncedAt: null,
          lastError: null,
          lastErrorType: null,
          lastErrorAt: null,
        ),
    ];
  }
}
