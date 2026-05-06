import 'package:go_router/go_router.dart';

import '../../../modules/pedidos/presentation/pages/kitchen_order_view_page.dart';
import '../../../modules/pedidos/presentation/pages/order_detail_page.dart';
import '../../../modules/pedidos/presentation/pages/orders_page.dart';
import '../route_names.dart';
import '../route_param_parsers.dart';

List<RouteBase> buildOrdersRoutes() {
  return <RouteBase>[
    GoRoute(
      path: AppRoutePaths.orders,
      name: AppRouteNames.orders,
      builder: (context, state) => const OrdersPage(),
    ),
    GoRoute(
      path: AppRoutePaths.orderDetail,
      name: AppRouteNames.orderDetail,
      builder: (context, state) => buildIntParamRoute(
        state,
        'orderId',
        (orderId) => OrderDetailPage(orderId: orderId),
      ),
    ),
    GoRoute(
      path: AppRoutePaths.orderKitchen,
      name: AppRouteNames.orderKitchen,
      builder: (context, state) => buildIntParamRoute(
        state,
        'orderId',
        (orderId) => KitchenOrderViewPage(orderId: orderId),
      ),
    ),
  ];
}
