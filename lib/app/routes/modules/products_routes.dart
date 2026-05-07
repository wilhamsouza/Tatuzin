import 'package:go_router/go_router.dart';

import '../../core/entitlements/feature_gate.dart';
import '../../core/entitlements/plan_entitlements.dart';
import '../../../modules/categorias/domain/entities/category.dart';
import '../../../modules/categorias/presentation/pages/categories_page.dart';
import '../../../modules/categorias/presentation/pages/category_form_page.dart';
import '../../../modules/insumos/domain/entities/supply.dart';
import '../../../modules/insumos/presentation/pages/reorder_suggestions_page.dart';
import '../../../modules/insumos/presentation/pages/supplies_page.dart';
import '../../../modules/insumos/presentation/pages/supply_form_page.dart';
import '../../../modules/insumos/presentation/pages/supply_inventory_page.dart';
import '../../../modules/produtos/domain/entities/product.dart';
import '../../../modules/produtos/presentation/pages/product_form_page.dart';
import '../../../modules/produtos/presentation/pages/product_profitability_page.dart';
import '../../../modules/produtos/presentation/pages/products_page.dart';
import '../route_names.dart';
import '../route_param_parsers.dart';

List<RouteBase> buildProductsRoutes() {
  return <RouteBase>[
    GoRoute(
      path: AppRoutePaths.categories,
      name: AppRouteNames.categories,
      builder: (context, state) => const CategoriesPage(),
    ),
    GoRoute(
      path: AppRoutePaths.categoryForm,
      name: AppRouteNames.categoryForm,
      builder: (context, state) =>
          CategoryFormPage(initialCategory: routeExtraAs<Category>(state)),
    ),
    GoRoute(
      path: AppRoutePaths.products,
      name: AppRouteNames.products,
      builder: (context, state) => const ProductsPage(),
    ),
    GoRoute(
      path: AppRoutePaths.productForm,
      name: AppRouteNames.productForm,
      builder: (context, state) =>
          ProductFormPage(initialProduct: routeExtraAs<Product>(state)),
    ),
    GoRoute(
      path: AppRoutePaths.productProfitability,
      name: AppRouteNames.productProfitability,
      builder: (context, state) => const FeatureGate(
        feature: FeatureKey.reportsAdvanced,
        child: ProductProfitabilityPage(),
      ),
    ),
    GoRoute(
      path: AppRoutePaths.supplies,
      name: AppRouteNames.supplies,
      builder: (context, state) => const FeatureGate(
        feature: FeatureKey.supplies,
        child: SuppliesPage(),
      ),
    ),
    GoRoute(
      path: AppRoutePaths.supplyForm,
      name: AppRouteNames.supplyForm,
      builder: (context, state) => FeatureGate(
        feature: FeatureKey.supplies,
        child: SupplyFormPage(initialSupply: routeExtraAs<Supply>(state)),
      ),
    ),
    GoRoute(
      path: AppRoutePaths.supplyInventory,
      name: AppRouteNames.supplyInventory,
      builder: (context, state) => FeatureGate(
        feature: FeatureKey.supplies,
        child: SupplyInventoryPage(initialSupplyId: routeExtraAs<int>(state)),
      ),
    ),
    GoRoute(
      path: AppRoutePaths.reorderSuggestions,
      name: AppRouteNames.reorderSuggestions,
      builder: (context, state) => const FeatureGate(
        feature: FeatureKey.supplies,
        child: ReorderSuggestionsPage(),
      ),
    ),
  ];
}
