import 'package:sqflite/sqflite.dart';

import '../../../../app/core/database/table_names.dart';
import '../../../../app/core/errors/app_exceptions.dart';
import '../../../vendas/domain/entities/sale_enums.dart';
import '../../domain/entities/purchase.dart';
import '../../domain/entities/purchase_status.dart';
import '../models/purchase_item_model.dart';

class PurchasePreparationSupport {
  const PurchasePreparationSupport._();

  static Future<PurchasePreparationResult> preparePurchase(
    DatabaseExecutor db,
    PurchaseUpsertInput input,
  ) async {
    if (input.items.isEmpty) {
      throw const ValidationException(
        'Adicione pelo menos um item para confirmar a compra.',
      );
    }
    if (input.initialPaidAmountCents < 0) {
      throw const ValidationException(
        'O valor pago na compra nao pode ser negativo.',
      );
    }
    if (input.initialPaidAmountCents > 0 &&
        (input.paymentMethod == null ||
            input.paymentMethod == PaymentMethod.fiado)) {
      throw const ValidationException(
        'Informe uma forma de pagamento valida para registrar a saida no caixa.',
      );
    }

    final supplierRows = await db.query(
      TableNames.fornecedores,
      columns: ['id', 'nome', 'deletado_em'],
      where: 'id = ?',
      whereArgs: [input.supplierId],
      limit: 1,
    );
    if (supplierRows.isEmpty ||
        (supplierRows.first['deletado_em'] as String?) != null) {
      throw const ValidationException('Fornecedor nao encontrado.');
    }

    final uniqueProductIds = input.items
        .map((item) => item.productId)
        .toSet()
        .toList();
    final placeholders = List.filled(uniqueProductIds.length, '?').join(',');
    final productRows = await db.rawQuery(
      '''
      SELECT
        id,
        nome,
        unidade_medida,
        estoque_mil,
        deletado_em
      FROM ${TableNames.produtos}
      WHERE id IN ($placeholders)
    ''',
      uniqueProductIds,
    );
    final productMap = {for (final row in productRows) row['id'] as int: row};

    final items = <PurchaseItemModel>[];
    var subtotalCents = 0;

    for (final inputItem in input.items) {
      if (inputItem.quantityMil <= 0) {
        throw const ValidationException(
          'A quantidade dos itens da compra deve ser maior que zero.',
        );
      }
      if (inputItem.unitCostCents < 0) {
        throw const ValidationException(
          'O custo unitario do item nao pode ser negativo.',
        );
      }

      final productRow = productMap[inputItem.productId];
      if (productRow == null ||
          (productRow['deletado_em'] as String?) != null) {
        throw const ValidationException(
          'Um dos produtos selecionados nao esta mais disponivel.',
        );
      }

      final itemSubtotal = calculateSubtotalCents(
        quantityMil: inputItem.quantityMil,
        unitCostCents: inputItem.unitCostCents,
      );
      subtotalCents += itemSubtotal;

      items.add(
        PurchaseItemModel(
          id: 0,
          uuid: '',
          purchaseId: 0,
          productId: inputItem.productId,
          productNameSnapshot: productRow['nome'] as String,
          unitMeasureSnapshot: productRow['unidade_medida'] as String? ?? 'un',
          quantityMil: inputItem.quantityMil,
          unitCostCents: inputItem.unitCostCents,
          subtotalCents: itemSubtotal,
        ),
      );
    }

    final finalAmountCents =
        subtotalCents -
        input.discountCents +
        input.surchargeCents +
        input.freightCents;
    if (finalAmountCents < 0) {
      throw const ValidationException(
        'O valor final da compra nao pode ficar negativo.',
      );
    }
    if (input.initialPaidAmountCents > finalAmountCents) {
      throw const ValidationException(
        'O valor pago nao pode ser maior que o valor final da compra.',
      );
    }

    return PurchasePreparationResult(
      supplierName: supplierRows.first['nome'] as String,
      items: items,
      subtotalCents: subtotalCents,
      finalAmountCents: finalAmountCents,
      paidAmountCents: input.initialPaidAmountCents,
      pendingAmountCents: finalAmountCents - input.initialPaidAmountCents,
      paymentMethod: input.paymentMethod,
      status: resolveStatus(
        finalAmountCents: finalAmountCents,
        paidAmountCents: input.initialPaidAmountCents,
        dueDate: input.dueDate,
      ),
    );
  }

  static PurchaseStatus resolveStatus({
    required int finalAmountCents,
    required int paidAmountCents,
    required DateTime? dueDate,
  }) {
    final pending = finalAmountCents - paidAmountCents;
    if (pending <= 0) {
      return PurchaseStatus.paga;
    }
    if (paidAmountCents > 0) {
      return PurchaseStatus.parcialmentePaga;
    }
    if (dueDate != null) {
      return PurchaseStatus.aberta;
    }
    return PurchaseStatus.recebida;
  }

  static int calculateSubtotalCents({
    required int quantityMil,
    required int unitCostCents,
  }) {
    return ((quantityMil * unitCostCents) / 1000).round();
  }
}

class PurchasePreparationResult {
  const PurchasePreparationResult({
    required this.supplierName,
    required this.items,
    required this.subtotalCents,
    required this.finalAmountCents,
    required this.paidAmountCents,
    required this.pendingAmountCents,
    required this.paymentMethod,
    required this.status,
  });

  final String supplierName;
  final List<PurchaseItemModel> items;
  final int subtotalCents;
  final int finalAmountCents;
  final int paidAmountCents;
  final int pendingAmountCents;
  final PaymentMethod? paymentMethod;
  final PurchaseStatus status;
}
