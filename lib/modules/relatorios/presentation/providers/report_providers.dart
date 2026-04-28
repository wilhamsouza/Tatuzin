import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/database/app_database.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/providers/provider_guard.dart';
import '../../../../app/core/session/session_provider.dart';
import '../../../categorias/domain/entities/category.dart';
import '../../../categorias/presentation/providers/category_providers.dart';
import '../../../clientes/domain/entities/client.dart';
import '../../../clientes/presentation/providers/client_providers.dart';
import '../../../fornecedores/domain/entities/supplier.dart';
import '../../../fornecedores/presentation/providers/supplier_providers.dart';
import '../../../produtos/domain/entities/product.dart';
import '../../../produtos/presentation/providers/product_providers.dart';
import '../../data/analytics_report_repository.dart';
import '../../data/datasources/analytics_reports_remote_datasource.dart';
import '../../data/real/real_analytics_reports_remote_datasource.dart';
import '../../data/sqlite_report_repository.dart';
import '../../data/support/report_date_range_support.dart';
import '../../data/support/report_drilldown_support.dart';
import '../../data/support/report_export_csv_support.dart';
import '../../data/support/report_export_pdf_support.dart';
import '../../data/support/report_filter_preset_support.dart';
import '../../../vendas/domain/entities/sale_enums.dart';
import '../../domain/entities/report_cashflow_summary.dart';
import '../../domain/entities/report_customer_ranking_row.dart';
import '../../domain/entities/report_data_origin_notice.dart';
import '../../domain/entities/report_data_source_strategy.dart';
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
import '../../../../app/core/app_context/app_operational_context.dart';
import '../../../../app/core/network/network_providers.dart';
import '../../../../app/core/session/auth_token_storage.dart';

final pdvOperationalReportRepositoryProvider = Provider<ReportRepository>((
  ref,
) {
  return SqliteReportRepository(ref.watch(appDatabaseProvider));
});

final reportRemoteDatasourceProvider =
    Provider<AnalyticsReportsRemoteDatasource>((ref) {
      return RealAnalyticsReportsRemoteDatasource(
        apiClient: ref.watch(apiClientProvider),
        tokenStorage: ref.watch(authTokenStorageProvider),
        operationalContext: ref.watch(appOperationalContextProvider),
      );
    });

final erpManagementReportRepositoryProvider =
    Provider<AnalyticsReportRepository>((ref) {
      final operationalContext = ref.watch(appOperationalContextProvider);
      return AnalyticsReportRepository(
        remoteDatasource: ref.watch(reportRemoteDatasourceProvider),
        localFallbackRepository: ref.watch(
          pdvOperationalReportRepositoryProvider,
        ),
        canUseRemoteAnalytics: operationalContext.session.user.isPlatformAdmin,
      );
    });

final reportRepositoryProvider = Provider<ReportRepository>((ref) {
  return ref.watch(erpManagementReportRepositoryProvider);
});

final reportDataSourceStrategyProvider =
    Provider.family<ReportDataSourceStrategy, ReportPageKey>((ref, page) {
      return reportStrategyForPage(page);
    });

final reportPageDataOriginNoticeProvider =
    Provider.family<ReportDataOriginNotice?, ReportPageKey>((ref, page) {
      ReportDataOriginNotice? noticeOf<T>(
        ProviderBase<AsyncValue<ReportResult<T>>> provider,
      ) {
        if (!ref.exists(provider)) {
          return null;
        }
        return ref.watch(provider).asData?.value.notice;
      }

      return switch (page) {
        ReportPageKey.overview =>
          noticeOf(reportOverviewResultProvider) ??
              noticeOf(topProductsReportResultProvider) ??
              noticeOf(inventoryHealthReportResultProvider),
        ReportPageKey.sales =>
          noticeOf(salesTrendResultProvider) ??
              noticeOf(topProductsReportResultProvider) ??
              noticeOf(topVariantsReportResultProvider),
        ReportPageKey.cash => noticeOf(cashflowReportResultProvider),
        ReportPageKey.inventory => noticeOf(
          inventoryHealthReportResultProvider,
        ),
        ReportPageKey.customers => noticeOf(
          customerRankingReportResultProvider,
        ),
        ReportPageKey.purchases => noticeOf(
          purchaseSummaryReportResultProvider,
        ),
        ReportPageKey.profitability =>
          noticeOf(profitabilityReportResultProvider) ??
              noticeOf(profitabilityCategoryReportResultProvider),
      };
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

final reportOverviewResultProvider =
    FutureProvider<ReportResult<ReportOverviewSummary>>((ref) async {
      ref.watch(sessionRuntimeKeyProvider);
      ref.watch(appDataRefreshProvider);
      final filter = ref.watch(reportFilterProvider);
      return runProviderGuarded(
        'reportOverviewResultProvider',
        () => ref
            .watch(erpManagementReportRepositoryProvider)
            .fetchOverviewResult(filter: filter),
        timeout: localProviderTimeout,
      );
    });

final reportOverviewProvider = FutureProvider<ReportOverviewSummary>((
  ref,
) async {
  final result = await ref.watch(reportOverviewResultProvider.future);
  return result.data;
});

final reportPreviousOverviewResultProvider =
    FutureProvider<ReportResult<ReportOverviewSummary>>((ref) async {
      ref.watch(sessionRuntimeKeyProvider);
      ref.watch(appDataRefreshProvider);
      final filter = ref.watch(reportPreviousFilterProvider);
      return runProviderGuarded(
        'reportPreviousOverviewResultProvider',
        () => ref
            .watch(erpManagementReportRepositoryProvider)
            .fetchOverviewResult(filter: filter),
        timeout: localProviderTimeout,
      );
    });

final reportPreviousOverviewProvider = FutureProvider<ReportOverviewSummary>((
  ref,
) async {
  final result = await ref.watch(reportPreviousOverviewResultProvider.future);
  return result.data;
});

final salesTrendResultProvider =
    FutureProvider<ReportResult<List<ReportSalesTrendPoint>>>((ref) async {
      ref.watch(sessionRuntimeKeyProvider);
      ref.watch(appDataRefreshProvider);
      final filter = ref.watch(reportFilterProvider);
      return runProviderGuarded(
        'salesTrendResultProvider',
        () => ref
            .watch(erpManagementReportRepositoryProvider)
            .fetchSalesTrendResult(filter: filter),
        timeout: localProviderTimeout,
      );
    });

final salesTrendProvider = FutureProvider<List<ReportSalesTrendPoint>>((
  ref,
) async {
  final result = await ref.watch(salesTrendResultProvider.future);
  return result.data;
});

final topProductsReportResultProvider =
    FutureProvider<ReportResult<List<ReportSoldProductSummary>>>((ref) async {
      ref.watch(sessionRuntimeKeyProvider);
      ref.watch(appDataRefreshProvider);
      final filter = ref.watch(reportFilterProvider);
      return runProviderGuarded(
        'topProductsReportResultProvider',
        () => ref
            .watch(erpManagementReportRepositoryProvider)
            .fetchTopProductsResult(filter: filter),
        timeout: localProviderTimeout,
      );
    });

final topProductsReportProvider =
    FutureProvider<List<ReportSoldProductSummary>>((ref) async {
      final result = await ref.watch(topProductsReportResultProvider.future);
      return result.data;
    });

final topVariantsReportResultProvider =
    FutureProvider<ReportResult<List<ReportVariantSummary>>>((ref) async {
      ref.watch(sessionRuntimeKeyProvider);
      ref.watch(appDataRefreshProvider);
      final filter = ref.watch(reportFilterProvider);
      return runProviderGuarded(
        'topVariantsReportResultProvider',
        () => ref
            .watch(erpManagementReportRepositoryProvider)
            .fetchTopVariantsResult(filter: filter),
        timeout: localProviderTimeout,
      );
    });

final topVariantsReportProvider = FutureProvider<List<ReportVariantSummary>>((
  ref,
) async {
  final result = await ref.watch(topVariantsReportResultProvider.future);
  return result.data;
});

final profitabilityReportResultProvider =
    FutureProvider<ReportResult<List<ReportProfitabilityRow>>>((ref) async {
      ref.watch(sessionRuntimeKeyProvider);
      ref.watch(appDataRefreshProvider);
      final filter = ref.watch(reportFilterProvider);
      return runProviderGuarded(
        'profitabilityReportResultProvider',
        () => ref
            .watch(erpManagementReportRepositoryProvider)
            .fetchProfitabilityResult(filter: filter),
        timeout: localProviderTimeout,
      );
    });

final profitabilityReportProvider =
    FutureProvider<List<ReportProfitabilityRow>>((ref) async {
      final result = await ref.watch(profitabilityReportResultProvider.future);
      return result.data;
    });

final profitabilityCategoryReportResultProvider =
    FutureProvider<ReportResult<List<ReportProfitabilityRow>>>((ref) async {
      ref.watch(sessionRuntimeKeyProvider);
      ref.watch(appDataRefreshProvider);
      final filter = ref.watch(
        reportFilterProvider.select(
          (value) => value.copyWith(grouping: ReportGrouping.category),
        ),
      );
      return runProviderGuarded(
        'profitabilityCategoryReportResultProvider',
        () => ref
            .watch(erpManagementReportRepositoryProvider)
            .fetchProfitabilityResult(filter: filter, limit: 10),
        timeout: localProviderTimeout,
      );
    });

final profitabilityCategoryReportProvider =
    FutureProvider<List<ReportProfitabilityRow>>((ref) async {
      final result = await ref.watch(
        profitabilityCategoryReportResultProvider.future,
      );
      return result.data;
    });

final cashflowReportResultProvider =
    FutureProvider<ReportResult<ReportCashflowSummary>>((ref) async {
      ref.watch(sessionRuntimeKeyProvider);
      ref.watch(appDataRefreshProvider);
      final filter = ref.watch(reportFilterProvider);
      return runProviderGuarded(
        'cashflowReportResultProvider',
        () async => ReportResult<ReportCashflowSummary>(
          data: await ref
              .watch(pdvOperationalReportRepositoryProvider)
              .fetchCashflow(filter: filter),
        ),
        timeout: localProviderTimeout,
      );
    });

final cashflowReportProvider = FutureProvider<ReportCashflowSummary>((
  ref,
) async {
  final result = await ref.watch(cashflowReportResultProvider.future);
  return result.data;
});

final inventoryHealthReportResultProvider =
    FutureProvider<ReportResult<ReportInventoryHealthSummary>>((ref) async {
      ref.watch(sessionRuntimeKeyProvider);
      ref.watch(appDataRefreshProvider);
      final filter = ref.watch(reportFilterProvider);
      return runProviderGuarded(
        'inventoryHealthReportResultProvider',
        () => ref
            .watch(erpManagementReportRepositoryProvider)
            .fetchInventoryHealthResult(filter: filter),
        timeout: localProviderTimeout,
      );
    });

final inventoryHealthReportProvider =
    FutureProvider<ReportInventoryHealthSummary>((ref) async {
      final result = await ref.watch(
        inventoryHealthReportResultProvider.future,
      );
      return result.data;
    });

final customerRankingReportResultProvider =
    FutureProvider<ReportResult<List<ReportCustomerRankingRow>>>((ref) async {
      ref.watch(sessionRuntimeKeyProvider);
      ref.watch(appDataRefreshProvider);
      final filter = ref.watch(reportFilterProvider);
      return runProviderGuarded(
        'customerRankingReportResultProvider',
        () => ref
            .watch(erpManagementReportRepositoryProvider)
            .fetchCustomerRankingResult(filter: filter, limit: 100),
        timeout: localProviderTimeout,
      );
    });

final customerRankingReportProvider =
    FutureProvider<List<ReportCustomerRankingRow>>((ref) async {
      final result = await ref.watch(
        customerRankingReportResultProvider.future,
      );
      return result.data;
    });

final purchaseSummaryReportResultProvider =
    FutureProvider<ReportResult<ReportPurchaseSummary>>((ref) async {
      ref.watch(sessionRuntimeKeyProvider);
      ref.watch(appDataRefreshProvider);
      final filter = ref.watch(reportFilterProvider);
      return runProviderGuarded(
        'purchaseSummaryReportResultProvider',
        () => ref
            .watch(erpManagementReportRepositoryProvider)
            .fetchPurchaseSummaryResult(filter: filter),
        timeout: localProviderTimeout,
      );
    });

final purchaseSummaryReportProvider = FutureProvider<ReportPurchaseSummary>((
  ref,
) async {
  final result = await ref.watch(purchaseSummaryReportResultProvider.future);
  return result.data;
});

final reportSummaryProvider = FutureProvider<ReportSummary>((ref) async {
  ref.watch(sessionRuntimeKeyProvider);
  ref.watch(appDataRefreshProvider);
  final period = ref.watch(reportPeriodProvider);
  final filter = ref.watch(reportFilterProvider);
  return runProviderGuarded(
    'reportSummaryProvider',
    () => ref
        .watch(reportRepositoryProvider)
        .fetchSummary(period: period, filter: filter),
    timeout: localProviderTimeout,
  );
});

final reportClientOptionsProvider = FutureProvider<List<Client>>((ref) async {
  ref.watch(sessionRuntimeKeyProvider);
  ref.watch(appDataRefreshProvider);
  return runProviderGuarded(
    'reportClientOptionsProvider',
    () => ref.watch(clientRepositoryProvider).search(),
    timeout: defaultProviderTimeout,
  );
});

final reportCategoryOptionsProvider = FutureProvider<List<Category>>((
  ref,
) async {
  ref.watch(sessionRuntimeKeyProvider);
  ref.watch(appDataRefreshProvider);
  return runProviderGuarded(
    'reportCategoryOptionsProvider',
    () => ref.watch(categoryOptionsProvider.future),
    timeout: localProviderTimeout,
  );
});

final reportProductOptionsProvider = FutureProvider<List<Product>>((ref) async {
  ref.watch(sessionRuntimeKeyProvider);
  ref.watch(appDataRefreshProvider);
  return runProviderGuarded(
    'reportProductOptionsProvider',
    () => ref.watch(productCatalogProvider.future),
    timeout: defaultProviderTimeout,
  );
});

final reportSupplierOptionsProvider = FutureProvider<List<Supplier>>((
  ref,
) async {
  ref.watch(sessionRuntimeKeyProvider);
  ref.watch(appDataRefreshProvider);
  return runProviderGuarded(
    'reportSupplierOptionsProvider',
    () => ref.watch(supplierOptionsProvider.future),
    timeout: localProviderTimeout,
  );
});

final reportVariantOptionsProvider =
    FutureProvider<List<ReportVariantFilterOption>>((ref) async {
      ref.watch(sessionRuntimeKeyProvider);
      return runProviderGuarded('reportVariantOptionsProvider', () async {
        final products = await ref.watch(reportProductOptionsProvider.future);
        final options = <ReportVariantFilterOption>[];
        for (final product in products) {
          for (final variant in product.variants.where(
            (item) => item.isActive,
          )) {
            final details = <String>[
              if (variant.colorLabel.trim().isNotEmpty)
                variant.colorLabel.trim(),
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
      }, timeout: defaultProviderTimeout);
    });

final reportFilterOptionLabelsProvider =
    FutureProvider<ReportFilterOptionLabels>((ref) async {
      ref.watch(sessionRuntimeKeyProvider);
      return runProviderGuarded('reportFilterOptionLabelsProvider', () async {
        final customers = await ref.watch(reportClientOptionsProvider.future);
        final categories = await ref.watch(
          reportCategoryOptionsProvider.future,
        );
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
      }, timeout: defaultProviderTimeout);
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
