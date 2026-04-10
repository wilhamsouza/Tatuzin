import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/widgets/app_section_card.dart';
import '../mappers/order_ticket_mapper.dart';
import '../providers/order_providers.dart';

class OrderTicketPreviewPage extends ConsumerWidget {
  const OrderTicketPreviewPage({super.key, required this.orderId});

  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(operationalOrderDetailProvider(orderId));

    return Scaffold(
      appBar: AppBar(title: const Text('Ticket operacional')),
      body: detailAsync.when(
        data: (detail) {
          if (detail == null) {
            return const Center(child: Text('Pedido nao encontrado.'));
          }

          final ticket = OrderTicketMapper.fromDetail(detail);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              AppSectionCard(
                title: 'Preview local',
                subtitle:
                    'Este ticket operacional e interno e nao substitui comprovante comercial.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pedido ${ticket.orderNumber}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text('Status: ${ticket.statusLabel}'),
                    Text('Atualizado: ${ticket.updatedAtLabel}'),
                    if (ticket.headerNotes?.trim().isNotEmpty ?? false)
                      Text('Obs.: ${ticket.headerNotes!}'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              for (final line in ticket.lines) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          line.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${line.quantityLabel} x ${line.unitPriceLabel} = ${line.totalPriceLabel}',
                        ),
                        if (line.modifierLines.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          ...line.modifierLines.map(
                            (modifier) => Text(
                              modifier,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                        if (line.notes?.trim().isNotEmpty ?? false) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Obs.: ${line.notes!}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Expanded(child: Text('Total operacional')),
                      Text(
                        ticket.totalLabel,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Falha ao montar ticket: $error')),
      ),
    );
  }
}
