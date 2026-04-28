import 'package:erp_pdv_app/app/core/app_context/app_operational_context.dart';
import 'package:erp_pdv_app/app/core/app_context/data_access_policy.dart';
import 'package:erp_pdv_app/app/core/config/app_data_mode.dart';
import 'package:erp_pdv_app/app/core/config/app_environment.dart';
import 'package:erp_pdv_app/app/core/database/app_database.dart';
import 'package:erp_pdv_app/app/core/errors/app_exceptions.dart';
import 'package:erp_pdv_app/app/core/network/contracts/api_client_contract.dart';
import 'package:erp_pdv_app/app/core/session/app_session.dart';
import 'package:erp_pdv_app/app/core/session/app_user.dart';
import 'package:erp_pdv_app/app/core/session/auth_token_storage.dart';
import 'package:erp_pdv_app/app/core/session/company_context.dart';
import 'package:erp_pdv_app/modules/custos/data/cost_repository_impl.dart';
import 'package:erp_pdv_app/modules/custos/data/datasources/costs_remote_datasource.dart';
import 'package:erp_pdv_app/modules/custos/data/models/remote_cost_record.dart';
import 'package:erp_pdv_app/modules/custos/data/real/real_costs_remote_datasource.dart';
import 'package:erp_pdv_app/modules/custos/data/sqlite_cost_repository.dart';
import 'package:erp_pdv_app/modules/custos/domain/entities/cost_entry.dart';
import 'package:erp_pdv_app/modules/custos/domain/entities/cost_overview.dart';
import 'package:erp_pdv_app/modules/custos/domain/entities/cost_status.dart';
import 'package:erp_pdv_app/modules/custos/domain/entities/cost_type.dart';
import 'package:erp_pdv_app/modules/custos/domain/repositories/cost_repository.dart';
import 'package:erp_pdv_app/modules/estoque/data/inventory_repository_impl.dart';
import 'package:erp_pdv_app/modules/estoque/data/real/real_inventory_remote_datasource.dart';
import 'package:erp_pdv_app/modules/estoque/data/sqlite_inventory_repository.dart';
import 'package:erp_pdv_app/modules/estoque/domain/entities/inventory_adjustment_input.dart';
import 'package:erp_pdv_app/modules/estoque/domain/entities/inventory_item.dart';
import 'package:erp_pdv_app/modules/estoque/domain/entities/inventory_movement.dart';
import 'package:erp_pdv_app/modules/vendas/domain/entities/sale_enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Inventory datasource chama endpoints tenant de estoque', () async {
    final apiClient = _RecordingApiClient();
    final datasource = RealInventoryRemoteDatasource(
      apiClient: apiClient,
      tokenStorage: const _MemoryTokenStorage('access-token'),
    );

    final items = await datasource.listItems(filter: 'zeroed');
    final summary = await datasource.fetchSummary();

    expect(items.single.name, 'Produto remoto');
    expect(summary.totalItemsCount, 1);
    expect(apiClient.paths, containsAll(['/inventory', '/inventory/summary']));
    expect(apiClient.paths.any((path) => path.contains('/admin/')), isFalse);
  });

  test(
    'Inventory API 200 vira dados remotos e falha cai para cache local',
    () async {
      final remoteRepository = InventoryRepositoryImpl(
        localRepository: _FakeLocalInventoryRepository([
          _inventoryItem('Produto local'),
        ]),
        inventoryRemoteDatasource: RealInventoryRemoteDatasource(
          apiClient: _RecordingApiClient(),
          tokenStorage: const _MemoryTokenStorage('access-token'),
        ),
        operationalContext: _remoteContext(),
        dataAccessPolicy: DataAccessPolicy.fromMode(
          AppDataMode.futureRemoteReady,
        ),
      );
      final remoteItems = await remoteRepository.listItems();
      expect(remoteItems.single.productName, 'Produto remoto');

      final fallbackRepository = InventoryRepositoryImpl(
        localRepository: _FakeLocalInventoryRepository([
          _inventoryItem('Produto local'),
        ]),
        inventoryRemoteDatasource: RealInventoryRemoteDatasource(
          apiClient: _RecordingApiClient(throwOnGet: true),
          tokenStorage: const _MemoryTokenStorage('access-token'),
        ),
        operationalContext: _remoteContext(),
        dataAccessPolicy: DataAccessPolicy.fromMode(
          AppDataMode.futureRemoteReady,
        ),
      );
      final fallbackItems = await fallbackRepository.listItems();
      expect(fallbackItems.single.productName, 'Produto local');
    },
  );

  test(
    'Costs datasource chama endpoints tenant e escritas API-first',
    () async {
      final apiClient = _RecordingApiClient();
      final datasource = RealCostsRemoteDatasource(
        apiClient: apiClient,
        tokenStorage: const _MemoryTokenStorage('access-token'),
      );

      await datasource.fetchSummary();
      await datasource.list(type: CostType.fixed);
      await datasource.create(
        RemoteCostRecord.fromCreateInput(
          localUuid: 'cost-local-1',
          input: _createInput(),
        ),
      );
      await datasource.update(remoteId: 'cost-remote-1', input: _updateInput());
      await datasource.pay(remoteId: 'cost-remote-1', input: _payInput());
      await datasource.cancel(remoteId: 'cost-remote-1', notes: 'cancelar');

      expect(
        apiClient.paths,
        containsAll([
          '/costs/summary',
          '/costs',
          '/costs/cost-remote-1',
          '/costs/cost-remote-1/pay',
          '/costs/cost-remote-1/cancel',
        ]),
      );
      expect(apiClient.paths.any((path) => path.contains('/admin/')), isFalse);
    },
  );

  test(
    'Costs leitura remota cai para cache local e escrita remota falha',
    () async {
      final local = _FakeLocalCostRepository([_costEntry('Custo local')]);
      final repository = CostRepositoryImpl(
        localRepository: local,
        remoteDatasource: const _FailingCostsRemoteDatasource(),
        operationalContext: _remoteContext(),
        dataAccessPolicy: DataAccessPolicy.fromMode(
          AppDataMode.futureRemoteReady,
        ),
      );

      final overview = await repository.fetchOverview();
      final costs = await repository.searchCosts(type: CostType.fixed);

      expect(overview.pendingFixedCents, 1000);
      expect(costs.single.description, 'Custo local');
      await expectLater(
        repository.createCost(_createInput()),
        throwsA(isA<NetworkRequestException>()),
      );
      expect(local.createdCalls, 0);
    },
  );

  test('Custos locais antigos sem remoteId nao quebram tela', () async {
    final repository = CostRepositoryImpl(
      localRepository: _FakeLocalCostRepository([_costEntry('Legado')]),
    );

    final costs = await repository.searchCosts(type: CostType.fixed);

    expect(costs.single.remoteId, isNull);
    expect(costs.single.description, 'Legado');
  });
}

CreateCostInput _createInput() {
  return CreateCostInput(
    description: 'Custo remoto',
    type: CostType.fixed,
    amountCents: 1000,
    referenceDate: DateTime(2026, 4, 28),
  );
}

UpdateCostInput _updateInput() {
  return UpdateCostInput(
    description: 'Custo atualizado',
    type: CostType.fixed,
    amountCents: 2000,
    referenceDate: DateTime(2026, 4, 28),
  );
}

MarkCostPaidInput _payInput() {
  return MarkCostPaidInput(
    costId: 1,
    paidAt: DateTime(2026, 4, 28),
    paymentMethod: PaymentMethod.pix,
    registerInCash: false,
  );
}

InventoryItem _inventoryItem(String name) {
  return InventoryItem(
    productId: 1,
    productVariantId: null,
    productName: name,
    sku: null,
    variantColorLabel: null,
    variantSizeLabel: null,
    unitMeasure: 'un',
    currentStockMil: 1000,
    minimumStockMil: 0,
    reorderPointMil: null,
    allowNegativeStock: false,
    costCents: 100,
    salePriceCents: 200,
    isActive: true,
    updatedAt: DateTime(2026, 4, 28),
  );
}

CostEntry _costEntry(String description, {String? remoteId}) {
  return CostEntry(
    id: 1,
    uuid: 'cost-local-1',
    remoteId: remoteId,
    description: description,
    type: CostType.fixed,
    category: null,
    amountCents: 1000,
    referenceDate: DateTime(2026, 4, 28),
    paidAt: null,
    paymentMethod: null,
    notes: null,
    isRecurring: false,
    status: CostStatus.pending,
    cashMovementId: null,
    createdAt: DateTime(2026, 4, 28),
    updatedAt: DateTime(2026, 4, 28),
    canceledAt: null,
  );
}

AppOperationalContext _remoteContext() {
  return AppOperationalContext(
    environment: const AppEnvironment.localDefault().copyWith(
      dataMode: AppDataMode.futureRemoteReady,
      remoteSyncEnabled: true,
    ),
    session: AppSession(
      scope: SessionScope.authenticatedRemote,
      user: const AppUser(
        localId: 1,
        remoteId: 'user-1',
        displayName: 'Operador',
        email: 'operador@tatuzin.test',
        roleLabel: 'Operador',
        kind: AppUserKind.remoteAuthenticated,
      ),
      company: const CompanyContext(
        localId: 1,
        remoteId: 'company-1',
        displayName: 'Empresa',
        legalName: 'Empresa',
        documentNumber: null,
        licensePlan: 'pro',
        licenseStatus: 'ACTIVE',
        syncEnabled: true,
      ),
      startedAt: DateTime(2026, 4, 28),
      isOfflineFallback: false,
    ),
  );
}

class _FakeLocalInventoryRepository extends SqliteInventoryRepository {
  _FakeLocalInventoryRepository(this.items)
    : super.forDatabase(databaseLoader: () => AppDatabase.instance.database);

  final List<InventoryItem> items;

  @override
  Future<List<InventoryItem>> listItems({
    String query = '',
    InventoryListFilter filter = InventoryListFilter.all,
  }) async {
    return items;
  }

  @override
  Future<void> adjustStock(InventoryAdjustmentInput input) async {}

  @override
  Future<InventoryItem?> findItem({
    required int productId,
    int? productVariantId,
  }) async {
    return items.firstOrNull;
  }

  @override
  Future<List<InventoryMovement>> listMovements({
    int? productId,
    int? productVariantId,
    bool includeVariantsForProduct = false,
    InventoryMovementType? movementType,
    DateTime? createdFrom,
    DateTime? createdTo,
    int limit = 300,
  }) async {
    return const [];
  }
}

class _FakeLocalCostRepository extends SqliteCostRepository {
  _FakeLocalCostRepository(this.entries)
    : super.forDatabase(
        databaseLoader: () => AppDatabase.instance.database,
        operationalContext: _remoteContext(),
      );

  final List<CostEntry> entries;
  int createdCalls = 0;

  @override
  Future<CostOverview> fetchOverview() async {
    return const CostOverview(
      pendingFixedCents: 1000,
      pendingVariableCents: 0,
      overdueFixedCents: 0,
      overdueVariableCents: 0,
      paidFixedThisMonthCents: 0,
      paidVariableThisMonthCents: 0,
      openFixedCount: 1,
      openVariableCount: 0,
    );
  }

  @override
  Future<List<CostEntry>> searchCosts({
    required CostType type,
    String query = '',
    CostStatus? status,
    DateTime? from,
    DateTime? to,
    bool overdueOnly = false,
  }) async {
    return entries;
  }

  @override
  Future<int> createCost(CreateCostInput input) async {
    createdCalls++;
    return 1;
  }

  @override
  Future<CostEntry> fetchCost(int costId) async => entries.first;

  @override
  Future<CostEntry> upsertFromRemote(RemoteCostRecord remote) async {
    return _costEntry(remote.description, remoteId: remote.remoteId);
  }
}

class _FailingCostsRemoteDatasource implements CostsRemoteDatasource {
  const _FailingCostsRemoteDatasource();

  @override
  Future<RemoteCostRecord> cancel({
    required String remoteId,
    String? notes,
  }) async {
    throw const NetworkRequestException('falha remota');
  }

  @override
  Future<RemoteCostRecord> create(RemoteCostRecord record) async {
    throw const NetworkRequestException('falha remota');
  }

  @override
  Future<RemoteCostOverview> fetchSummary() async {
    throw const NetworkRequestException('falha remota');
  }

  @override
  Future<List<RemoteCostRecord>> list({
    required CostType type,
    String query = '',
    CostStatus? status,
    DateTime? from,
    DateTime? to,
    bool overdueOnly = false,
  }) async {
    throw const NetworkRequestException('falha remota');
  }

  @override
  Future<RemoteCostRecord> pay({
    required String remoteId,
    required MarkCostPaidInput input,
  }) async {
    throw const NetworkRequestException('falha remota');
  }

  @override
  Future<RemoteCostRecord> update({
    required String remoteId,
    required UpdateCostInput input,
  }) async {
    throw const NetworkRequestException('falha remota');
  }
}

class _RecordingApiClient implements ApiClientContract {
  _RecordingApiClient({this.throwOnGet = false});

  final bool throwOnGet;
  final paths = <String>[];

  @override
  Future<ApiResponse<void>> delete(
    String path, {
    ApiRequestOptions options = const ApiRequestOptions(),
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ApiResponse<Map<String, dynamic>>> getJson(
    String path, {
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async {
    paths.add(path);
    if (throwOnGet) {
      throw const NetworkRequestException('falha remota');
    }
    return ApiResponse<Map<String, dynamic>>(
      statusCode: 200,
      headers: const <String, String>{},
      data: _payloadFor(path),
    );
  }

  @override
  Future<ApiResponse<Map<String, dynamic>>> postJson(
    String path, {
    Map<String, dynamic>? body,
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async {
    paths.add(path);
    return ApiResponse<Map<String, dynamic>>(
      statusCode: 200,
      headers: const <String, String>{},
      data: _costPayload(),
    );
  }

  @override
  Future<ApiResponse<Map<String, dynamic>>> putJson(
    String path, {
    Map<String, dynamic>? body,
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async {
    paths.add(path);
    return ApiResponse<Map<String, dynamic>>(
      statusCode: 200,
      headers: const <String, String>{},
      data: _costPayload(),
    );
  }

  @override
  Future<ApiResponse<Map<String, dynamic>>> patchJson(
    String path, {
    Map<String, dynamic>? body,
    ApiRequestOptions options = const ApiRequestOptions(),
  }) {
    throw UnimplementedError();
  }

  Map<String, dynamic> _payloadFor(String path) {
    if (path == '/inventory') {
      return {
        'items': [
          {
            'productId': 'product-remote-1',
            'productVariantId': null,
            'name': 'Produto remoto',
            'variantName': null,
            'sku': null,
            'unitMeasure': 'un',
            'currentStockMil': 1000,
            'minimumStockMil': 0,
            'costPriceCents': 100,
            'salePriceCents': 200,
            'status': 'active',
          },
        ],
      };
    }
    if (path == '/inventory/summary') {
      return {
        'summary': {
          'totalItemsCount': 1,
          'activeItemsCount': 1,
          'zeroedItemsCount': 0,
          'belowMinimumItemsCount': 0,
          'inventoryCostValueCents': 100,
          'inventorySaleValueCents': 200,
          'divergenceItemsCount': 0,
        },
      };
    }
    if (path == '/costs/summary') {
      return {
        'summary': {
          'pendingFixedCents': 1000,
          'pendingVariableCents': 0,
          'overdueFixedCents': 0,
          'overdueVariableCents': 0,
          'paidFixedThisMonthCents': 0,
          'paidVariableThisMonthCents': 0,
          'openFixedCount': 1,
          'openVariableCount': 0,
        },
      };
    }
    if (path == '/costs') {
      return {
        'items': [_costJson()],
      };
    }
    return _costPayload();
  }

  Map<String, dynamic> _costPayload() => {'cost': _costJson()};

  Map<String, dynamic> _costJson() {
    return {
      'id': 'cost-remote-1',
      'localUuid': 'cost-local-1',
      'description': 'Custo remoto',
      'type': 'fixed',
      'category': null,
      'amountCents': 1000,
      'referenceDate': '2026-04-28T00:00:00.000Z',
      'status': 'pending',
      'isRecurring': false,
      'paidAt': null,
      'paymentMethod': null,
      'notes': null,
      'createdAt': '2026-04-28T00:00:00.000Z',
      'updatedAt': '2026-04-28T00:00:00.000Z',
      'canceledAt': null,
    };
  }
}

class _MemoryTokenStorage implements AuthTokenStorage {
  const _MemoryTokenStorage(this.accessToken);

  final String accessToken;

  @override
  Future<void> clear() async {}

  @override
  Future<AuthClientContext> ensureClientContext({
    required String clientType,
    String? deviceLabel,
    String? platform,
    String? appVersion,
  }) async {
    return AuthClientContext(
      clientType: clientType,
      clientInstanceId: 'test-device',
      deviceLabel: deviceLabel,
      platform: platform,
      appVersion: appVersion,
    );
  }

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<AuthClientContext?> readClientContext() async => null;

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {}
}
