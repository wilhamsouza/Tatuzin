import 'package:sqflite/sqflite.dart';

import '../../../estoque/data/support/inventory_balance_support.dart';
import '../../../estoque/data/support/inventory_movement_writer.dart';
import '../../../estoque/domain/entities/inventory_movement.dart';
import '../../domain/entities/purchase_item.dart';

class PurchaseStockSupport {
  const PurchaseStockSupport._();

  static Future<void> applyStockEntries(
    DatabaseExecutor db,
    List<PurchaseItem> items, {
    required int factor,
    int? referenceId,
    DateTime? occurredAt,
  }) async {
    await _runInWriteTransaction(db, (txn) async {
      final productEntries = _groupProductEntries(items, factor: factor);
      final stockChanges = <InventoryBalanceMutation>[];

      for (final entry in productEntries) {
        final insufficientMessage = factor < 0
            ? _buildPurchaseReversalInsufficientMessage(entry)
            : null;
        stockChanges.add(
          await InventoryBalanceSupport.applyStockDelta(
            txn,
            productId: entry.productId,
            productVariantId: entry.productVariantId,
            quantityDeltaMil: entry.quantityMil,
            allowNegativeStock: false,
            productNotFoundMessage:
                'Nao foi possivel atualizar o estoque de um dos produtos.',
            variantNotFoundMessage:
                'Nao foi possivel atualizar o estoque de uma das variacoes compradas.',
            insufficientProductStockMessage:
                insufficientMessage ??
                'Nao ha estoque suficiente para cancelar esta compra.',
            insufficientVariantStockMessage:
                insufficientMessage ??
                'Nao ha estoque suficiente na variante para reverter esta compra.',
            changedAt: occurredAt,
          ),
        );
      }

      if (stockChanges.isEmpty) {
        return;
      }

      await InventoryMovementWriter.recordChanges(
        txn,
        changes: stockChanges,
        movementType: factor > 0
            ? InventoryMovementType.purchaseIn
            : InventoryMovementType.purchaseReversalOut,
        referenceType: 'purchase',
        referenceId: referenceId,
        notes: factor > 0
            ? 'Movimento registrado automaticamente a partir da compra.'
            : 'Reversao registrada automaticamente a partir da compra.',
        createdAt: occurredAt,
      );
    });
  }

  static Future<void> validateStockReversal(
    DatabaseExecutor db,
    List<PurchaseItem> items,
  ) async {
    final productEntries = _groupProductEntries(items);

    for (final entry in productEntries) {
      final insufficientMessage = _buildPurchaseReversalInsufficientMessage(
        entry,
      );
      await InventoryBalanceSupport.previewStockDelta(
        db,
        productId: entry.productId,
        productVariantId: entry.productVariantId,
        quantityDeltaMil: -entry.quantityMil,
        allowNegativeStock: false,
        productNotFoundMessage:
            'Nao foi possivel validar o estoque de um dos itens da compra.',
        variantNotFoundMessage:
            'Nao foi possivel validar o estoque de uma das variacoes da compra.',
        insufficientProductStockMessage: insufficientMessage,
        insufficientVariantStockMessage: insufficientMessage,
      );
    }
  }

  static List<_ProductStockEntry> _groupProductEntries(
    List<PurchaseItem> items, {
    int factor = 1,
  }) {
    final grouped = <String, _ProductStockEntry>{};
    for (final item in items) {
      if (!item.isProduct || item.productId == null) {
        continue;
      }

      final key = '${item.productId}:${item.productVariantId ?? 0}';
      grouped.update(
        key,
        (current) => current.copyWith(
          quantityMil: current.quantityMil + (item.quantityMil * factor),
        ),
        ifAbsent: () => _ProductStockEntry(
          productId: item.productId!,
          productVariantId: item.productVariantId,
          productName: item.itemNameSnapshot,
          variantSummary: item.variantSummary,
          quantityMil: item.quantityMil * factor,
        ),
      );
    }

    grouped.removeWhere((_, value) => value.quantityMil == 0);
    return grouped.values.toList(growable: false);
  }

  static Future<void> _runInWriteTransaction(
    DatabaseExecutor db,
    Future<void> Function(DatabaseExecutor txn) action,
  ) async {
    if (db is Database) {
      await db.transaction((txn) async {
        await action(txn);
      });
      return;
    }
    await action(db);
  }

  static String _buildPurchaseReversalInsufficientMessage(
    _ProductStockEntry entry,
  ) {
    final productName = entry.productName.trim();
    final variantSummary = entry.variantSummary?.trim();
    final itemLabel = productName.isEmpty ? 'o item selecionado' : productName;
    if (entry.productVariantId == null || variantSummary == null) {
      return 'Nao ha estoque suficiente para reverter a compra de $itemLabel.';
    }
    return 'Nao ha estoque suficiente para reverter a compra de $itemLabel ($variantSummary).';
  }
}

class _ProductStockEntry {
  const _ProductStockEntry({
    required this.productId,
    required this.productVariantId,
    required this.productName,
    required this.variantSummary,
    required this.quantityMil,
  });

  final int productId;
  final int? productVariantId;
  final String productName;
  final String? variantSummary;
  final int quantityMil;

  _ProductStockEntry copyWith({int? quantityMil}) {
    return _ProductStockEntry(
      productId: productId,
      productVariantId: productVariantId,
      productName: productName,
      variantSummary: variantSummary,
      quantityMil: quantityMil ?? this.quantityMil,
    );
  }
}
