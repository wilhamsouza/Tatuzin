import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../modules/account/presentation/pages/account_cloud_page.dart';
import '../../modules/auth/presentation/pages/login_page.dart';
import '../../modules/admin/presentation/pages/admin_page.dart';
import '../../modules/backup/presentation/pages/backup_restore_page.dart';
import '../../modules/carrinho/presentation/pages/cart_page.dart';
import '../../modules/categorias/domain/entities/category.dart';
import '../../modules/categorias/presentation/pages/categories_page.dart';
import '../../modules/categorias/presentation/pages/category_form_page.dart';
import '../../modules/checkout/presentation/pages/checkout_page.dart';
import '../../modules/clientes/domain/entities/client.dart';
import '../../modules/clientes/presentation/pages/client_form_page.dart';
import '../../modules/clientes/presentation/pages/client_credit_statement_page.dart';
import '../../modules/clientes/presentation/pages/clients_page.dart';
import '../../modules/caixa/presentation/pages/cash_page.dart';
import '../../modules/caixa/presentation/pages/cash_count_page.dart';
import '../../modules/compras/presentation/pages/purchase_detail_page.dart';
import '../../modules/compras/presentation/pages/purchase_form_page.dart';
import '../../modules/compras/presentation/pages/purchases_page.dart';
import '../../modules/comprovantes/presentation/pages/receipt_preview_page.dart';
import '../../modules/dashboard/presentation/pages/dashboard_page.dart';
import '../../modules/pedidos/presentation/pages/order_detail_page.dart';
import '../../modules/pedidos/presentation/pages/kitchen_order_view_page.dart';
import '../../modules/pedidos/presentation/pages/orders_page.dart';
import '../../modules/fiado/presentation/pages/fiado_detail_page.dart';
import '../../modules/fiado/presentation/pages/fiado_page.dart';
import '../../modules/custos/presentation/pages/costs_page.dart';
import '../../modules/fornecedores/domain/entities/supplier.dart';
import '../../modules/fornecedores/presentation/pages/supplier_detail_page.dart';
import '../../modules/fornecedores/presentation/pages/supplier_form_page.dart';
import '../../modules/fornecedores/presentation/pages/suppliers_page.dart';
import '../../modules/historico_vendas/presentation/pages/sale_detail_page.dart';
import '../../modules/historico_vendas/presentation/pages/sales_history_page.dart';
import '../../modules/produtos/domain/entities/product.dart';
import '../../modules/produtos/presentation/pages/product_form_page.dart';
import '../../modules/produtos/presentation/pages/products_page.dart';
import '../../modules/relatorios/presentation/pages/reports_page.dart';
import '../../modules/system/presentation/pages/system_page.dart';
import '../../modules/vendas/presentation/pages/sales_page.dart';
import '../core/widgets/app_async_value_view.dart';
import '../core/session/auth_provider.dart';
import 'route_names.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutePaths.login,
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutePaths.login,
        name: AppRouteNames.login,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: AppRoutePaths.dashboard,
        name: AppRouteNames.dashboard,
        builder: (context, state) => const DashboardPage(),
      ),
      GoRoute(
        path: AppRoutePaths.accountCloud,
        name: AppRouteNames.accountCloud,
        builder: (context, state) => const AccountCloudPage(),
      ),
      GoRoute(
        path: AppRoutePaths.categories,
        name: AppRouteNames.categories,
        builder: (context, state) => const CategoriesPage(),
      ),
      GoRoute(
        path: AppRoutePaths.categoryForm,
        name: AppRouteNames.categoryForm,
        builder: (context, state) =>
            CategoryFormPage(initialCategory: state.extra as Category?),
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
            ProductFormPage(initialProduct: state.extra as Product?),
      ),
      GoRoute(
        path: AppRoutePaths.clients,
        name: AppRouteNames.clients,
        builder: (context, state) => const ClientsPage(),
      ),
      GoRoute(
        path: AppRoutePaths.suppliers,
        name: AppRouteNames.suppliers,
        builder: (context, state) => const SuppliersPage(),
      ),
      GoRoute(
        path: AppRoutePaths.supplierForm,
        name: AppRouteNames.supplierForm,
        builder: (context, state) =>
            SupplierFormPage(initialSupplier: state.extra as Supplier?),
      ),
      GoRoute(
        path: AppRoutePaths.supplierDetail,
        name: AppRouteNames.supplierDetail,
        builder: (context, state) {
          final supplierId = int.parse(state.pathParameters['supplierId']!);
          return SupplierDetailPage(supplierId: supplierId);
        },
      ),
      GoRoute(
        path: AppRoutePaths.clientForm,
        name: AppRouteNames.clientForm,
        builder: (context, state) =>
            ClientFormPage(initialClient: state.extra as Client?),
      ),
      GoRoute(
        path: AppRoutePaths.clientCreditStatement,
        name: AppRouteNames.clientCreditStatement,
        builder: (context, state) {
          final clientId = int.parse(state.pathParameters['clientId']!);
          return ClientCreditStatementPage(
            clientId: clientId,
            initialClient: state.extra as Client?,
          );
        },
      ),
      GoRoute(
        path: AppRoutePaths.purchases,
        name: AppRouteNames.purchases,
        builder: (context, state) => const PurchasesPage(),
      ),
      GoRoute(
        path: AppRoutePaths.purchaseForm,
        name: AppRouteNames.purchaseForm,
        builder: (context, state) {
          final args = state.extra;
          return PurchaseFormPage(
            args: args is PurchaseFormArgs
                ? args
                : args is int
                ? PurchaseFormArgs(preselectedSupplierId: args)
                : null,
          );
        },
      ),
      GoRoute(
        path: AppRoutePaths.purchaseDetail,
        name: AppRouteNames.purchaseDetail,
        builder: (context, state) {
          final purchaseId = int.parse(state.pathParameters['purchaseId']!);
          return PurchaseDetailPage(purchaseId: purchaseId);
        },
      ),
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
        path: AppRoutePaths.orders,
        name: AppRouteNames.orders,
        builder: (context, state) => const OrdersPage(),
      ),
      GoRoute(
        path: AppRoutePaths.orderDetail,
        name: AppRouteNames.orderDetail,
        builder: (context, state) {
          final orderId = int.parse(state.pathParameters['orderId']!);
          return OrderDetailPage(orderId: orderId);
        },
      ),
      GoRoute(
        path: AppRoutePaths.orderKitchen,
        name: AppRouteNames.orderKitchen,
        builder: (context, state) {
          final orderId = int.parse(state.pathParameters['orderId']!);
          return KitchenOrderViewPage(orderId: orderId);
        },
      ),
      GoRoute(
        path: AppRoutePaths.checkout,
        name: AppRouteNames.checkout,
        builder: (context, state) => const CheckoutPage(),
      ),
      GoRoute(
        path: AppRoutePaths.fiado,
        name: AppRouteNames.fiado,
        builder: (context, state) => const FiadoPage(),
      ),
      GoRoute(
        path: AppRoutePaths.costs,
        name: AppRouteNames.costs,
        builder: (context, state) => const CostsPage(),
      ),
      GoRoute(
        path: AppRoutePaths.fiadoDetail,
        name: AppRouteNames.fiadoDetail,
        builder: (context, state) {
          final fiadoId = int.parse(state.pathParameters['fiadoId']!);
          return FiadoDetailPage(fiadoId: fiadoId);
        },
      ),
      GoRoute(
        path: AppRoutePaths.cash,
        name: AppRouteNames.cash,
        builder: (context, state) => const CashPage(),
      ),
      GoRoute(
        path: AppRoutePaths.cashCount,
        name: AppRouteNames.cashCount,
        builder: (context, state) => const CashCountPage(),
      ),
      GoRoute(
        path: AppRoutePaths.salesHistory,
        name: AppRouteNames.salesHistory,
        builder: (context, state) => const SalesHistoryPage(),
      ),
      GoRoute(
        path: AppRoutePaths.saleDetail,
        name: AppRouteNames.saleDetail,
        builder: (context, state) {
          final saleId = int.parse(state.pathParameters['saleId']!);
          return SaleDetailPage(saleId: saleId);
        },
      ),
      GoRoute(
        path: AppRoutePaths.saleReceipt,
        name: AppRouteNames.saleReceipt,
        builder: (context, state) {
          final saleId = int.parse(state.pathParameters['saleId']!);
          return ReceiptPreviewPage.sale(
            saleId: saleId,
            showSuccessBanner: state.extra == true,
          );
        },
      ),
      GoRoute(
        path: AppRoutePaths.fiadoPaymentReceipt,
        name: AppRouteNames.fiadoPaymentReceipt,
        builder: (context, state) {
          final fiadoId = int.parse(state.pathParameters['fiadoId']!);
          final entryId = int.parse(state.pathParameters['entryId']!);
          return ReceiptPreviewPage.fiadoPayment(
            fiadoId: fiadoId,
            entryId: entryId,
            showSuccessBanner: state.extra == true,
          );
        },
      ),
      GoRoute(
        path: AppRoutePaths.customerCreditReceipt,
        name: AppRouteNames.customerCreditReceipt,
        builder: (context, state) {
          final transactionId = int.parse(
            state.pathParameters['transactionId']!,
          );
          return ReceiptPreviewPage.customerCredit(
            transactionId: transactionId,
            showSuccessBanner: state.extra == true,
          );
        },
      ),
      GoRoute(
        path: AppRoutePaths.backup,
        name: AppRouteNames.backup,
        builder: (context, state) => const BackupRestorePage(),
      ),
      GoRoute(
        path: AppRoutePaths.system,
        name: AppRouteNames.system,
        redirect: (context, state) => AppRoutePaths.accountCloud,
      ),
      GoRoute(
        path: AppRoutePaths.technicalSystem,
        name: AppRouteNames.technicalSystem,
        redirect: (context, state) {
          final authStatus = ref.read(authStatusProvider);
          if (kDebugMode || authStatus.isPlatformAdmin) {
            return null;
          }
          return AppRoutePaths.accountCloud;
        },
        builder: (context, state) => const SystemPage(),
      ),
      GoRoute(
        path: AppRoutePaths.legacyAdmin,
        redirect: (context, state) => AppRoutePaths.accountCloud,
      ),
      GoRoute(
        path: AppRoutePaths.admin,
        name: AppRouteNames.admin,
        redirect: (context, state) {
          final authStatus = ref.read(authStatusProvider);
          if (authStatus.isRemoteAuthenticated && authStatus.isPlatformAdmin) {
            return null;
          }
          return AppRoutePaths.accountCloud;
        },
        builder: (context, state) => const AdminPage(),
      ),
      GoRoute(
        path: AppRoutePaths.reports,
        name: AppRouteNames.reports,
        builder: (context, state) => const ReportsPage(),
      ),
    ],
    errorBuilder: (context, state) {
      return AppAsyncValueView.error(
        title: 'Rota indisponível',
        message:
            state.error?.toString() ??
            'Não foi possível encontrar a tela solicitada.',
      );
    },
  );
});
