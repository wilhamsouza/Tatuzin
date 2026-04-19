import 'report_filter_preset_support.dart';
import '../../domain/entities/report_filter.dart';

class ReportDrilldownContext {
  const ReportDrilldownContext({
    required this.page,
    required this.sourcePage,
    required this.sourceLabel,
    required this.message,
    required this.baselineFilter,
    this.isFocusOnly = false,
  });

  final ReportPageKey page;
  final ReportPageKey sourcePage;
  final String sourceLabel;
  final String message;
  final ReportFilter baselineFilter;
  final bool isFocusOnly;

  String get bannerLabel =>
      'Aberto via ${sourcePage.label.toLowerCase()}: $sourceLabel';

  String get exportLabel {
    final prefix = 'Drill-down: ${sourcePage.label} -> $sourceLabel';
    if (!isFocusOnly) {
      return prefix;
    }
    return '$prefix | foco de leitura';
  }
}

class ReportPageSessionState {
  const ReportPageSessionState({
    this.drilldowns = const <ReportPageKey, ReportDrilldownContext>{},
    this.lastPresetIds = const <ReportPageKey, String>{},
  });

  final Map<ReportPageKey, ReportDrilldownContext> drilldowns;
  final Map<ReportPageKey, String> lastPresetIds;

  ReportDrilldownContext? drilldownFor(ReportPageKey page) => drilldowns[page];

  String? lastPresetIdFor(ReportPageKey page) => lastPresetIds[page];

  ReportPageSessionState copyWith({
    Map<ReportPageKey, ReportDrilldownContext>? drilldowns,
    Map<ReportPageKey, String>? lastPresetIds,
  }) {
    return ReportPageSessionState(
      drilldowns: drilldowns ?? this.drilldowns,
      lastPresetIds: lastPresetIds ?? this.lastPresetIds,
    );
  }
}

class ReportFocusHintData {
  const ReportFocusHintData({
    required this.title,
    required this.message,
    this.isFocusOnly = false,
  });

  final String title;
  final String message;
  final bool isFocusOnly;
}

abstract final class ReportDrilldownSupport {
  static ReportFocusHintData? focusHintForPage(
    ReportPageKey page,
    ReportFilter filter,
  ) {
    if (filter.onlyCanceled) {
      return const ReportFocusHintData(
        title: 'Leitura focada em cancelamentos',
        message:
            'Este atalho destaca os cancelamentos sem recalcular rankings por item fora da base atual de vendas ativas.',
        isFocusOnly: true,
      );
    }

    switch (page) {
      case ReportPageKey.sales:
        return _salesHint(filter);
      case ReportPageKey.cash:
        return _cashHint(filter);
      case ReportPageKey.inventory:
        return _inventoryHint(filter);
      case ReportPageKey.customers:
        return _customersHint(filter);
      case ReportPageKey.purchases:
        return _purchasesHint(filter);
      case ReportPageKey.profitability:
        return _profitabilityHint(filter);
      case ReportPageKey.overview:
        return null;
    }
  }

  static ReportFocusHintData? _salesHint(ReportFilter filter) {
    switch (filter.focus) {
      case ReportFocus.salesProducts:
        return const ReportFocusHintData(
          title: 'Produtos em destaque',
          message:
              'A tela puxa os itens vendidos para frente, mas o recorte principal continua o mesmo do periodo atual.',
          isFocusOnly: true,
        );
      case ReportFocus.salesPaymentMethods:
        return const ReportFocusHintData(
          title: 'Formas de pagamento em foco',
          message:
              'O destaque reorganiza a leitura pelos recebimentos das vendas, sem criar uma base paralela para os itens.',
          isFocusOnly: true,
        );
      case null:
        return null;
      default:
        return null;
    }
  }

  static ReportFocusHintData? _cashHint(ReportFilter filter) {
    switch (filter.focus) {
      case ReportFocus.cashEntries:
      case ReportFocus.cashFiadoReceipts:
      case ReportFocus.cashManualEntries:
      case ReportFocus.cashNetFlow:
        return ReportFocusHintData(
          title: 'Caixa com foco operacional',
          message:
              'O atalho destaca ${filter.focus!.label.toLowerCase()} na leitura do caixa, mas os totais continuam vindo da mesma base do periodo.',
          isFocusOnly: true,
        );
      case null:
        return null;
      default:
        return null;
    }
  }

  static ReportFocusHintData? _inventoryHint(ReportFilter filter) {
    switch (filter.focus) {
      case ReportFocus.inventoryCritical:
      case ReportFocus.inventoryZeroed:
      case ReportFocus.inventoryDivergence:
      case ReportFocus.inventoryAlerts:
        return ReportFocusHintData(
          title: 'Estoque com foco de leitura',
          message:
              'O destaque prioriza ${filter.focus!.label.toLowerCase()} sem recalcular a saude do estoque fora da base ja consolidada.',
          isFocusOnly: true,
        );
      case null:
        return null;
      default:
        return null;
    }
  }

  static ReportFocusHintData? _customersHint(ReportFilter filter) {
    switch (filter.focus) {
      case ReportFocus.customersWithFiado:
      case ReportFocus.customersWithCredit:
      case ReportFocus.customersTopPurchases:
      case ReportFocus.customersPending:
        return ReportFocusHintData(
          title: 'Clientes em foco',
          message:
              'O preset puxa ${filter.focus!.label.toLowerCase()} para a frente, mantendo a mesma base de clientes do recorte atual.',
          isFocusOnly: true,
        );
      case null:
        return null;
      default:
        return null;
    }
  }

  static ReportFocusHintData? _purchasesHint(ReportFilter filter) {
    switch (filter.focus) {
      case ReportFocus.purchasesSuppliers:
      case ReportFocus.purchasesItems:
      case ReportFocus.purchasesReplenishment:
        return ReportFocusHintData(
          title: 'Compras em foco',
          message:
              'A leitura destaca ${filter.focus!.label.toLowerCase()} sem trocar a base das compras e pendencias do periodo.',
          isFocusOnly: true,
        );
      case null:
        return null;
      default:
        return null;
    }
  }

  static ReportFocusHintData? _profitabilityHint(ReportFilter filter) {
    switch (filter.focus) {
      case ReportFocus.profitabilityTop:
        return const ReportFocusHintData(
          title: 'Mais lucrativos em destaque',
          message:
              'A tabela mostra os itens com maior lucro dentro da mesma semantica atual de receita, custo e margem.',
          isFocusOnly: true,
        );
      case null:
        return null;
      default:
        return null;
    }
  }
}
