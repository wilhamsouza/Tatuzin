import 'package:sqflite/sqflite.dart';

import '../../../../app/core/database/table_names.dart';
import '../../../../app/core/errors/app_exceptions.dart';
import '../../../../app/core/utils/app_logger.dart';
import '../../../caixa/data/cash_database_support.dart';
import '../../../carrinho/domain/entities/cart_item.dart';
import '../../domain/entities/checkout_input.dart';
import '../../domain/entities/sale_enums.dart';

class SaleValidationSupport {
  const SaleValidationSupport._();

  static void validateCompletionInput({
    required CheckoutInput input,
    required SaleType saleType,
  }) {
    if (input.items.isEmpty) {
      throw const ValidationException(
        'Adicione ao menos um item antes de finalizar a venda.',
      );
    }

    if (input.discountCents < 0 || input.surchargeCents < 0) {
      throw const ValidationException(
        'Descontos e acrescimos precisam ser positivos.',
      );
    }

    if (input.discountCents > input.itemsTotalCents) {
      throw const ValidationException(
        'O desconto nao pode ser maior que o subtotal da venda.',
      );
    }

    if (input.finalTotalCents < 0) {
      throw const ValidationException(
        'O valor final da venda nao pode ser negativo.',
      );
    }

    if (input.customerCreditUsedCents < 0 ||
        input.changeLeftAsCreditCents < 0) {
      throw const ValidationException(
        'Os valores de haver precisam ser positivos.',
      );
    }

    if (input.customerCreditUsedCents > input.finalTotalCents) {
      throw const ValidationException(
        'O haver utilizado nao pode exceder o total da venda.',
      );
    }

    if ((input.customerCreditUsedCents > 0 ||
            input.changeLeftAsCreditCents > 0) &&
        input.clientId == null) {
      throw const ValidationException(
        'Selecione um cliente para movimentar haver na venda.',
      );
    }

    if (saleType == SaleType.fiado && input.customerCreditUsedCents > 0) {
      throw const ValidationException(
        'O uso de haver esta disponivel apenas para venda a vista nesta etapa.',
      );
    }

    if (saleType == SaleType.fiado && input.dueDate == null) {
      throw const ValidationException(
        'Informe o vencimento para registrar uma venda fiado.',
      );
    }

    if (input.changeLeftAsCreditCents > 0 &&
        (saleType != SaleType.cash ||
            input.paymentMethod != PaymentMethod.cash)) {
      throw const ValidationException(
        'Somente vendas em dinheiro podem transformar troco em haver.',
      );
    }

    for (final item in input.items) {
      if (!item.hasOperationalRemoteIdentity) {
        AppLogger.warn(
          '[Checkout] blocked sale item without remote identity | '
          'productLocalId=${item.productId} '
          'productVariantLocalId=${item.productVariantId} '
          'missingProductRemote=${item.productRemoteId?.trim().isEmpty ?? true} '
          'missingVariantRemote=${item.productVariantId != null && (item.productVariantRemoteId?.trim().isEmpty ?? true)}',
        );
        throw ValidationException(
          '${item.productName}: $operationalProductMissingRemoteMessage',
        );
      }
    }
  }

  static Future<void> ensureClientExists(
    DatabaseExecutor txn,
    int clientId,
  ) async {
    final clientRows = await txn.query(
      TableNames.clientes,
      columns: ['id', 'deletado_em'],
      where: 'id = ?',
      whereArgs: [clientId],
      limit: 1,
    );

    if (clientRows.isEmpty || clientRows.first['deletado_em'] != null) {
      throw const ValidationException(
        'Cliente selecionado nao esta disponivel.',
      );
    }
  }

  static Future<void> ensureOperationalOrderCanBeConverted(
    DatabaseExecutor txn, {
    required int orderId,
  }) async {
    final rows = await txn.rawQuery(
      '''
      SELECT
        p.status AS status,
        vpo.venda_id AS venda_id
      FROM ${TableNames.pedidosOperacionais} p
      LEFT JOIN ${TableNames.vendasPedidosOperacionais} vpo
        ON vpo.pedido_operacional_id = p.id
      WHERE p.id = ?
      LIMIT 1
    ''',
      [orderId],
    );

    if (rows.isEmpty) {
      throw ValidationException(
        'Pedido de venda #$orderId nao foi encontrado.',
      );
    }

    final row = rows.first;
    final linkedSaleId = row['venda_id'] as int?;
    if (linkedSaleId != null) {
      throw ValidationException(
        'Pedido de venda #$orderId ja foi convertido na venda #$linkedSaleId.',
      );
    }

    final status = row['status'] as String?;
    if (status == 'canceled') {
      throw ValidationException(
        'Pedido de venda #$orderId esta cancelado e nao pode ser convertido.',
      );
    }
    if (status != 'ready' && status != 'delivered') {
      throw ValidationException(
        'Pedido de venda #$orderId ainda nao esta separado e nao pode ser faturado.',
      );
    }
  }

  static Future<void> ensureImmediateReceiptHasOpenCashSession(
    DatabaseExecutor txn, {
    required CheckoutInput input,
    required SaleType saleType,
  }) async {
    if (saleType != SaleType.cash || input.immediateReceivedCents <= 0) {
      return;
    }

    await CashDatabaseSupport.requireOpenSessionIdWithMessage(
      txn,
      message: input.paymentMethod == PaymentMethod.cash
          ? 'Abra o caixa antes de registrar venda em dinheiro.'
          : 'Abra o caixa antes de concluir uma venda com recebimento imediato.',
    );
  }

  static String? cleanNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
