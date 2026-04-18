import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/utils/quantity_parser.dart';
import '../../../../app/core/widgets/app_bottom_sheet_container.dart';
import '../../../../app/core/widgets/app_feedback.dart';
import '../../../../app/core/widgets/app_list_tile_card.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_metric_card.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_search_field.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/core/widgets/app_state_card.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../../app/routes/route_names.dart';
import '../../../../app/theme/app_design_tokens.dart';
import '../../domain/entities/inventory_count_item.dart';
import '../../domain/entities/inventory_count_item_input.dart';
import '../../domain/entities/inventory_count_session.dart';
import '../../domain/entities/inventory_count_session_detail.dart';
import '../../domain/entities/inventory_item.dart';
import '../providers/inventory_providers.dart';

class InventoryCountSessionDetailPage extends ConsumerStatefulWidget {
  const InventoryCountSessionDetailPage({required this.sessionId, super.key});

  final int sessionId;

  @override
  ConsumerState<InventoryCountSessionDetailPage> createState() =>
      _InventoryCountSessionDetailPageState();
}

class _InventoryCountSessionDetailPageState
    extends ConsumerState<InventoryCountSessionDetailPage> {
  _InventoryCountItemFilter _selectedFilter = _InventoryCountItemFilter.all;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final detailAsync = ref.watch(
      inventoryCountSessionDetailProvider(widget.sessionId),
    );
    final itemOptionsAsync = ref.watch(inventoryActiveItemOptionsProvider);
    final actionState = ref.watch(inventoryCountActionControllerProvider);
    final itemOptions = itemOptionsAsync.valueOrNull ?? const <InventoryItem>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Sessao de inventario')),
      drawer: const AppMainDrawer(),
      floatingActionButton:
          detailAsync.valueOrNull?.session.status.canEdit == true
          ? FloatingActionButton.extended(
              onPressed: actionState.isLoading
                  ? null
                  : () => _addItem(itemOptions),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Adicionar item'),
            )
          : null,
      body: detailAsync.when(
        data: (detail) {
          if (detail == null) {
            return Padding(
              padding: EdgeInsets.all(layout.pagePadding),
              child: const AppStateCard(
                title: 'Sessao nao encontrada',
                message:
                    'Nao foi possivel localizar a sessao de inventario solicitada.',
                tone: AppStateTone.error,
              ),
            );
          }

          final filteredItems = detail.items
              .where((item) => _selectedFilter.matches(item))
              .toList(growable: false);
          final pendingReviewCount = detail.items
              .where((item) => item.needsReview)
              .length;

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(
                inventoryCountSessionDetailProvider(widget.sessionId),
              );
              await ref.read(
                inventoryCountSessionDetailProvider(widget.sessionId).future,
              );
            },
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                layout.pagePadding,
                layout.pagePadding,
                layout.pagePadding,
                layout.pagePadding * 2,
              ),
              children: [
                AppPageHeader(
                  title: detail.session.name,
                  subtitle:
                      'Contagem ${detail.session.status.label.toLowerCase()} para comparar o estoque fisico com o saldo atual do sistema.',
                  badgeLabel: detail.session.status.label,
                  badgeIcon: Icons.fact_check_rounded,
                  emphasized: true,
                ),
                SizedBox(height: layout.space4),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            context.pushNamed(AppRouteNames.inventoryCounts),
                        icon: const Icon(Icons.list_alt_rounded),
                        label: const Text('Ver sessoes'),
                      ),
                    ),
                    SizedBox(width: layout.space4),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed:
                            detail.session.status.canEdit &&
                                !actionState.isLoading
                            ? () => _addItem(itemOptions)
                            : null,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Adicionar item'),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: layout.space5),
                _InventoryCountSummaryPanel(detail: detail),
                SizedBox(height: layout.space5),
                AppSectionCard(
                  title: 'Aplicacao',
                  subtitle:
                      pendingReviewCount > 0
                      ? 'Existem itens desatualizados. Revise o saldo atual antes de aplicar o lote.'
                      : 'Revise a sessao antes de aplicar. O ajuste em lote usa a divergencia registrada em cada item.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (pendingReviewCount > 0) ...[
                        AppStateCard(
                          title: 'Sessao com itens desatualizados',
                          message:
                              '$pendingReviewCount item(ns) mudaram de saldo desde a contagem. Recalcule o saldo do sistema ou mantenha a divergencia conscientemente antes de aplicar.',
                          tone: AppStateTone.warning,
                          compact: true,
                        ),
                        SizedBox(height: layout.space4),
                      ],
                      Wrap(
                        spacing: layout.space3,
                        runSpacing: layout.space3,
                        children: [
                          AppStatusBadge(
                            label:
                                'Criada ${AppFormatters.shortDateTime(detail.session.createdAt)}',
                            tone: AppStatusTone.neutral,
                          ),
                          AppStatusBadge(
                            label:
                                '${detail.summary.readyItems} item(ns) prontos para aplicar',
                            tone: pendingReviewCount > 0
                                ? AppStatusTone.warning
                                : AppStatusTone.success,
                          ),
                          if (detail.session.appliedAt != null)
                            AppStatusBadge(
                              label:
                                  'Aplicada ${AppFormatters.shortDateTime(detail.session.appliedAt!)}',
                              tone: AppStatusTone.success,
                            ),
                          FilledButton.tonalIcon(
                            onPressed:
                                detail.session.status.canEdit &&
                                    !actionState.isLoading
                                ? () => _markReviewed(detail)
                                : null,
                            icon: const Icon(Icons.rule_folder_outlined),
                            label: const Text('Marcar revisada'),
                          ),
                          FilledButton.icon(
                            onPressed:
                                detail.session.status.canApply &&
                                    pendingReviewCount == 0 &&
                                    !actionState.isLoading
                                ? () => _applySession(detail)
                                : null,
                            icon: actionState.isLoading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.check_circle_outline_rounded,
                                  ),
                            label: const Text('Aplicar sessao'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: layout.space5),
                Wrap(
                  spacing: layout.space3,
                  runSpacing: layout.space3,
                  children: [
                    for (final filter in _InventoryCountItemFilter.values)
                      ChoiceChip(
                        label: Text(filter.label),
                        selected: _selectedFilter == filter,
                        onSelected: (_) =>
                            setState(() => _selectedFilter = filter),
                      ),
                  ],
                ),
                SizedBox(height: layout.space5),
                if (filteredItems.isEmpty)
                  const AppStateCard(
                    title: 'Nenhum item para o filtro',
                    message:
                        'Adicione itens a sessao ou ajuste o filtro para revisar outra parte da contagem.',
                  )
                else
                  for (final item in filteredItems) ...[
                    _InventoryCountItemTile(
                      item: item,
                      editable: detail.session.status.canEdit,
                      actionInProgress: actionState.isLoading,
                      onTap: detail.session.status.canEdit
                          ? () => _editItem(item)
                          : null,
                      onRecalculate:
                          detail.session.status.canEdit && !actionState.isLoading
                          ? () => _recalculateStaleItem(item)
                          : null,
                      onKeepDifference:
                          detail.session.status.canEdit && !actionState.isLoading
                          ? () => _keepRecordedDifference(item)
                          : null,
                    ),
                    SizedBox(height: layout.space4),
                  ],
              ],
            ),
          );
        },
        loading: () => Padding(
          padding: EdgeInsets.all(layout.pagePadding),
          child: const AppStateCard(
            title: 'Carregando sessao',
            message: 'Buscando itens e divergencias desta contagem.',
            tone: AppStateTone.loading,
            compact: true,
          ),
        ),
        error: (error, _) => Padding(
          padding: EdgeInsets.all(layout.pagePadding),
          child: AppStateCard(
            title: 'Falha ao carregar a sessao',
            message: '$error',
            tone: AppStateTone.error,
            compact: true,
            actionLabel: 'Tentar novamente',
            onAction: () => ref.invalidate(
              inventoryCountSessionDetailProvider(widget.sessionId),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _addItem(List<InventoryItem> itemOptions) async {
    if (itemOptions.isEmpty) {
      AppFeedback.error(
        context,
        'Nao ha itens ativos disponiveis para contar.',
      );
      return;
    }

    final selectedItem = await showModalBottomSheet<InventoryItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _InventoryCountItemPickerSheet(items: itemOptions),
    );
    if (selectedItem == null) {
      return;
    }
    if (!mounted) {
      return;
    }

    final result = await showModalBottomSheet<_CountItemSheetResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _InventoryCountItemEditorSheet(
        item: selectedItem,
        initialCountedStockMil: selectedItem.currentStockMil,
        initialNotes: null,
        systemStockMil: selectedItem.currentStockMil,
      ),
    );
    if (result == null) {
      return;
    }

    await _saveCountItem(
      productId: selectedItem.productId,
      productVariantId: selectedItem.productVariantId,
      countedStockMil: result.countedStockMil,
      notes: result.notes,
    );
  }

  Future<void> _editItem(InventoryCountItem item) async {
    final selectedItem = await ref
        .read(inventoryRepositoryProvider)
        .findItem(
          productId: item.productId,
          productVariantId: item.productVariantId,
        );
    if (selectedItem == null) {
      if (!mounted) {
        return;
      }
      AppFeedback.error(
        context,
        'Nao foi possivel localizar o item ativo para editar a contagem.',
      );
      return;
    }
    if (!mounted) {
      return;
    }

    final result = await showModalBottomSheet<_CountItemSheetResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _InventoryCountItemEditorSheet(
        item: selectedItem,
        initialCountedStockMil: item.countedStockMil,
        initialNotes: item.notes,
        systemStockMil: item.systemStockMil,
      ),
    );
    if (result == null) {
      return;
    }

    await _saveCountItem(
      productId: item.productId,
      productVariantId: item.productVariantId,
      countedStockMil: result.countedStockMil,
      notes: result.notes,
    );
  }

  Future<void> _saveCountItem({
    required int productId,
    required int? productVariantId,
    required int countedStockMil,
    required String? notes,
  }) async {
    try {
      await ref
          .read(inventoryCountActionControllerProvider.notifier)
          .upsertItem(
            InventoryCountItemInput(
              sessionId: widget.sessionId,
              productId: productId,
              productVariantId: productVariantId,
              countedStockMil: countedStockMil,
              notes: notes,
            ),
          );
      if (!mounted) {
        return;
      }
      AppFeedback.success(context, 'Item da contagem salvo com sucesso.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppFeedback.error(context, 'Nao foi possivel salvar a contagem: $error');
    }
  }

  Future<void> _markReviewed(InventoryCountSessionDetail detail) async {
    try {
      await ref
          .read(inventoryCountActionControllerProvider.notifier)
          .markSessionReviewed(detail.session.id);
      if (!mounted) {
        return;
      }
      AppFeedback.success(context, 'Sessao marcada como revisada.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppFeedback.error(context, 'Nao foi possivel revisar a sessao: $error');
    }
  }

  Future<void> _recalculateStaleItem(InventoryCountItem item) async {
    try {
      await ref
          .read(inventoryCountActionControllerProvider.notifier)
          .recalculateItemFromCurrentStock(item.id);
      if (!mounted) {
        return;
      }
      AppFeedback.success(
        context,
        'Saldo do sistema atualizado para ${item.displayName}.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppFeedback.error(context, 'Nao foi possivel revisar o item: $error');
    }
  }

  Future<void> _keepRecordedDifference(InventoryCountItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Manter divergencia registrada'),
          content: Text(
            'O saldo atual de "${item.displayName}" mudou desde a contagem. Se voce continuar, o lote aplicara a divergencia originalmente registrada, mesmo com o saldo atual diferente. Deseja manter essa divergencia conscientemente?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Voltar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Manter divergencia'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }

    try {
      await ref
          .read(inventoryCountActionControllerProvider.notifier)
          .keepRecordedDifference(item.id);
      if (!mounted) {
        return;
      }
      AppFeedback.success(
        context,
        'Divergencia mantida conscientemente para ${item.displayName}.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppFeedback.error(context, 'Nao foi possivel revisar o item: $error');
    }
  }

  Future<void> _applySession(InventoryCountSessionDetail detail) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Aplicar sessao'),
          content: Text(
            'Os ajustes desta sessao serao aplicados em lote e gravados no extrato de estoque. Deseja continuar com "${detail.session.name}"?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Aplicar'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }

    try {
      await ref
          .read(inventoryCountActionControllerProvider.notifier)
          .applySession(detail.session.id);
      if (!mounted) {
        return;
      }
      AppFeedback.success(
        context,
        'Sessao aplicada com sucesso no estoque atual.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppFeedback.error(context, 'Nao foi possivel aplicar a sessao: $error');
    }
  }
}

class _InventoryCountSummaryPanel extends StatelessWidget {
  const _InventoryCountSummaryPanel({required this.detail});

  final InventoryCountSessionDetail detail;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return Wrap(
      spacing: layout.space4,
      runSpacing: layout.space4,
      children: [
        SizedBox(
          width: 190,
          child: AppMetricCard(
            label: 'Itens contados',
            value: '${detail.summary.totalItems}',
            icon: Icons.qr_code_scanner_rounded,
            caption: 'Itens incluidos na sessao',
            accentColor: context.appColors.brand.base,
          ),
        ),
        SizedBox(
          width: 190,
          child: AppMetricCard(
            label: 'Com divergencia',
            value: '${detail.summary.itemsWithDifference}',
            icon: Icons.compare_arrows_rounded,
            caption: 'Precisam de ajuste em lote',
            accentColor: context.appColors.warning.base,
          ),
        ),
        SizedBox(
          width: 190,
          child: AppMetricCard(
            label: 'Desatualizados',
            value: '${detail.summary.staleItems}',
            icon: Icons.sync_problem_rounded,
            caption: 'Mudaram desde a contagem',
            accentColor: context.appColors.danger.base,
          ),
        ),
        SizedBox(
          width: 190,
          child: AppMetricCard(
            label: 'Prontos',
            value: '${detail.summary.readyItems}',
            icon: Icons.task_alt_rounded,
            caption: 'Sem revisao pendente',
            accentColor: context.appColors.success.base,
          ),
        ),
        SizedBox(
          width: 190,
          child: AppMetricCard(
            label: 'Sobra total',
            value: AppFormatters.quantityFromMil(detail.summary.surplusMil),
            icon: Icons.arrow_circle_up_outlined,
            caption: 'Diferenca positiva apurada',
            accentColor: context.appColors.success.base,
          ),
        ),
        SizedBox(
          width: 190,
          child: AppMetricCard(
            label: 'Falta total',
            value: AppFormatters.quantityFromMil(detail.summary.shortageMil),
            icon: Icons.arrow_circle_down_outlined,
            caption: 'Diferenca negativa apurada',
            accentColor: context.appColors.danger.base,
          ),
        ),
      ],
    );
  }
}

class _InventoryCountItemTile extends StatelessWidget {
  const _InventoryCountItemTile({
    required this.item,
    required this.editable,
    required this.actionInProgress,
    required this.onTap,
    required this.onRecalculate,
    required this.onKeepDifference,
  });

  final InventoryCountItem item;
  final bool editable;
  final bool actionInProgress;
  final VoidCallback? onTap;
  final VoidCallback? onRecalculate;
  final VoidCallback? onKeepDifference;

  @override
  Widget build(BuildContext context) {
    final differenceLabel =
        '${item.differenceMil > 0 ? '+' : ''}${AppFormatters.quantityFromMil(item.differenceMil)} ${item.unitMeasure}';
    final subtitleParts = <String>[
      if ((item.sku ?? '').trim().isNotEmpty) 'SKU ${item.sku!.trim()}',
      'Contagem ${AppFormatters.quantityFromMil(item.systemStockMil)} ${item.unitMeasure}',
      'Atual ${AppFormatters.quantityFromMil(item.currentStockMil)} ${item.unitMeasure}',
    ];
    final hasFooter =
        item.isStale ||
        (item.notes ?? '').trim().isNotEmpty;
    return AppListTileCard(
      title: item.displayName,
      subtitle: subtitleParts.join('  |  '),
      badges: [
        AppStatusBadge(
          label:
              'Contado ${AppFormatters.quantityFromMil(item.countedStockMil)} ${item.unitMeasure}',
          tone: AppStatusTone.info,
        ),
        AppStatusBadge(
          label: 'Divergencia $differenceLabel',
          tone: item.differenceMil == 0
              ? AppStatusTone.success
              : item.differenceMil > 0
              ? AppStatusTone.success
              : AppStatusTone.warning,
        ),
        if (item.hasVariant)
          const AppStatusBadge(label: 'Variante', tone: AppStatusTone.neutral),
        if (item.needsReview)
          const AppStatusBadge(
            label: 'Desatualizado',
            tone: AppStatusTone.warning,
          ),
        if (item.usesFrozenDifference)
          const AppStatusBadge(
            label: 'Divergencia mantida',
            tone: AppStatusTone.neutral,
          ),
        if (item.isZeroed)
          const AppStatusBadge(label: 'Zerado', tone: AppStatusTone.warning),
      ],
      footer: hasFooter
          ? _InventoryCountItemFooter(
              item: item,
              editable: editable,
              actionInProgress: actionInProgress,
              onRecalculate: onRecalculate,
              onKeepDifference: onKeepDifference,
            )
          : null,
      onTap: editable ? onTap : null,
    );
  }
}

class _InventoryCountItemFooter extends StatelessWidget {
  const _InventoryCountItemFooter({
    required this.item,
    required this.editable,
    required this.actionInProgress,
    required this.onRecalculate,
    required this.onKeepDifference,
  });

  final InventoryCountItem item;
  final bool editable;
  final bool actionInProgress;
  final VoidCallback? onRecalculate;
  final VoidCallback? onKeepDifference;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final notes = (item.notes ?? '').trim();
    final children = <Widget>[];

    if (item.isStale) {
      children.add(
        Text(
          'Saldo na contagem: ${AppFormatters.quantityFromMil(item.systemStockMil)} ${item.unitMeasure}  |  '
          'Saldo atual: ${AppFormatters.quantityFromMil(item.currentStockMil)} ${item.unitMeasure}  |  '
          'Divergencia registrada: ${item.differenceMil > 0 ? '+' : ''}${AppFormatters.quantityFromMil(item.differenceMil)} ${item.unitMeasure}',
        ),
      );
    }

    if (notes.isNotEmpty) {
      if (children.isNotEmpty) {
        children.add(SizedBox(height: layout.space3));
      }
      children.add(Text(notes));
    }

    if (editable && item.isStale) {
      if (children.isNotEmpty) {
        children.add(SizedBox(height: layout.space4));
      }
      children.add(
        Wrap(
          spacing: layout.space3,
          runSpacing: layout.space3,
          children: [
            FilledButton.tonalIcon(
              onPressed: actionInProgress ? null : onRecalculate,
              icon: const Icon(Icons.sync_alt_rounded),
              label: const Text('Atualizar saldo do sistema'),
            ),
            OutlinedButton.icon(
              onPressed: actionInProgress ? null : onKeepDifference,
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('Manter divergencia'),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

enum _InventoryCountItemFilter { all, withDifference, stale, zeroed, variants }

extension on _InventoryCountItemFilter {
  String get label {
    return switch (this) {
      _InventoryCountItemFilter.all => 'Todos',
      _InventoryCountItemFilter.withDifference => 'Com divergencia',
      _InventoryCountItemFilter.stale => 'Desatualizados',
      _InventoryCountItemFilter.zeroed => 'Zerados',
      _InventoryCountItemFilter.variants => 'Variantes',
    };
  }

  bool matches(InventoryCountItem item) {
    return switch (this) {
      _InventoryCountItemFilter.all => true,
      _InventoryCountItemFilter.withDifference => item.hasDifference,
      _InventoryCountItemFilter.stale => item.isStale,
      _InventoryCountItemFilter.zeroed => item.isZeroed,
      _InventoryCountItemFilter.variants => item.hasVariant,
    };
  }
}

class _InventoryCountItemPickerSheet extends StatefulWidget {
  const _InventoryCountItemPickerSheet({required this.items});

  final List<InventoryItem> items;

  @override
  State<_InventoryCountItemPickerSheet> createState() =>
      _InventoryCountItemPickerSheetState();
}

class _InventoryCountItemPickerSheetState
    extends State<_InventoryCountItemPickerSheet> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final filteredItems = widget.items
        .where(_matchesSearch)
        .toList(growable: false);

    return AppBottomSheetContainer(
      title: 'Selecionar item',
      subtitle: 'Escolha o produto simples ou a variante que sera contada.',
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(
          children: [
            AppSearchField(
              controller: _searchController,
              hintText: 'Buscar nome, SKU, cor ou tamanho',
              onChanged: (_) => setState(() {}),
              onClear: () {
                _searchController.clear();
                setState(() {});
              },
            ),
            SizedBox(height: layout.space4),
            Expanded(
              child: filteredItems.isEmpty
                  ? const AppStateCard(
                      title: 'Nenhum item encontrado',
                      message:
                          'Tente outra busca para localizar o SKU que deseja contar.',
                      compact: true,
                    )
                  : ListView.separated(
                      itemCount: filteredItems.length,
                      separatorBuilder: (_, __) =>
                          SizedBox(height: layout.space3),
                      itemBuilder: (context, index) {
                        final item = filteredItems[index];
                        return AppListTileCard(
                          title: item.displayName,
                          subtitle: (item.sku ?? '').trim().isEmpty
                              ? 'Produto ativo'
                              : 'SKU ${item.sku!.trim()}',
                          badges: [
                            AppStatusBadge(
                              label:
                                  'Saldo ${AppFormatters.quantityFromMil(item.currentStockMil)} ${item.unitMeasure}',
                              tone: AppStatusTone.info,
                            ),
                          ],
                          onTap: () => Navigator.of(context).pop(item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  bool _matchesSearch(InventoryItem item) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }

    final haystack = [
      item.productName,
      item.sku,
      item.variantColorLabel,
      item.variantSizeLabel,
    ].whereType<String>().join(' ').toLowerCase();
    return haystack.contains(query);
  }
}

class _InventoryCountItemEditorSheet extends StatefulWidget {
  const _InventoryCountItemEditorSheet({
    required this.item,
    required this.initialCountedStockMil,
    required this.initialNotes,
    required this.systemStockMil,
  });

  final InventoryItem item;
  final int initialCountedStockMil;
  final String? initialNotes;
  final int systemStockMil;

  @override
  State<_InventoryCountItemEditorSheet> createState() =>
      _InventoryCountItemEditorSheetState();
}

class _InventoryCountItemEditorSheetState
    extends State<_InventoryCountItemEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _countedController;
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _countedController = TextEditingController(
      text: AppFormatters.quantityFromMil(widget.initialCountedStockMil),
    );
    _notesController = TextEditingController(text: widget.initialNotes ?? '');
  }

  @override
  void dispose() {
    _countedController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return AppBottomSheetContainer(
      title: widget.item.displayName,
      subtitle:
          'Informe a quantidade contada. O estoque do sistema fica congelado no momento da inclusao do item.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: layout.space3,
              runSpacing: layout.space3,
              children: [
                AppStatusBadge(
                  label:
                      'Sistema ${AppFormatters.quantityFromMil(widget.systemStockMil)} ${widget.item.unitMeasure}',
                  tone: AppStatusTone.info,
                ),
                if ((widget.item.sku ?? '').trim().isNotEmpty)
                  AppStatusBadge(
                    label: 'SKU ${widget.item.sku!.trim()}',
                    tone: AppStatusTone.neutral,
                  ),
              ],
            ),
            SizedBox(height: layout.space4),
            TextFormField(
              controller: _countedController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Quantidade contada',
                hintText: 'Ex.: 1 ou 1,250',
              ),
              validator: (value) {
                if (QuantityParser.parseToMil(value ?? '') < 0) {
                  return 'A quantidade contada nao pode ser negativa';
                }
                return null;
              },
            ),
            SizedBox(height: layout.space4),
            TextFormField(
              controller: _notesController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Observacao',
                hintText: 'Opcional',
              ),
            ),
            SizedBox(height: layout.space5),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Salvar item'),
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    Navigator.of(context).pop(
      _CountItemSheetResult(
        countedStockMil: QuantityParser.parseToMil(_countedController.text),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      ),
    );
  }
}

class _CountItemSheetResult {
  const _CountItemSheetResult({
    required this.countedStockMil,
    required this.notes,
  });

  final int countedStockMil;
  final String? notes;
}
