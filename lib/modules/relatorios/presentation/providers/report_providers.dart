import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/database/app_database.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/session/session_provider.dart';
import '../../../categorias/domain/entities/category.dart';
import '../../../categorias/presentation/providers/category_providers.dart';
import '../../../clientes/domain/entities/client.dart';
import '../../../clientes/presentation/providers/client_providers.dart';
import '../../../fornecedores/domain/entities/supplier.dart';
import '../../../fornecedores/presentation/providers/supplier_providers.dart';
import '../../../produtos/domain/entities/product.dart';
import '../../../produtos/presentation/providers/product_providers.dart';
import '../../data/sqlite_report_repository.dart';
import '../../data/support/report_date_range_support.dart';
import '../../data/support/report_drilldown_support.dart';
import '../../data/support/report_export_csv_support.dart';
import '../../data/support/report_export_pdf_support.dart';
import '../../data/support/report_filter_preset_support.dart';
import '../../../vendas/domain/entities/sale_enums.dart';
import '../../domain/entities/report_cashflow_summary.dart';
import '../../domain/entities/report_customer_ranking_row.dart';
import '../../domain/entities/report_filter.dart';
import '../../domain/entities/report_inventory_health_summary.dart';
import '../../domain/entities/report_overview_summary.dart';
import '../../domain/entities/report_period.dart';
import '../../domain/entities/report_profitability_row.dart';
import '../../domain/entities/report_purchase_summary.dart';
import '../../domain/entities/report_sales_trend_point.dart';
import '../../domain/entities/report_sold_product_summary.dart';
import '../../domain/entities/report_summary.dart';
import '../../domain/entities/report_variant_summary.dart';
import '../../domain/repositories/report_repository.dart';

final reportRepositoryProvider = Provider<ReportRepository>((ref) {
  return SqliteReportRepository(ref.watch(appDatabaseProvider));
});

final reportExportCsvSupportProvider = Provider<ReportExportCsvSupport>((ref) {
  return ReportExportCsvSupport();
});

final reportExportPdfSupportProvider = Provider<ReportExportPdfSupport>((ref) {
  return ReportExportPdfSupport();
});

final reportFilterProvider =
    NotifierProvider<ReportFilterController, ReportFilter>(
      ReportFilterController.new,
    );

final reportPageSessionProvider =
    NotifierProvider<ReportPageSessionController, ReportPageSessionState>(
      ReportPageSessionController.new,
    );

final reportPeriodProvider = Provider<ReportPeriod>((ref) {
  final matchedPeriod = ReportDateRangeSupport.matchPeriod(
    ref.watch(reportFilterProvider).range,
  );
  return matchedPeriod ?? ReportPeriod.daily;
});

final reportPreviousFilterProvider = Provider<ReportFilter>((ref) {
  final currentFilter = ref.watch(reportFilterProvider);
  final previousRange = ReportDateRangeSupport.previousPeriod(
    currentFilter.range,
  );
  return currentFilter.copyWithRange(previousRange);
});

final reportOverviewProvider = FutureProvider<ReportOverviewSummary>((
  ref,
) async {
  ref.watch(sessionRuntimeKeyProvider);
  ref.watch(appDataRefreshProvider);
  return ref
      .watch(reportRepositoryProvider)
      .fetchOverview(filter: ref.watch(reportFilterProvider));
});

final reportPreviousOverviewProvider = FutureProvider<ReportOverviewSummary>((
  ref,
) async {
  ref.watch(sessionRuntimeKeyProvider);
  ref.watch(appDataRefreshProvider);
  return ref
      .watch(reportRepositoryProvider)
      .fetchOverview(filter: ref.watch(reportPreviousFilterProvider));
});

final salesTrendProvider = FutureProvider<List<ReportSalesTrendPoint>>((
  ref,
) async {
  ref.watch(sessionRuntimeKeyProvider);
  ref.watch(appDataRefreshProvider);
  return ref
      .watch(reportRepositoryProvider)
      .fetchSalesTrend(filter: ref.watch(reportFilterProvider));
});

final topProductsReportProvider =
    FutureProvider<List<ReportSoldProductSummary>>((ref) async {
      ref.watch(sessionRuntimeKeyProvider);
      ref.watch(appDataRefreshProvider);
      return ref
          .watch(reportRepositoryProvider)
          .fetchTopProducts(filter: ref.watch(reportFilterProvider));
    });

final topVariantsReportProvider = FutureProvider<List<ReportVariantSummary>>((
  ref,
) async {
  ref.watch(sessionRuntimeKeyProvider);
  ref.watch(appDataRefreshProvider);
  return ref
      .watch(reportRepositoryProvider)
      .fetchTopVariants(filter: ref.watch(reportFilterProvider));
});

final profitabilityReportProvider =
    FutureProvider<List<ReportProfitabilityRow>>((ref) async {
      ref.watch(sessionRuntimeKeyProvider);
      ref.watch(appDataRefreshProvider);
      return ref
          .watch(reportRepositoryProvider)
          .fetchProfitability(filter: ref.watch(reportFilterProvider));
    });

final profitabilityCategoryReportProvider =
    FutureProvider<List<ReportProfitabilityRow>>((ref) async {
      ref.watch(sessionRuntimeKeyProvider);
      ref.watch(appDataRefreshProvider);
      final filter = ref.watch(
        reportFilterProvider.select(
          (value) => value.copyWith(grouping: ReportGrouping.category),
        ),
      );
      return ref
          .watch(reportRepositoryProvider)
          .fetchProfitability(filter: filter, limit: 10);
    });

final cashflowReportProvider = FutureProvider<ReportCashflowSummary>((
  ref,
) async {
  ref.watch(sessionRuntimeKeyProvider);
  ref.watch(appDataRefreshProvider);
  return ref
      .watch(reportRepositoryProvider)
      .fetchCashflow(filter: ref.watch(reportFilterProvider));
});

final inventoryHealthReportProvider =
    FutureProvider<ReportInventoryHealthSummary>((ref) async {
      ref.watch(sessionRuntimeKeyProvider);
      ref.watch(appDataRefreshProvider);
      return ref
          .watch(reportRepositoryProvider)
          .fetchInventoryHealth(filter: ref.watch(reportFilterProvider));
    });

final customerRankingReportProvider =
    FutureProvider<List<ReportCustomerRankingRow>>((ref) async {
      ref.watch(sessionRuntimeKeyProvider);
      ref.watch(appDataRefreshProvider);
      return ref
          .watch(reportRepositoryProvider)
          .fetchCustomerRanking(
            filter: ref.watch(reportFilterProvider),
            limit: 100,
          );
    });

final purchaseSummaryReportProvider = FutureProvider<ReportPurchaseSummary>((
  ref,
) async {
  ref.watch(sessionRuntimeKeyProvider);
  ref.watch(appDataRefreshProvider);
  return ref
      .watch(reportRepositoryProvider)
      .fetchPurchaseSummary(filter: ref.watch(reportFilterProvider));
});

final reportSummaryProvider = FutureProvider<ReportSummary>((ref) async {
  ref.watch(sessionRuntimeKeyProvider);
  ref.watch(appDataRefreshProvider);
  return ref
      .watch(reportRepositoryProvider)
      .fetchSummary(
        period: ref.watch(reportPeriodProvider),
        filter: ref.watch(reportFilterProvider),
      );
});

final reportClientOptionsProvider = FutureProvider<List<Client>>((ref) async {
  ref.watch(sessionRuntimeKeyProvider);
  ref.watch(appDataRefreshProvider);
  return ref.watch(clientRepositoryProvider).search();
});

final reportCategoryOptionsProvider = FutureProvider<List<Category>>((
  ref,
) async {
  ref.watch(sessionRuntimeKeyProvider);
  ref.watch(appDataRefreshProvider);
  return ref.watch(categoryOptionsProvider.future);
});

final reportProductOptionsProvider = FutureProvider<List<Product>>((ref) async {
  ref.watch(sessionRuntimeKeyProvider);
  ref.watch(appDataRefreshProvider);
  return ref.watch(productCatalogProvider.future);
});

final reportSupplierOptionsProvider = FutureProvider<List<Supplier>>((
  ref,
) async {
  ref.watch(sessionRuntimeKeyProvider);
  ref.watch(appDataRefreshProvider);
  return ref.watch(supplierOptionsProvider.future);
});

final reportVariantOptionsProvider =
    FutureProvider<List<ReportVariantFilterOption>>((ref) async {
      ref.watch(sessionRuntimeKeyProvider);
      final products = await ref.watch(reportProductOptionsProvider.future);
      final options = <ReportVariantFilterOption>[];
      for (final product in products) {
        for (final variant in product.variants.where((item) => item.isActive)) {
          final details = <String>[
            if (variant.colorLabel.trim().isNotEmpty) variant.colorLabel.trim(),
            if (variant.sizeLabel.trim().isNotEmpty) variant.sizeLabel.trim(),
          ];
          final suffix = details.isEmpty
              ? variant.sku.trim()
              : details.join(' / ');
          options.add(
            ReportVariantFilterOption(
              id: variant.id,
              productId: product.id,
              productName: product.displayName,
              label: suffix.isEmpty
                  ? product.displayName
                  : '${product.displayName} - $suffix',
            ),
          );
        }
      }
      return options;
    });

final reportFilterOptionLabelsProvider =
    FutureProvider<ReportFilterOptionLabels>((ref) async {
      ref.watch(sessionRuntimeKeyProvider);
      final customers = await ref.watch(reportClientOptionsProvider.future);
      final categories = await ref.watch(reportCategoryOptionsProvider.future);
      final products = await ref.watch(reportProductOptionsProvider.future);
      final variants = await ref.watch(reportVariantOptionsProvider.future);
      final suppliers = await ref.watch(reportSupplierOptionsProvider.future);

      return ReportFilterOptionLabels(
        customers: {
          for (final customer in customers) customer.id: customer.name,
        },
        categories: {
          for (final category in categories) category.id: category.name,
        },
        products: {
          for (final product in products) product.id: product.displayName,
        },
        variants: {for (final variant in variants) variant.id: variant.label},
        suppliers: {
          for (final supplier in suppliers)
            supplier.id: (supplier.tradeName?.trim().isNotEmpty ?? false)
                ? supplier.tradeName!.trim()
                : supplier.name,
        },
      );
    });

class ReportVariantFilterOption {
  const ReportVariantFilterOption({
    required this.id,
    required this.productId,
    required this.productName,
    required this.label,
  });

  final int id;
  final int productId;
  final String productName;
  final String label;
}

class ReportFilterController extends Notifier<ReportFilter> {
  @override
  ReportFilter build() {
    return ReportFilter.fromPeriod(ReportPeriod.daily);
  }

  void replace(ReportFilter next) {
    state = next;
  }

  void applyDrilldown({
    required ReportPageKey page,
    required ReportFilter nextFilter,
    required ReportPageKey sourcePage,
    required String sourceLabel,
    required String message,
    bool isFocusOnly = false,
  }) {
    ref
        .read(reportPageSessionProvider.notifier)
        .setDrilldown(
          ReportDrilldownContext(
            page: page,
            sourcePage: sourcePage,
            sourceLabel: sourceLabel,
            message: message,
            baselineFilter: state,
            isFocusOnly: isFocusOnly,
          ),
        );
    state = nextFilter;
  }

  void clearDrilldown(ReportPageKey page) {
    final context = ref.read(reportPageSessionProvider).drilldownFor(page);
    if (context == null) {
      return;
    }
    ref.read(reportPageSessionProvider.notifier).clearDrilldown(page);
    state = context.baselineFilter;
  }

  void applyPeriod(ReportPeriod period, {DateTime? reference}) {
    final nextRange = period.resolveRange(reference ?? DateTime.now());
    state = state.copyWith(
      start: nextRange.start,
      endExclusive: nextRange.endExclusive,
      grouping: switch (period) {
        ReportPeriod.yearly => ReportGrouping.month,
        ReportPeriod.daily ||
        ReportPeriod.weekly ||
        ReportPeriod.monthly => ReportGrouping.day,
      },
    );
  }

  void setCustomRange({
    required DateTime start,
    required DateTime endExclusive,
  }) {
    state = state.copyWith(start: start, endExclusive: endExclusive);
  }

  void setGrouping(ReportGrouping grouping) {
    state = state.copyWith(grouping: grouping);
  }

  void setIncludeCanceled(bool includeCanceled) {
    state = state.copyWith(
      includeCanceled: includeCanceled,
      onlyCanceled: includeCanceled ? state.onlyCanceled : false,
    );
  }

  void setCustomer(int? customerId) {
    state = state.copyWith(
      customerId: customerId,
      clearCustomerId: customerId == null,
    );
  }

  void setCategory(int? categoryId) {
    state = state.copyWith(
      categoryId: categoryId,
      clearCategoryId: categoryId == null,
    );
  }

  void setProduct(int? productId) {
    state = state.copyWith(
      productId: productId,
      clearProductId: productId == null,
    );
  }

  void setVariant(int? variantId) {
    state = state.copyWith(
      variantId: variantId,
      clearVariantId: variantId == null,
    );
  }

  void setSupplier(int? supplierId) {
    state = state.copyWith(
      supplierId: supplierId,
      clearSupplierId: supplierId == null,
    );
  }

  void setPaymentMethod(PaymentMethod? paymentMethod) {
    state = state.copyWith(
      paymentMethod: paymentMethod,
      clearPaymentMethod: paymentMethod == null,
    );
  }

  void resetScope() {
    state = ReportFilter.fromPeriod(reportPeriodFromCurrentState());
  }

  void clearOptionalFilters() {
    state = state.clearScopedFilters();
  }

  ReportPeriod reportPeriodFromCurrentState() {
    return ReportDateRangeSupport.matchPeriod(state.range) ??
        ReportPeriod.daily;
  }
}

class ReportPageSessionController extends Notifier<ReportPageSessionState> {
  @override
  ReportPageSessionState build() {
    return const ReportPageSessionState();
  }

  void setDrilldown(ReportDrilldownContext context) {
    state = state.copyWith(
      drilldowns: {...state.drilldowns, context.page: context},
    );
  }

  void clearDrilldown(ReportPageKey page) {
    if (!state.drilldowns.containsKey(page)) {
      return;
    }
    final next = Map<ReportPageKey, ReportDrilldownContext>.from(
      state.drilldowns,
    )..remove(page);
    state = state.copyWith(drilldowns: next);
  }

  void rememberPreset(ReportPageKey page, String presetId) {
    state = state.copyWith(
      lastPresetIds: {...state.lastPresetIds, page: presetId},
    );
  }
}
