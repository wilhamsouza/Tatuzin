import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/utils/money_parser.dart';
import '../../../../app/core/widgets/app_feedback.dart';
import '../../../../app/routes/route_names.dart';
import '../../domain/entities/client.dart';
import '../providers/client_providers.dart';

Future<void> openCustomerCreditActionDialog(
  BuildContext context,
  WidgetRef ref, {
  required Client? client,
  required bool isCredit,
}) async {
  if (client == null) {
    AppFeedback.error(
      context,
      'Cliente nao foi encontrado para esta movimentacao.',
    );
    return;
  }

  final amountController = TextEditingController();
  final descriptionController = TextEditingController();
  final submitted = await showDialog<(int, String?)>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(isCredit ? 'Adicionar haver' : 'Registrar pendencia'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Valor'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(
                labelText: 'Descricao',
                hintText: 'Opcional',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop((
                MoneyParser.parseToCents(amountController.text),
                descriptionController.text.trim().isEmpty
                    ? null
                    : descriptionController.text.trim(),
              ));
            },
            child: const Text('Confirmar'),
          ),
        ],
      );
    },
  );
  amountController.dispose();
  descriptionController.dispose();

  if (submitted == null) {
    return;
  }

  try {
    final controller = ref.read(customerCreditControllerProvider.notifier);
    final transaction = isCredit
        ? await controller.addManualCredit(
            customerId: client.id,
            amountCents: submitted.$1,
            description: submitted.$2 ?? 'Haver adicionado manualmente.',
          )
        : await controller.addManualDebit(
            customerId: client.id,
            amountCents: submitted.$1,
            description: submitted.$2 ?? 'Pendencia registrada manualmente.',
          );
    if (!context.mounted) {
      return;
    }

    AppFeedback.success(
      context,
      isCredit
          ? 'Haver adicionado com sucesso.'
          : 'Pendencia registrada com sucesso.',
    );
    context.pushNamed(
      AppRouteNames.customerCreditReceipt,
      pathParameters: {'transactionId': '${transaction.id}'},
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }

    AppFeedback.error(
      context,
      isCredit
          ? 'Nao foi possivel adicionar o haver: $error'
          : 'Nao foi possivel registrar a pendencia: $error',
    );
  }
}
