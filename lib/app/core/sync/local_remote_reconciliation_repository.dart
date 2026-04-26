import 'package:sqflite/sqflite.dart';

import '../../../modules/categorias/data/datasources/categories_remote_datasource.dart';
import '../../../modules/categorias/data/models/remote_category_record.dart';
import '../../../modules/clientes/data/datasources/customers_remote_datasource.dart';
import '../../../modules/clientes/data/models/remote_customer_record.dart';
import '../../../modules/compras/data/datasources/purchases_remote_datasource.dart';
import '../../../modules/compras/data/models/remote_purchase_record.dart';
import '../../../modules/compras/data/sqlite_purchase_repository.dart';
import '../../../modules/fiado/data/sqlite_fiado_repository.dart';
import '../../../modules/fornecedores/data/datasources/suppliers_remote_datasource.dart';
import '../../../modules/fornecedores/data/models/remote_supplier_record.dart';
import '../../../modules/produtos/data/datasources/products_remote_datasource.dart';
import '../../../modules/produtos/data/models/remote_product_record.dart';
import '../../../modules/vendas/data/datasources/sales_remote_datasource.dart';
import '../../../modules/vendas/data/models/remote_sale_record.dart';
import '../../../modules/vendas/data/sqlite_sale_repository.dart';
import '../database/app_database.dart';
import '../database/table_names.dart';
import 'financial_events_remote_datasource.dart';
import 'reconciliation_decision_policy.dart';
import 'reconciliation_decision_support.dart';
import 'reconciliation_local_comparable_record.dart';
import 'reconciliation_local_rich_loader.dart';
import 'reconciliation_local_simple_loader.dart';
import 'reconciliation_payload_support.dart';
import 'reconciliation_repair_dispatch.dart';
import 'reconciliation_repair_issue_dispatch.dart';
import 'reconciliation_repair_metadata_support.dart';
import 'reconciliation_repair_queue_support.dart';
import 'reconciliation_repair_relink_support.dart';
import 'reconciliation_retry_dependency_dispatch.dart';
import 'reconciliation_remote_comparable_record.dart';
import 'reconciliation_remote_record_mapper.dart';
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
      final severity = ReconciliationDecisionSupport.repairPriority(
        right,
      ).compareTo(ReconciliationDecisionSupport.repairPriority(left));
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
    final decision = ReconciliationDecisionSupport.findDecision(
      buildDecisions(freshResults),
      action.target,
    );
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

    final issue = ReconciliationDecisionSupport.findIssue(
      freshResults,
      action.target,
    );
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
      final afterIssue = ReconciliationDecisionSupport.findIssue(
        <SyncReconciliationResult>[refreshed],
        action.target,
      );
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

  Future<List<ReconciliationLocalComparableRecord>> _loadLocalCategories({
    required Map<int, SyncMetadata> metadataByLocalId,
    required Map<String, SyncQueueItem> queueByEntityKey,
  }) async {
    final database = await _appDatabase.database;
    return ReconciliationLocalSimpleLoader.loadCategories(
      database,
      metadataByLocalId: metadataByLocalId,
      queueByEntityKey: queueByEntityKey,
    );
  }

  Future<List<ReconciliationLocalComparableRecord>> _loadLocalProducts({
    required Map<int, SyncMetadata> metadataByLocalId,
    required Map<String, SyncQueueItem> queueByEntityKey,
  }) async {
    final database = await _appDatabase.database;
    return ReconciliationLocalRichLoader.loadProducts(
      database,
      metadataByLocalId: metadataByLocalId,
      queueByEntityKey: queueByEntityKey,
    );
  }

  Future<List<ReconciliationLocalComparableRecord>> _loadLocalCustomers({
    required Map<int, SyncMetadata> metadataByLocalId,
    required Map<String, SyncQueueItem> queueByEntityKey,
  }) async {
    final database = await _appDatabase.database;
    return ReconciliationLocalSimpleLoader.loadCustomers(
      database,
      metadataByLocalId: metadataByLocalId,
      queueByEntityKey: queueByEntityKey,
    );
  }

  Future<List<ReconciliationLocalComparableRecord>> _loadLocalSuppliers({
    required Map<int, SyncMetadata> metadataByLocalId,
    required Map<String, SyncQueueItem> queueByEntityKey,
  }) async {
    final database = await _appDatabase.database;
    return ReconciliationLocalSimpleLoader.loadSuppliers(
      database,
      metadataByLocalId: metadataByLocalId,
      queueByEntityKey: queueByEntityKey,
    );
  }

  Future<List<ReconciliationLocalComparableRecord>> _loadLocalPurchases({
    required Map<int, SyncMetadata> metadataByLocalId,
    required Map<String, SyncQueueItem> queueByEntityKey,
  }) async {
    final database = await _appDatabase.database;
    return ReconciliationLocalRichLoader.loadPurchases(
      database,
      metadataByLocalId: metadataByLocalId,
      queueByEntityKey: queueByEntityKey,
      purchaseRepository: _purchaseRepository,
    );
  }

  Future<List<ReconciliationLocalComparableRecord>> _loadLocalSales({
    required Map<int, SyncMetadata> metadataByLocalId,
    required Map<String, SyncQueueItem> queueByEntityKey,
  }) async {
    final database = await _appDatabase.database;
    return ReconciliationLocalRichLoader.loadSales(
      database,
      metadataByLocalId: metadataByLocalId,
      queueByEntityKey: queueByEntityKey,
      saleRepository: _saleRepository,
    );
  }

  Future<List<ReconciliationLocalComparableRecord>> _loadLocalFinancialEvents({
    required Map<int, SyncMetadata> cancellationMetadataByLocalId,
    required Map<int, SyncMetadata> paymentMetadataByLocalId,
    required Map<String, SyncQueueItem> queueByEntityKey,
  }) async {
    final database = await _appDatabase.database;
    return ReconciliationLocalRichLoader.loadFinancialEvents(
      database,
      cancellationMetadataByLocalId: cancellationMetadataByLocalId,
      paymentMetadataByLocalId: paymentMetadataByLocalId,
      queueByEntityKey: queueByEntityKey,
      saleRepository: _saleRepository,
      fiadoRepository: _fiadoRepository,
    );
  }

  ReconciliationRemoteComparableRecord _mapRemoteCategory(
    RemoteCategoryRecord remote,
  ) {
    return ReconciliationRemoteRecordMapper.mapCategory(remote);
  }

  ReconciliationRemoteComparableRecord _mapRemoteSupplier(
    RemoteSupplierRecord remote,
  ) {
    return ReconciliationRemoteRecordMapper.mapSupplier(remote);
  }

  ReconciliationRemoteComparableRecord _mapRemoteProduct(
    RemoteProductRecord remote,
  ) {
    return ReconciliationRemoteRecordMapper.mapProduct(remote);
  }

  ReconciliationRemoteComparableRecord _mapRemotePurchase(
    RemotePurchaseRecord remote,
  ) {
    return ReconciliationRemoteRecordMapper.mapPurchase(remote);
  }

  ReconciliationRemoteComparableRecord _mapRemoteCustomer(
    RemoteCustomerRecord remote,
  ) {
    return ReconciliationRemoteRecordMapper.mapCustomer(remote);
  }

  ReconciliationRemoteComparableRecord _mapRemoteSale(RemoteSaleRecord remote) {
    return ReconciliationRemoteRecordMapper.mapSale(remote);
  }

  ReconciliationRemoteComparableRecord _mapRemoteFinancialEvent(
    RemoteFinancialEventRecord remote,
  ) {
    return ReconciliationRemoteRecordMapper.mapFinancialEvent(remote);
  }

  SyncReconciliationResult _reconcileComparableFeature({
    required String featureKey,
    required String displayName,
    required List<ReconciliationLocalComparableRecord> localRecords,
    required List<ReconciliationRemoteComparableRecord> remoteRecords,
    bool preferOrphanRemoteWhenLocalUuidAvailable = false,
  }) {
    final remoteById = <String, ReconciliationRemoteComparableRecord>{
      for (final remote in remoteRecords) remote.remoteId: remote,
    };
    final remoteByLocalUuid = <String, ReconciliationRemoteComparableRecord>{
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
          remotePayloadSignature: ReconciliationPayloadSupport.payloadSignature(
            remote.payload,
          ),
        ),
      );
    }

    issues.sort((left, right) {
      final severityCompare = ReconciliationDecisionSupport.severityOf(
        right.status,
      ).compareTo(ReconciliationDecisionSupport.severityOf(left.status));
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
    ReconciliationLocalComparableRecord local, {
    required Map<String, ReconciliationRemoteComparableRecord> remoteById,
    required Map<String, ReconciliationRemoteComparableRecord>
    remoteByLocalUuid,
    required Set<String> matchedRemoteIds,
  }) {
    final remoteByLinkedId = local.remoteId == null
        ? null
        : remoteById[local.remoteId!];
    final remoteByUuid = remoteByLocalUuid[local.localUuid];
    final remote = remoteByLinkedId ?? remoteByUuid;
    final pendingMetadata = ReconciliationDecisionSupport.hasPendingMetadata(
      local.metadataStatus,
    );
    final hasPendingQueue = ReconciliationDecisionSupport.hasPendingQueue(
      local.queueItem,
    );

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
        localPayloadSignature: ReconciliationPayloadSupport.payloadSignature(
          local.payload,
        ),
        remotePayloadSignature: remote == null
            ? null
            : ReconciliationPayloadSupport.payloadSignature(remote.payload),
      );
    }

    if (local.remoteId == null || local.remoteId!.isEmpty) {
      if (remoteByUuid != null) {
        matchedRemoteIds.add(remoteByUuid.remoteId);
        final signaturesMatch = ReconciliationPayloadSupport.signaturesMatch(
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
          localPayloadSignature: ReconciliationPayloadSupport.payloadSignature(
            local.payload,
          ),
          remotePayloadSignature: ReconciliationPayloadSupport.payloadSignature(
            remoteByUuid.payload,
          ),
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
            ? ReconciliationDecisionSupport.pendingMessage(local)
            : 'O registro continua apenas na base local, sem vinculo remoto.',
        localEntityId: local.localId,
        localUuid: local.localUuid,
        localUpdatedAt: local.updatedAt,
        metadataStatus: local.metadataStatus,
        queueStatus: local.queueItem?.status,
        lastError: local.lastError,
        lastErrorType: local.lastErrorType,
        canMarkForResync: local.allowRepair,
        localPayloadSignature: ReconciliationPayloadSupport.payloadSignature(
          local.payload,
        ),
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
        localPayloadSignature: ReconciliationPayloadSupport.payloadSignature(
          local.payload,
        ),
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
        localPayloadSignature: ReconciliationPayloadSupport.payloadSignature(
          local.payload,
        ),
        remotePayloadSignature: ReconciliationPayloadSupport.payloadSignature(
          remoteByLinkedId.payload,
        ),
      );
    }

    if (pendingMetadata || hasPendingQueue) {
      return SyncReconciliationIssue(
        featureKey: local.featureKey,
        entityType: local.entityType,
        entityLabel: local.label,
        status: SyncReconciliationStatus.pendingSync,
        reasonCode: 'pending_with_remote_link',
        message: ReconciliationDecisionSupport.pendingMessage(local),
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
        localPayloadSignature: ReconciliationPayloadSupport.payloadSignature(
          local.payload,
        ),
        remotePayloadSignature: ReconciliationPayloadSupport.payloadSignature(
          remoteByLinkedId.payload,
        ),
      );
    }

    if (!ReconciliationPayloadSupport.signaturesMatch(
      local.payload,
      remoteByLinkedId.payload,
    )) {
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
        localPayloadSignature: ReconciliationPayloadSupport.payloadSignature(
          local.payload,
        ),
        remotePayloadSignature: ReconciliationPayloadSupport.payloadSignature(
          remoteByLinkedId.payload,
        ),
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
      localPayloadSignature: ReconciliationPayloadSupport.payloadSignature(
        local.payload,
      ),
      remotePayloadSignature: ReconciliationPayloadSupport.payloadSignature(
        remoteByLinkedId.payload,
      ),
    );
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

    switch (ReconciliationRepairIssueDispatch.resolve(featureKey)) {
      case RepairIssueDispatchTarget.repairSupplier:
        return _repairSupplier(txn, localEntityId);
      case RepairIssueDispatchTarget.repairCategory:
        return _repairCategory(txn, localEntityId);
      case RepairIssueDispatchTarget.repairProduct:
        return _repairProduct(txn, localEntityId);
      case RepairIssueDispatchTarget.repairCustomer:
        return _repairCustomer(txn, localEntityId);
      case RepairIssueDispatchTarget.repairPurchase:
        return _repairPurchase(txn, localEntityId);
      case RepairIssueDispatchTarget.repairSale:
        return _repairSale(txn, localEntityId);
      case RepairIssueDispatchTarget.repairFinancialEvent:
        return _repairFinancialEvent(
          txn,
          entityType: issue.entityType,
          localEntityId: localEntityId,
        );
      case RepairIssueDispatchTarget.unsupported:
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

  SyncRepairDecision _buildDecision(
    SyncReconciliationIssue issue,
    List<SyncReconciliationIssue> allIssues,
  ) {
    return ReconciliationDecisionPolicy.buildDecision(issue, allIssues);
  }

  Future<bool> _applyRepairAction(
    DatabaseExecutor txn,
    SyncReconciliationIssue issue,
    SyncRepairDecision decision,
    SyncRepairActionType actionType,
  ) async {
    switch (ReconciliationRepairDispatch.resolve(actionType)) {
      case RepairDispatchTarget.repairIssue:
        return _repairIssue(txn, issue.featureKey, issue);
      case RepairDispatchTarget.applyRemoteRelink:
        return _applyRemoteRelink(txn, issue, decision);
      case RepairDispatchTarget.clearBrokenRemoteLink:
        return _clearBrokenRemoteLink(txn, issue);
      case RepairDispatchTarget.retryDependencyChain:
        return _retryDependencyChain(txn, issue);
      case RepairDispatchTarget.clearStaleBlock:
        return _clearStaleBlock(txn, issue);
      case RepairDispatchTarget.unsupported:
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
    final touchedAt = DateTime.now();

    await ReconciliationRepairRelinkSupport.applyRemoteRelink(
      txn,
      syncMetadataRepository: _syncMetadataRepository,
      metadataFeatureKey: metadataFeatureKey,
      issue: issue,
      localId: frame.localId,
      localUuid: frame.localUuid,
      remoteId: remoteId,
      nextStatus: nextStatus,
      queueStatus: nextStatus == SyncStatus.synced
          ? SyncQueueStatus.synced
          : SyncQueueStatus.pendingUpdate,
      createdAt: frame.createdAt,
      updatedAt: frame.updatedAt,
      syncedAt: syncedAt,
      touchedAt: touchedAt,
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
    await ReconciliationRepairMetadataSupport.clearBrokenRemoteLink(
      txn,
      syncMetadataRepository: _syncMetadataRepository,
      metadataFeatureKey: metadataFeatureKey,
      issue: issue,
      localId: frame.localId,
      localUuid: frame.localUuid,
      createdAt: frame.createdAt,
      updatedAt: frame.updatedAt,
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

    switch (ReconciliationRetryDependencyDispatch.resolve(
      featureKey: issue.featureKey,
      entityType: issue.entityType,
    )) {
      case RetryDependencyDispatchTarget.productDependencyChain:
        return _retryProductDependencyChain(txn, localEntityId: localEntityId);
      case RetryDependencyDispatchTarget.purchaseDependencyChain:
        return _retryPurchaseDependencyChain(txn, localEntityId: localEntityId);
      case RetryDependencyDispatchTarget.saleDependencyChain:
        return _retrySaleDependencyChain(txn, localEntityId: localEntityId);
      case RetryDependencyDispatchTarget.canceledSaleFinancialEventChain:
        return _retryCanceledSaleFinancialEventChain(
          txn,
          issue: issue,
          localEntityId: localEntityId,
        );
      case RetryDependencyDispatchTarget.fiadoPaymentFinancialEventChain:
        return _retryFiadoPaymentFinancialEventChain(
          txn,
          issue: issue,
          localEntityId: localEntityId,
        );
      case RetryDependencyDispatchTarget.directRepair:
        return _repairIssue(txn, issue.featureKey, issue);
      case RetryDependencyDispatchTarget.unsupported:
        return false;
    }
  }

  Future<bool> _retryProductDependencyChain(
    DatabaseExecutor txn, {
    required int localEntityId,
  }) async {
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
  }

  Future<bool> _retryPurchaseDependencyChain(
    DatabaseExecutor txn, {
    required int localEntityId,
  }) async {
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
  }

  Future<bool> _retrySaleDependencyChain(
    DatabaseExecutor txn, {
    required int localEntityId,
  }) async {
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
  }

  Future<bool> _retryCanceledSaleFinancialEventChain(
    DatabaseExecutor txn, {
    required SyncReconciliationIssue issue,
    required int localEntityId,
  }) async {
    await _repairSale(txn, localEntityId);
    return _repairFinancialEvent(
      txn,
      entityType: issue.entityType,
      localEntityId: localEntityId,
    );
  }

  Future<bool> _retryFiadoPaymentFinancialEventChain(
    DatabaseExecutor txn, {
    required SyncReconciliationIssue issue,
    required int localEntityId,
  }) async {
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
  }

  Future<bool> _clearStaleBlock(
    DatabaseExecutor txn,
    SyncReconciliationIssue issue,
  ) async {
    if (issue.localEntityId == null) {
      return false;
    }

    await ReconciliationRepairQueueSupport.clearStaleBlock(
      txn,
      issue: issue,
      touchedAt: DateTime.now(),
    );
    return _retryDependencyChain(txn, issue);
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
