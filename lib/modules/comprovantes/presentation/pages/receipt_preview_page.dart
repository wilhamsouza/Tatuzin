import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/widgets/app_section_card.dart';
import '../../domain/entities/commercial_receipt_request.dart';
import '../providers/receipt_providers.dart';
import '../widgets/commercial_receipt_view.dart';
import '../widgets/receipt_action_bar.dart';

class ReceiptPreviewPage extends ConsumerWidget {
  ReceiptPreviewPage.sale({
    super.key,
    required int saleId,
    this.showSuccessBanner = false,
  }) : request = CommercialReceiptRequest.sale(saleId: saleId);

  ReceiptPreviewPage.fiadoPayment({
    super.key,
    required int fiadoId,
    required int entryId,
    this.showSuccessBanner = false,
  }) : request = CommercialReceiptRequest.fiadoPayment(
         fiadoId: fiadoId,
         paymentEntryId: entryId,
       );

  final CommercialReceiptRequest request;
  final bool showSuccessBanner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receiptAsync = ref.watch(commercialReceiptProvider(request));

    return Scaffold(
      appBar: AppBar(title: const Text('Comprovante')),
      body: receiptAsync.when(
        data: (receipt) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: AppSectionCard(
                  title: 'Ações do comprovante',
                  subtitle:
                      'Visualize, salve em PDF ou compartilhe o documento comercial.',
                  child: ReceiptActionBar(
                    request: request,
                    showViewAction: false,
                  ),
                ),
              ),
              Expanded(
                child: CommercialReceiptView(
                  receipt: receipt,
                  showSuccessBanner: showSuccessBanner,
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(error.toString()),
          ),
        ),
      ),
    );
  }
}
