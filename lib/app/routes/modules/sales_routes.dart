import 'package:go_router/go_router.dart';

import '../../../modules/comprovantes/presentation/pages/receipt_preview_page.dart';
import '../../../modules/custos/presentation/pages/costs_page.dart';
import '../../../modules/fiado/presentation/pages/fiado_detail_page.dart';
import '../../../modules/fiado/presentation/pages/fiado_page.dart';
import '../../../modules/historico_vendas/presentation/pages/sale_detail_page.dart';
import '../../../modules/historico_vendas/presentation/pages/sales_history_page.dart';
import '../route_names.dart';
import '../route_param_parsers.dart';

List<RouteBase> buildSalesRoutes() {
  return <RouteBase>[
    GoRoute(
      path: AppRoutePaths.costs,
      name: AppRouteNames.costs,
      builder: (context, state) => const CostsPage(),
    ),
    GoRoute(
      path: AppRoutePaths.fiado,
      name: AppRouteNames.fiado,
      builder: (context, state) => const FiadoPage(),
    ),
    GoRoute(
      path: AppRoutePaths.fiadoDetail,
      name: AppRouteNames.fiadoDetail,
      builder: (context, state) => buildIntParamRoute(
        state,
        'fiadoId',
        (fiadoId) => FiadoDetailPage(fiadoId: fiadoId),
      ),
    ),
    GoRoute(
      path: AppRoutePaths.salesHistory,
      name: AppRouteNames.salesHistory,
      builder: (context, state) => const SalesHistoryPage(),
    ),
    GoRoute(
      path: AppRoutePaths.saleDetail,
      name: AppRouteNames.saleDetail,
      builder: (context, state) => buildIntParamRoute(
        state,
        'saleId',
        (saleId) => SaleDetailPage(saleId: saleId),
      ),
    ),
    GoRoute(
      path: AppRoutePaths.saleReceipt,
      name: AppRouteNames.saleReceipt,
      builder: (context, state) => buildIntParamRoute(
        state,
        'saleId',
        (saleId) => ReceiptPreviewPage.sale(
          saleId: saleId,
          showSuccessBanner: state.extra == true,
        ),
      ),
    ),
    GoRoute(
      path: AppRoutePaths.fiadoPaymentReceipt,
      name: AppRouteNames.fiadoPaymentReceipt,
      builder: (context, state) => buildTwoIntParamRoute(
        state,
        'fiadoId',
        'entryId',
        (fiadoId, entryId) => ReceiptPreviewPage.fiadoPayment(
          fiadoId: fiadoId,
          entryId: entryId,
          showSuccessBanner: state.extra == true,
        ),
      ),
    ),
    GoRoute(
      path: AppRoutePaths.customerCreditReceipt,
      name: AppRouteNames.customerCreditReceipt,
      builder: (context, state) => buildIntParamRoute(
        state,
        'transactionId',
        (transactionId) => ReceiptPreviewPage.customerCredit(
          transactionId: transactionId,
          showSuccessBanner: state.extra == true,
        ),
      ),
    ),
  ];
}
