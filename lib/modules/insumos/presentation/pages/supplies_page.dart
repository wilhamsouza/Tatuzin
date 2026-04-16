import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_feedback.dart';
import '../../../../app/core/widgets/app_list_tile_card.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_quick_action_card.dart';
import '../../../../app/core/widgets/app_search_field.dart';
import '../../../../app/core/widgets/app_state_card.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../../app/routes/route_names.dart';
import '../../../../app/theme/app_design_tokens.dart';
import '../../domain/entities/supply_inventory.dart';
import '../providers/supply_providers.dart';

class SuppliesPage extends ConsumerStatefulWidget {
  const SuppliesPage({super.key});

  @override
  ConsumerState<SuppliesPage> createState() => _SuppliesPageState();
}

class _SuppliesPageState extends ConsumerState<SuppliesPage> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: ref.read(supplySearchQueryProvider),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final suppliesAsync = ref.watch(supplyInventoryOverviewProvider);
    final layout = context.appLayout;

    return Scaffold(
      appBar: AppBar(title: const Text('Insumos')),
      drawer: const AppMainDrawer(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await context.pushNamed(AppRouteNames.supplyForm);
          if (created == true) {
            ref.invalidate(supplyInventoryOverviewProvider);
          }
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Novo insumo'),
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              layout.pagePadding,
              layout.space5,
              layout.pagePadding,
              layout.space4,
            ),
            child: const AppPageHeader(
              title: 'Insumos',
              subtitle:
                  'Cadastre materia-prima, embalagem e itens de composicao sem misturar com despesas operacionais.',
              badgeLabel: 'Composicao',
              badgeIcon: Icons.scale_rounded,
              emphasized: true,
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              layout.pagePadding,
              0,
              layout.pagePadding,
              layout.space4,
            ),
            child: Column(
              children: [
                AppQuickActionCard(
                  title: 'Movimentacoes operacionais',
                  subtitle:
                      'Consulte entradas, saidas, ajustes e estornos do ledger local.',
                  icon: Icons.inventory_2_outlined,
                  onTap: () => context.pushNamed(AppRouteNames.supplyInventory),
                ),
                SizedBox(height: layout.space4),
                AppQuickActionCard(
                  title: 'Sugestao de recompra',
                  subtitle:
                      'Veja rapidamente os insumos ativos abaixo do minimo.',
                  icon: Icons.shopping_bag_outlined,
                  onTap: () =>
                      context.pushNamed(AppRouteNames.reorderSuggestions),
                  palette: context.appColors.warning,
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              layout.pagePadding,
              0,
              layout.pagePadding,
              layout.space5,
            ),
            child: AppSearchField(
              controller: _searchController,
              hintText: 'Buscar por nome, SKU ou fornecedor',
              onChanged: (value) {
                ref.read(supplySearchQueryProvider.notifier).state = value;
                setState(() {});
              },
              onClear: () {
                _searchController.clear();
                ref.read(supplySearchQueryProvider.notifier).state = '';
                setState(() {});
              },
            ),
          ),
          Expanded(
            child: suppliesAsync.when(
              data: (supplies) {
                if (supplies.isEmpty) {
                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                      layout.pagePadding,
                      layout.space4,
                      layout.pagePadding,
                      92,
                    ),
                    child: AppStateCard(
                      title: 'Nenhum insumo cadastrado',
                      message:
                          'Cadastre ingredientes, embalagem ou componentes para montar fichas tecnicas.',
                      actionLabel: 'Novo insumo',
                      onAction: () =>
                          context.pushNamed(AppRouteNames.supplyForm),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(supplyInventoryOverviewProvider);
                    await ref.read(supplyInventoryOverviewProvider.future);
                  },
                  child: ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                      layout.pagePadding,
                      0,
                      layout.pagePadding,
                      92,
                    ),
                    itemCount: supplies.length,
                    separatorBuilder: (_, __) =>
                        SizedBox(height: layout.space4),
                    itemBuilder: (context, index) {
                      final supply = supplies[index];
                      return _SupplyTile(supply: supply);
                    },
                  ),
                );
              },
              loading: () => Padding(
                padding: EdgeInsets.all(layout.pagePadding),
                child: const AppStateCard(
                  title: 'Carregando insumos',
                  message: 'Buscando cadastro local de insumos.',
                  tone: AppStateTone.loading,
                  compact: true,
                ),
              ),
              error: (error, _) => Center(
                child: Padding(
                  padding: EdgeInsets.all(layout.pagePadding),
                  child: AppStateCard(
                    title: 'Falha ao carregar insumos',
                    message: '$error',
                    tone: AppStateTone.error,
                    compact: true,
                    actionLabel: 'Tentar novamente',
                    onAction: () =>
                        ref.invalidate(supplyInventoryOverviewProvider),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SupplyTile extends ConsumerWidget {
  const _SupplyTile({required this.supply});

  final SupplyInventoryOverview supply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unitType = supply.supply.unitType;
    final stockLabel =
        !supply.hasOperationalBaseline || supply.currentStockMil == null
        ? 'Sem baseline operacional'
        : 'Saldo ${AppFormatters.quantityFromMil(supply.currentStockMil!)} $unitType';
    final minimumLabel = supply.minimumStockMil == null
        ? 'Sem minimo'
        : 'Minimo ${AppFormatters.quantityFromMil(supply.minimumStockMil!)} $unitType';

    return AppListTileCard(
      title: supply.supply.name,
      subtitle:
          '${supply.supply.purchaseUnitType} -> ${supply.supply.unitType} • fator ${supply.supply.normalizedConversionFactor}',
      leading: DecoratedBox(
        decoration: BoxDecoration(
          color: supply.supply.isActive
              ? context.appColors.brand.surface
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(context.appLayout.radiusMd),
        ),
        child: Padding(
          padding: EdgeInsets.all(context.appLayout.space4),
          child: Icon(
            Icons.inventory_2_outlined,
            size: context.appLayout.iconLg,
            color: supply.supply.isActive
                ? context.appColors.brand.base
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      badges: [
        AppStatusBadge(
          label: supply.supply.isActive ? 'Ativo' : 'Inativo',
          tone: supply.supply.isActive
              ? AppStatusTone.success
              : AppStatusTone.neutral,
        ),
        AppStatusBadge(
          label:
              'Ultima compra ${AppFormatters.currencyFromCents(supply.supply.lastPurchasePriceCents)}',
          tone: AppStatusTone.info,
        ),
        AppStatusBadge(
          label:
              'Custo uso ${AppFormatters.currencyFromCents(supply.supply.usageUnitCostCentsRounded)}/$unitType',
          tone: AppStatusTone.info,
        ),
        AppStatusBadge(label: stockLabel, tone: AppStatusTone.neutral),
        AppStatusBadge(label: minimumLabel, tone: AppStatusTone.neutral),
        AppStatusBadge(label: supply.statusLabel, tone: _statusTone(supply)),
      ],
      footer: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => context.pushNamed(
                AppRouteNames.supplyInventory,
                extra: supply.supply.id,
              ),
              icon: const Icon(Icons.history_rounded),
              label: const Text('Movimentos'),
            ),
          ),
          SizedBox(width: context.appLayout.space4),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _openEditor(context, ref),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Editar'),
            ),
          ),
          SizedBox(width: context.appLayout.space4),
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: supply.supply.isActive
                  ? () => _deactivate(context, ref)
                  : null,
              icon: const Icon(Icons.pause_circle_outline_rounded),
              label: const Text('Desativar'),
            ),
          ),
        ],
      ),
      onTap: () => _openEditor(context, ref),
    );
  }

  Future<void> _openEditor(BuildContext context, WidgetRef ref) async {
    final updated = await context.pushNamed(
      AppRouteNames.supplyForm,
      extra: supply.supply,
    );
    if (updated == true) {
      ref.invalidate(supplyInventoryOverviewProvider);
    }
  }

  Future<void> _deactivate(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Desativar insumo'),
          content: Text(
            'Deseja desativar "${supply.supply.name}"? Ele deixara de aparecer para novas fichas tecnicas.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Desativar'),
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
          .read(supplyActionControllerProvider.notifier)
          .deactivateSupply(supply.supply.id);
      ref.invalidate(supplyInventoryOverviewProvider);
      if (!context.mounted) {
        return;
      }
      AppFeedback.success(
        context,
        'Insumo "${supply.supply.name}" desativado.',
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      AppFeedback.error(context, 'Nao foi possivel desativar o insumo: $error');
    }
  }

  AppStatusTone _statusTone(SupplyInventoryOverview overview) {
    return switch (overview.inventoryStatus) {
      SupplyInventoryStatus.critical => AppStatusTone.danger,
      SupplyInventoryStatus.low => AppStatusTone.warning,
      SupplyInventoryStatus.normal => AppStatusTone.success,
      SupplyInventoryStatus.unknown => AppStatusTone.neutral,
    };
  }
}
