import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'route_names.dart';

void showCompletedSaleReceipt(
  GoRouter router, {
  required int saleId,
  required bool Function() isCurrentSession,
}) {
  router.goNamed(AppRouteNames.sales);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!isCurrentSession() ||
        router.routeInformationProvider.value.uri.path != AppRoutePaths.sales) {
      return;
    }
    router.pushNamed(
      AppRouteNames.saleReceipt,
      pathParameters: {'saleId': '$saleId'},
      extra: true,
    );
  });
}
