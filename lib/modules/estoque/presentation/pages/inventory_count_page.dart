import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_card.dart';
import '../../../../app/core/widgets/app_feedback.dart';
import '../../../../app/core/widgets/app_list_tile_card.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_state_card.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../../app/routes/route_names.dart';
import '../../../../app/core/theme/app_design_tokens.dart';
import '../../domain/entities/inventory_count_session.dart';
import '../providers/inventory_providers.dart';

class InventoryCountPage extends ConsumerStatefulWidget {
  const InventoryCountPage({super.key});

  @override
  ConsumerState<InventoryCountPage> createState() => _InventoryCountPageState();
}

class _InventoryCountPageState extends ConsumerState<InventoryCountPage> {
  _InventoryCountStatusFilter _selectedFilter = _InventoryCountStatusFilter.all;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final sessionsAsync = ref.watch(inventoryCountSessionsProvider);
    final actionState = ref.watch(inventoryCountActionControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Inventário físico')),
      drawer: const AppMainDrawer(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: actionState.isLoading ? null : _createSession,
        icon: const Icon(Icons.add_task_rounded),
        label: const Text('Nova sessão'),
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              layout.pagePadding,
              layout.space4,
              layout.pagePadding,
              layout.space3,
            ),
            child: const AppPageHeader(
              title: 'Inventário físico',
              subtitle:
                  'Conte produtos, revise divergências e aplique ajustes com auditoria.',
              badgeLabel: 'Contagem',
              badgeIcon: Icons.fact_check_rounded,
              emphasized: true,
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              layout.pagePadding,
              0,
              layout.pagePadding,
              layout.space3,
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.goNamed(AppRouteNames.inventory),
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: const Text('Estoque atual'),
                  ),
                ),
                SizedBox(width: layout.space4),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: actionState.isLoading ? null : _createSession,
                    icon: const Icon(Icons.add_task_rounded),
                    label: const Text('Nova sessão'),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: layout.pagePadding),
              itemCount: _InventoryCountStatusFilter.values.length,
              separatorBuilder: (_, __) => SizedBox(width: layout.space3),
              itemBuilder: (context, index) {
                final filter = _InventoryCountStatusFilter.values[index];
                return ChoiceChip(
                  label: Text(filter.label),
                  selected: _selectedFilter == filter,
                  onSelected: (_) => setState(() => _selectedFilter = filter),
                );
              },
            ),
          ),
          Expanded(
            child: sessionsAsync.when(
              data: (sessions) {
                final filteredSessions = sessions
                    .where((session) => _selectedFilter.matches(session.status))
                    .toList(growable: false);
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(inventoryCountSessionsProvider);
                    await ref.read(inventoryCountSessionsProvider.future);
                  },
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      layout.pagePadding,
                      0,
                      layout.pagePadding,
                      layout.pagePadding * 2,
                    ),
                    children: [
                      _InventoryCountOverviewPanel(sessions: sessions),
                      SizedBox(height: layout.space4),
                      if (filteredSessions.isEmpty)
                        const AppStateCard(
                          title: 'Nenhuma sessao encontrada',
                          message:
                              'Crie uma nova sessao para iniciar a contagem fisica do estoque.',
                        )
                      else
                        for (final session in filteredSessions) ...[
                          _InventoryCountSessionTile(session: session),
                          SizedBox(height: layout.space4),
                        ],
                    ],
                  ),
                );
              },
              loading: () => Padding(
                padding: EdgeInsets.all(layout.pagePadding),
                child: const AppStateCard(
                  title: 'Carregando sessoes',
                  message: 'Buscando as sessoes de inventario do dispositivo.',
                  tone: AppStateTone.loading,
                  compact: true,
                ),
              ),
              error: (error, _) => Padding(
                padding: EdgeInsets.all(layout.pagePadding),
                child: AppStateCard(
                  title: 'Falha ao carregar inventarios',
                  message: '$error',
                  tone: AppStateTone.error,
                  compact: true,
                  actionLabel: 'Tentar novamente',
                  onAction: () =>
                      ref.invalidate(inventoryCountSessionsProvider),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createSession() async {
    final controller = TextEditingController();
    final sessionName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Nova sessão de inventário'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nome da sessao',
              hintText: 'Ex.: Inventário loja abril',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('Criar'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (sessionName == null) {
      return;
    }

    try {
      final session = await ref
          .read(inventoryCountActionControllerProvider.notifier)
          .createSession(sessionName);
      if (!mounted) {
        return;
      }
      AppFeedback.success(context, 'Sessao criada com sucesso.');
      context.pushNamed(
        AppRouteNames.inventoryCountSessionDetail,
        pathParameters: {'sessionId': '${session.id}'},
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppFeedback.error(context, 'Nao foi possivel criar a sessao: $error');
    }
  }
}

class _InventoryCountOverviewPanel extends StatelessWidget {
  const _InventoryCountOverviewPanel({required this.sessions});

  final List<InventoryCountSession> sessions;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final openCount = sessions
        .where(
          (session) =>
              session.status == InventoryCountSessionStatus.open ||
              session.status == InventoryCountSessionStatus.counting,
        )
        .length;
    final reviewedCount = sessions
        .where(
          (session) => session.status == InventoryCountSessionStatus.reviewed,
        )
        .length;
    final appliedCount = sessions
        .where(
          (session) => session.status == InventoryCountSessionStatus.applied,
        )
        .length;

    return Wrap(
      spacing: layout.space3,
      runSpacing: layout.space3,
      children: [
        _InventoryCountMetricTile(
          label: 'Em andamento',
          value: '$openCount',
          icon: Icons.playlist_add_check_circle_rounded,
          accentColor: context.appColors.warning.base,
        ),
        _InventoryCountMetricTile(
          label: 'Revisadas',
          value: '$reviewedCount',
          icon: Icons.rule_folder_outlined,
          accentColor: context.appColors.brand.base,
        ),
        _InventoryCountMetricTile(
          label: 'Aplicadas',
          value: '$appliedCount',
          icon: Icons.check_circle_outline_rounded,
          accentColor: context.appColors.success.base,
        ),
      ],
    );
  }
}

class _InventoryCountMetricTile extends StatelessWidget {
  const _InventoryCountMetricTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.accentColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 112, maxWidth: 178),
      child: AppCard(
        padding: EdgeInsets.all(layout.compactCardPadding - 1),
        borderRadius: layout.radiusLg,
        color: accentColor.withValues(alpha: 0.08),
        borderColor: accentColor.withValues(alpha: 0.12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: accentColor, size: 18),
            SizedBox(width: layout.space3),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InventoryCountSessionTile extends StatelessWidget {
  const _InventoryCountSessionTile({required this.session});

  final InventoryCountSession session;

  @override
  Widget build(BuildContext context) {
    final badges = <Widget>[
      AppStatusBadge(
        label: session.status.label,
        tone: switch (session.status) {
          InventoryCountSessionStatus.open => AppStatusTone.neutral,
          InventoryCountSessionStatus.counting => AppStatusTone.warning,
          InventoryCountSessionStatus.reviewed => AppStatusTone.info,
          InventoryCountSessionStatus.applied => AppStatusTone.success,
          InventoryCountSessionStatus.canceled => AppStatusTone.danger,
        },
      ),
      AppStatusBadge(
        label: '${session.totalItems} itens',
        tone: AppStatusTone.neutral,
      ),
      AppStatusBadge(
        label: '${session.itemsWithDifference} com divergencia',
        tone: session.itemsWithDifference > 0
            ? AppStatusTone.warning
            : AppStatusTone.success,
      ),
      if (session.surplusMil > 0)
        AppStatusBadge(
          label: 'Sobra ${AppFormatters.quantityFromMil(session.surplusMil)}',
          tone: AppStatusTone.success,
        ),
      if (session.shortageMil > 0)
        AppStatusBadge(
          label: 'Falta ${AppFormatters.quantityFromMil(session.shortageMil)}',
          tone: AppStatusTone.warning,
        ),
    ];

    return AppListTileCard(
      title: session.name,
      subtitle:
          'Criada em ${AppFormatters.shortDateTime(session.createdAt)}${session.appliedAt == null ? '' : '  |  Aplicada em ${AppFormatters.shortDateTime(session.appliedAt!)}'}',
      badges: badges,
      onTap: () => context.pushNamed(
        AppRouteNames.inventoryCountSessionDetail,
        pathParameters: {'sessionId': '${session.id}'},
      ),
    );
  }
}

enum _InventoryCountStatusFilter { all, open, reviewed, applied }

extension on _InventoryCountStatusFilter {
  String get label {
    return switch (this) {
      _InventoryCountStatusFilter.all => 'Todas',
      _InventoryCountStatusFilter.open => 'Abertas',
      _InventoryCountStatusFilter.reviewed => 'Revisadas',
      _InventoryCountStatusFilter.applied => 'Aplicadas',
    };
  }

  bool matches(InventoryCountSessionStatus status) {
    return switch (this) {
      _InventoryCountStatusFilter.all => true,
      _InventoryCountStatusFilter.open =>
        status == InventoryCountSessionStatus.open ||
            status == InventoryCountSessionStatus.counting,
      _InventoryCountStatusFilter.reviewed =>
        status == InventoryCountSessionStatus.reviewed,
      _InventoryCountStatusFilter.applied =>
        status == InventoryCountSessionStatus.applied,
    };
  }
}
