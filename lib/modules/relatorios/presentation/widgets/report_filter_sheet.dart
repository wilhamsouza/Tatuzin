import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_bottom_sheet_container.dart';
import '../../../../app/theme/app_design_tokens.dart';
import '../../../categorias/domain/entities/category.dart';
import '../../../clientes/domain/entities/client.dart';
import '../../../fornecedores/domain/entities/supplier.dart';
import '../../../produtos/domain/entities/product.dart';
import '../../../vendas/domain/entities/sale_enums.dart';
import '../../data/support/report_date_range_support.dart';
import '../../data/support/report_filter_preset_support.dart';
import '../../domain/entities/report_filter.dart';
import '../../domain/entities/report_period.dart';
import '../providers/report_providers.dart';
import 'report_filter_section.dart';

Future<void> showReportFilterSheet(
  BuildContext context, {
  required ReportPageKey page,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ReportFilterSheet(page: page),
  );
}

class ReportFilterSheet extends ConsumerStatefulWidget {
  const ReportFilterSheet({
    super.key,
    required this.page,
  });

  final ReportPageKey page;

  @override
  ConsumerState<ReportFilterSheet> createState() => _ReportFilterSheetState();
}

class _ReportFilterSheetState extends ConsumerState<ReportFilterSheet> {
  late ReportFilter _draft;
  var _initialized = false;

  ReportFilterPageConfig get _config =>
      ReportFilterPresetSupport.configFor(widget.page);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }
    _draft = ref.read(reportFilterProvider);
    _initialized = true;
  }

  @override
  Widget build(BuildContext context) {
    final customers =
        ref.watch(reportClientOptionsProvider).valueOrNull ?? const <Client>[];
    final categories =
        ref.watch(reportCategoryOptionsProvider).valueOrNull ??
        const <Category>[];
    final products =
        ref.watch(reportProductOptionsProvider).valueOrNull ?? const <Product>[];
    final variants =
        ref.watch(reportVariantOptionsProvider).valueOrNull ??
        const <ReportVariantFilterOption>[];
    final suppliers =
        ref.watch(reportSupplierOptionsProvider).valueOrNull ??
        const <Supplier>[];
    final matchingVariants = _draft.productId == null
        ? variants
        : variants
            .where((variant) => variant.productId == _draft.productId)
            .toList(growable: false);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: AppBottomSheetContainer(
        title: 'Filtros avancados',
        subtitle: 'Refine o relatorio sem perder o contexto da pagina.',
        trailing: IconButton(
          tooltip: 'Fechar',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ReportFilterSection(
                  title: 'Periodo',
                  subtitle: 'Use um recorte rapido ou escolha um intervalo.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final period in ReportPeriod.values)
                            ChoiceChip(
                              label: Text(period.label),
                              selected:
                                  ReportDateRangeSupport.matchPeriod(
                                    _draft.range,
                                  ) ==
                                  period,
                              onSelected: (_) => _applyPeriod(period),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _pickCustomRange,
                        icon: const Icon(Icons.date_range_outlined),
                        label: Text(
                          'Personalizar: ${AppFormatters.shortDate(_draft.start)} ate ${AppFormatters.shortDate(_draft.endExclusive.subtract(const Duration(days: 1)))}',
                        ),
                      ),
                    ],
                  ),
                ),
                if (_config.supports(ReportFilterField.grouping)) ...[
                  SizedBox(height: context.appLayout.sectionGap),
                  ReportFilterSection(
                    title: 'Agrupamento',
                    subtitle: 'Define como os numeros sao organizados.',
                    child: _buildGroupingField(),
                  ),
                ],
                if (_config.supports(ReportFilterField.includeCanceled)) ...[
                  SizedBox(height: context.appLayout.sectionGap),
                  ReportFilterSection(
                    title: 'Status',
                    child: SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Incluir canceladas'),
                      subtitle: const Text(
                        'Mantem as vendas canceladas na leitura do periodo.',
                      ),
                      value: _draft.includeCanceled,
                      onChanged: (value) {
                        setState(() {
                          _draft = _draft.copyWith(
                            includeCanceled: value,
                            onlyCanceled: value ? _draft.onlyCanceled : false,
                          );
                        });
                      },
                    ),
                  ),
                ],
                if (_config.supports(ReportFilterField.customer)) ...[
                  SizedBox(height: context.appLayout.sectionGap),
                  ReportFilterSection(
                    title: 'Cliente',
                    child: DropdownButtonFormField<int?>(
                      key: ValueKey<int?>(_draft.customerId),
                      initialValue: _draft.customerId,
                      decoration: const InputDecoration(
                        labelText: 'Cliente',
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Todos os clientes'),
                        ),
                        for (final customer in customers)
                          DropdownMenuItem<int?>(
                            value: customer.id,
                            child: Text(customer.name),
                          ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _draft = _draft.copyWith(
                            customerId: value,
                            clearCustomerId: value == null,
                          );
                        });
                      },
                    ),
                  ),
                ],
                if (_config.supports(ReportFilterField.category)) ...[
                  SizedBox(height: context.appLayout.sectionGap),
                  ReportFilterSection(
                    title: 'Categoria',
                    child: DropdownButtonFormField<int?>(
                      key: ValueKey<int?>(_draft.categoryId),
                      initialValue: _draft.categoryId,
                      decoration: const InputDecoration(
                        labelText: 'Categoria',
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Todas as categorias'),
                        ),
                        for (final category in categories)
                          DropdownMenuItem<int?>(
                            value: category.id,
                            child: Text(category.name),
                          ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _draft = _draft.copyWith(
                            categoryId: value,
                            clearCategoryId: value == null,
                            clearProductId: true,
                            clearVariantId: true,
                          );
                        });
                      },
                    ),
                  ),
                ],
                if (_config.supports(ReportFilterField.product)) ...[
                  SizedBox(height: context.appLayout.sectionGap),
                  ReportFilterSection(
                    title: 'Produto',
                    child: DropdownButtonFormField<int?>(
                      key: ValueKey<int?>(_draft.productId),
                      initialValue: _draft.productId,
                      decoration: const InputDecoration(
                        labelText: 'Produto',
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Todos os produtos'),
                        ),
                        for (final product in products)
                          DropdownMenuItem<int?>(
                            value: product.id,
                            child: Text(product.displayName),
                          ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _draft = _draft.copyWith(
                            productId: value,
                            clearProductId: value == null,
                            clearVariantId: true,
                          );
                        });
                      },
                    ),
                  ),
                ],
                if (_config.supports(ReportFilterField.variant)) ...[
                  SizedBox(height: context.appLayout.sectionGap),
                  ReportFilterSection(
                    title: 'Variante',
                    child: DropdownButtonFormField<int?>(
                      key: ValueKey<int?>(_draft.variantId),
                      initialValue: _draft.variantId,
                      decoration: const InputDecoration(
                        labelText: 'Variante',
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Todas as variantes'),
                        ),
                        for (final variant in matchingVariants)
                          DropdownMenuItem<int?>(
                            value: variant.id,
                            child: Text(variant.label),
                          ),
                      ],
                      onChanged: (value) {
                        ReportVariantFilterOption? selectedVariant;
                        for (final variant in variants) {
                          if (variant.id == value) {
                            selectedVariant = variant;
                            break;
                          }
                        }
                        setState(() {
                          _draft = _draft.copyWith(
                            productId: selectedVariant?.productId,
                            clearProductId: value == null && _draft.productId == null,
                            variantId: value,
                            clearVariantId: value == null,
                          );
                        });
                      },
                    ),
                  ),
                ],
                if (_config.supports(ReportFilterField.paymentMethod)) ...[
                  SizedBox(height: context.appLayout.sectionGap),
                  ReportFilterSection(
                    title: 'Forma de pagamento',
                    child: DropdownButtonFormField<PaymentMethod?>(
                      key: ValueKey<PaymentMethod?>(_draft.paymentMethod),
                      initialValue: _draft.paymentMethod,
                      decoration: const InputDecoration(
                        labelText: 'Forma',
                      ),
                      items: [
                        const DropdownMenuItem<PaymentMethod?>(
                          value: null,
                          child: Text('Todas as formas'),
                        ),
                        for (final method in PaymentMethod.values)
                          DropdownMenuItem<PaymentMethod?>(
                            value: method,
                            child: Text(method.label),
                          ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _draft = _draft.copyWith(
                            paymentMethod: value,
                            clearPaymentMethod: value == null,
                          );
                        });
                      },
                    ),
                  ),
                ],
                if (_config.supports(ReportFilterField.supplier)) ...[
                  SizedBox(height: context.appLayout.sectionGap),
                  ReportFilterSection(
                    title: 'Fornecedor',
                    child: DropdownButtonFormField<int?>(
                      key: ValueKey<int?>(_draft.supplierId),
                      initialValue: _draft.supplierId,
                      decoration: const InputDecoration(
                        labelText: 'Fornecedor',
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Todos os fornecedores'),
                        ),
                        for (final supplier in suppliers)
                          DropdownMenuItem<int?>(
                            value: supplier.id,
                            child: Text(
                              (supplier.tradeName?.trim().isNotEmpty ?? false)
                                  ? supplier.tradeName!.trim()
                                  : supplier.name,
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _draft = _draft.copyWith(
                            supplierId: value,
                            clearSupplierId: value == null,
                          );
                        });
                      },
                    ),
                  ),
                ],
                SizedBox(height: context.appLayout.sectionGap),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _draft = ReportFilterPresetSupport.clearForPage(
                              widget.page,
                              _draft,
                            );
                          });
                        },
                        child: const Text('Limpar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _apply,
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Aplicar filtros'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGroupingField() {
    final options = _config.groupingOptions.isEmpty
        ? <ReportGrouping>[_config.defaultGrouping]
        : _config.groupingOptions;
    final current = options.contains(_draft.grouping)
        ? _draft.grouping
        : _config.defaultGrouping;

    return DropdownButtonFormField<ReportGrouping>(
      key: ValueKey<ReportGrouping>(current),
      initialValue: current,
      decoration: const InputDecoration(labelText: 'Agrupar por'),
      items: [
        for (final grouping in options)
          DropdownMenuItem<ReportGrouping>(
            value: grouping,
            child: Text(grouping.label),
          ),
      ],
      onChanged: (value) {
        if (value == null) {
          return;
        }
        setState(() {
          _draft = _draft.copyWith(grouping: value);
        });
      },
    );
  }

  Future<void> _pickCustomRange() async {
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(
        start: _draft.start,
        end: _draft.endExclusive.subtract(const Duration(days: 1)),
      ),
    );
    if (selected == null) {
      return;
    }

    setState(() {
      _draft = _draft.copyWith(
        start: DateTime(
          selected.start.year,
          selected.start.month,
          selected.start.day,
        ),
        endExclusive: DateTime(
          selected.end.year,
          selected.end.month,
          selected.end.day + 1,
        ),
      );
    });
  }

  void _applyPeriod(ReportPeriod period) {
    final next = ReportFilter.fromPeriod(period);
    final preserveGrouping =
        _config.groupingOptions.isEmpty ||
        _config.groupingOptions.every((grouping) => !grouping.isTimeSeries);
    setState(() {
      _draft = _draft.copyWith(
        start: next.start,
        endExclusive: next.endExclusive,
        grouping: preserveGrouping ? _draft.grouping : next.grouping,
      );
    });
  }

  void _apply() {
    ref.read(reportFilterProvider.notifier).replace(_draft);
    Navigator.of(context).pop();
  }
}
