import 'package:go_router/go_router.dart';

import '../../../modules/carrinho/presentation/pages/cart_page.dart';
import '../../../modules/checkout/presentation/pages/checkout_page.dart';
import '../../../modules/vendas/presentation/pages/sales_page.dart';
import '../route_names.dart';

List<RouteBase> buildPdvRoutes() {
  return <RouteBase>[
    GoRoute(
      path: AppRoutePaths.sales,
      name: AppRouteNames.sales,
      builder: (context, state) => const SalesPage(),
    ),
    GoRoute(
      path: AppRoutePaths.cart,
      name: AppRouteNames.cart,
      builder: (context, state) => const CartPage(),
    ),
    GoRoute(
      path: AppRoutePaths.checkout,
      name: AppRouteNames.checkout,
      builder: (context, state) => const CheckoutPage(),
    ),
  ];
}
