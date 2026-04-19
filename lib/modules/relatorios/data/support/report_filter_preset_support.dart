import '../../../vendas/domain/entities/sale_enums.dart';
import '../../domain/entities/report_filter.dart';
import '../../domain/entities/report_period.dart';

enum ReportPageKey {
  overview,
  sales,
  cash,
  inventory,
  customers,
  purchases,
  profitability,
}

extension ReportPageKeyX on ReportPageKey {
  String get label {
    switch (this) {
      case ReportPageKey.overview:
        return 'Hub executivo';
      case ReportPageKey.sales:
        return 'Vendas';
      case ReportPageKey.cash:
        return 'Caixa';
      case ReportPageKey.inventory:
        return 'Estoque';
      case ReportPageKey.customers:
        return 'Clientes';
      case ReportPageKey.purchases:
        return 'Compras';
      case ReportPageKey.profitability:
        return 'Lucratividade';
    }
  }
}

enum ReportFilterField {
  grouping,
  includeCanceled,
  onlyCanceled,
  customer,
  category,
  product,
  variant,
  paymentMethod,
  supplier,
  focus,
}

class ReportFilterPreset {
  const ReportFilterPreset({
    required this.id,
    required this.label,
    required this.transform,
    this.helperText,
  });

  final String id;
  final String label;
  final String? helperText;
  final ReportFilter Function(ReportFilter current) transform;

  bool matches(ReportFilter filter) => transform(filter) == filter;
}

class ReportFilterPageConfig {
  const ReportFilterPageConfig({
    required this.page,
    this.supportedFields = const <ReportFilterField>{},
    this.groupingOptions = const <ReportGrouping>[],
    this.defaultPeriod = ReportPeriod.daily,
    this.defaultGrouping = ReportGrouping.day,
    this.defaultIncludeCanceled = false,
    this.defaultFocus,
    this.presets = const <ReportFilterPreset>[],
  });

  final ReportPageKey page;
  final Set<ReportFilterField> supportedFields;
  final List<ReportGrouping> groupingOptions;
  final ReportPeriod defaultPeriod;
  final ReportGrouping defaultGrouping;
  final bool defaultIncludeCanceled;
  final ReportFocus? defaultFocus;
  final List<ReportFilterPreset> presets;

  bool supports(ReportFilterField field) => supportedFields.contains(field);
}

class ReportFilterOptionLabels {
  const ReportFilterOptionLabels({
    this.customers = const <int, String>{},
    this.categories = const <int, String>{},
    this.products = const <int, String>{},
    this.variants = const <int, String>{},
    this.suppliers = const <int, String>{},
  });

  final Map<int, String> customers;
  final Map<int, String> categories;
  final Map<int, String> products;
  final Map<int, String> variants;
  final Map<int, String> suppliers;
}

class ReportActiveFilterDescriptor {
  const ReportActiveFilterDescriptor({
    required this.field,
    required this.label,
    required this.value,
  });

  final ReportFilterField field;
  final String label;
  final String value;

  String get displayLabel => value.isEmpty ? label : '$label: $value';
}

abstract final class ReportFilterPresetSupport {
  static ReportFilterPageConfig configFor(ReportPageKey page) {
    switch (page) {
      case ReportPageKey.overview:
        return ReportFilterPageConfig(
          page: page,
          defaultPeriod: ReportPeriod.monthly,
          supportedFields: const {
            ReportFilterField.category,
            ReportFilterField.product,
            ReportFilterField.variant,
          },
          presets: [
            ReportFilterPreset(
              id: 'weekly',
              label: 'Semana',
              helperText: 'Troca o hub para a leitura desta semana.',
              transform: (current) => _applyPeriod(current, ReportPeriod.weekly),
            ),
            ReportFilterPreset(
              id: 'monthly',
              label: 'Mes',
              helperText: 'Resume o desempenho do mes atual.',
              transform: (current) =>
                  _applyPeriod(current, ReportPeriod.monthly),
            ),
          ],
        );
      case ReportPageKey.sales:
        return ReportFilterPageConfig(
          page: page,
          defaultPeriod: ReportPeriod.monthly,
          supportedFields: const {
            ReportFilterField.grouping,
            ReportFilterField.includeCanceled,
            ReportFilterField.onlyCanceled,
            ReportFilterField.customer,
            ReportFilterField.category,
            ReportFilterField.product,
            ReportFilterField.variant,
            ReportFilterField.paymentMethod,
            ReportFilterField.focus,
          },
          groupingOptions: const [
            ReportGrouping.day,
            ReportGrouping.week,
            ReportGrouping.month,
          ],
          defaultGrouping: ReportGrouping.day,
          presets: [
            ReportFilterPreset(
              id: 'today',
              label: 'Hoje',
              helperText: 'Foca nas vendas fechadas hoje.',
              transform: (current) => _applyPeriod(current, ReportPeriod.daily),
            ),
            ReportFilterPreset(
              id: 'week',
              label: 'Esta semana',
              helperText: 'Organiza a leitura pelas vendas da semana atual.',
              transform: (current) => _applyPeriod(current, ReportPeriod.weekly),
            ),
            ReportFilterPreset(
              id: 'month',
              label: 'Este mes',
              helperText: 'Mantem o recorte mensal da pagina de vendas.',
              transform: (current) => _applyPeriod(current, ReportPeriod.monthly),
            ),
            ReportFilterPreset(
              id: 'canceled-only',
              label: 'So canceladas',
              helperText:
                  'Mostra o resumo de cancelamentos sem recalcular rankings por item.',
              transform: (current) => current.copyWith(
                includeCanceled: true,
                onlyCanceled: true,
                clearFocus: true,
              ),
            ),
            ReportFilterPreset(
              id: 'products',
              label: 'Por produto',
              helperText: 'Prioriza os blocos de itens vendidos.',
              transform: (current) => current.copyWith(
                focus: ReportFocus.salesProducts,
                onlyCanceled: false,
              ),
            ),
            ReportFilterPreset(
              id: 'payments',
              label: 'Por forma',
              helperText: 'Destaca as formas de pagamento do periodo.',
              transform: (current) => current.copyWith(
                focus: ReportFocus.salesPaymentMethods,
                onlyCanceled: false,
              ),
            ),
          ],
        );
      case ReportPageKey.cash:
        return ReportFilterPageConfig(
          page: page,
          defaultPeriod: ReportPeriod.daily,
          supportedFields: const {
            ReportFilterField.grouping,
            ReportFilterField.paymentMethod,
            ReportFilterField.focus,
          },
          groupingOptions: const [
            ReportGrouping.day,
            ReportGrouping.week,
            ReportGrouping.month,
          ],
          defaultGrouping: ReportGrouping.day,
          presets: [
            ReportFilterPreset(
              id: 'today',
              label: 'Hoje',
              helperText: 'Acompanha o caixa do dia atual.',
              transform: (current) => _applyPeriod(current, ReportPeriod.daily),
            ),
            ReportFilterPreset(
              id: 'entries',
              label: 'Entradas',
              helperText: 'Traz as entradas para a frente da leitura.',
              transform: (current) => current.copyWith(
                focus: ReportFocus.cashEntries,
              ),
            ),
            ReportFilterPreset(
              id: 'fiado',
              label: 'Fiado recebido',
              helperText: 'Destaque para o que voltou do fiado.',
              transform: (current) => current.copyWith(
                focus: ReportFocus.cashFiadoReceipts,
              ),
            ),
            ReportFilterPreset(
              id: 'manual',
              label: 'Entradas manuais',
              helperText: 'Mostra suprimentos e ajustes positivos primeiro.',
              transform: (current) => current.copyWith(
                focus: ReportFocus.cashManualEntries,
              ),
            ),
            ReportFilterPreset(
              id: 'net',
              label: 'Fluxo do periodo',
              helperText: 'Prioriza a linha do tempo do saldo liquido.',
              transform: (current) => current.copyWith(
                focus: ReportFocus.cashNetFlow,
              ),
            ),
          ],
        );
      case ReportPageKey.inventory:
        return ReportFilterPageConfig(
          page: page,
          defaultPeriod: ReportPeriod.monthly,
          supportedFields: const {
            ReportFilterField.category,
            ReportFilterField.product,
            ReportFilterField.variant,
            ReportFilterField.focus,
          },
          presets: [
            ReportFilterPreset(
              id: 'critical',
              label: 'Criticos',
              helperText: 'Destaca os itens que pedem reposicao agora.',
              transform: (current) => current.copyWith(
                focus: ReportFocus.inventoryCritical,
              ),
            ),
            ReportFilterPreset(
              id: 'zeroed',
              label: 'Zerados',
              helperText: 'Filtra a leitura para quem esta sem saldo.',
              transform: (current) => current.copyWith(
                focus: ReportFocus.inventoryZeroed,
              ),
            ),
            ReportFilterPreset(
              id: 'divergence',
              label: 'Com divergencia',
              helperText: 'Puxa para frente os sinais de inventario divergente.',
              transform: (current) => current.copyWith(
                focus: ReportFocus.inventoryDivergence,
              ),
            ),
            ReportFilterPreset(
              id: 'alerts',
              label: 'Todos com alerta',
              helperText: 'Une zerados, abaixo do minimo e divergencias.',
              transform: (current) => current.copyWith(
                focus: ReportFocus.inventoryAlerts,
              ),
            ),
          ],
        );
      case ReportPageKey.customers:
        return ReportFilterPageConfig(
          page: page,
          defaultPeriod: ReportPeriod.monthly,
          supportedFields: const {
            ReportFilterField.customer,
            ReportFilterField.category,
            ReportFilterField.product,
            ReportFilterField.variant,
            ReportFilterField.focus,
          },
          presets: [
            ReportFilterPreset(
              id: 'fiado',
              label: 'Com fiado',
              helperText: 'Traz os saldos pendentes para a frente.',
              transform: (current) => current.copyWith(
                focus: ReportFocus.customersWithFiado,
              ),
            ),
            ReportFilterPreset(
              id: 'credit',
              label: 'Com haver',
              helperText: 'Mostra primeiro os clientes com saldo positivo.',
              transform: (current) => current.copyWith(
                focus: ReportFocus.customersWithCredit,
              ),
            ),
            ReportFilterPreset(
              id: 'top',
              label: 'Top compras',
              helperText: 'Prioriza quem mais comprou no periodo.',
              transform: (current) => current.copyWith(
                focus: ReportFocus.customersTopPurchases,
              ),
            ),
            ReportFilterPreset(
              id: 'pending',
              label: 'Pendencia aberta',
              helperText: 'Foca nos clientes que mais pedem cobranca.',
              transform: (current) => current.copyWith(
                focus: ReportFocus.customersPending,
              ),
            ),
          ],
        );
      case ReportPageKey.purchases:
        return ReportFilterPageConfig(
          page: page,
          defaultPeriod: ReportPeriod.monthly,
          supportedFields: const {
            ReportFilterField.category,
            ReportFilterField.product,
            ReportFilterField.variant,
            ReportFilterField.supplier,
            ReportFilterField.focus,
          },
          presets: [
            ReportFilterPreset(
              id: 'suppliers',
              label: 'Por fornecedor',
              helperText: 'Abre a leitura pelas compras concentradas em fornecedor.',
              transform: (current) => current.copyWith(
                focus: ReportFocus.purchasesSuppliers,
              ),
            ),
            ReportFilterPreset(
              id: 'items',
              label: 'Itens comprados',
              helperText: 'Puxa para frente os itens com maior peso nas compras.',
              transform: (current) => current.copyWith(
                focus: ReportFocus.purchasesItems,
              ),
            ),
            ReportFilterPreset(
              id: 'replenishment',
              label: 'Reposicao',
              helperText: 'Destaca as variantes que mais entraram no periodo.',
              transform: (current) => current.copyWith(
                focus: ReportFocus.purchasesReplenishment,
              ),
            ),
            ReportFilterPreset(
              id: 'period-current',
              label: 'Periodo atual',
              helperText: 'Volta ao recorte padrao da pagina de compras.',
              transform: (current) => _resetPeriod(
                current,
                configFor(ReportPageKey.purchases),
              ),
            ),
          ],
        );
      case ReportPageKey.profitability:
        return ReportFilterPageConfig(
          page: page,
          defaultPeriod: ReportPeriod.monthly,
          supportedFields: const {
            ReportFilterField.grouping,
            ReportFilterField.category,
            ReportFilterField.product,
            ReportFilterField.variant,
            ReportFilterField.focus,
          },
          groupingOptions: const [
            ReportGrouping.product,
            ReportGrouping.variant,
            ReportGrouping.category,
          ],
          defaultGrouping: ReportGrouping.product,
          presets: [
            ReportFilterPreset(
              id: 'top',
              label: 'Mais lucrativos',
              helperText: 'Mantem a tabela focada nos itens que mais lucram.',
              transform: (current) => current.copyWith(
                grouping: ReportGrouping.product,
                focus: ReportFocus.profitabilityTop,
              ),
            ),
            ReportFilterPreset(
              id: 'category',
              label: 'Por categoria',
              helperText: 'Agrupa o lucro por categoria.',
              transform: (current) => current.copyWith(
                grouping: ReportGrouping.category,
                clearFocus: true,
              ),
            ),
            ReportFilterPreset(
              id: 'product',
              label: 'Por produto',
              helperText: 'Volta para a leitura por produto.',
              transform: (current) => current.copyWith(
                grouping: ReportGrouping.product,
                clearFocus: true,
              ),
            ),
            ReportFilterPreset(
              id: 'variant',
              label: 'Por variante',
              helperText: 'Mostra a margem quebrada pela grade.',
              transform: (current) => current.copyWith(
                grouping: ReportGrouping.variant,
                clearFocus: true,
              ),
            ),
          ],
        );
    }
  }

  static ReportFilter defaultFilterForPage(
    ReportPageKey page, {
    DateTime? reference,
  }) {
    final config = configFor(page);
    final base = ReportFilter.fromPeriod(
      config.defaultPeriod,
      reference: reference,
      includeCanceled: config.defaultIncludeCanceled,
      grouping: config.defaultGrouping,
    );
    return base.copyWith(
      includeCanceled: config.defaultIncludeCanceled,
      onlyCanceled: false,
      focus: config.defaultFocus,
      clearFocus: config.defaultFocus == null,
    );
  }

  static ReportFilter clearForPage(ReportPageKey page, ReportFilter current) {
    final config = configFor(page);
    return current.copyWith(
      clearCustomerId: true,
      clearCategoryId: true,
      clearProductId: true,
      clearVariantId: true,
      clearSupplierId: true,
      clearPaymentMethod: true,
      includeCanceled: current.onlyCanceled
          ? config.defaultIncludeCanceled
          : current.includeCanceled,
      onlyCanceled: false,
      clearFocus: true,
    );
  }

  static ReportFilter resetToPageDefault(
    ReportPageKey page, {
    DateTime? reference,
  }) {
    return defaultFilterForPage(page, reference: reference);
  }

  static ReportFilterPreset? activePresetForPage(
    ReportPageKey page,
    ReportFilter filter,
  ) {
    final presets = configFor(page).presets;
    for (final preset in presets) {
      if (preset.matches(filter)) {
        return preset;
      }
    }
    return null;
  }

  static ReportFilterPreset? presetById(ReportPageKey page, String id) {
    final presets = configFor(page).presets;
    for (final preset in presets) {
      if (preset.id == id) {
        return preset;
      }
    }
    return null;
  }

  static ReportFilter removeField(
    ReportPageKey page,
    ReportFilter current,
    ReportFilterField field,
  ) {
    final config = configFor(page);
    switch (field) {
      case ReportFilterField.grouping:
        return current.copyWith(grouping: config.defaultGrouping);
      case ReportFilterField.includeCanceled:
        return current.copyWith(includeCanceled: config.defaultIncludeCanceled);
      case ReportFilterField.onlyCanceled:
        return current.copyWith(
          includeCanceled: config.defaultIncludeCanceled,
          onlyCanceled: false,
        );
      case ReportFilterField.customer:
        return current.copyWith(clearCustomerId: true);
      case ReportFilterField.category:
        return current.copyWith(clearCategoryId: true);
      case ReportFilterField.product:
        return current.copyWith(clearProductId: true);
      case ReportFilterField.variant:
        return current.copyWith(clearVariantId: true);
      case ReportFilterField.paymentMethod:
        return current.copyWith(clearPaymentMethod: true);
      case ReportFilterField.supplier:
        return current.copyWith(clearSupplierId: true);
      case ReportFilterField.focus:
        return current.copyWith(clearFocus: true);
    }
  }

  static List<ReportActiveFilterDescriptor> activeFiltersForPage({
    required ReportPageKey page,
    required ReportFilter filter,
    required ReportFilterOptionLabels labels,
  }) {
    final config = configFor(page);
    final descriptors = <ReportActiveFilterDescriptor>[];

    if (config.supports(ReportFilterField.grouping) &&
        filter.grouping != config.defaultGrouping) {
      descriptors.add(
        ReportActiveFilterDescriptor(
          field: ReportFilterField.grouping,
          label: 'Agrupamento',
          value: filter.grouping.label,
        ),
      );
    }
    if (config.supports(ReportFilterField.onlyCanceled) && filter.onlyCanceled) {
      descriptors.add(
        const ReportActiveFilterDescriptor(
          field: ReportFilterField.onlyCanceled,
          label: 'Status',
          value: 'Somente canceladas',
        ),
      );
    } else if (config.supports(ReportFilterField.includeCanceled) &&
        filter.includeCanceled) {
      descriptors.add(
        const ReportActiveFilterDescriptor(
          field: ReportFilterField.includeCanceled,
          label: 'Canceladas',
          value: '',
        ),
      );
    }
    if (config.supports(ReportFilterField.customer) && filter.customerId != null) {
      descriptors.add(
        ReportActiveFilterDescriptor(
          field: ReportFilterField.customer,
          label: 'Cliente',
          value:
              labels.customers[filter.customerId!] ?? 'Cliente #${filter.customerId}',
        ),
      );
    }
    if (config.supports(ReportFilterField.category) &&
        filter.categoryId != null) {
      descriptors.add(
        ReportActiveFilterDescriptor(
          field: ReportFilterField.category,
          label: 'Categoria',
          value: labels.categories[filter.categoryId!] ??
              'Categoria #${filter.categoryId}',
        ),
      );
    }
    if (config.supports(ReportFilterField.product) && filter.productId != null) {
      descriptors.add(
        ReportActiveFilterDescriptor(
          field: ReportFilterField.product,
          label: 'Produto',
          value:
              labels.products[filter.productId!] ?? 'Produto #${filter.productId}',
        ),
      );
    }
    if (config.supports(ReportFilterField.variant) && filter.variantId != null) {
      descriptors.add(
        ReportActiveFilterDescriptor(
          field: ReportFilterField.variant,
          label: 'Variante',
          value:
              labels.variants[filter.variantId!] ?? 'Variante #${filter.variantId}',
        ),
      );
    }
    if (config.supports(ReportFilterField.paymentMethod) &&
        filter.paymentMethod != null) {
      descriptors.add(
        ReportActiveFilterDescriptor(
          field: ReportFilterField.paymentMethod,
          label: 'Forma',
          value: filter.paymentMethod!.label,
        ),
      );
    }
    if (config.supports(ReportFilterField.supplier) &&
        filter.supplierId != null) {
      descriptors.add(
        ReportActiveFilterDescriptor(
          field: ReportFilterField.supplier,
          label: 'Fornecedor',
          value: labels.suppliers[filter.supplierId!] ??
              'Fornecedor #${filter.supplierId}',
        ),
      );
    }
    if (config.supports(ReportFilterField.focus) && filter.focus != null) {
      descriptors.add(
        ReportActiveFilterDescriptor(
          field: ReportFilterField.focus,
          label: 'Leitura',
          value: filter.focus!.label,
        ),
      );
    }

    return descriptors;
  }

  static ReportFilter applyPreset(
    ReportFilter current,
    ReportFilterPreset preset,
  ) {
    return preset.transform(current);
  }

  static ReportFilterPreset? firstMatchingPreset(
    ReportPageKey page,
    ReportFilter filter,
  ) {
    final config = configFor(page);
    for (final preset in config.presets) {
      if (preset.matches(filter)) {
        return preset;
      }
    }
    return null;
  }

  static ReportFilter _applyPeriod(ReportFilter current, ReportPeriod period) {
    final next = ReportFilter.fromPeriod(period);
    return current.copyWith(
      start: next.start,
      endExclusive: next.endExclusive,
      grouping: next.grouping,
      onlyCanceled: false,
    );
  }

  static ReportFilter _resetPeriod(
    ReportFilter current,
    ReportFilterPageConfig config,
  ) {
    final next = ReportFilter.fromPeriod(config.defaultPeriod);
    return current.copyWith(
      start: next.start,
      endExclusive: next.endExclusive,
      grouping: config.defaultGrouping,
      includeCanceled: config.defaultIncludeCanceled,
      onlyCanceled: false,
      focus: config.defaultFocus,
      clearFocus: config.defaultFocus == null,
    );
  }
}
