import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/route_names.dart';
import '../../domain/entities/commercial_receipt_request.dart';
import '../providers/receipt_providers.dart';

class ReceiptActionBar extends ConsumerWidget {
  const ReceiptActionBar({
    super.key,
    required this.request,
    this.enabled = true,
    this.blockedMessage,
    this.showViewAction = true,
  });

  final CommercialReceiptRequest request;
  final bool enabled;
  final String? blockedMessage;
  final bool showViewAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionState = ref.watch(receiptActionControllerProvider);
    final isBusy = actionState.isLoading;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        if (showViewAction)
          FilledButton.icon(
            onPressed: isBusy ? null : () => _openPreview(context),
            icon: const Icon(Icons.receipt_long_rounded),
            label: const Text('Ver comprovante'),
          ),
        OutlinedButton.icon(
          onPressed: isBusy
              ? null
              : () => _runGuardedAction(
                  context,
                  enabled: enabled,
                  blockedMessage: blockedMessage,
                  action: () async {
                    await ref
                        .read(receiptActionControllerProvider.notifier)
                        .sharePdf(request);
                    if (!context.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Comprovante compartilhado com sucesso.'),
                      ),
                    );
                  },
                ),
          icon: const Icon(Icons.share_outlined),
          label: Text(isBusy ? 'Processando...' : 'Compartilhar'),
        ),
        OutlinedButton.icon(
          onPressed: isBusy
              ? null
              : () => _runGuardedAction(
                  context,
                  enabled: enabled,
                  blockedMessage: blockedMessage,
                  action: () async {
                    final savedPath = await ref
                        .read(receiptActionControllerProvider.notifier)
                        .savePdf(request);
                    if (!context.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('PDF salvo em $savedPath')),
                    );
                  },
                ),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Salvar PDF'),
        ),
      ],
    );
  }

  Future<void> _runGuardedAction(
    BuildContext context, {
    required bool enabled,
    required String? blockedMessage,
    required Future<void> Function() action,
  }) async {
    if (!enabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            blockedMessage ??
                'O comprovante comercial não está disponível para esta operação.',
          ),
        ),
      );
      return;
    }

    try {
      await action();
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _openPreview(BuildContext context) {
    if (!enabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            blockedMessage ??
                'O comprovante comercial não está disponível para esta operação.',
          ),
        ),
      );
      return;
    }

    switch (request.type) {
      case CommercialReceiptRequestType.sale:
        context.pushNamed(
          AppRouteNames.saleReceipt,
          pathParameters: {'saleId': '${request.saleId}'},
        );
      case CommercialReceiptRequestType.fiadoPayment:
        context.pushNamed(
          AppRouteNames.fiadoPaymentReceipt,
          pathParameters: {
            'fiadoId': '${request.fiadoId}',
            'entryId': '${request.paymentEntryId}',
          },
        );
    }
  }
}
