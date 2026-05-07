import 'package:go_router/go_router.dart';

import '../../core/entitlements/feature_gate.dart';
import '../../core/entitlements/plan_entitlements.dart';
import '../../../modules/compras/presentation/pages/purchase_detail_page.dart';
import '../../../modules/compras/presentation/pages/purchase_form_page.dart';
import '../../../modules/compras/presentation/pages/purchases_page.dart';
import '../../../modules/fornecedores/domain/entities/supplier.dart';
import '../../../modules/fornecedores/presentation/pages/supplier_detail_page.dart';
import '../../../modules/fornecedores/presentation/pages/supplier_form_page.dart';
import '../../../modules/fornecedores/presentation/pages/suppliers_page.dart';
import '../route_names.dart';
import '../route_param_parsers.dart';

List<RouteBase> buildPurchasesRoutes() {
  return <RouteBase>[
    GoRoute(
      path: AppRoutePaths.suppliers,
      name: AppRouteNames.suppliers,
      builder: (context, state) => const FeatureGate(
        feature: FeatureKey.suppliers,
        child: SuppliersPage(),
      ),
    ),
    GoRoute(
      path: AppRoutePaths.supplierForm,
      name: AppRouteNames.supplierForm,
      builder: (context, state) => FeatureGate(
        feature: FeatureKey.suppliers,
        child: SupplierFormPage(initialSupplier: routeExtraAs<Supplier>(state)),
      ),
    ),
    GoRoute(
      path: AppRoutePaths.supplierDetail,
      name: AppRouteNames.supplierDetail,
      builder: (context, state) => FeatureGate(
        feature: FeatureKey.suppliers,
        child: buildIntParamRoute(
          state,
          'supplierId',
          (supplierId) => SupplierDetailPage(supplierId: supplierId),
        ),
      ),
    ),
    GoRoute(
      path: AppRoutePaths.purchases,
      name: AppRouteNames.purchases,
      builder: (context, state) => const FeatureGate(
        feature: FeatureKey.purchases,
        child: PurchasesPage(),
      ),
    ),
    GoRoute(
      path: AppRoutePaths.purchaseForm,
      name: AppRouteNames.purchaseForm,
      builder: (context, state) {
        final args = state.extra;
        return FeatureGate(
          feature: FeatureKey.purchases,
          child: PurchaseFormPage(
            args: args is PurchaseFormArgs
                ? args
                : args is int
                ? PurchaseFormArgs(preselectedSupplierId: args)
                : null,
          ),
        );
      },
    ),
    GoRoute(
      path: AppRoutePaths.purchaseDetail,
      name: AppRouteNames.purchaseDetail,
      builder: (context, state) => FeatureGate(
        feature: FeatureKey.purchases,
        child: buildIntParamRoute(
          state,
          'purchaseId',
          (purchaseId) => PurchaseDetailPage(purchaseId: purchaseId),
        ),
      ),
    ),
  ];
}
