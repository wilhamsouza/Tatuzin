import '../../../vendas/domain/entities/sale_enums.dart';
import 'report_period.dart';

enum ReportGrouping {
  day,
  week,
  month,
  category,
  product,
  variant,
  customer,
  supplier,
}

extension ReportGroupingX on ReportGrouping {
  String get label {
    switch (this) {
      case ReportGrouping.day:
        return 'Dia';
      case ReportGrouping.week:
        return 'Semana';
      case ReportGrouping.month:
        return 'Mes';
      case ReportGrouping.category:
        return 'Categoria';
      case ReportGrouping.product:
        return 'Produto';
      case ReportGrouping.variant:
        return 'Variante';
      case ReportGrouping.customer:
        return 'Cliente';
      case ReportGrouping.supplier:
        return 'Fornecedor';
    }
  }

  bool get isTimeSeries {
    switch (this) {
      case ReportGrouping.day:
      case ReportGrouping.week:
      case ReportGrouping.month:
        return true;
      case ReportGrouping.category:
      case ReportGrouping.product:
      case ReportGrouping.variant:
      case ReportGrouping.customer:
      case ReportGrouping.supplier:
        return false;
    }
  }
}

enum ReportFocus {
  salesProducts,
  salesPaymentMethods,
  cashEntries,
  cashFiadoReceipts,
  cashManualEntries,
  cashNetFlow,
  inventoryCritical,
  inventoryZeroed,
  inventoryDivergence,
  inventoryAlerts,
  customersWithFiado,
  customersWithCredit,
  customersTopPurchases,
  customersPending,
  purchasesSuppliers,
  purchasesItems,
  purchasesReplenishment,
  profitabilityTop,
}

extension ReportFocusX on ReportFocus {
  String get label {
    switch (this) {
      case ReportFocus.salesProducts:
        return 'Por produto';
      case ReportFocus.salesPaymentMethods:
        return 'Por forma de pagamento';
      case ReportFocus.cashEntries:
        return 'Entradas';
      case ReportFocus.cashFiadoReceipts:
        return 'Recebimentos de fiado';
      case ReportFocus.cashManualEntries:
        return 'Entradas manuais';
      case ReportFocus.cashNetFlow:
        return 'Fluxo do periodo';
      case ReportFocus.inventoryCritical:
        return 'Criticos';
      case ReportFocus.inventoryZeroed:
        return 'Zerados';
      case ReportFocus.inventoryDivergence:
        return 'Com divergencia';
      case ReportFocus.inventoryAlerts:
        return 'Todos com alerta';
      case ReportFocus.customersWithFiado:
        return 'Com fiado';
      case ReportFocus.customersWithCredit:
        return 'Com haver';
      case ReportFocus.customersTopPurchases:
        return 'Top compras';
      case ReportFocus.customersPending:
        return 'Pendencia aberta';
      case ReportFocus.purchasesSuppliers:
        return 'Por fornecedor';
      case ReportFocus.purchasesItems:
        return 'Itens comprados';
      case ReportFocus.purchasesReplenishment:
        return 'Reposicao';
      case ReportFocus.profitabilityTop:
        return 'Mais lucrativos';
    }
  }
}

class ReportFilter {
  const ReportFilter({
    required this.start,
    required this.endExclusive,
    this.customerId,
    this.categoryId,
    this.productId,
    this.variantId,
    this.supplierId,
    this.includeCanceled = false,
    this.onlyCanceled = false,
    this.paymentMethod,
    this.grouping = ReportGrouping.day,
    this.focus,
  });

  factory ReportFilter.fromPeriod(
    ReportPeriod period, {
    DateTime? reference,
    bool includeCanceled = false,
    PaymentMethod? paymentMethod,
    ReportGrouping? grouping,
  }) {
    final range = period.resolveRange(reference ?? DateTime.now());
    return ReportFilter(
      start: range.start,
      endExclusive: range.endExclusive,
      includeCanceled: includeCanceled,
      paymentMethod: paymentMethod,
      grouping:
          grouping ??
          switch (period) {
            ReportPeriod.yearly => ReportGrouping.month,
            ReportPeriod.daily ||
            ReportPeriod.weekly ||
            ReportPeriod.monthly => ReportGrouping.day,
          },
    );
  }

  final DateTime start;
  final DateTime endExclusive;
  final int? customerId;
  final int? categoryId;
  final int? productId;
  final int? variantId;
  final int? supplierId;
  final bool includeCanceled;
  final bool onlyCanceled;
  final PaymentMethod? paymentMethod;
  final ReportGrouping grouping;
  final ReportFocus? focus;

  ReportDateRange get range =>
      ReportDateRange(start: start, endExclusive: endExclusive);

  Duration get span => endExclusive.difference(start);

  ReportFilter copyWith({
    DateTime? start,
    DateTime? endExclusive,
    int? customerId,
    bool clearCustomerId = false,
    int? categoryId,
    bool clearCategoryId = false,
    int? productId,
    bool clearProductId = false,
    int? variantId,
    bool clearVariantId = false,
    int? supplierId,
    bool clearSupplierId = false,
    bool? includeCanceled,
    bool? onlyCanceled,
    PaymentMethod? paymentMethod,
    bool clearPaymentMethod = false,
    ReportGrouping? grouping,
    ReportFocus? focus,
    bool clearFocus = false,
  }) {
    return ReportFilter(
      start: start ?? this.start,
      endExclusive: endExclusive ?? this.endExclusive,
      customerId: clearCustomerId ? null : customerId ?? this.customerId,
      categoryId: clearCategoryId ? null : categoryId ?? this.categoryId,
      productId: clearProductId ? null : productId ?? this.productId,
      variantId: clearVariantId ? null : variantId ?? this.variantId,
      supplierId: clearSupplierId ? null : supplierId ?? this.supplierId,
      includeCanceled: includeCanceled ?? this.includeCanceled,
      onlyCanceled: onlyCanceled ?? this.onlyCanceled,
      paymentMethod: clearPaymentMethod
          ? null
          : paymentMethod ?? this.paymentMethod,
      grouping: grouping ?? this.grouping,
      focus: clearFocus ? null : focus ?? this.focus,
    );
  }

  ReportFilter copyWithRange(ReportDateRange range) {
    return copyWith(start: range.start, endExclusive: range.endExclusive);
  }

  ReportFilter clearScopedFilters() {
    return copyWith(
      clearCustomerId: true,
      clearCategoryId: true,
      clearProductId: true,
      clearVariantId: true,
      clearSupplierId: true,
      clearPaymentMethod: true,
      includeCanceled: false,
      onlyCanceled: false,
      clearFocus: true,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ReportFilter &&
        other.start == start &&
        other.endExclusive == endExclusive &&
        other.customerId == customerId &&
        other.categoryId == categoryId &&
        other.productId == productId &&
        other.variantId == variantId &&
        other.supplierId == supplierId &&
        other.includeCanceled == includeCanceled &&
        other.onlyCanceled == onlyCanceled &&
        other.paymentMethod == paymentMethod &&
        other.grouping == grouping &&
        other.focus == focus;
  }

  @override
  int get hashCode => Object.hash(
    start,
    endExclusive,
    customerId,
    categoryId,
    productId,
    variantId,
    supplierId,
    includeCanceled,
    onlyCanceled,
    paymentMethod,
    grouping,
    focus,
  );
}
