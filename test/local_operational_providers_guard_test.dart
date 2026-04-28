import 'dart:async';

import 'package:erp_pdv_app/app/theme/app_theme.dart';
import 'package:erp_pdv_app/app/core/database/app_database.dart';
import 'package:erp_pdv_app/app/core/providers/app_data_refresh_provider.dart';
import 'package:erp_pdv_app/app/core/session/app_session.dart';
import 'package:erp_pdv_app/app/core/session/app_user.dart';
import 'package:erp_pdv_app/app/core/session/company_context.dart';
import 'package:erp_pdv_app/app/core/session/session_provider.dart';
import 'package:erp_pdv_app/modules/caixa/domain/entities/cash_manual_movement_input.dart';
import 'package:erp_pdv_app/modules/caixa/domain/entities/cash_movement.dart';
import 'package:erp_pdv_app/modules/caixa/domain/entities/cash_session.dart';
import 'package:erp_pdv_app/modules/caixa/domain/entities/cash_session_detail.dart';
import 'package:erp_pdv_app/modules/caixa/domain/repositories/cash_repository.dart';
import 'package:erp_pdv_app/modules/caixa/presentation/providers/cash_providers.dart';
import 'package:erp_pdv_app/modules/custos/domain/entities/cost_entry.dart';
import 'package:erp_pdv_app/modules/custos/domain/entities/cost_overview.dart';
import 'package:erp_pdv_app/modules/custos/domain/entities/cost_status.dart';
import 'package:erp_pdv_app/modules/custos/domain/entities/cost_type.dart';
import 'package:erp_pdv_app/modules/custos/domain/repositories/cost_repository.dart';
import 'package:erp_pdv_app/modules/custos/presentation/providers/cost_providers.dart';
import 'package:erp_pdv_app/modules/estoque/domain/entities/inventory_adjustment_input.dart';
import 'package:erp_pdv_app/modules/estoque/domain/entities/inventory_item.dart';
import 'package:erp_pdv_app/modules/estoque/domain/entities/inventory_movement.dart';
import 'package:erp_pdv_app/modules/estoque/domain/repositories/inventory_repository.dart';
import 'package:erp_pdv_app/modules/estoque/presentation/providers/inventory_providers.dart';
import 'package:erp_pdv_app/modules/fiado/domain/entities/fiado_account.dart';
import 'package:erp_pdv_app/modules/fiado/domain/entities/fiado_detail.dart';
import 'package:erp_pdv_app/modules/fiado/domain/entities/fiado_payment_input.dart';
import 'package:erp_pdv_app/modules/fiado/domain/repositories/fiado_repository.dart';
import 'package:erp_pdv_app/modules/fiado/presentation/providers/fiado_providers.dart';
import 'package:erp_pdv_app/modules/pedidos/domain/entities/operational_order.dart';
import 'package:erp_pdv_app/modules/pedidos/domain/entities/operational_order_item.dart';
import 'package:erp_pdv_app/modules/pedidos/domain/entities/operational_order_item_modifier.dart';
import 'package:erp_pdv_app/modules/pedidos/domain/entities/operational_order_summary.dart';
import 'package:erp_pdv_app/modules/pedidos/domain/repositories/operational_order_repository.dart';
import 'package:erp_pdv_app/modules/pedidos/presentation/providers/order_providers.dart';
import 'package:erp_pdv_app/modules/produtos/domain/entities/product.dart';
import 'package:erp_pdv_app/modules/produtos/domain/repositories/product_repository.dart';
import 'package:erp_pdv_app/modules/vendas/presentation/pages/sales_page.dart';
import 'package:erp_pdv_app/modules/vendas/presentation/providers/sales_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'provider logado aguarda tenant bootstrap antes de ler repositorio',
    () async {
      final startupCompleter = Completer<AppStartupState>();
      final repository = _CountingProductRepository();
      final container = ProviderContainer(
        overrides: [
          appStartupProvider.overrideWith((ref) => startupCompleter.future),
          salesCatalogRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      _setRemoteSession(container);

      final future = container.read(salesCatalogProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(repository.searchCalls, 0);

      startupCompleter.complete(const AppStartupState.success());
      expect(await future, isEmpty);
      expect(repository.searchCalls, 1);
    },
  );

  test(
    'salesCatalogProvider retorna lista vazia quando local retorna vazio',
    () async {
      final container = ProviderContainer(
        overrides: [
          salesCatalogRepositoryProvider.overrideWithValue(
            const _FakeProductRepository(<Product>[]),
          ),
        ],
      );
      addTearDown(container.dispose);

      final catalog = await container.read(salesCatalogProvider.future);

      expect(catalog, isEmpty);
    },
  );

  test(
    'salesCatalogProvider gera timeout quando local nao completa',
    () async {
      final container = ProviderContainer(
        overrides: [
          salesCatalogRepositoryProvider.overrideWithValue(
            _NeverCompletesProductRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(salesCatalogProvider.future),
        throwsA(isA<TimeoutException>()),
      );
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets('SalesPage mostra erro e retry do catalogo', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          salesCatalogProvider.overrideWith((ref) async {
            attempts++;
            throw TimeoutException('catalogo travado');
          }),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const SalesPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Falha ao carregar catalogo'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
    expect(attempts, 1);

    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
  });

  test('Fiado: banco vazio retorna vazio pelo provider', () async {
    final container = ProviderContainer(
      overrides: [
        fiadoRepositoryProvider.overrideWithValue(_EmptyFiadoRepository()),
      ],
    );
    addTearDown(container.dispose);

    expect(await container.read(fiadoListProvider.future), isEmpty);
  });

  test('Pedidos: banco vazio retorna fila vazia pelo provider', () async {
    final container = ProviderContainer(
      overrides: [
        operationalOrderRepositoryProvider.overrideWithValue(
          _EmptyOperationalOrderRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final board = await container.read(operationalOrderBoardProvider.future);

    expect(board.orders, isEmpty);
    expect(board.activeCount, 0);
  });

  test('Custos: banco vazio retorna resumo zerado e lista vazia', () async {
    final container = ProviderContainer(
      overrides: [
        costRepositoryProvider.overrideWithValue(_EmptyCostRepository()),
      ],
    );
    addTearDown(container.dispose);

    final overview = await container.read(costOverviewProvider.future);
    final costs = await container.read(costsProvider(CostType.fixed).future);

    expect(overview.pendingFixedCents, 0);
    expect(overview.pendingVariableCents, 0);
    expect(costs, isEmpty);
  });

  test('Estoque: local vazio retorna vazio pelo provider', () async {
    final container = ProviderContainer(
      overrides: [
        inventoryRepositoryProvider.overrideWithValue(
          _EmptyInventoryRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(await container.read(inventoryItemsProvider.future), isEmpty);
  });

  test('Caixa continua respondendo com banco vazio', () async {
    final container = ProviderContainer(
      overrides: [
        cashRepositoryProvider.overrideWithValue(_EmptyCashRepository()),
      ],
    );
    addTearDown(container.dispose);

    expect(await container.read(currentCashSessionProvider.future), isNull);
  });

  test('modo autenticado mantem Vendas Fiado Pedidos e Caixa locais', () async {
    final container = ProviderContainer(
      overrides: [
        salesCatalogRepositoryProvider.overrideWithValue(
          const _FakeProductRepository(<Product>[]),
        ),
        fiadoRepositoryProvider.overrideWithValue(_EmptyFiadoRepository()),
        operationalOrderRepositoryProvider.overrideWithValue(
          _EmptyOperationalOrderRepository(),
        ),
        cashRepositoryProvider.overrideWithValue(_EmptyCashRepository()),
        appStartupProvider.overrideWith(
          (ref) async => const AppStartupState.success(),
        ),
      ],
    );
    addTearDown(container.dispose);
    _setRemoteSession(container);

    expect(await container.read(salesCatalogProvider.future), isEmpty);
    expect(await container.read(fiadoListProvider.future), isEmpty);
    expect(
      (await container.read(operationalOrderBoardProvider.future)).orders,
      isEmpty,
    );
    expect(await container.read(currentCashSessionProvider.future), isNull);
  });

  test('login nao cria loop nas chaves de sessao e refresh', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    _setRemoteSession(container);

    final runtimeKey = container.read(sessionRuntimeKeyProvider);
    final refreshKey = container.read(appDataRefreshProvider);

    expect(runtimeKey, startsWith('remote:company-1:'));
    expect(container.read(sessionRuntimeKeyProvider), runtimeKey);
    expect(container.read(appDataRefreshProvider), refreshKey);
  });

  test('modo offline continua usando banco local padrao', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(sessionRuntimeKeyProvider),
      startsWith('local_default:'),
    );
    expect(
      AppDatabase.databaseNameForIsolationKey(
        container.read(sessionIsolationKeyProvider),
      ),
      'simples_erp_pdv.db',
    );
  });
}

void _setRemoteSession(ProviderContainer container) {
  container
      .read(appSessionProvider.notifier)
      .setAuthenticatedSession(
        scope: SessionScope.authenticatedRemote,
        user: const AppUser(
          localId: null,
          remoteId: 'user-1',
          displayName: 'Operador',
          email: 'operador@tatuzin.test',
          roleLabel: 'Operador',
          kind: AppUserKind.remoteAuthenticated,
        ),
        company: const CompanyContext(
          localId: null,
          remoteId: 'company-1',
          displayName: 'Cafe Oliveira',
          legalName: 'Cafe Oliveira LTDA',
          documentNumber: null,
          licensePlan: 'trial',
          licenseStatus: 'trial',
          syncEnabled: true,
        ),
      );
}

class _FakeProductRepository implements ProductRepository {
  const _FakeProductRepository(this.products);

  final List<Product> products;

  @override
  Future<List<Product>> search({String query = ''}) async => products;

  @override
  Future<List<Product>> searchAvailable({String query = ''}) async => products;

  @override
  Future<int> create(ProductInput input) => throw UnimplementedError();

  @override
  Future<void> update(int id, ProductInput input) => throw UnimplementedError();

  @override
  Future<void> delete(int id) => throw UnimplementedError();
}

class _NeverCompletesProductRepository extends _FakeProductRepository {
  _NeverCompletesProductRepository() : super(const <Product>[]);

  @override
  Future<List<Product>> search({String query = ''}) =>
      Completer<List<Product>>().future;
}

class _CountingProductRepository extends _FakeProductRepository {
  _CountingProductRepository() : super(const <Product>[]);

  int searchCalls = 0;

  @override
  Future<List<Product>> search({String query = ''}) async {
    searchCalls++;
    return const <Product>[];
  }
}

class _EmptyFiadoRepository implements FiadoRepository {
  @override
  Future<FiadoDetail> fetchDetail(int fiadoId) => throw UnimplementedError();

  @override
  Future<FiadoDetail> registerPayment(FiadoPaymentInput input) =>
      throw UnimplementedError();

  @override
  Future<List<FiadoAccount>> search({
    String query = '',
    String? status,
    bool overdueOnly = false,
  }) async => const <FiadoAccount>[];
}

class _EmptyOperationalOrderRepository implements OperationalOrderRepository {
  @override
  Future<int> create(OperationalOrderInput input) => throw UnimplementedError();

  @override
  Future<List<OperationalOrder>> list({String query = ''}) async =>
      const <OperationalOrder>[];

  @override
  Future<List<OperationalOrderSummary>> listSummaries({
    String query = '',
    OperationalOrderStatus? status,
  }) async => const <OperationalOrderSummary>[];

  @override
  Future<OperationalOrder?> findById(int orderId) => throw UnimplementedError();

  @override
  Future<List<OperationalOrderItem>> listItems(int orderId) =>
      throw UnimplementedError();

  @override
  Future<List<OperationalOrderItemModifier>> listItemModifiers(
    int orderItemId,
  ) => throw UnimplementedError();

  @override
  Future<int?> findLinkedSaleId(int orderId) => throw UnimplementedError();

  @override
  Future<void> linkToSale({required int orderId, required int saleId}) =>
      throw UnimplementedError();

  @override
  Future<void> updateDraft(int orderId, OperationalOrderDraftInput input) =>
      throw UnimplementedError();

  @override
  Future<void> sendToKitchen(int orderId) => throw UnimplementedError();

  @override
  Future<void> updateStatus(int orderId, OperationalOrderStatus status) =>
      throw UnimplementedError();

  @override
  Future<void> updateTicketDispatchState({
    required int orderId,
    required OrderTicketDispatchStatus status,
    String? failureMessage,
  }) => throw UnimplementedError();

  @override
  Future<int> addItem(int orderId, OperationalOrderItemInput input) =>
      throw UnimplementedError();

  @override
  Future<void> updateItem(int orderItemId, OperationalOrderItemInput input) =>
      throw UnimplementedError();

  @override
  Future<void> removeItem(int orderItemId) => throw UnimplementedError();

  @override
  Future<int> addItemModifier(
    int orderItemId,
    OperationalOrderItemModifierInput input,
  ) => throw UnimplementedError();

  @override
  Future<void> replaceItemModifiers(
    int orderItemId,
    List<OperationalOrderItemModifierInput> modifiers,
  ) => throw UnimplementedError();
}

class _EmptyCostRepository implements CostRepository {
  @override
  Future<CostOverview> fetchOverview() async => const CostOverview(
    pendingFixedCents: 0,
    pendingVariableCents: 0,
    overdueFixedCents: 0,
    overdueVariableCents: 0,
    paidFixedThisMonthCents: 0,
    paidVariableThisMonthCents: 0,
    openFixedCount: 0,
    openVariableCount: 0,
  );

  @override
  Future<List<CostEntry>> searchCosts({
    required CostType type,
    String query = '',
    CostStatus? status,
    DateTime? from,
    DateTime? to,
    bool overdueOnly = false,
  }) async => const <CostEntry>[];

  @override
  Future<CostEntry> fetchCost(int costId) => throw UnimplementedError();

  @override
  Future<int> createCost(CreateCostInput input) => throw UnimplementedError();

  @override
  Future<CostEntry> updateCost({
    required int costId,
    required UpdateCostInput input,
  }) => throw UnimplementedError();

  @override
  Future<CostEntry> markCostPaid(MarkCostPaidInput input) =>
      throw UnimplementedError();

  @override
  Future<CostEntry> cancelCost({required int costId, String? notes}) =>
      throw UnimplementedError();
}

class _EmptyInventoryRepository implements InventoryRepository {
  @override
  Future<List<InventoryItem>> listItems({
    String query = '',
    InventoryListFilter filter = InventoryListFilter.all,
  }) async => const <InventoryItem>[];

  @override
  Future<InventoryItem?> findItem({
    required int productId,
    int? productVariantId,
  }) async => null;

  @override
  Future<List<InventoryMovement>> listMovements({
    int? productId,
    int? productVariantId,
    bool includeVariantsForProduct = false,
    InventoryMovementType? movementType,
    DateTime? createdFrom,
    DateTime? createdTo,
    int limit = 300,
  }) async => const <InventoryMovement>[];

  @override
  Future<void> adjustStock(InventoryAdjustmentInput input) async {}
}

class _EmptyCashRepository implements CashRepository {
  @override
  Future<CashSession?> getCurrentSession() async => null;

  @override
  Future<List<CashMovement>> listCurrentSessionMovements() async =>
      const <CashMovement>[];

  @override
  Future<List<CashSession>> listSessions() async => const <CashSession>[];

  @override
  Future<CashSessionDetail> fetchSessionDetail(int sessionId) =>
      throw UnimplementedError();

  @override
  Future<CashSession> openSession({
    required int initialFloatCents,
    String? notes,
  }) => throw UnimplementedError();

  @override
  Future<CashSession> confirmAutoOpenedSession({
    required int initialFloatCents,
  }) => throw UnimplementedError();

  @override
  Future<CashSession> closeSession({
    required int countedBalanceCents,
    String? notes,
  }) => throw UnimplementedError();

  @override
  Future<void> registerManualMovement(CashManualMovementInput input) =>
      throw UnimplementedError();
}
