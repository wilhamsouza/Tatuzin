import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/widgets/app_section_card.dart';
import '../../domain/entities/order_ticket_document.dart';
import '../mappers/order_ticket_mapper.dart';
import '../providers/order_print_providers.dart';
import '../providers/order_providers.dart';
import '../support/order_ui_support.dart';
import '../widgets/kitchen_printer_config_dialog.dart';

class OrderTicketPreviewPage extends ConsumerStatefulWidget {
  const OrderTicketPreviewPage({super.key, required this.orderId});

  final int orderId;

  @override
  ConsumerState<OrderTicketPreviewPage> createState() =>
      _OrderTicketPreviewPageState();
}

class _OrderTicketPreviewPageState
    extends ConsumerState<OrderTicketPreviewPage> {
  OrderTicketProfile _profile = OrderTicketProfile.kitchen;

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(
      operationalOrderDetailProvider(widget.orderId),
    );
    final ticketAsync = ref.watch(
      orderTicketDocumentProvider((orderId: widget.orderId, profile: _profile)),
    );
    final reprintState = ref.watch(orderTicketReprintControllerProvider);
    final printerAsync = ref.watch(kitchenPrinterConfigProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Preview tecnico do ticket'),
        actions: [
          IconButton(
            tooltip: 'Configurar impressora',
            onPressed: _openPrinterConfig,
            icon: const Icon(Icons.print_outlined),
          ),
        ],
      ),
      body: ticketAsync.when(
        data: (ticket) {
          final viewModel = OrderTicketMapper.fromDocument(ticket);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            children: [
              detailAsync.maybeWhen(
                data: (detail) {
                  if (detail == null) {
                    return const SizedBox.shrink();
                  }
                  return AppSectionCard(
                    title: 'Uso deste preview',
                    subtitle:
                        'Fallback tecnico para conferencia visual, diagnostico e comparacao com a impressao real.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Status do ticket: ${orderTicketDispatchStatusLabel(detail.order.ticketMeta.status)}',
                        ),
                        const SizedBox(height: 4),
                        Text(
                          printerAsync.maybeWhen(
                            data: (config) => config == null
                                ? 'Impressora: nao configurada'
                                : 'Impressora: ${config.displayName} | ${config.targetLabel}',
                            orElse: () => 'Impressora: carregando...',
                          ),
                        ),
                      ],
                    ),
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Cozinha'),
                    selected: _profile == OrderTicketProfile.kitchen,
                    onSelected: (_) {
                      setState(() => _profile = OrderTicketProfile.kitchen);
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Interno'),
                    selected: _profile == OrderTicketProfile.internal,
                    onSelected: (_) {
                      setState(() => _profile = OrderTicketProfile.internal);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppSectionCard(
                title: viewModel.title,
                subtitle: _profile == OrderTicketProfile.kitchen
                    ? 'Representacao visual da comanda enviada para cozinha.'
                    : 'Visual tecnico do documento interno usado para conferencia.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pedido ${viewModel.orderNumber}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${viewModel.profileLabel} | ${viewModel.statusLabel}',
                    ),
                    if (viewModel.businessName?.trim().isNotEmpty ?? false) ...[
                      const SizedBox(height: 4),
                      Text(viewModel.businessName!),
                    ],
                    if (viewModel.headerNotes?.trim().isNotEmpty ?? false) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('Obs.: ${viewModel.headerNotes!}'),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              AppSectionCard(
                title: 'Cabecalho do ticket',
                child: Column(
                  children: viewModel.infoLines
                      .map(
                        (line) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              Expanded(child: Text(line.label)),
                              const SizedBox(width: 12),
                              Text(
                                line.value,
                                textAlign: TextAlign.right,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
              const SizedBox(height: 12),
              for (final line in viewModel.lines) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${line.quantityLabel}x',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    line.title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(line.summaryLabel),
                                ],
                              ),
                            ),
                            if (line.totalLabel != null)
                              Text(
                                line.totalLabel!,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                          ],
                        ),
                        if (line.modifierLines.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          ...line.modifierLines.map(
                            (modifier) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(modifier),
                            ),
                          ),
                        ],
                        if (line.notes?.trim().isNotEmpty ?? false) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .errorContainer
                                  .withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('Obs.: ${line.notes!}'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (viewModel.showFinancialSummary)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        const Expanded(child: Text('Total operacional')),
                        Text(
                          viewModel.totalLabel,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ),
              if (viewModel.footerLines.isNotEmpty) ...[
                const SizedBox(height: 12),
                AppSectionCard(
                  title: 'Rodape',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: viewModel.footerLines
                        .map(
                          (line) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(line),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
              ],
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Falha ao montar ticket: $error')),
      ),
      bottomNavigationBar: _profile == OrderTicketProfile.kitchen
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton.icon(
                onPressed: reprintState.isLoading ? null : _reprint,
                icon: reprintState.isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.print_rounded),
                label: Text(
                  reprintState.isLoading
                      ? 'Reimprimindo...'
                      : 'Reimprimir ticket',
                ),
              ),
            )
          : null,
    );
  }

  Future<void> _reprint() async {
    final result = await ref
        .read(orderTicketReprintControllerProvider.notifier)
        .reprint(widget.orderId);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            result.hasFailure
                ? 'Falha ao reimprimir: ${result.failureMessage}'
                : 'Ticket reimpresso com sucesso.',
          ),
        ),
      );
  }

  Future<void> _openPrinterConfig() async {
    final config = await ref.read(kitchenPrinterConfigProvider.future);
    if (!mounted) {
      return;
    }

    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => KitchenPrinterConfigDialog(initialConfig: config),
    );

    if (updated == true && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Configuracao da impressora atualizada.'),
          ),
        );
    }
  }
}
