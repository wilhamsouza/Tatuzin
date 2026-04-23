import 'package:erp_pdv_app/app/core/database/app_database.dart';
import 'package:erp_pdv_app/app/core/database/table_names.dart';
import 'package:erp_pdv_app/app/core/session/app_session.dart';
import 'package:erp_pdv_app/app/core/session/app_user.dart';
import 'package:erp_pdv_app/app/core/session/company_context.dart';
import 'package:erp_pdv_app/app/core/session/session_provider.dart';
import 'package:erp_pdv_app/app/core/session/session_reset.dart';
import 'package:erp_pdv_app/modules/categorias/domain/entities/category.dart';
import 'package:erp_pdv_app/modules/categorias/presentation/providers/category_providers.dart';
import 'package:erp_pdv_app/modules/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:erp_pdv_app/modules/produtos/domain/entities/product.dart';
import 'package:erp_pdv_app/modules/produtos/presentation/providers/product_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('session tenancy switch', () {
    late ProviderContainer container;
    late AppSession sessionA;
    late AppSession sessionB;

    setUp(() async {
      final suffix = DateTime.now().microsecondsSinceEpoch;
      sessionA = _remoteSession(
        companyId: 'cmp_test_a_$suffix',
        companyName: 'Empresa A',
        userEmail: 'a_$suffix@tatuzin.test',
      );
      sessionB = _remoteSession(
        companyId: 'cmp_test_b_$suffix',
        companyName: 'Empresa B',
        userEmail: 'b_$suffix@tatuzin.test',
      );

      await AppDatabase.deleteDatabaseForIsolationKeyForTesting(
        SessionIsolation.keyFor(sessionA),
      );
      await AppDatabase.deleteDatabaseForIsolationKeyForTesting(
        SessionIsolation.keyFor(sessionB),
      );

      container = ProviderContainer();
      container.read(sessionContextResetProvider);
      addTearDown(() async {
        container.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await AppDatabase.deleteDatabaseForIsolationKeyForTesting(
          SessionIsolation.keyFor(sessionA),
        );
        await AppDatabase.deleteDatabaseForIsolationKeyForTesting(
          SessionIsolation.keyFor(sessionB),
        );
      });
    });

    test('catalogo e dashboard nao vazam dados entre empresas', () async {
      await _switchTo(container, sessionA);
      final categoryId = await container
          .read(categoryRepositoryProvider)
          .create(const CategoryInput(name: 'Categoria A'));
      await container
          .read(productRepositoryProvider)
          .create(
            ProductInput(
              name: 'Produto da empresa A',
              categoryId: categoryId,
              unitMeasure: 'un',
              costCents: 400,
              salePriceCents: 1000,
              stockMil: 5000,
            ),
          );
      await _insertDashboardSale(container, totalCents: 1000);

      final productsA = await container.read(productCatalogProvider.future);
      final metricsA = await container.read(dashboardMetricsProvider.future);
      expect(productsA.map((product) => product.name), [
        'Produto da empresa A',
      ]);
      expect(metricsA.soldTodayCents, 1000);

      await _switchTo(container, sessionB);

      final productsB = await container.read(productCatalogProvider.future);
      final metricsB = await container.read(dashboardMetricsProvider.future);
      expect(productsB, isEmpty);
      expect(metricsB.soldTodayCents, 0);

      await _switchTo(container, sessionA);

      final productsAAgain = await container.read(
        productCatalogProvider.future,
      );
      final metricsAAgain = await container.read(
        dashboardMetricsProvider.future,
      );
      expect(productsAAgain.map((product) => product.name), [
        'Produto da empresa A',
      ]);
      expect(metricsAAgain.soldTodayCents, 1000);
    });
  });
}

AppSession _remoteSession({
  required String companyId,
  required String companyName,
  required String userEmail,
}) {
  return AppSession(
    scope: SessionScope.authenticatedRemote,
    user: AppUser(
      localId: null,
      remoteId: 'usr_$companyId',
      displayName: 'Operador $companyName',
      email: userEmail,
      roleLabel: 'Operador',
      kind: AppUserKind.remoteAuthenticated,
    ),
    company: CompanyContext(
      localId: null,
      remoteId: companyId,
      displayName: companyName,
      legalName: '$companyName LTDA',
      documentNumber: null,
      licensePlan: 'pro',
      licenseStatus: 'active',
      syncEnabled: true,
    ),
    startedAt: DateTime.now(),
    isOfflineFallback: false,
  );
}

Future<void> _switchTo(ProviderContainer container, AppSession session) async {
  container
      .read(appSessionProvider.notifier)
      .setAuthenticatedSession(
        scope: session.scope,
        user: session.user,
        company: session.company,
        isOfflineFallback: session.isOfflineFallback,
      );
  await container.read(appStartupProvider.future);
}

Future<void> _insertDashboardSale(
  ProviderContainer container, {
  required int totalCents,
}) async {
  final database = await container.read(appDatabaseProvider).database;
  final now = DateTime.now();
  await database.insert(TableNames.vendas, {
    'uuid': 'sale-${now.microsecondsSinceEpoch}',
    'cliente_id': null,
    'tipo_venda': 'vista',
    'forma_pagamento': 'dinheiro',
    'status': 'ativa',
    'desconto_centavos': 0,
    'acrescimo_centavos': 0,
    'valor_total_centavos': totalCents,
    'valor_final_centavos': totalCents,
    'numero_cupom': 'cupom-${now.microsecondsSinceEpoch}',
    'data_venda': now.toIso8601String(),
    'usuario_id': null,
    'observacao': null,
    'cancelada_em': null,
    'venda_origem_id': null,
  });
}
