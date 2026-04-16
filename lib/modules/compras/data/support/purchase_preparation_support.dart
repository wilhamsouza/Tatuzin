import 'package:sqflite/sqflite.dart';

import '../../../../app/core/database/table_names.dart';
import '../../../../app/core/errors/app_exceptions.dart';
import '../../../vendas/domain/entities/sale_enums.dart';
import '../../domain/entities/purchase.dart';
import '../../domain/entities/purchase_item.dart';
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
        .where((item) => item.itemType == PurchaseItemType.product)
        .map((item) => item.productId)
        .whereType<int>()
        .toSet()
        .toList(growable: false);
    final uniqueSupplyIds = input.items
        .where((item) => item.itemType == PurchaseItemType.supply)
        .map((item) => item.supplyId)
        .whereType<int>()
        .toSet()
        .toList(growable: false);

    final productMap = <int, Map<String, Object?>>{};
    final productVariantMap = <int, Map<String, Object?>>{};
    if (uniqueProductIds.isNotEmpty) {
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
      productMap.addEntries(
        productRows.map((row) => MapEntry(row['id'] as int, row)),
      );

      final variantRows = await db.rawQuery(
        '''
        SELECT
          id,
          produto_id,
          sku,
          cor,
          tamanho,
          ativo
        FROM ${TableNames.produtoVariantes}
        WHERE produto_id IN ($placeholders)
      ''',
        uniqueProductIds,
      );
      productVariantMap.addEntries(
        variantRows.map((row) => MapEntry(row['id'] as int, row)),
      );
    }

    final supplyMap = <int, Map<String, Object?>>{};
    if (uniqueSupplyIds.isNotEmpty) {
      final placeholders = List.filled(uniqueSupplyIds.length, '?').join(',');
      final supplyRows = await db.rawQuery(
        '''
        SELECT
          id,
          name,
          purchase_unit_type,
          conversion_factor
        FROM ${TableNames.supplies}
        WHERE id IN ($placeholders)
      ''',
        uniqueSupplyIds,
      );
      supplyMap.addEntries(
        supplyRows.map((row) => MapEntry(row['id'] as int, row)),
      );
    }

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

      final itemSubtotal = calculateSubtotalCents(
        quantityMil: inputItem.quantityMil,
        unitCostCents: inputItem.unitCostCents,
      );
      subtotalCents += itemSubtotal;

      if (inputItem.itemType == PurchaseItemType.product) {
        if (inputItem.productId == null || inputItem.supplyId != null) {
          throw const ValidationException(
            'Cada item de produto precisa apontar apenas para um produto valido.',
          );
        }
        final productRow = productMap[inputItem.productId];
        if (productRow == null ||
            (productRow['deletado_em'] as String?) != null) {
          throw const ValidationException(
            'Um dos produtos selecionados nao esta mais disponivel.',
          );
        }
        final productVariantId = inputItem.productVariantId;
        Map<String, Object?>? productVariantRow;
        if (productVariantId != null) {
          productVariantRow = productVariantMap[productVariantId];
          if (productVariantRow == null ||
              productVariantRow['produto_id'] != inputItem.productId ||
              (productVariantRow['ativo'] as int? ?? 0) != 1) {
            throw const ValidationException(
              'A variante selecionada nao pertence ao produto informado.',
            );
          }
        } else {
          final hasAnyActiveVariant = productVariantMap.values.any(
            (row) =>
                row['produto_id'] == inputItem.productId &&
                (row['ativo'] as int? ?? 0) == 1,
          );
          if (hasAnyActiveVariant) {
            throw const ValidationException(
              'Selecione a cor e o tamanho corretos para lancar esta compra.',
            );
          }
        }

        items.add(
          PurchaseItemModel(
            id: 0,
            uuid: '',
            purchaseId: 0,
            itemType: PurchaseItemType.product,
            productId: inputItem.productId,
            productVariantId: productVariantId,
            supplyId: null,
            itemNameSnapshot: productRow['nome'] as String,
            variantSkuSnapshot: productVariantRow?['sku'] as String?,
            variantColorLabelSnapshot: productVariantRow?['cor'] as String?,
            variantSizeLabelSnapshot: productVariantRow?['tamanho'] as String?,
            unitMeasureSnapshot: productRow['unidade_medida'] as String? ?? 'un',
            quantityMil: inputItem.quantityMil,
            unitCostCents: inputItem.unitCostCents,
            subtotalCents: itemSubtotal,
          ),
        );
        continue;
      }

      if (inputItem.supplyId == null || inputItem.productId != null) {
        throw const ValidationException(
          'Cada item de insumo precisa apontar apenas para um insumo valido.',
        );
      }
      final supplyRow = supplyMap[inputItem.supplyId];
      if (supplyRow == null) {
        throw const ValidationException(
          'Um dos insumos selecionados nao esta mais disponivel.',
        );
      }

      items.add(
        PurchaseItemModel(
          id: 0,
          uuid: '',
          purchaseId: 0,
          itemType: PurchaseItemType.supply,
          productId: null,
          productVariantId: null,
          supplyId: inputItem.supplyId,
          itemNameSnapshot: supplyRow['name'] as String? ?? 'Insumo',
          variantSkuSnapshot: null,
          variantColorLabelSnapshot: null,
          variantSizeLabelSnapshot: null,
          unitMeasureSnapshot:
              supplyRow['purchase_unit_type'] as String? ?? 'un',
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
