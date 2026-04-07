import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../modules/categorias/data/datasources/categories_remote_datasource.dart';
import '../../../modules/categorias/data/models/remote_category_record.dart';
import '../../../modules/clientes/data/datasources/customers_remote_datasource.dart';
import '../../../modules/clientes/data/models/remote_customer_record.dart';
import '../../../modules/compras/data/datasources/purchases_remote_datasource.dart';
import '../../../modules/compras/data/models/remote_purchase_record.dart';
import '../../../modules/compras/data/sqlite_purchase_repository.dart';
import '../../../modules/compras/domain/entities/purchase_status.dart';
import '../../../modules/fiado/data/sqlite_fiado_repository.dart';
import '../../../modules/fornecedores/data/datasources/suppliers_remote_datasource.dart';
import '../../../modules/fornecedores/data/models/remote_supplier_record.dart';
import '../../../modules/produtos/data/datasources/products_remote_datasource.dart';
import '../../../modules/produtos/data/models/remote_product_record.dart';
import '../../../modules/vendas/data/datasources/sales_remote_datasource.dart';
import '../../../modules/vendas/data/models/remote_sale_record.dart';
import '../../../modules/vendas/data/sqlite_sale_repository.dart';
import '../../../modules/vendas/domain/entities/sale_enums.dart';
import '../app_context/record_identity.dart';
import '../database/app_database.dart';
import '../database/table_names.dart';
import 'financial_events_remote_datasource.dart';
import 'remote_financial_event_record.dart';
import 'sqlite_sync_audit_repository.dart';
import 'sqlite_sync_metadata_repository.dart';
import 'sqlite_sync_queue_repository.dart';
import 'sync_audit_event_type.dart';
import 'sync_error_type.dart';
import 'sync_feature_keys.dart';
import 'sync_metadata.dart';
import 'sync_queue_item.dart';
import 'sync_queue_operation.dart';
import 'sync_queue_status.dart';
import 'sync_reconciliation_issue.dart';
import 'sync_reconciliation_repository.dart';
import 'sync_reconciliation_result.dart';
import 'sync_reconciliation_status.dart';
import 'sync_repair_action.dart';
import 'sync_repair_action_type.dart';
import 'sync_repair_decision.dart';
import 'sync_repair_repository.dart';
import 'sync_repair_result.dart';
import 'sync_repair_summary.dart';
import 'sync_repair_target.dart';
import 'sync_repairability.dart';
import 'sync_status.dart';

class LocalRemoteReconciliationRepository
    implements SyncReconciliationRepository, SyncRepairRepository {
  LocalRemoteReconciliationRepository({
    required AppDatabase appDatabase,
    required SuppliersRemoteDatasource suppliersRemoteDatasource,
    required CategoriesRemoteDatasource categoriesRemoteDatasource,
    required ProductsRemoteDatasource productsRemoteDatasource,
    required CustomersRemoteDatasource customersRemoteDatasource,
    required PurchasesRemoteDatasource purchasesRemoteDatasource,
    required SalesRemoteDatasource salesRemoteDatasource,
    required FinancialEventsRemoteDatasource financialEventsRemoteDatasource,
    required SqlitePurchaseRepository purchaseRepository,
    required SqliteSaleRepository saleRepository,
    required SqliteFiadoRepository fiadoRepository,
  }) : _appDatabase = appDatabase,
       _suppliersRemoteDatasource = suppliersRemoteDatasource,
       _categoriesRemoteDatasource = categoriesRemoteDatasource,
       _productsRemoteDatasource = productsRemoteDatasource,
       _customersRemoteDatasource = customersRemoteDatasource,
       _purchasesRemoteDatasource = purchasesRemoteDatasource,
       _salesRemoteDatasource = salesRemoteDatasource,
       _financialEventsRemoteDatasource = financialEventsRemoteDatasource,
       _purchaseRepository = purchaseRepository,
       _saleRepository = saleRepository,
       _fiadoRepository = fiadoRepository,
       _syncMetadataRepository = SqliteSyncMetadataRepository(appDatabase),
       _syncQueueRepository = SqliteSyncQueueRepository(appDatabase),
       _syncAuditRepository = SqliteSyncAuditRepository(appDatabase);

  final AppDatabase _appDatabase;
  final SuppliersRemoteDatasource _suppliersRemoteDatasource;
  final CategoriesRemoteDatasource _categoriesRemoteDatasource;
  final ProductsRemoteDatasource _productsRemoteDatasource;
  final CustomersRemoteDatasource _customersRemoteDatasource;
  final PurchasesRemoteDatasource _purchasesRemoteDatasource;
  final SalesRemoteDatasource _salesRemoteDatasource;
  final FinancialEventsRemoteDatasource _financialEventsRemoteDatasource;
  final SqlitePurchaseRepository _purchaseRepository;
  final SqliteSaleRepository _saleRepository;
  final SqliteFiadoRepository _fiadoRepository;
  final SqliteSyncMetadataRepository _syncMetadataRepository;
  final SqliteSyncQueueRepository _syncQueueRepository;
  final SqliteSyncAuditRepository _syncAuditRepository;

  @override
  Future<List<SyncReconciliationResult>> reconcileAll() async {
    return <SyncReconciliationResult>[
      await reconcileFeature(SyncFeatureKeys.suppliers),
      await reconcileFeature(SyncFeatureKeys.categories),
      await reconcileFeature(SyncFeatureKeys.products),
      await reconcileFeature(SyncFeatureKeys.customers),
      await reconcileFeature(SyncFeatureKeys.purchases),
      await reconcileFeature(SyncFeatureKeys.sales),
      await reconcileFeature(SyncFeatureKeys.financialEvents),
    ];
  }

  @override
  Future<SyncReconciliationResult> reconcileFeature(String featureKey) async {
    return switch (featureKey) {
      SyncFeatureKeys.suppliers => _reconcileSuppliers(),
      SyncFeatureKeys.categories => _reconcileCategories(),
      SyncFeatureKeys.products => _reconcileProducts(),
      SyncFeatureKeys.customers => _reconcileCustomers(),
      SyncFeatureKeys.purchases => _reconcilePurchases(),
      SyncFeatureKeys.sales => _reconcileSales(),
      SyncFeatureKeys.financialEvents => _reconcileFinancialEvents(),
      _ => _unknownFeature(featureKey),
    };
  }

  @override
  Future<int> markFeatureForResync(String featureKey) async {
    final result = await reconcileFeature(featureKey);
    final repairableIssues = result.issues
        .where((issue) => issue.canMarkForResync && issue.localEntityId != null)
        .toList();

    if (repairableIssues.isEmpty) {
      return 0;
    }

    final database = await _appDatabase.database;
    var repairedCount = 0;
    await database.transaction((txn) async {
      for (final issue in repairableIssues) {
        final repaired = await _repairIssue(txn, featureKey, issue);
        if (repaired) {
          repairedCount++;
        }
      }
    });

    if (repairedCount > 0) {
      await _syncAuditRepository.log(
        featureKey: featureKey,
        eventType: SyncAuditEventType.repairQueued,
        message:
            '$repairedCount item(ns) de ${syncFeatureDisplayName(featureKey)} foram marcados para reenvio.',
        details: <String, dynamic>{
          'repairableCount': repairableIssues.length,
          'repairedCount': repairedCount,
        },
      );
    }

    return repairedCount;
  }

  @override
  List<SyncRepairDecision> buildDecisions(
    List<SyncReconciliationResult> reconciliationResults,
  ) {
    final allIssues = <SyncReconciliationIssue>[
      for (final result in reconciliationResults) ...result.issues,
    ];
    final decisions = <SyncRepairDecision>[];
    for (final result in reconciliationResults) {
      for (final issue in result.issues) {
        if (issue.status.isHealthy) {
          continue;
        }
        decisions.add(_buildDecision(issue, allIssues));
      }
    }

    decisions.sort((left, right) {
      final severity = _repairPriority(right).compareTo(_repairPriority(left));
      if (severity != 0) {
        return severity;
      }
      return right.confidence.compareTo(left.confidence);
    });
    return decisions;
  }

  @override
  SyncRepairSummary buildSummary(List<SyncRepairDecision> decisions) {
    if (decisions.isEmpty) {
      return const SyncRepairSummary.empty();
    }

    var autoSafeCount = 0;
    var assistedSafeCount = 0;
    var manualReviewCount = 0;
    var blockedCount = 0;
    var notRepairableCount = 0;
    var batchSafeCount = 0;

    for (final decision in decisions) {
      switch (decision.repairability) {
        case SyncRepairability.autoSafe:
          autoSafeCount++;
          break;
        case SyncRepairability.assistedSafe:
          assistedSafeCount++;
          break;
        case SyncRepairability.manualReviewOnly:
          manualReviewCount++;
          break;
        case SyncRepairability.blocked:
          blockedCount++;
          break;
        case SyncRepairability.notRepairableYet:
          notRepairableCount++;
          break;
      }

      if (decision.isBatchSafe) {
        batchSafeCount++;
      }
    }

    return SyncRepairSummary(
      totalIssues: decisions.length,
      autoSafeCount: autoSafeCount,
      assistedSafeCount: assistedSafeCount,
      manualReviewCount: manualReviewCount,
      blockedCount: blockedCount,
      notRepairableCount: notRepairableCount,
      batchSafeCount: batchSafeCount,
    );
  }

  @override
  Future<SyncRepairResult> applyAction(SyncRepairAction action) async {
    final executedAt = DateTime.now();
    final freshResults = <SyncReconciliationResult>[
      await reconcileFeature(action.target.featureKey),
    ];
    final decision = _findDecision(buildDecisions(freshResults), action.target);
    if (decision == null) {
      await _syncAuditRepository.log(
        featureKey: action.target.featureKey,
        entityType: action.target.entityType,
        localEntityId: action.target.localEntityId,
        localUuid: action.target.localUuid,
        remoteId: action.target.remoteId,
        eventType: SyncAuditEventType.repairSkipped,
        message: 'Repair ignorado porque o alvo nao possui mais issue ativa.',
        details: <String, dynamic>{'actionType': action.type.storageValue},
        createdAt: executedAt,
      );
      return SyncRepairResult(
        requestedCount: 1,
        appliedCount: 0,
        skippedCount: 1,
        failedCount: 0,
        executedAt: executedAt,
        actionType: action.type,
        message: 'O item nao exige mais repair no estado atual.',
      );
    }

    final issue = _findIssue(freshResults, action.target);
    if (issue == null) {
      return SyncRepairResult(
        requestedCount: 1,
        appliedCount: 0,
        skippedCount: 1,
        failedCount: 0,
        executedAt: executedAt,
        actionType: action.type,
        message: 'Nao foi possivel localizar a issue atual para repair.',
      );
    }

    if (!decision.availableActions.contains(action.type)) {
      final eventType = decision.needsManualReview
          ? SyncAuditEventType.repairManualReviewRequired
          : SyncAuditEventType.repairSkipped;
      await _syncAuditRepository.log(
        featureKey: action.target.featureKey,
        entityType: action.target.entityType,
        localEntityId: action.target.localEntityId,
        localUuid: action.target.localUuid,
        remoteId: action.target.remoteId,
        eventType: eventType,
        message: decision.needsManualReview
            ? 'O caso exige revisao manual antes de qualquer repair.'
            : 'A acao solicitada nao e segura para o estado atual do item.',
        details: <String, dynamic>{
          'actionType': action.type.storageValue,
          'repairability': decision.repairability.name,
          'reason': decision.reason,
          'confidence': decision.confidence,
        },
        createdAt: executedAt,
      );
      return SyncRepairResult(
        requestedCount: 1,
        appliedCount: 0,
        skippedCount: 1,
        failedCount: 0,
        executedAt: executedAt,
        actionType: action.type,
        message: decision.needsManualReview
            ? 'Este caso segue em revisao manual.'
            : 'A acao nao esta disponivel para o estado atual.',
      );
    }

    await _syncAuditRepository.log(
      featureKey: action.target.featureKey,
      entityType: action.target.entityType,
      localEntityId: action.target.localEntityId,
      localUuid: action.target.localUuid,
      remoteId: action.target.remoteId,
      eventType: SyncAuditEventType.repairRequested,
      message: 'Repair solicitado para ${action.type.label.toLowerCase()}.',
      details: <String, dynamic>{
        'actionType': action.type.storageValue,
        'reason': action.reason,
        'confidence': action.confidence,
        'beforeStatus': issue.status.name,
        'beforeQueueStatus': issue.queueStatus?.storageValue,
        'beforeMetadataStatus': issue.metadataStatus?.storageValue,
        'beforeRemoteId': issue.remoteId,
      },
      createdAt: executedAt,
    );

    try {
      var applied = false;
      await (await _appDatabase.database).transaction((txn) async {
        applied = await _applyRepairAction(txn, issue, decision, action.type);
      });

      final refreshed = await reconcileFeature(action.target.featureKey);
      final afterIssue = _findIssue(<SyncReconciliationResult>[
        refreshed,
      ], action.target);
      await _logRepairOutcome(
        action: action,
        issue: issue,
        decision: decision,
        applied: applied,
        afterIssue: afterIssue,
        executedAt: executedAt,
      );

      return SyncRepairResult(
        requestedCount: 1,
        appliedCount: applied ? 1 : 0,
        skippedCount: applied ? 0 : 1,
        failedCount: 0,
        executedAt: executedAt,
        actionType: action.type,
        message: applied
            ? 'Repair aplicado com sucesso.'
            : 'Nenhuma alteracao foi aplicada no estado atual.',
      );
    } catch (error) {
      await _syncAuditRepository.log(
        featureKey: action.target.featureKey,
        entityType: action.target.entityType,
        localEntityId: action.target.localEntityId,
        localUuid: action.target.localUuid,
        remoteId: action.target.remoteId,
        eventType: SyncAuditEventType.repairFailed,
        message: 'Repair falhou: $error',
        details: <String, dynamic>{
          'actionType': action.type.storageValue,
          'reason': action.reason,
        },
        createdAt: executedAt,
      );
      return SyncRepairResult(
        requestedCount: 1,
        appliedCount: 0,
        skippedCount: 0,
        failedCount: 1,
        executedAt: executedAt,
        actionType: action.type,
        message: 'Falha ao aplicar repair: $error',
      );
    }
  }

  @override
  Future<SyncRepairResult> applySafeRepairs({
    Iterable<String>? featureKeys,
  }) async {
    final executedAt = DateTime.now();
    final results = featureKeys == null
        ? await reconcileAll()
        : <SyncReconciliationResult>[
            for (final featureKey in featureKeys)
              await reconcileFeature(featureKey),
          ];
    final decisions = buildDecisions(results)
        .where(
          (decision) =>
              decision.isBatchSafe && decision.suggestedActionType != null,
        )
        .toList();

    if (decisions.isEmpty) {
      return SyncRepairResult(
        requestedCount: 0,
        appliedCount: 0,
        skippedCount: 0,
        failedCount: 0,
        executedAt: executedAt,
        message: 'Nao ha repairs seguros disponiveis em lote.',
      );
    }

    var appliedCount = 0;
    var skippedCount = 0;
    var failedCount = 0;

    for (final decision in decisions) {
      final result = await applyAction(
        SyncRepairAction(
          type: decision.suggestedActionType!,
          target: decision.target,
          confidence: decision.confidence,
          reason: decision.reason,
        ),
      );
      appliedCount += result.appliedCount;
      skippedCount += result.skippedCount;
      failedCount += result.failedCount;
    }

    return SyncRepairResult(
      requestedCount: decisions.length,
      appliedCount: appliedCount,
      skippedCount: skippedCount,
      failedCount: failedCount,
      executedAt: executedAt,
      message: appliedCount > 0
          ? 'Repair em lote concluido com acoes seguras.'
          : 'Nenhum repair em lote foi aplicado.',
    );
  }

  Future<SyncReconciliationResult> _reconcileCategories() async {
    final metadataByLocalId = await _loadMetadataByLocalId(
      SyncFeatureKeys.categories,
    );
    final queueByEntityKey = await _loadQueueByEntityKey(const <String>[
      SyncFeatureKeys.categories,
    ]);
    final localRecords = await _loadLocalCategories(
      metadataByLocalId: metadataByLocalId,
      queueByEntityKey: queueByEntityKey,
    );

    try {
      final remoteRecords = (await _categoriesRemoteDatasource.listAll())
          .map(_mapRemoteCategory)
          .toList();
      final result = _reconcileComparableFeature(
        featureKey: SyncFeatureKeys.categories,
        displayName: syncFeatureDisplayName(SyncFeatureKeys.categories),
        localRecords: localRecords,
        remoteRecords: remoteRecords,
      );
      await _logReconciliationResult(result);
      return result;
    } catch (error) {
      return _buildFetchFailureResult(
        featureKey: SyncFeatureKeys.categories,
        totalLocal: localRecords.length,
        error: error,
      );
    }
  }

  Future<SyncReconciliationResult> _reconcileSuppliers() async {
    final metadataByLocalId = await _loadMetadataByLocalId(
      SyncFeatureKeys.suppliers,
    );
    final queueByEntityKey = await _loadQueueByEntityKey(const <String>[
      SyncFeatureKeys.suppliers,
    ]);
    final localRecords = await _loadLocalSuppliers(
      metadataByLocalId: metadataByLocalId,
      queueByEntityKey: queueByEntityKey,
    );

    try {
      final remoteRecords = (await _suppliersRemoteDatasource.listAll())
          .map(_mapRemoteSupplier)
          .toList();
      final result = _reconcileComparableFeature(
        featureKey: SyncFeatureKeys.suppliers,
        displayName: syncFeatureDisplayName(SyncFeatureKeys.suppliers),
        localRecords: localRecords,
        remoteRecords: remoteRecords,
      );
      await _logReconciliationResult(result);
      return result;
    } catch (error) {
      return _buildFetchFailureResult(
        featureKey: SyncFeatureKeys.suppliers,
        totalLocal: localRecords.length,
        error: error,
      );
    }
  }

  Future<SyncReconciliationResult> _reconcileProducts() async {
    final metadataByLocalId = await _loadMetadataByLocalId(
      SyncFeatureKeys.products,
    );
    final queueByEntityKey = await _loadQueueByEntityKey(const <String>[
      SyncFeatureKeys.products,
    ]);
    final localRecords = await _loadLocalProducts(
      metadataByLocalId: metadataByLocalId,
      queueByEntityKey: queueByEntityKey,
    );

    try {
      final remoteRecords = (await _productsRemoteDatasource.listAll())
          .map(_mapRemoteProduct)
          .toList();
      final result = _reconcileComparableFeature(
        featureKey: SyncFeatureKeys.products,
        displayName: syncFeatureDisplayName(SyncFeatureKeys.products),
        localRecords: localRecords,
        remoteRecords: remoteRecords,
      );
      await _logReconciliationResult(result);
      return result;
    } catch (error) {
      return _buildFetchFailureResult(
        featureKey: SyncFeatureKeys.products,
        totalLocal: localRecords.length,
        error: error,
      );
    }
  }

  Future<SyncReconciliationResult> _reconcileCustomers() async {
    final metadataByLocalId = await _loadMetadataByLocalId(
      SyncFeatureKeys.customers,
    );
    final queueByEntityKey = await _loadQueueByEntityKey(const <String>[
      SyncFeatureKeys.customers,
    ]);
    final localRecords = await _loadLocalCustomers(
      metadataByLocalId: metadataByLocalId,
      queueByEntityKey: queueByEntityKey,
    );

    try {
      final remoteRecords = (await _customersRemoteDatasource.listAll())
          .map(_mapRemoteCustomer)
          .toList();
      final result = _reconcileComparableFeature(
        featureKey: SyncFeatureKeys.customers,
        displayName: syncFeatureDisplayName(SyncFeatureKeys.customers),
        localRecords: localRecords,
        remoteRecords: remoteRecords,
      );
      await _logReconciliationResult(result);
      return result;
    } catch (error) {
      return _buildFetchFailureResult(
        featureKey: SyncFeatureKeys.customers,
        totalLocal: localRecords.length,
        error: error,
      );
    }
  }

  Future<SyncReconciliationResult> _reconcileSales() async {
    final metadataByLocalId = await _loadMetadataByLocalId(
      SyncFeatureKeys.sales,
    );
    final queueByEntityKey = await _loadQueueByEntityKey(const <String>[
      SyncFeatureKeys.sales,
    ]);
    final localRecords = await _loadLocalSales(
      metadataByLocalId: metadataByLocalId,
      queueByEntityKey: queueByEntityKey,
    );

    try {
      final remoteRecords = (await _salesRemoteDatasource.listAll())
          .map(_mapRemoteSale)
          .toList();
      final result = _reconcileComparableFeature(
        featureKey: SyncFeatureKeys.sales,
        displayName: syncFeatureDisplayName(SyncFeatureKeys.sales),
        localRecords: localRecords,
        remoteRecords: remoteRecords,
        preferOrphanRemoteWhenLocalUuidAvailable: true,
      );
      await _logReconciliationResult(result);
      return result;
    } catch (error) {
      return _buildFetchFailureResult(
        featureKey: SyncFeatureKeys.sales,
        totalLocal: localRecords.length,
        error: error,
      );
    }
  }

  Future<SyncReconciliationResult> _reconcilePurchases() async {
    final metadataByLocalId = await _loadMetadataByLocalId(
      SyncFeatureKeys.purchases,
    );
    final queueByEntityKey = await _loadQueueByEntityKey(const <String>[
      SyncFeatureKeys.purchases,
    ]);
    final localRecords = await _loadLocalPurchases(
      metadataByLocalId: metadataByLocalId,
      queueByEntityKey: queueByEntityKey,
    );

    try {
      final remoteRecords = (await _purchasesRemoteDatasource.listAll())
          .map(_mapRemotePurchase)
          .toList();
      final result = _reconcileComparableFeature(
        featureKey: SyncFeatureKeys.purchases,
        displayName: syncFeatureDisplayName(SyncFeatureKeys.purchases),
        localRecords: localRecords,
        remoteRecords: remoteRecords,
        preferOrphanRemoteWhenLocalUuidAvailable: true,
      );
      await _logReconciliationResult(result);
      return result;
    } catch (error) {
      return _buildFetchFailureResult(
        featureKey: SyncFeatureKeys.purchases,
        totalLocal: localRecords.length,
        error: error,
      );
    }
  }

  Future<SyncReconciliationResult> _reconcileFinancialEvents() async {
    final cancellationMetadataByLocalId = await _loadMetadataByLocalId(
      SyncFeatureKeys.saleCancellations,
    );
    final paymentMetadataByLocalId = await _loadMetadataByLocalId(
      SyncFeatureKeys.fiadoPayments,
    );
    final queueByEntityKey = await _loadQueueByEntityKey(const <String>[
      SyncFeatureKeys.financialEvents,
    ]);
    final localRecords = await _loadLocalFinancialEvents(
      cancellationMetadataByLocalId: cancellationMetadataByLocalId,
      paymentMetadataByLocalId: paymentMetadataByLocalId,
      queueByEntityKey: queueByEntityKey,
    );

    try {
      final remoteRecords = (await _financialEventsRemoteDatasource.listAll())
          .map(_mapRemoteFinancialEvent)
          .toList();
      final result = _reconcileComparableFeature(
        featureKey: SyncFeatureKeys.financialEvents,
        displayName: syncFeatureDisplayName(SyncFeatureKeys.financialEvents),
        localRecords: localRecords,
        remoteRecords: remoteRecords,
        preferOrphanRemoteWhenLocalUuidAvailable: true,
      );
      await _logReconciliationResult(result);
      return result;
    } catch (error) {
      return _buildFetchFailureResult(
        featureKey: SyncFeatureKeys.financialEvents,
        totalLocal: localRecords.length,
        error: error,
      );
    }
  }

  Future<SyncReconciliationResult> _unknownFeature(String featureKey) async {
    final result = SyncReconciliationResult.fromIssues(
      featureKey: featureKey,
      displayName: syncFeatureDisplayName(featureKey),
      checkedAt: DateTime.now(),
      totalLocal: 0,
      totalRemote: 0,
      issues: <SyncReconciliationIssue>[
        SyncReconciliationIssue(
          featureKey: featureKey,
          entityType: featureKey,
          entityLabel: syncFeatureDisplayName(featureKey),
          status: SyncReconciliationStatus.unknown,
          reasonCode: 'feature_not_supported',
          message: 'Feature ainda nao suportada pela reconciliacao tecnica.',
        ),
      ],
      fetchError: 'Feature nao suportada.',
    );
    await _logReconciliationResult(result);
    return result;
  }

  Future<Map<int, SyncMetadata>> _loadMetadataByLocalId(
    String featureKey,
  ) async {
    final items = await _syncMetadataRepository.listByFeature(featureKey);
    return <int, SyncMetadata>{
      for (final item in items)
        if (item.identity.localId != null) item.identity.localId!: item,
    };
  }

  Future<Map<String, SyncQueueItem>> _loadQueueByEntityKey(
    Iterable<String> featureKeys,
  ) async {
    final database = await _appDatabase.database;
    final placeholders = List.filled(featureKeys.length, '?').join(', ');
    final rows = await database.query(
      TableNames.syncQueue,
      where: 'feature_key IN ($placeholders)',
      whereArgs: featureKeys.toList(),
      orderBy: 'updated_at DESC, id DESC',
    );

    final map = <String, SyncQueueItem>{};
    for (final row in rows) {
      final item = _mapQueueRow(row);
      final key = _entityKey(
        item.featureKey,
        item.entityType,
        item.localEntityId,
      );
      map.putIfAbsent(key, () => item);
    }
    return map;
  }

  Future<List<_LocalComparableRecord>> _loadLocalCategories({
    required Map<int, SyncMetadata> metadataByLocalId,
    required Map<String, SyncQueueItem> queueByEntityKey,
  }) async {
    final database = await _appDatabase.database;
    final rows = await database.rawQuery('''
      SELECT
        id,
        uuid,
        nome,
        descricao,
        ativo,
        criado_em,
        atualizado_em,
        deletado_em
      FROM ${TableNames.categorias}
      ORDER BY nome COLLATE NOCASE ASC, id ASC
    ''');

    return rows.map((row) {
      final localId = row['id'] as int;
      final metadata = metadataByLocalId[localId];
      return _LocalComparableRecord(
        featureKey: SyncFeatureKeys.categories,
        entityType: 'category',
        localId: localId,
        localUuid: row['uuid'] as String,
        remoteId: metadata?.identity.remoteId,
        label: row['nome'] as String? ?? 'Categoria',
        createdAt: DateTime.parse(row['criado_em'] as String),
        updatedAt: DateTime.parse(row['atualizado_em'] as String),
        metadataStatus: metadata?.status,
        queueItem:
            queueByEntityKey[_entityKey(
              SyncFeatureKeys.categories,
              'category',
              localId,
            )],
        lastError: metadata?.lastError,
        lastErrorType: metadata?.lastErrorType,
        payload: <String, dynamic>{
          'name': row['nome'] as String? ?? '',
          'description': row['descricao'] as String?,
          'isActive': (row['ativo'] as int? ?? 0) == 1,
          'deletedAt': row['deletado_em'] as String?,
        },
        allowRepair: true,
      );
    }).toList();
  }

  Future<List<_LocalComparableRecord>> _loadLocalProducts({
    required Map<int, SyncMetadata> metadataByLocalId,
    required Map<String, SyncQueueItem> queueByEntityKey,
  }) async {
    final database = await _appDatabase.database;
    final rows = await database.rawQuery('''
      SELECT
        p.id,
        p.uuid,
        p.nome,
        p.descricao,
        p.codigo_barras,
        p.tipo_produto,
        p.catalog_type,
        p.model_name,
        p.variant_label,
        p.unidade_medida,
        p.custo_centavos,
        p.preco_venda_centavos,
        p.estoque_mil,
        p.ativo,
        p.criado_em,
        p.atualizado_em,
        p.deletado_em,
        p.categoria_id,
        c.nome AS categoria_nome,
        category_sync.remote_id AS categoria_remote_id
      FROM ${TableNames.produtos} p
      LEFT JOIN ${TableNames.categorias} c ON c.id = p.categoria_id
      LEFT JOIN ${TableNames.syncRegistros} category_sync
        ON category_sync.feature_key = '${SyncFeatureKeys.categories}'
        AND category_sync.local_id = p.categoria_id
      ORDER BY p.nome COLLATE NOCASE ASC, p.id ASC
    ''');

    return rows.map((row) {
      final localId = row['id'] as int;
      final metadata = metadataByLocalId[localId];
      return _LocalComparableRecord(
        featureKey: SyncFeatureKeys.products,
        entityType: 'product',
        localId: localId,
        localUuid: row['uuid'] as String,
        remoteId: metadata?.identity.remoteId,
        label: row['nome'] as String? ?? 'Produto',
        createdAt: DateTime.parse(row['criado_em'] as String),
        updatedAt: DateTime.parse(row['atualizado_em'] as String),
        metadataStatus: metadata?.status,
        queueItem:
            queueByEntityKey[_entityKey(
              SyncFeatureKeys.products,
              'product',
              localId,
            )],
        lastError: metadata?.lastError,
        lastErrorType: metadata?.lastErrorType,
        payload: <String, dynamic>{
          'name': row['nome'] as String? ?? '',
          'categoryId': row['categoria_remote_id'] as String?,
          'description': row['descricao'] as String?,
          'barcode': row['codigo_barras'] as String?,
          'productType': row['tipo_produto'] as String? ?? 'unidade',
          'catalogType': (row['catalog_type'] as String?) ?? 'simple',
          'modelName': row['model_name'] as String?,
          'variantLabel': row['variant_label'] as String?,
          'unitMeasure': row['unidade_medida'] as String? ?? 'un',
          'costPriceCents': row['custo_centavos'] as int? ?? 0,
          'salePriceCents': row['preco_venda_centavos'] as int? ?? 0,
          'stockMil': row['estoque_mil'] as int? ?? 0,
          'isActive': (row['ativo'] as int? ?? 0) == 1,
          'deletedAt': row['deletado_em'] as String?,
        },
        allowRepair: true,
      );
    }).toList();
  }

  Future<List<_LocalComparableRecord>> _loadLocalCustomers({
    required Map<int, SyncMetadata> metadataByLocalId,
    required Map<String, SyncQueueItem> queueByEntityKey,
  }) async {
    final database = await _appDatabase.database;
    final rows = await database.rawQuery('''
      SELECT
        id,
        uuid,
        nome,
        telefone,
        endereco,
        observacao,
        ativo,
        criado_em,
        atualizado_em,
        deletado_em
      FROM ${TableNames.clientes}
      ORDER BY nome COLLATE NOCASE ASC, id ASC
    ''');

    return rows.map((row) {
      final localId = row['id'] as int;
      final metadata = metadataByLocalId[localId];
      return _LocalComparableRecord(
        featureKey: SyncFeatureKeys.customers,
        entityType: 'customer',
        localId: localId,
        localUuid: row['uuid'] as String,
        remoteId: metadata?.identity.remoteId,
        label: row['nome'] as String? ?? 'Cliente',
        createdAt: DateTime.parse(row['criado_em'] as String),
        updatedAt: DateTime.parse(row['atualizado_em'] as String),
        metadataStatus: metadata?.status,
        queueItem:
            queueByEntityKey[_entityKey(
              SyncFeatureKeys.customers,
              'customer',
              localId,
            )],
        lastError: metadata?.lastError,
        lastErrorType: metadata?.lastErrorType,
        payload: <String, dynamic>{
          'name': row['nome'] as String? ?? '',
          'phone': row['telefone'] as String?,
          'address': row['endereco'] as String?,
          'notes': row['observacao'] as String?,
          'isActive': (row['ativo'] as int? ?? 0) == 1,
          'deletedAt': row['deletado_em'] as String?,
        },
        allowRepair: true,
      );
    }).toList();
  }

  Future<List<_LocalComparableRecord>> _loadLocalSuppliers({
    required Map<int, SyncMetadata> metadataByLocalId,
    required Map<String, SyncQueueItem> queueByEntityKey,
  }) async {
    final database = await _appDatabase.database;
    final rows = await database.rawQuery('''
      SELECT
        id,
        uuid,
        nome,
        nome_fantasia,
        telefone,
        email,
        endereco,
        documento,
        contato_responsavel,
        observacao,
        ativo,
        criado_em,
        atualizado_em,
        deletado_em
      FROM ${TableNames.fornecedores}
      ORDER BY nome COLLATE NOCASE ASC, id ASC
    ''');

    return rows.map((row) {
      final localId = row['id'] as int;
      final metadata = metadataByLocalId[localId];
      return _LocalComparableRecord(
        featureKey: SyncFeatureKeys.suppliers,
        entityType: 'supplier',
        localId: localId,
        localUuid: row['uuid'] as String,
        remoteId: metadata?.identity.remoteId,
        label: row['nome'] as String? ?? 'Fornecedor',
        createdAt: DateTime.parse(row['criado_em'] as String),
        updatedAt: DateTime.parse(row['atualizado_em'] as String),
        metadataStatus: metadata?.status,
        queueItem:
            queueByEntityKey[_entityKey(
              SyncFeatureKeys.suppliers,
              'supplier',
              localId,
            )],
        lastError: metadata?.lastError,
        lastErrorType: metadata?.lastErrorType,
        payload: <String, dynamic>{
          'localUuid': row['uuid'] as String,
          'name': row['nome'] as String? ?? '',
          'tradeName': row['nome_fantasia'] as String?,
          'phone': row['telefone'] as String?,
          'email': row['email'] as String?,
          'address': row['endereco'] as String?,
          'document': row['documento'] as String?,
          'contactPerson': row['contato_responsavel'] as String?,
          'notes': row['observacao'] as String?,
          'isActive': (row['ativo'] as int? ?? 0) == 1,
          'deletedAt': row['deletado_em'] as String?,
        },
        allowRepair: true,
      );
    }).toList();
  }

  Future<List<_LocalComparableRecord>> _loadLocalPurchases({
    required Map<int, SyncMetadata> metadataByLocalId,
    required Map<String, SyncQueueItem> queueByEntityKey,
  }) async {
    final database = await _appDatabase.database;
    final idRows = await database.query(
      TableNames.compras,
      columns: const ['id'],
      orderBy: 'data_compra DESC, id DESC',
    );

    final records = <_LocalComparableRecord>[];
    for (final row in idRows) {
      final localId = row['id'] as int;
      final purchase = await _purchaseRepository.findPurchaseForSync(localId);
      if (purchase == null) {
        continue;
      }
      final metadata = metadataByLocalId[localId];
      records.add(
        _LocalComparableRecord(
          featureKey: SyncFeatureKeys.purchases,
          entityType: 'purchase',
          localId: localId,
          localUuid: purchase.purchaseUuid,
          remoteId: metadata?.identity.remoteId ?? purchase.remoteId,
          label: purchase.documentNumber?.trim().isNotEmpty == true
              ? 'Compra ${purchase.documentNumber}'
              : 'Compra #$localId',
          createdAt: purchase.createdAt,
          updatedAt: purchase.updatedAt,
          metadataStatus: metadata?.status,
          queueItem:
              queueByEntityKey[_entityKey(
                SyncFeatureKeys.purchases,
                'purchase',
                localId,
              )],
          lastError: metadata?.lastError,
          lastErrorType: metadata?.lastErrorType,
          payload: <String, dynamic>{
            'localUuid': purchase.purchaseUuid,
            'supplierId': purchase.supplierRemoteId,
            'documentNumber': purchase.documentNumber,
            'notes': purchase.notes,
            'purchasedAt': purchase.purchasedAt.toIso8601String(),
            'dueDate': purchase.dueDate?.toIso8601String(),
            'paymentMethod': purchase.paymentMethod?.dbValue,
            'status': purchase.status.dbValue,
            'subtotalCents': purchase.subtotalCents,
            'discountCents': purchase.discountCents,
            'surchargeCents': purchase.surchargeCents,
            'freightCents': purchase.freightCents,
            'finalAmountCents': purchase.finalAmountCents,
            'paidAmountCents': purchase.paidAmountCents,
            'pendingAmountCents': purchase.pendingAmountCents,
            'canceledAt': purchase.cancelledAt?.toIso8601String(),
            'items': purchase.items
                .map(
                  (item) => <String, dynamic>{
                    'localUuid': item.itemUuid,
                    'productId': item.productRemoteId,
                    'productNameSnapshot': item.productNameSnapshot,
                    'unitMeasureSnapshot': item.unitMeasureSnapshot,
                    'quantityMil': item.quantityMil,
                    'unitCostCents': item.unitCostCents,
                    'subtotalCents': item.subtotalCents,
                  },
                )
                .toList(),
            'payments': purchase.payments
                .map(
                  (payment) => <String, dynamic>{
                    'localUuid': payment.paymentUuid,
                    'amountCents': payment.amountCents,
                    'paymentMethod': payment.paymentMethod.dbValue,
                    'paidAt': payment.paidAt.toIso8601String(),
                    'notes': payment.notes,
                  },
                )
                .toList(),
          },
          allowRepair: true,
        ),
      );
    }

    return records;
  }

  Future<List<_LocalComparableRecord>> _loadLocalSales({
    required Map<int, SyncMetadata> metadataByLocalId,
    required Map<String, SyncQueueItem> queueByEntityKey,
  }) async {
    final database = await _appDatabase.database;
    final idRows = await database.query(
      TableNames.vendas,
      columns: const ['id'],
      orderBy: 'data_venda DESC, id DESC',
    );

    final records = <_LocalComparableRecord>[];
    for (final row in idRows) {
      final localId = row['id'] as int;
      final payload = await _saleRepository.findSaleForSync(localId);
      if (payload == null) {
        continue;
      }
      final metadata = metadataByLocalId[localId];
      records.add(
        _LocalComparableRecord(
          featureKey: SyncFeatureKeys.sales,
          entityType: 'sale',
          localId: payload.saleId,
          localUuid: payload.saleUuid,
          remoteId: payload.remoteId,
          label: 'Cupom ${payload.receiptNumber}',
          createdAt: payload.soldAt,
          updatedAt: payload.updatedAt,
          metadataStatus: payload.syncStatus,
          queueItem:
              queueByEntityKey[_entityKey(
                SyncFeatureKeys.sales,
                'sale',
                payload.saleId,
              )],
          lastError: metadata?.lastError,
          lastErrorType: metadata?.lastErrorType,
          payload: _normalizedSalePayload(
            RemoteSaleRecord.fromSyncPayload(payload).toCreateBody(),
          ),
          allowRepair: payload.status.name != 'cancelled',
        ),
      );
    }
    return records;
  }

  Future<List<_LocalComparableRecord>> _loadLocalFinancialEvents({
    required Map<int, SyncMetadata> cancellationMetadataByLocalId,
    required Map<int, SyncMetadata> paymentMetadataByLocalId,
    required Map<String, SyncQueueItem> queueByEntityKey,
  }) async {
    final database = await _appDatabase.database;
    final records = <_LocalComparableRecord>[];

    final canceledSaleRows = await database.query(
      TableNames.vendas,
      columns: const ['id'],
      where: 'status = ? AND cancelada_em IS NOT NULL',
      whereArgs: const ['cancelada'],
      orderBy: 'cancelada_em DESC, id DESC',
    );
    for (final row in canceledSaleRows) {
      final saleId = row['id'] as int;
      final payload = await _saleRepository.findSaleCancellationForSync(saleId);
      if (payload == null) {
        continue;
      }
      final metadata = cancellationMetadataByLocalId[saleId];
      records.add(
        _LocalComparableRecord(
          featureKey: SyncFeatureKeys.financialEvents,
          entityType: 'sale_canceled_event',
          localId: payload.saleId,
          localUuid: payload.saleUuid,
          remoteId: payload.remoteId,
          label: 'Cancelamento venda #${payload.saleId}',
          createdAt: payload.canceledAt,
          updatedAt: payload.updatedAt,
          metadataStatus: payload.syncStatus,
          queueItem:
              queueByEntityKey[_entityKey(
                SyncFeatureKeys.financialEvents,
                'sale_canceled_event',
                payload.saleId,
              )],
          lastError: metadata?.lastError,
          lastErrorType: metadata?.lastErrorType,
          payload: RemoteFinancialEventRecord(
            remoteId: payload.remoteId ?? '',
            companyId: '',
            saleId: payload.saleRemoteId,
            fiadoId: null,
            eventType: 'sale_canceled',
            localUuid: payload.saleUuid,
            amountCents: payload.amountCents,
            paymentType: payload.paymentType,
            createdAt: payload.canceledAt,
            updatedAt: payload.updatedAt,
            metadata: <String, dynamic>{
              'saleLocalId': payload.saleId,
              if (payload.notes != null && payload.notes!.trim().isNotEmpty)
                'notes': payload.notes!.trim(),
            },
          ).toCreateBody(),
          allowRepair:
              payload.saleRemoteId != null && payload.saleRemoteId!.isNotEmpty,
        ),
      );
    }

    final paymentRows = await database.query(
      TableNames.fiadoLancamentos,
      columns: const ['id'],
      where: 'tipo_lancamento = ?',
      whereArgs: const ['pagamento'],
      orderBy: 'data_lancamento DESC, id DESC',
    );
    for (final row in paymentRows) {
      final paymentId = row['id'] as int;
      final payload = await _fiadoRepository.findPaymentForSync(paymentId);
      if (payload == null) {
        continue;
      }
      final metadata = paymentMetadataByLocalId[paymentId];
      records.add(
        _LocalComparableRecord(
          featureKey: SyncFeatureKeys.financialEvents,
          entityType: 'fiado_payment_event',
          localId: payload.entryId,
          localUuid: payload.entryUuid,
          remoteId: payload.remoteId,
          label: 'Pagamento fiado #${payload.entryId}',
          createdAt: payload.createdAt,
          updatedAt: payload.updatedAt,
          metadataStatus: payload.syncStatus,
          queueItem:
              queueByEntityKey[_entityKey(
                SyncFeatureKeys.financialEvents,
                'fiado_payment_event',
                payload.entryId,
              )],
          lastError: metadata?.lastError,
          lastErrorType: metadata?.lastErrorType,
          payload: RemoteFinancialEventRecord(
            remoteId: payload.remoteId ?? '',
            companyId: '',
            saleId: payload.saleRemoteId,
            fiadoId: payload.fiadoUuid,
            eventType: 'fiado_payment',
            localUuid: payload.entryUuid,
            amountCents: payload.amountCents,
            paymentType: payload.paymentMethod.dbValue,
            createdAt: payload.createdAt,
            updatedAt: payload.updatedAt,
            metadata: <String, dynamic>{
              'fiadoLocalId': payload.fiadoId,
              'paymentEntryLocalId': payload.entryId,
              if (payload.notes != null && payload.notes!.trim().isNotEmpty)
                'notes': payload.notes!.trim(),
            },
          ).toCreateBody(),
          allowRepair:
              payload.saleRemoteId != null && payload.saleRemoteId!.isNotEmpty,
        ),
      );
    }

    return records;
  }

  _RemoteComparableRecord _mapRemoteCategory(RemoteCategoryRecord remote) {
    return _RemoteComparableRecord(
      entityType: 'category',
      remoteId: remote.remoteId,
      localUuid: remote.localUuid,
      label: remote.name,
      updatedAt: remote.updatedAt,
      payload: remote.toUpsertBody(),
    );
  }

  _RemoteComparableRecord _mapRemoteSupplier(RemoteSupplierRecord remote) {
    return _RemoteComparableRecord(
      entityType: 'supplier',
      remoteId: remote.remoteId,
      localUuid: remote.localUuid,
      label: remote.name,
      updatedAt: remote.updatedAt,
      payload: remote.toUpsertBody(),
    );
  }

  _RemoteComparableRecord _mapRemoteProduct(RemoteProductRecord remote) {
    return _RemoteComparableRecord(
      entityType: 'product',
      remoteId: remote.remoteId,
      localUuid: remote.localUuid,
      label: remote.displayName,
      updatedAt: remote.updatedAt,
      payload: remote.toUpsertBody(),
    );
  }

  _RemoteComparableRecord _mapRemotePurchase(RemotePurchaseRecord remote) {
    return _RemoteComparableRecord(
      entityType: 'purchase',
      remoteId: remote.remoteId,
      localUuid: remote.localUuid,
      label: remote.documentNumber?.trim().isNotEmpty == true
          ? 'Compra ${remote.documentNumber}'
          : 'Compra ${remote.remoteId}',
      updatedAt: remote.updatedAt,
      payload: remote.toUpsertBody(),
    );
  }

  _RemoteComparableRecord _mapRemoteCustomer(RemoteCustomerRecord remote) {
    return _RemoteComparableRecord(
      entityType: 'customer',
      remoteId: remote.remoteId,
      localUuid: remote.localUuid,
      label: remote.name,
      updatedAt: remote.updatedAt,
      payload: remote.toUpsertBody(),
    );
  }

  _RemoteComparableRecord _mapRemoteSale(RemoteSaleRecord remote) {
    return _RemoteComparableRecord(
      entityType: 'sale',
      remoteId: remote.remoteId,
      localUuid: remote.localUuid,
      label: remote.receiptNumber ?? 'Venda ${remote.remoteId}',
      updatedAt: remote.updatedAt,
      payload: _normalizedSalePayload(remote.toCreateBody()),
    );
  }

  _RemoteComparableRecord _mapRemoteFinancialEvent(
    RemoteFinancialEventRecord remote,
  ) {
    return _RemoteComparableRecord(
      entityType: remote.eventType == 'sale_canceled'
          ? 'sale_canceled_event'
          : 'fiado_payment_event',
      remoteId: remote.remoteId,
      localUuid: remote.localUuid,
      label: remote.eventType == 'sale_canceled'
          ? 'Cancelamento remoto ${remote.localUuid}'
          : 'Pagamento remoto ${remote.localUuid}',
      updatedAt: remote.updatedAt,
      payload: remote.toCreateBody(),
    );
  }

  SyncReconciliationResult _reconcileComparableFeature({
    required String featureKey,
    required String displayName,
    required List<_LocalComparableRecord> localRecords,
    required List<_RemoteComparableRecord> remoteRecords,
    bool preferOrphanRemoteWhenLocalUuidAvailable = false,
  }) {
    final remoteById = <String, _RemoteComparableRecord>{
      for (final remote in remoteRecords) remote.remoteId: remote,
    };
    final remoteByLocalUuid = <String, _RemoteComparableRecord>{
      for (final remote in remoteRecords)
        if (remote.localUuid != null && remote.localUuid!.isNotEmpty)
          remote.localUuid!: remote,
    };
    final matchedRemoteIds = <String>{};
    final issues = <SyncReconciliationIssue>[];

    for (final local in localRecords) {
      issues.add(
        _buildIssueForLocalRecord(
          local,
          remoteById: remoteById,
          remoteByLocalUuid: remoteByLocalUuid,
          matchedRemoteIds: matchedRemoteIds,
        ),
      );
    }

    for (final remote in remoteRecords) {
      if (matchedRemoteIds.contains(remote.remoteId)) {
        continue;
      }

      final isOrphanRemote =
          preferOrphanRemoteWhenLocalUuidAvailable &&
          remote.localUuid != null &&
          remote.localUuid!.isNotEmpty;
      issues.add(
        SyncReconciliationIssue(
          featureKey: featureKey,
          entityType: remote.entityType,
          entityLabel: remote.label,
          status: isOrphanRemote
              ? SyncReconciliationStatus.orphanRemote
              : SyncReconciliationStatus.remoteOnly,
          reasonCode: isOrphanRemote ? 'orphan_remote' : 'remote_only',
          message: isOrphanRemote
              ? 'Existe espelho remoto com localUuid ${remote.localUuid}, mas sem correspondente local nesta base.'
              : 'O backend possui um registro sem correspondente local.',
          remoteId: remote.remoteId,
          remoteUpdatedAt: remote.updatedAt,
          remotePayloadSignature: _payloadSignature(remote.payload),
        ),
      );
    }

    issues.sort((left, right) {
      final severityCompare = _severityOf(
        right.status,
      ).compareTo(_severityOf(left.status));
      if (severityCompare != 0) {
        return severityCompare;
      }
      return left.entityLabel.toLowerCase().compareTo(
        right.entityLabel.toLowerCase(),
      );
    });

    return SyncReconciliationResult.fromIssues(
      featureKey: featureKey,
      displayName: displayName,
      checkedAt: DateTime.now(),
      totalLocal: localRecords.length,
      totalRemote: remoteRecords.length,
      issues: issues,
    );
  }

  SyncReconciliationIssue _buildIssueForLocalRecord(
    _LocalComparableRecord local, {
    required Map<String, _RemoteComparableRecord> remoteById,
    required Map<String, _RemoteComparableRecord> remoteByLocalUuid,
    required Set<String> matchedRemoteIds,
  }) {
    final remoteByLinkedId = local.remoteId == null
        ? null
        : remoteById[local.remoteId!];
    final remoteByUuid = remoteByLocalUuid[local.localUuid];
    final remote = remoteByLinkedId ?? remoteByUuid;
    final pendingMetadata = _hasPendingMetadata(local.metadataStatus);
    final hasPendingQueue = _hasPendingQueue(local.queueItem);

    if ((local.queueItem?.status == SyncQueueStatus.conflict) ||
        local.metadataStatus == SyncStatus.conflict) {
      return SyncReconciliationIssue(
        featureKey: local.featureKey,
        entityType: local.entityType,
        entityLabel: local.label,
        status: SyncReconciliationStatus.conflict,
        reasonCode: 'conflict_open',
        message:
            local.queueItem?.conflictReason ??
            local.lastError ??
            'Conflito previamente detectado para este registro.',
        localEntityId: local.localId,
        localUuid: local.localUuid,
        remoteId: local.remoteId ?? remote?.remoteId,
        localUpdatedAt: local.updatedAt,
        remoteUpdatedAt: remote?.updatedAt ?? local.queueItem?.remoteUpdatedAt,
        metadataStatus: local.metadataStatus,
        queueStatus: local.queueItem?.status,
        lastError: local.lastError,
        lastErrorType: local.lastErrorType,
        localPayloadSignature: _payloadSignature(local.payload),
        remotePayloadSignature: remote == null
            ? null
            : _payloadSignature(remote.payload),
      );
    }

    if (local.remoteId == null || local.remoteId!.isEmpty) {
      if (remoteByUuid != null) {
        matchedRemoteIds.add(remoteByUuid.remoteId);
        final signaturesMatch = _signaturesMatch(
          local.payload,
          remoteByUuid.payload,
        );
        return SyncReconciliationIssue(
          featureKey: local.featureKey,
          entityType: local.entityType,
          entityLabel: local.label,
          status: signaturesMatch
              ? SyncReconciliationStatus.invalidLink
              : SyncReconciliationStatus.outOfSync,
          reasonCode: signaturesMatch
              ? 'missing_link_uuid_match'
              : 'missing_link_uuid_payload_diverged',
          message: signaturesMatch
              ? 'O espelho remoto existe para este localUuid, mas o remoteId nao esta vinculado localmente.'
              : 'O espelho remoto encontrado por localUuid divergiu do payload local.',
          localEntityId: local.localId,
          localUuid: local.localUuid,
          remoteId: remoteByUuid.remoteId,
          localUpdatedAt: local.updatedAt,
          remoteUpdatedAt: remoteByUuid.updatedAt,
          metadataStatus: local.metadataStatus,
          queueStatus: local.queueItem?.status,
          lastError: local.lastError,
          lastErrorType: local.lastErrorType,
          canMarkForResync: local.allowRepair,
          localPayloadSignature: _payloadSignature(local.payload),
          remotePayloadSignature: _payloadSignature(remoteByUuid.payload),
        );
      }

      final pending = pendingMetadata || hasPendingQueue;
      return SyncReconciliationIssue(
        featureKey: local.featureKey,
        entityType: local.entityType,
        entityLabel: local.label,
        status: pending
            ? SyncReconciliationStatus.pendingSync
            : SyncReconciliationStatus.localOnly,
        reasonCode: pending ? 'local_pending' : 'local_only',
        message: pending
            ? _pendingMessage(local)
            : 'O registro continua apenas na base local, sem vinculo remoto.',
        localEntityId: local.localId,
        localUuid: local.localUuid,
        localUpdatedAt: local.updatedAt,
        metadataStatus: local.metadataStatus,
        queueStatus: local.queueItem?.status,
        lastError: local.lastError,
        lastErrorType: local.lastErrorType,
        canMarkForResync: local.allowRepair,
        localPayloadSignature: _payloadSignature(local.payload),
      );
    }

    if (remoteByLinkedId == null) {
      return SyncReconciliationIssue(
        featureKey: local.featureKey,
        entityType: local.entityType,
        entityLabel: local.label,
        status: SyncReconciliationStatus.missingRemote,
        reasonCode: 'missing_remote',
        message:
            'O registro local esta vinculado a ${local.remoteId}, mas o espelho remoto nao foi encontrado.',
        localEntityId: local.localId,
        localUuid: local.localUuid,
        remoteId: local.remoteId,
        localUpdatedAt: local.updatedAt,
        metadataStatus: local.metadataStatus,
        queueStatus: local.queueItem?.status,
        lastError: local.lastError,
        lastErrorType: local.lastErrorType,
        canMarkForResync: local.allowRepair,
        localPayloadSignature: _payloadSignature(local.payload),
      );
    }

    matchedRemoteIds.add(remoteByLinkedId.remoteId);

    if (remoteByLinkedId.localUuid != null &&
        remoteByLinkedId.localUuid!.isNotEmpty &&
        remoteByLinkedId.localUuid != local.localUuid) {
      return SyncReconciliationIssue(
        featureKey: local.featureKey,
        entityType: local.entityType,
        entityLabel: local.label,
        status: SyncReconciliationStatus.invalidLink,
        reasonCode: 'linked_remote_uuid_mismatch',
        message:
            'O remoteId aponta para um espelho com localUuid diferente do registro local.',
        localEntityId: local.localId,
        localUuid: local.localUuid,
        remoteId: local.remoteId,
        localUpdatedAt: local.updatedAt,
        remoteUpdatedAt: remoteByLinkedId.updatedAt,
        metadataStatus: local.metadataStatus,
        queueStatus: local.queueItem?.status,
        lastError: local.lastError,
        lastErrorType: local.lastErrorType,
        canMarkForResync: local.allowRepair,
        localPayloadSignature: _payloadSignature(local.payload),
        remotePayloadSignature: _payloadSignature(remoteByLinkedId.payload),
      );
    }

    if (pendingMetadata || hasPendingQueue) {
      return SyncReconciliationIssue(
        featureKey: local.featureKey,
        entityType: local.entityType,
        entityLabel: local.label,
        status: SyncReconciliationStatus.pendingSync,
        reasonCode: 'pending_with_remote_link',
        message: _pendingMessage(local),
        localEntityId: local.localId,
        localUuid: local.localUuid,
        remoteId: local.remoteId,
        localUpdatedAt: local.updatedAt,
        remoteUpdatedAt: remoteByLinkedId.updatedAt,
        metadataStatus: local.metadataStatus,
        queueStatus: local.queueItem?.status,
        lastError: local.lastError,
        lastErrorType: local.lastErrorType,
        canMarkForResync: local.allowRepair,
        localPayloadSignature: _payloadSignature(local.payload),
        remotePayloadSignature: _payloadSignature(remoteByLinkedId.payload),
      );
    }

    if (!_signaturesMatch(local.payload, remoteByLinkedId.payload)) {
      return SyncReconciliationIssue(
        featureKey: local.featureKey,
        entityType: local.entityType,
        entityLabel: local.label,
        status: SyncReconciliationStatus.outOfSync,
        reasonCode: 'payload_mismatch',
        message:
            'Os campos espelhados divergem entre o registro local e o remoto.',
        localEntityId: local.localId,
        localUuid: local.localUuid,
        remoteId: local.remoteId,
        localUpdatedAt: local.updatedAt,
        remoteUpdatedAt: remoteByLinkedId.updatedAt,
        metadataStatus: local.metadataStatus,
        queueStatus: local.queueItem?.status,
        lastError: local.lastError,
        lastErrorType: local.lastErrorType,
        canMarkForResync: local.allowRepair,
        localPayloadSignature: _payloadSignature(local.payload),
        remotePayloadSignature: _payloadSignature(remoteByLinkedId.payload),
      );
    }

    return SyncReconciliationIssue(
      featureKey: local.featureKey,
      entityType: local.entityType,
      entityLabel: local.label,
      status: SyncReconciliationStatus.consistent,
      reasonCode: 'consistent',
      message: 'Registro local e espelho remoto estao consistentes.',
      localEntityId: local.localId,
      localUuid: local.localUuid,
      remoteId: local.remoteId,
      localUpdatedAt: local.updatedAt,
      remoteUpdatedAt: remoteByLinkedId.updatedAt,
      metadataStatus: local.metadataStatus,
      queueStatus: local.queueItem?.status,
      lastError: local.lastError,
      lastErrorType: local.lastErrorType,
      localPayloadSignature: _payloadSignature(local.payload),
      remotePayloadSignature: _payloadSignature(remoteByLinkedId.payload),
    );
  }

  bool _hasPendingMetadata(SyncStatus? status) {
    return status == SyncStatus.pendingUpload ||
        status == SyncStatus.pendingUpdate ||
        status == SyncStatus.syncError;
  }

  bool _hasPendingQueue(SyncQueueItem? item) {
    if (item == null) {
      return false;
    }

    return item.status == SyncQueueStatus.pendingUpload ||
        item.status == SyncQueueStatus.pendingUpdate ||
        item.status == SyncQueueStatus.processing ||
        item.status == SyncQueueStatus.syncError ||
        item.status == SyncQueueStatus.blockedDependency;
  }

  String _pendingMessage(_LocalComparableRecord local) {
    final queueItem = local.queueItem;
    if (queueItem == null) {
      return 'O registro local ainda aguarda envio para o backend.';
    }

    switch (queueItem.status) {
      case SyncQueueStatus.pendingUpload:
      case SyncQueueStatus.pendingUpdate:
        return 'O item esta aguardando a proxima rodada da fila de sincronizacao.';
      case SyncQueueStatus.processing:
        return 'O item esta em processamento pela fila de sincronizacao.';
      case SyncQueueStatus.syncError:
        return local.lastError ??
            queueItem.lastError ??
            'O item falhou na ultima tentativa e aguarda novo processamento.';
      case SyncQueueStatus.blockedDependency:
        return queueItem.lastError ??
            local.lastError ??
            'O item aguarda uma dependencia remota antes de ser reenviado.';
      case SyncQueueStatus.conflict:
        return queueItem.conflictReason ??
            local.lastError ??
            'Existe um conflito em aberto para este item.';
      case SyncQueueStatus.synced:
        return 'O item ainda nao foi revalidado contra o espelho remoto.';
    }
  }

  Future<SyncReconciliationResult> _buildFetchFailureResult({
    required String featureKey,
    required int totalLocal,
    required Object error,
  }) async {
    final result = SyncReconciliationResult.fromIssues(
      featureKey: featureKey,
      displayName: syncFeatureDisplayName(featureKey),
      checkedAt: DateTime.now(),
      totalLocal: totalLocal,
      totalRemote: 0,
      issues: <SyncReconciliationIssue>[
        SyncReconciliationIssue(
          featureKey: featureKey,
          entityType: featureKey,
          entityLabel: syncFeatureDisplayName(featureKey),
          status: SyncReconciliationStatus.unknown,
          reasonCode: 'remote_fetch_failed',
          message:
              'Falha ao consultar o espelho remoto para reconciliar ${syncFeatureDisplayName(featureKey).toLowerCase()}: $error',
        ),
      ],
      fetchError: error.toString(),
    );
    await _logReconciliationResult(result);
    return result;
  }

  Future<void> _logReconciliationResult(SyncReconciliationResult result) {
    return _syncAuditRepository.log(
      featureKey: result.featureKey,
      eventType: SyncAuditEventType.reconciliationChecked,
      message:
          '${result.displayName}: ${result.consistentCount} consistente(s), ${result.pendingSyncCount} pendente(s), ${result.outOfSyncCount + result.missingRemoteCount + result.invalidLinkCount + result.remoteOnlyCount + result.orphanRemoteCount} divergencia(s) e ${result.conflictCount} conflito(s).',
      details: <String, dynamic>{
        'totalLocal': result.totalLocal,
        'totalRemote': result.totalRemote,
        'consistentCount': result.consistentCount,
        'localOnlyCount': result.localOnlyCount,
        'remoteOnlyCount': result.remoteOnlyCount,
        'pendingSyncCount': result.pendingSyncCount,
        'conflictCount': result.conflictCount,
        'outOfSyncCount': result.outOfSyncCount,
        'missingRemoteCount': result.missingRemoteCount,
        'invalidLinkCount': result.invalidLinkCount,
        'orphanRemoteCount': result.orphanRemoteCount,
        'unknownCount': result.unknownCount,
        if (result.fetchError != null) 'fetchError': result.fetchError,
      },
      createdAt: result.checkedAt,
    );
  }

  Future<bool> _repairIssue(
    DatabaseExecutor txn,
    String featureKey,
    SyncReconciliationIssue issue,
  ) async {
    final localEntityId = issue.localEntityId;
    if (localEntityId == null) {
      return false;
    }

    switch (featureKey) {
      case SyncFeatureKeys.suppliers:
        return _repairSupplier(txn, localEntityId);
      case SyncFeatureKeys.categories:
        return _repairCategory(txn, localEntityId);
      case SyncFeatureKeys.products:
        return _repairProduct(txn, localEntityId);
      case SyncFeatureKeys.customers:
        return _repairCustomer(txn, localEntityId);
      case SyncFeatureKeys.purchases:
        return _repairPurchase(txn, localEntityId);
      case SyncFeatureKeys.sales:
        return _repairSale(txn, localEntityId);
      case SyncFeatureKeys.financialEvents:
        return _repairFinancialEvent(
          txn,
          entityType: issue.entityType,
          localEntityId: localEntityId,
        );
      default:
        return false;
    }
  }

  Future<bool> _repairCategory(DatabaseExecutor txn, int localId) async {
    final rows = await txn.query(
      TableNames.categorias,
      columns: const [
        'id',
        'uuid',
        'criado_em',
        'atualizado_em',
        'deletado_em',
      ],
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return false;
    }

    final row = rows.first;
    final localUuid = row['uuid'] as String;
    final createdAt = DateTime.parse(row['criado_em'] as String);
    final updatedAt = DateTime.parse(row['atualizado_em'] as String);
    final deletedAt = row['deletado_em'] as String?;
    final metadata = await _syncMetadataRepository.findByLocalId(
      txn,
      featureKey: SyncFeatureKeys.categories,
      localId: localId,
    );
    final remoteId = metadata?.identity.remoteId;

    if (remoteId == null || remoteId.isEmpty) {
      await _syncMetadataRepository.markPendingUpload(
        txn,
        featureKey: SyncFeatureKeys.categories,
        localId: localId,
        localUuid: localUuid,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
    } else {
      await _syncMetadataRepository.markPendingUpdate(
        txn,
        featureKey: SyncFeatureKeys.categories,
        localId: localId,
        localUuid: localUuid,
        remoteId: remoteId,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
    }

    await _syncQueueRepository.enqueueMutation(
      txn,
      featureKey: SyncFeatureKeys.categories,
      entityType: 'category',
      localEntityId: localId,
      localUuid: localUuid,
      remoteId: remoteId,
      operation: deletedAt != null && remoteId != null
          ? SyncQueueOperation.delete
          : remoteId == null
          ? SyncQueueOperation.create
          : SyncQueueOperation.update,
      localUpdatedAt: updatedAt,
    );
    return true;
  }

  Future<bool> _repairSupplier(DatabaseExecutor txn, int localId) async {
    final rows = await txn.query(
      TableNames.fornecedores,
      columns: const [
        'id',
        'uuid',
        'criado_em',
        'atualizado_em',
        'deletado_em',
      ],
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return false;
    }

    final row = rows.first;
    final localUuid = row['uuid'] as String;
    final createdAt = DateTime.parse(row['criado_em'] as String);
    final updatedAt = DateTime.parse(row['atualizado_em'] as String);
    final deletedAt = row['deletado_em'] as String?;
    final metadata = await _syncMetadataRepository.findByLocalId(
      txn,
      featureKey: SyncFeatureKeys.suppliers,
      localId: localId,
    );
    final remoteId = metadata?.identity.remoteId;

    if (remoteId == null || remoteId.isEmpty) {
      await _syncMetadataRepository.markPendingUpload(
        txn,
        featureKey: SyncFeatureKeys.suppliers,
        localId: localId,
        localUuid: localUuid,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
    } else {
      await _syncMetadataRepository.markPendingUpdate(
        txn,
        featureKey: SyncFeatureKeys.suppliers,
        localId: localId,
        localUuid: localUuid,
        remoteId: remoteId,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
    }

    await _syncQueueRepository.enqueueMutation(
      txn,
      featureKey: SyncFeatureKeys.suppliers,
      entityType: 'supplier',
      localEntityId: localId,
      localUuid: localUuid,
      remoteId: remoteId,
      operation: deletedAt != null && remoteId != null
          ? SyncQueueOperation.delete
          : remoteId == null
          ? SyncQueueOperation.create
          : SyncQueueOperation.update,
      localUpdatedAt: updatedAt,
    );
    return true;
  }

  Future<bool> _repairProduct(DatabaseExecutor txn, int localId) async {
    final rows = await txn.query(
      TableNames.produtos,
      columns: const [
        'id',
        'uuid',
        'criado_em',
        'atualizado_em',
        'deletado_em',
      ],
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return false;
    }

    final row = rows.first;
    final localUuid = row['uuid'] as String;
    final createdAt = DateTime.parse(row['criado_em'] as String);
    final updatedAt = DateTime.parse(row['atualizado_em'] as String);
    final deletedAt = row['deletado_em'] as String?;
    final metadata = await _syncMetadataRepository.findByLocalId(
      txn,
      featureKey: SyncFeatureKeys.products,
      localId: localId,
    );
    final remoteId = metadata?.identity.remoteId;

    if (remoteId == null || remoteId.isEmpty) {
      await _syncMetadataRepository.markPendingUpload(
        txn,
        featureKey: SyncFeatureKeys.products,
        localId: localId,
        localUuid: localUuid,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
    } else {
      await _syncMetadataRepository.markPendingUpdate(
        txn,
        featureKey: SyncFeatureKeys.products,
        localId: localId,
        localUuid: localUuid,
        remoteId: remoteId,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
    }

    await _syncQueueRepository.enqueueMutation(
      txn,
      featureKey: SyncFeatureKeys.products,
      entityType: 'product',
      localEntityId: localId,
      localUuid: localUuid,
      remoteId: remoteId,
      operation: deletedAt != null && remoteId != null
          ? SyncQueueOperation.delete
          : remoteId == null
          ? SyncQueueOperation.create
          : SyncQueueOperation.update,
      localUpdatedAt: updatedAt,
    );
    return true;
  }

  Future<bool> _repairCustomer(DatabaseExecutor txn, int localId) async {
    final rows = await txn.query(
      TableNames.clientes,
      columns: const [
        'id',
        'uuid',
        'criado_em',
        'atualizado_em',
        'deletado_em',
      ],
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return false;
    }

    final row = rows.first;
    final localUuid = row['uuid'] as String;
    final createdAt = DateTime.parse(row['criado_em'] as String);
    final updatedAt = DateTime.parse(row['atualizado_em'] as String);
    final deletedAt = row['deletado_em'] as String?;
    final metadata = await _syncMetadataRepository.findByLocalId(
      txn,
      featureKey: SyncFeatureKeys.customers,
      localId: localId,
    );
    final remoteId = metadata?.identity.remoteId;

    if (remoteId == null || remoteId.isEmpty) {
      await _syncMetadataRepository.markPendingUpload(
        txn,
        featureKey: SyncFeatureKeys.customers,
        localId: localId,
        localUuid: localUuid,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
    } else {
      await _syncMetadataRepository.markPendingUpdate(
        txn,
        featureKey: SyncFeatureKeys.customers,
        localId: localId,
        localUuid: localUuid,
        remoteId: remoteId,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
    }

    await _syncQueueRepository.enqueueMutation(
      txn,
      featureKey: SyncFeatureKeys.customers,
      entityType: 'customer',
      localEntityId: localId,
      localUuid: localUuid,
      remoteId: remoteId,
      operation: deletedAt != null && remoteId != null
          ? SyncQueueOperation.delete
          : remoteId == null
          ? SyncQueueOperation.create
          : SyncQueueOperation.update,
      localUpdatedAt: updatedAt,
    );
    return true;
  }

  Future<bool> _repairSale(DatabaseExecutor txn, int localId) async {
    final sale = await _saleRepository.findSaleForSync(localId);
    if (sale == null || sale.status.name == 'cancelled') {
      return false;
    }

    if (sale.remoteId == null || sale.remoteId!.isEmpty) {
      await _syncMetadataRepository.markPendingUpload(
        txn,
        featureKey: SyncFeatureKeys.sales,
        localId: sale.saleId,
        localUuid: sale.saleUuid,
        createdAt: sale.soldAt,
        updatedAt: sale.updatedAt,
      );
    } else {
      await _syncMetadataRepository.markPendingUpdate(
        txn,
        featureKey: SyncFeatureKeys.sales,
        localId: sale.saleId,
        localUuid: sale.saleUuid,
        remoteId: sale.remoteId,
        createdAt: sale.soldAt,
        updatedAt: sale.updatedAt,
      );
    }

    await _syncQueueRepository.enqueueMutation(
      txn,
      featureKey: SyncFeatureKeys.sales,
      entityType: 'sale',
      localEntityId: sale.saleId,
      localUuid: sale.saleUuid,
      remoteId: sale.remoteId,
      operation: sale.remoteId == null
          ? SyncQueueOperation.create
          : SyncQueueOperation.update,
      localUpdatedAt: sale.updatedAt,
    );
    return true;
  }

  Future<bool> _repairPurchase(DatabaseExecutor txn, int localId) async {
    final purchase = await _purchaseRepository.findPurchaseForSync(localId);
    if (purchase == null) {
      return false;
    }

    if (purchase.supplierRemoteId == null ||
        purchase.supplierRemoteId!.isEmpty) {
      return false;
    }

    final hasProductDependencyMissing = purchase.items.any(
      (item) => item.productRemoteId == null || item.productRemoteId!.isEmpty,
    );
    if (hasProductDependencyMissing) {
      return false;
    }

    if (purchase.remoteId == null || purchase.remoteId!.isEmpty) {
      await _syncMetadataRepository.markPendingUpload(
        txn,
        featureKey: SyncFeatureKeys.purchases,
        localId: purchase.purchaseId,
        localUuid: purchase.purchaseUuid,
        createdAt: purchase.createdAt,
        updatedAt: purchase.updatedAt,
      );
    } else {
      await _syncMetadataRepository.markPendingUpdate(
        txn,
        featureKey: SyncFeatureKeys.purchases,
        localId: purchase.purchaseId,
        localUuid: purchase.purchaseUuid,
        remoteId: purchase.remoteId,
        createdAt: purchase.createdAt,
        updatedAt: purchase.updatedAt,
      );
    }

    await _syncQueueRepository.enqueueMutation(
      txn,
      featureKey: SyncFeatureKeys.purchases,
      entityType: 'purchase',
      localEntityId: purchase.purchaseId,
      localUuid: purchase.purchaseUuid,
      remoteId: purchase.remoteId,
      operation: purchase.remoteId == null
          ? SyncQueueOperation.create
          : SyncQueueOperation.update,
      localUpdatedAt: purchase.updatedAt,
    );
    return true;
  }

  Future<bool> _repairFinancialEvent(
    DatabaseExecutor txn, {
    required String entityType,
    required int localEntityId,
  }) async {
    switch (entityType) {
      case 'sale_canceled_event':
        final payload = await _saleRepository.findSaleCancellationForSync(
          localEntityId,
        );
        if (payload == null ||
            payload.saleRemoteId == null ||
            payload.saleRemoteId!.isEmpty) {
          return false;
        }
        if (payload.remoteId == null || payload.remoteId!.isEmpty) {
          await _syncMetadataRepository.markPendingUpload(
            txn,
            featureKey: SyncFeatureKeys.saleCancellations,
            localId: payload.saleId,
            localUuid: payload.saleUuid,
            createdAt: payload.canceledAt,
            updatedAt: payload.updatedAt,
          );
        } else {
          await _syncMetadataRepository.markPendingUpdate(
            txn,
            featureKey: SyncFeatureKeys.saleCancellations,
            localId: payload.saleId,
            localUuid: payload.saleUuid,
            remoteId: payload.remoteId,
            createdAt: payload.canceledAt,
            updatedAt: payload.updatedAt,
          );
        }
        await _syncQueueRepository.enqueueMutation(
          txn,
          featureKey: SyncFeatureKeys.financialEvents,
          entityType: 'sale_canceled_event',
          localEntityId: payload.saleId,
          localUuid: payload.saleUuid,
          remoteId: payload.remoteId,
          operation: SyncQueueOperation.create,
          localUpdatedAt: payload.updatedAt,
        );
        return true;
      case 'fiado_payment_event':
        final payload = await _fiadoRepository.findPaymentForSync(
          localEntityId,
        );
        if (payload == null ||
            payload.saleRemoteId == null ||
            payload.saleRemoteId!.isEmpty) {
          return false;
        }
        if (payload.remoteId == null || payload.remoteId!.isEmpty) {
          await _syncMetadataRepository.markPendingUpload(
            txn,
            featureKey: SyncFeatureKeys.fiadoPayments,
            localId: payload.entryId,
            localUuid: payload.entryUuid,
            createdAt: payload.createdAt,
            updatedAt: payload.updatedAt,
          );
        } else {
          await _syncMetadataRepository.markPendingUpdate(
            txn,
            featureKey: SyncFeatureKeys.fiadoPayments,
            localId: payload.entryId,
            localUuid: payload.entryUuid,
            remoteId: payload.remoteId,
            createdAt: payload.createdAt,
            updatedAt: payload.updatedAt,
          );
        }
        await _syncQueueRepository.enqueueMutation(
          txn,
          featureKey: SyncFeatureKeys.financialEvents,
          entityType: 'fiado_payment_event',
          localEntityId: payload.entryId,
          localUuid: payload.entryUuid,
          remoteId: payload.remoteId,
          operation: SyncQueueOperation.create,
          localUpdatedAt: payload.updatedAt,
        );
        return true;
      default:
        return false;
    }
  }

  SyncQueueItem _mapQueueRow(Map<String, Object?> row) {
    return SyncQueueItem(
      id: row['id'] as int,
      featureKey: row['feature_key'] as String,
      entityType: row['entity_type'] as String,
      localEntityId: row['local_entity_id'] as int,
      localUuid: row['local_uuid'] as String?,
      remoteId: row['remote_id'] as String?,
      operation: syncQueueOperationFromStorage(
        row['operation_type'] as String?,
      ),
      status: syncQueueStatusFromStorage(row['status'] as String?),
      attemptCount: row['attempt_count'] as int? ?? 0,
      nextRetryAt: row['next_retry_at'] == null
          ? null
          : DateTime.parse(row['next_retry_at'] as String),
      lastError: row['last_error'] as String?,
      lastErrorType: row['last_error_type'] == null
          ? null
          : syncErrorTypeFromStorage(row['last_error_type'] as String?),
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      lockedAt: row['locked_at'] == null
          ? null
          : DateTime.parse(row['locked_at'] as String),
      lastProcessedAt: row['last_processed_at'] == null
          ? null
          : DateTime.parse(row['last_processed_at'] as String),
      correlationKey: row['correlation_key'] as String,
      localUpdatedAt: row['local_updated_at'] == null
          ? null
          : DateTime.parse(row['local_updated_at'] as String),
      remoteUpdatedAt: row['remote_updated_at'] == null
          ? null
          : DateTime.parse(row['remote_updated_at'] as String),
      conflictReason: row['conflict_reason'] as String?,
    );
  }

  String _entityKey(String featureKey, String entityType, int localEntityId) {
    return '$featureKey:$entityType:$localEntityId';
  }

  bool _signaturesMatch(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    return _payloadSignature(local) == _payloadSignature(remote);
  }

  String _payloadSignature(Map<String, dynamic> payload) {
    return jsonEncode(_canonicalize(payload));
  }

  Object? _canonicalize(Object? value) {
    if (value is Map<String, dynamic>) {
      final sortedKeys = value.keys.toList()..sort();
      return <String, Object?>{
        for (final key in sortedKeys) key: _canonicalize(value[key]),
      };
    }
    if (value is List) {
      return value.map(_canonicalize).toList();
    }
    return value;
  }

  Map<String, dynamic> _normalizedSalePayload(Map<String, dynamic> payload) {
    final items = payload['items'];
    if (items is! List) {
      return payload;
    }

    final sortedItems =
        items
            .whereType<Map<String, dynamic>>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
          ..sort((left, right) {
            final nameCompare = (left['productNameSnapshot'] as String? ?? '')
                .compareTo(right['productNameSnapshot'] as String? ?? '');
            if (nameCompare != 0) {
              return nameCompare;
            }
            final quantityCompare = (left['quantityMil'] as int? ?? 0)
                .compareTo(right['quantityMil'] as int? ?? 0);
            if (quantityCompare != 0) {
              return quantityCompare;
            }
            return (left['totalPriceCents'] as int? ?? 0).compareTo(
              right['totalPriceCents'] as int? ?? 0,
            );
          });

    return <String, dynamic>{...payload, 'items': sortedItems};
  }

  int _severityOf(SyncReconciliationStatus status) {
    switch (status) {
      case SyncReconciliationStatus.conflict:
        return 100;
      case SyncReconciliationStatus.invalidLink:
        return 90;
      case SyncReconciliationStatus.missingRemote:
      case SyncReconciliationStatus.missingLocal:
        return 80;
      case SyncReconciliationStatus.outOfSync:
        return 70;
      case SyncReconciliationStatus.orphanRemote:
      case SyncReconciliationStatus.remoteOnly:
        return 60;
      case SyncReconciliationStatus.pendingSync:
        return 50;
      case SyncReconciliationStatus.localOnly:
        return 40;
      case SyncReconciliationStatus.unknown:
        return 30;
      case SyncReconciliationStatus.consistent:
        return 0;
    }
  }

  SyncReconciliationIssue? _findIssue(
    List<SyncReconciliationResult> results,
    SyncRepairTarget target,
  ) {
    for (final result in results) {
      for (final issue in result.issues) {
        final localKey =
            issue.localEntityId?.toString() ??
            issue.localUuid ??
            issue.remoteId ??
            'na';
        final stableKey = '${issue.featureKey}:${issue.entityType}:$localKey';
        if (stableKey == target.stableKey) {
          return issue;
        }
      }
    }

    return null;
  }

  SyncRepairDecision? _findDecision(
    List<SyncRepairDecision> decisions,
    SyncRepairTarget target,
  ) {
    for (final decision in decisions) {
      if (decision.stableKey == target.stableKey) {
        return decision;
      }
    }

    return null;
  }

  int _repairPriority(SyncRepairDecision decision) {
    final repairabilityWeight = switch (decision.repairability) {
      SyncRepairability.autoSafe => 50,
      SyncRepairability.assistedSafe => 40,
      SyncRepairability.manualReviewOnly => 20,
      SyncRepairability.blocked => 10,
      SyncRepairability.notRepairableYet => 0,
    };

    return _severityOf(decision.status) +
        repairabilityWeight +
        (decision.isBatchSafe ? 5 : 0);
  }

  SyncRepairDecision _buildDecision(
    SyncReconciliationIssue issue,
    List<SyncReconciliationIssue> allIssues,
  ) {
    final remoteMatch = _findSignatureMatchedRemoteIssue(issue, allIssues);
    final target = SyncRepairTarget(
      featureKey: issue.featureKey,
      entityType: issue.entityType,
      entityLabel: issue.entityLabel,
      localEntityId: issue.localEntityId,
      localUuid: issue.localUuid,
      remoteId: issue.remoteId ?? remoteMatch?.remoteId,
    );
    final hasDependencyBlock =
        issue.queueStatus == SyncQueueStatus.blockedDependency ||
        issue.lastErrorType == SyncErrorType.dependency.storageValue;
    final isPurchase = issue.featureKey == SyncFeatureKeys.purchases;
    final isSale = issue.featureKey == SyncFeatureKeys.sales;
    final isFinancial = issue.featureKey == SyncFeatureKeys.financialEvents;
    final isSupplier = issue.featureKey == SyncFeatureKeys.suppliers;
    final isCategory = issue.featureKey == SyncFeatureKeys.categories;
    final isProduct = issue.featureKey == SyncFeatureKeys.products;
    final isCustomer = issue.featureKey == SyncFeatureKeys.customers;
    final isFinancialSensitive = isPurchase || isSale || isFinancial;

    SyncRepairability repairability = SyncRepairability.notRepairableYet;
    var confidence = 0.40;
    final availableActions = <SyncRepairActionType>[];
    SyncRepairActionType? suggestedActionType;
    var reason = issue.message;
    var requiresConfirmation = false;
    var isBatchSafe = false;

    if (hasDependencyBlock) {
      availableActions.add(SyncRepairActionType.retryDependencyChain);
      suggestedActionType = SyncRepairActionType.retryDependencyChain;
      reason =
          'A fila indica dependencia bloqueada. O repair pode revalidar a cadeia e reenfileirar os pre-requisitos seguros.';
      confidence = isFinancial
          ? 0.62
          : isPurchase
          ? 0.72
          : 0.90;
      repairability = isFinancialSensitive
          ? SyncRepairability.assistedSafe
          : SyncRepairability.autoSafe;
      requiresConfirmation = isFinancialSensitive;
      isBatchSafe = !isFinancialSensitive;
    }

    switch (issue.reasonCode) {
      case 'missing_link_uuid_match':
        availableActions
          ..clear()
          ..add(SyncRepairActionType.relinkRemoteId);
        suggestedActionType = SyncRepairActionType.relinkRemoteId;
        reason =
            'Existe forte evidencia de correspondencia remota segura para religar o remoteId local.';
        confidence = isSale || isFinancial
            ? 0.99
            : isPurchase
            ? 0.96
            : 0.98;
        repairability = isSale || isFinancial
            ? SyncRepairability.assistedSafe
            : isPurchase
            ? SyncRepairability.assistedSafe
            : SyncRepairability.autoSafe;
        requiresConfirmation = isFinancialSensitive;
        isBatchSafe = !isFinancialSensitive && !isPurchase;
        break;
      case 'linked_remote_uuid_mismatch':
      case 'missing_remote':
        availableActions
          ..clear()
          ..add(SyncRepairActionType.clearInvalidRemoteId)
          ..add(SyncRepairActionType.reenqueueForSync);
        suggestedActionType = SyncRepairActionType.clearInvalidRemoteId;
        reason =
            'O vinculo remoto local parece invalido. O repair pode limpar o remoteId quebrado e reclassificar para novo envio.';
        confidence = isSale || isFinancial
            ? 0.45
            : isPurchase
            ? 0.64
            : isSupplier || isCategory
            ? 0.90
            : 0.78;
        repairability = isSale || isFinancial
            ? SyncRepairability.manualReviewOnly
            : isPurchase
            ? SyncRepairability.assistedSafe
            : isSupplier || isCategory
            ? SyncRepairability.autoSafe
            : SyncRepairability.assistedSafe;
        requiresConfirmation = isFinancialSensitive || isPurchase;
        isBatchSafe = !isFinancialSensitive && !isPurchase;
        break;
      case 'missing_link_uuid_payload_diverged':
        availableActions
          ..clear()
          ..add(SyncRepairActionType.reenqueueForSync);
        suggestedActionType = SyncRepairActionType.reenqueueForSync;
        reason =
            'O registro remoto foi encontrado, mas o payload divergiu. O repair apenas prepara um novo envio seguro sem sobrescrever automaticamente o espelho.';
        confidence = isFinancialSensitive ? 0.50 : 0.82;
        repairability = isFinancialSensitive
            ? SyncRepairability.manualReviewOnly
            : SyncRepairability.assistedSafe;
        requiresConfirmation = true;
        isBatchSafe = false;
        break;
      case 'payload_mismatch':
        availableActions
          ..clear()
          ..add(SyncRepairActionType.reenqueueForSync);
        suggestedActionType = SyncRepairActionType.reenqueueForSync;
        reason =
            'Os payloads divergiram. O repair apenas reclassifica para novo envio quando isso nao traz risco operacional.';
        confidence = isSale || isFinancial
            ? 0.46
            : isPurchase
            ? 0.58
            : isCategory || isSupplier
            ? 0.86
            : 0.72;
        repairability = isSale || isFinancial
            ? SyncRepairability.manualReviewOnly
            : isPurchase
            ? SyncRepairability.manualReviewOnly
            : isCategory || isSupplier
            ? SyncRepairability.assistedSafe
            : SyncRepairability.assistedSafe;
        requiresConfirmation = !isCategory;
        isBatchSafe = isCategory;
        break;
      case 'conflict_open':
        availableActions
          ..clear()
          ..add(SyncRepairActionType.markConflictReviewed);
        suggestedActionType = SyncRepairActionType.markConflictReviewed;
        reason =
            'Existe um conflito aberto. Esta fase apenas registra a revisao manual sem tentar sobrescrever dados.';
        confidence = 0.99;
        repairability = SyncRepairability.manualReviewOnly;
        requiresConfirmation = true;
        isBatchSafe = false;
        break;
      case 'remote_only':
      case 'orphan_remote':
      case 'feature_not_supported':
      case 'remote_fetch_failed':
        availableActions.clear();
        suggestedActionType = null;
        reason = issue.message;
        confidence = 0.20;
        repairability = issue.reasonCode == 'remote_fetch_failed'
            ? SyncRepairability.blocked
            : SyncRepairability.notRepairableYet;
        requiresConfirmation = false;
        isBatchSafe = false;
        break;
      case 'local_only':
      case 'local_pending':
      case 'pending_with_remote_link':
        if (remoteMatch != null) {
          availableActions
            ..clear()
            ..add(SyncRepairActionType.relinkRemoteId);
          suggestedActionType = SyncRepairActionType.relinkRemoteId;
          reason =
              'Foi encontrada uma correspondencia remota segura pela assinatura do payload. O repair pode religar o remoteId local.';
          confidence = isPurchase
              ? 0.95
              : isSale || isFinancial
              ? 0.55
              : isSupplier || isCategory
              ? 0.94
              : 0.86;
          repairability = isSale || isFinancial
              ? SyncRepairability.manualReviewOnly
              : isPurchase
              ? SyncRepairability.assistedSafe
              : isSupplier || isCategory
              ? SyncRepairability.autoSafe
              : SyncRepairability.assistedSafe;
          requiresConfirmation = isFinancialSensitive || isPurchase;
          isBatchSafe = !isFinancialSensitive && !isPurchase;
          break;
        }

        if (issue.canMarkForResync) {
          availableActions
            ..clear()
            ..add(SyncRepairActionType.reenqueueForSync);
          suggestedActionType = SyncRepairActionType.reenqueueForSync;
          reason =
              'O item pode ser preparado novamente para a fila, preservando a fonte de verdade local.';
          confidence = isSale || isFinancial
              ? 0.66
              : isPurchase
              ? 0.78
              : isSupplier || isCategory
              ? 0.94
              : isProduct || isCustomer
              ? 0.86
              : 0.72;
          repairability = isSale || isFinancial
              ? SyncRepairability.assistedSafe
              : isPurchase
              ? SyncRepairability.assistedSafe
              : SyncRepairability.autoSafe;
          requiresConfirmation = isFinancialSensitive || isPurchase;
          isBatchSafe = !isFinancialSensitive && !isPurchase;
        }
        break;
    }

    if (availableActions.isEmpty &&
        (issue.status == SyncReconciliationStatus.invalidLink ||
            issue.status == SyncReconciliationStatus.missingRemote)) {
      availableActions.add(SyncRepairActionType.revalidateRemotePresence);
      suggestedActionType ??= SyncRepairActionType.revalidateRemotePresence;
      repairability = SyncRepairability.notRepairableYet;
      reason =
          'O item exige revalidacao antes de qualquer repair estrutural mais forte.';
      confidence = 0.35;
      requiresConfirmation = false;
      isBatchSafe = false;
    }

    return SyncRepairDecision(
      target: target,
      status: issue.status,
      repairability: repairability,
      reason: reason,
      confidence: confidence,
      availableActions: List<SyncRepairActionType>.unmodifiable(
        availableActions,
      ),
      suggestedActionType: suggestedActionType,
      isBatchSafe: isBatchSafe,
      requiresConfirmation: requiresConfirmation,
      queueStatus: issue.queueStatus,
      metadataStatus: issue.metadataStatus,
      lastError: issue.lastError,
      lastErrorType: issue.lastErrorType,
      localPayloadSignature: issue.localPayloadSignature,
      remotePayloadSignature:
          issue.remotePayloadSignature ?? remoteMatch?.remotePayloadSignature,
    );
  }

  SyncReconciliationIssue? _findSignatureMatchedRemoteIssue(
    SyncReconciliationIssue issue,
    List<SyncReconciliationIssue> allIssues,
  ) {
    final localSignature = issue.localPayloadSignature;
    if (localSignature == null || localSignature.isEmpty) {
      return null;
    }

    final candidates = allIssues
        .where(
          (candidate) =>
              candidate.featureKey == issue.featureKey &&
              (candidate.status == SyncReconciliationStatus.remoteOnly ||
                  candidate.status == SyncReconciliationStatus.orphanRemote) &&
              candidate.remotePayloadSignature == localSignature,
        )
        .toList();
    if (candidates.length != 1) {
      return null;
    }

    return candidates.first;
  }

  Future<bool> _applyRepairAction(
    DatabaseExecutor txn,
    SyncReconciliationIssue issue,
    SyncRepairDecision decision,
    SyncRepairActionType actionType,
  ) async {
    switch (actionType) {
      case SyncRepairActionType.reenqueueForSync:
        return _repairIssue(txn, issue.featureKey, issue);
      case SyncRepairActionType.relinkRemoteId:
        return _applyRemoteRelink(txn, issue, decision);
      case SyncRepairActionType.clearInvalidRemoteId:
        return _clearBrokenRemoteLink(txn, issue);
      case SyncRepairActionType.retryDependencyChain:
        return _retryDependencyChain(txn, issue);
      case SyncRepairActionType.clearStaleBlock:
        return _clearStaleBlock(txn, issue);
      case SyncRepairActionType.markConflictReviewed:
      case SyncRepairActionType.markMissingRemote:
      case SyncRepairActionType.markMissingLocal:
      case SyncRepairActionType.refreshRemoteSnapshot:
      case SyncRepairActionType.repairRemoteLink:
      case SyncRepairActionType.repairLocalMetadata:
      case SyncRepairActionType.rebuildDependencyState:
      case SyncRepairActionType.reclassifySyncStatus:
      case SyncRepairActionType.revalidateRemotePresence:
      case SyncRepairActionType.relinkLocalUuid:
        return false;
    }
  }

  Future<void> _logRepairOutcome({
    required SyncRepairAction action,
    required SyncReconciliationIssue issue,
    required SyncRepairDecision decision,
    required bool applied,
    required SyncReconciliationIssue? afterIssue,
    required DateTime executedAt,
  }) async {
    final eventType = switch (action.type) {
      SyncRepairActionType.relinkRemoteId =>
        applied
            ? SyncAuditEventType.relinkApplied
            : SyncAuditEventType.relinkRejected,
      SyncRepairActionType.retryDependencyChain =>
        applied
            ? SyncAuditEventType.dependencyChainRetried
            : SyncAuditEventType.repairSkipped,
      SyncRepairActionType.clearStaleBlock =>
        applied
            ? SyncAuditEventType.staleBlockCleared
            : SyncAuditEventType.repairSkipped,
      SyncRepairActionType.reenqueueForSync =>
        applied
            ? SyncAuditEventType.reenqueueRequested
            : SyncAuditEventType.repairSkipped,
      SyncRepairActionType.markConflictReviewed =>
        decision.needsManualReview
            ? SyncAuditEventType.repairManualReviewRequired
            : SyncAuditEventType.statusReclassified,
      _ =>
        applied
            ? SyncAuditEventType.repairApplied
            : SyncAuditEventType.repairSkipped,
    };

    await _syncAuditRepository.log(
      featureKey: action.target.featureKey,
      entityType: action.target.entityType,
      localEntityId: action.target.localEntityId,
      localUuid: action.target.localUuid,
      remoteId: action.target.remoteId,
      eventType: eventType,
      message: applied
          ? 'Repair concluido para ${action.type.label.toLowerCase()}.'
          : 'Repair nao aplicou mudancas para ${action.type.label.toLowerCase()}.',
      details: <String, dynamic>{
        'actionType': action.type.storageValue,
        'confidence': action.confidence,
        'reason': action.reason,
        'beforeStatus': issue.status.name,
        'beforeQueueStatus': issue.queueStatus?.storageValue,
        'beforeMetadataStatus': issue.metadataStatus?.storageValue,
        'beforeRemoteId': issue.remoteId,
        'afterStatus': afterIssue?.status.name,
        'afterQueueStatus': afterIssue?.queueStatus?.storageValue,
        'afterMetadataStatus': afterIssue?.metadataStatus?.storageValue,
        'afterRemoteId': afterIssue?.remoteId,
      },
      createdAt: executedAt,
    );
  }

  Future<bool> _applyRemoteRelink(
    DatabaseExecutor txn,
    SyncReconciliationIssue issue,
    SyncRepairDecision decision,
  ) async {
    final frame = await _loadRepairFrame(
      txn,
      featureKey: issue.featureKey,
      localEntityId: issue.localEntityId,
    );
    final remoteId = decision.target.remoteId;
    if (frame == null || remoteId == null || remoteId.trim().isEmpty) {
      return false;
    }

    final metadataFeatureKey = _metadataFeatureKeyForIssue(issue);
    final exactPayloadMatch =
        issue.localPayloadSignature != null &&
        decision.remotePayloadSignature != null &&
        issue.localPayloadSignature == decision.remotePayloadSignature;
    final conservativeFeature =
        issue.featureKey == SyncFeatureKeys.purchases ||
        issue.featureKey == SyncFeatureKeys.sales ||
        issue.featureKey == SyncFeatureKeys.financialEvents;
    final nextStatus =
        exactPayloadMatch && !conservativeFeature && issue.queueStatus == null
        ? SyncStatus.synced
        : remoteId == issue.remoteId
        ? SyncStatus.pendingUpdate
        : exactPayloadMatch && !conservativeFeature
        ? SyncStatus.synced
        : SyncStatus.pendingUpdate;
    final syncedAt = nextStatus == SyncStatus.synced ? DateTime.now() : null;

    await _syncMetadataRepository.saveExplicit(
      txn,
      featureKey: metadataFeatureKey,
      localId: frame.localId,
      localUuid: frame.localUuid,
      remoteId: remoteId,
      status: nextStatus,
      origin: RecordOrigin.merged,
      createdAt: frame.createdAt,
      updatedAt: frame.updatedAt,
      lastSyncedAt: syncedAt,
      lastError: null,
      lastErrorType: null,
      lastErrorAt: null,
    );

    await _updateQueueLink(
      txn,
      issue: issue,
      remoteId: remoteId,
      status: nextStatus == SyncStatus.synced
          ? SyncQueueStatus.synced
          : SyncQueueStatus.pendingUpdate,
      touchedAt: DateTime.now(),
    );

    if (nextStatus != SyncStatus.synced) {
      return _repairIssue(txn, issue.featureKey, issue);
    }

    return true;
  }

  Future<bool> _clearBrokenRemoteLink(
    DatabaseExecutor txn,
    SyncReconciliationIssue issue,
  ) async {
    final frame = await _loadRepairFrame(
      txn,
      featureKey: issue.featureKey,
      localEntityId: issue.localEntityId,
    );
    if (frame == null) {
      return false;
    }

    final metadataFeatureKey = _metadataFeatureKeyForIssue(issue);
    await _syncMetadataRepository.saveExplicit(
      txn,
      featureKey: metadataFeatureKey,
      localId: frame.localId,
      localUuid: frame.localUuid,
      remoteId: null,
      status: SyncStatus.localOnly,
      origin: RecordOrigin.local,
      createdAt: frame.createdAt,
      updatedAt: frame.updatedAt,
      lastSyncedAt: null,
      lastError: issue.message,
      lastErrorType: SyncErrorType.dependency.storageValue,
      lastErrorAt: DateTime.now(),
    );

    await _updateQueueLink(
      txn,
      issue: issue,
      remoteId: null,
      status: issue.queueStatus == SyncQueueStatus.conflict
          ? SyncQueueStatus.conflict
          : SyncQueueStatus.pendingUpload,
      touchedAt: DateTime.now(),
    );

    return _repairIssue(txn, issue.featureKey, issue);
  }

  Future<bool> _retryDependencyChain(
    DatabaseExecutor txn,
    SyncReconciliationIssue issue,
  ) async {
    final localEntityId = issue.localEntityId;
    if (localEntityId == null) {
      return false;
    }

    switch (issue.featureKey) {
      case SyncFeatureKeys.products:
        final rows = await txn.query(
          TableNames.produtos,
          columns: const ['categoria_id'],
          where: 'id = ?',
          whereArgs: [localEntityId],
          limit: 1,
        );
        if (rows.isEmpty) {
          return false;
        }
        final categoryId = rows.first['categoria_id'] as int?;
        if (categoryId != null) {
          await _repairCategory(txn, categoryId);
        }
        return _repairProduct(txn, localEntityId);
      case SyncFeatureKeys.purchases:
        final purchaseRows = await txn.query(
          TableNames.compras,
          columns: const ['fornecedor_id'],
          where: 'id = ?',
          whereArgs: [localEntityId],
          limit: 1,
        );
        if (purchaseRows.isEmpty) {
          return false;
        }
        final supplierId = purchaseRows.first['fornecedor_id'] as int?;
        if (supplierId != null) {
          await _repairSupplier(txn, supplierId);
        }
        final itemRows = await txn.query(
          TableNames.itensCompra,
          columns: const ['produto_id'],
          where: 'compra_id = ?',
          whereArgs: [localEntityId],
        );
        for (final row in itemRows) {
          final productId = row['produto_id'] as int?;
          if (productId != null) {
            await _repairProduct(txn, productId);
          }
        }
        return _repairPurchase(txn, localEntityId);
      case SyncFeatureKeys.sales:
        final saleRows = await txn.query(
          TableNames.vendas,
          columns: const ['cliente_id'],
          where: 'id = ?',
          whereArgs: [localEntityId],
          limit: 1,
        );
        if (saleRows.isEmpty) {
          return false;
        }
        final clientId = saleRows.first['cliente_id'] as int?;
        if (clientId != null) {
          await _repairCustomer(txn, clientId);
        }
        final itemRows = await txn.query(
          TableNames.itensVenda,
          columns: const ['produto_id'],
          where: 'venda_id = ?',
          whereArgs: [localEntityId],
        );
        for (final row in itemRows) {
          final productId = row['produto_id'] as int?;
          if (productId != null) {
            await _repairProduct(txn, productId);
          }
        }
        return _repairSale(txn, localEntityId);
      case SyncFeatureKeys.financialEvents:
        switch (issue.entityType) {
          case 'sale_canceled_event':
            await _repairSale(txn, localEntityId);
            return _repairFinancialEvent(
              txn,
              entityType: issue.entityType,
              localEntityId: localEntityId,
            );
          case 'fiado_payment_event':
            final rows = await txn.rawQuery(
              '''
              SELECT fiado.venda_id
              FROM ${TableNames.fiadoLancamentos} lanc
              INNER JOIN ${TableNames.fiado} fiado ON fiado.id = lanc.fiado_id
              WHERE lanc.id = ?
              LIMIT 1
            ''',
              [localEntityId],
            );
            if (rows.isNotEmpty) {
              final saleId = rows.first['venda_id'] as int?;
              if (saleId != null) {
                await _repairSale(txn, saleId);
              }
            }
            return _repairFinancialEvent(
              txn,
              entityType: issue.entityType,
              localEntityId: localEntityId,
            );
          default:
            return false;
        }
      default:
        return _repairIssue(txn, issue.featureKey, issue);
    }
  }

  Future<bool> _clearStaleBlock(
    DatabaseExecutor txn,
    SyncReconciliationIssue issue,
  ) async {
    if (issue.localEntityId == null) {
      return false;
    }

    final now = DateTime.now();
    final nextStatus = issue.remoteId == null || issue.remoteId!.isEmpty
        ? SyncQueueStatus.pendingUpload
        : SyncQueueStatus.pendingUpdate;
    await txn.update(
      TableNames.syncQueue,
      <String, Object?>{
        'status': nextStatus.storageValue,
        'last_error': null,
        'last_error_type': null,
        'next_retry_at': null,
        'locked_at': null,
        'updated_at': now.toIso8601String(),
        'conflict_reason': null,
      },
      where: 'feature_key = ? AND entity_type = ? AND local_entity_id = ?',
      whereArgs: [issue.featureKey, issue.entityType, issue.localEntityId],
    );
    return _retryDependencyChain(txn, issue);
  }

  Future<void> _updateQueueLink(
    DatabaseExecutor txn, {
    required SyncReconciliationIssue issue,
    required String? remoteId,
    required SyncQueueStatus status,
    required DateTime touchedAt,
  }) async {
    if (issue.localEntityId == null) {
      return;
    }

    await txn.update(
      TableNames.syncQueue,
      <String, Object?>{
        'remote_id': remoteId,
        'status': status.storageValue,
        'next_retry_at': null,
        'last_error': null,
        'last_error_type': null,
        'locked_at': null,
        'updated_at': touchedAt.toIso8601String(),
        'last_processed_at': status == SyncQueueStatus.synced
            ? touchedAt.toIso8601String()
            : null,
        'remote_updated_at': status == SyncQueueStatus.synced
            ? touchedAt.toIso8601String()
            : null,
        'conflict_reason': null,
      },
      where: 'feature_key = ? AND entity_type = ? AND local_entity_id = ?',
      whereArgs: [issue.featureKey, issue.entityType, issue.localEntityId],
    );
  }

  String _metadataFeatureKeyForIssue(SyncReconciliationIssue issue) {
    if (issue.featureKey != SyncFeatureKeys.financialEvents) {
      return issue.featureKey;
    }

    switch (issue.entityType) {
      case 'sale_canceled_event':
        return SyncFeatureKeys.saleCancellations;
      case 'fiado_payment_event':
        return SyncFeatureKeys.fiadoPayments;
      default:
        return issue.featureKey;
    }
  }

  Future<_RepairFrame?> _loadRepairFrame(
    DatabaseExecutor txn, {
    required String featureKey,
    required int? localEntityId,
  }) async {
    if (localEntityId == null) {
      return null;
    }

    switch (featureKey) {
      case SyncFeatureKeys.categories:
        return _loadRepairFrameFromTable(
          txn,
          tableName: TableNames.categorias,
          localEntityId: localEntityId,
        );
      case SyncFeatureKeys.products:
        return _loadRepairFrameFromTable(
          txn,
          tableName: TableNames.produtos,
          localEntityId: localEntityId,
        );
      case SyncFeatureKeys.customers:
        return _loadRepairFrameFromTable(
          txn,
          tableName: TableNames.clientes,
          localEntityId: localEntityId,
        );
      case SyncFeatureKeys.suppliers:
        return _loadRepairFrameFromTable(
          txn,
          tableName: TableNames.fornecedores,
          localEntityId: localEntityId,
        );
      case SyncFeatureKeys.purchases:
        return _loadRepairFrameFromTable(
          txn,
          tableName: TableNames.compras,
          localEntityId: localEntityId,
        );
      case SyncFeatureKeys.sales:
        final sale = await _saleRepository.findSaleForSync(localEntityId);
        if (sale == null) {
          return null;
        }
        return _RepairFrame(
          localId: sale.saleId,
          localUuid: sale.saleUuid,
          createdAt: sale.soldAt,
          updatedAt: sale.updatedAt,
        );
      case SyncFeatureKeys.financialEvents:
        return null;
      default:
        return null;
    }
  }

  Future<_RepairFrame?> _loadRepairFrameFromTable(
    DatabaseExecutor txn, {
    required String tableName,
    required int localEntityId,
  }) async {
    final rows = await txn.query(
      tableName,
      columns: const ['id', 'uuid', 'criado_em', 'atualizado_em'],
      where: 'id = ?',
      whereArgs: [localEntityId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    final row = rows.first;
    return _RepairFrame(
      localId: row['id'] as int,
      localUuid: row['uuid'] as String,
      createdAt: DateTime.parse(row['criado_em'] as String),
      updatedAt: DateTime.parse(row['atualizado_em'] as String),
    );
  }
}

class _RepairFrame {
  const _RepairFrame({
    required this.localId,
    required this.localUuid,
    required this.createdAt,
    required this.updatedAt,
  });

  final int localId;
  final String localUuid;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class _LocalComparableRecord {
  const _LocalComparableRecord({
    required this.featureKey,
    required this.entityType,
    required this.localId,
    required this.localUuid,
    required this.remoteId,
    required this.label,
    required this.createdAt,
    required this.updatedAt,
    required this.metadataStatus,
    required this.queueItem,
    required this.lastError,
    required this.lastErrorType,
    required this.payload,
    required this.allowRepair,
  });

  final String featureKey;
  final String entityType;
  final int localId;
  final String localUuid;
  final String? remoteId;
  final String label;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus? metadataStatus;
  final SyncQueueItem? queueItem;
  final String? lastError;
  final String? lastErrorType;
  final Map<String, dynamic> payload;
  final bool allowRepair;
}

class _RemoteComparableRecord {
  const _RemoteComparableRecord({
    required this.entityType,
    required this.remoteId,
    required this.localUuid,
    required this.label,
    required this.updatedAt,
    required this.payload,
  });

  final String entityType;
  final String remoteId;
  final String? localUuid;
  final String label;
  final DateTime updatedAt;
  final Map<String, dynamic> payload;
}
