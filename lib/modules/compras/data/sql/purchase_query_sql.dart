import '../../../../app/core/database/table_names.dart';

class PurchaseQuerySql {
  const PurchaseQuerySql._();

  static String selectPurchaseBase({required String featureKey}) {
    return '''
      SELECT
        c.*,
        f.nome AS fornecedor_nome,
        sync.remote_id AS sync_remote_id,
        sync.sync_status AS sync_status,
        sync.last_error AS sync_last_error,
        sync.last_error_type AS sync_last_error_type,
        sync.last_synced_at AS sync_last_synced_at,
        COUNT(ic.id) AS itens_quantidade
      FROM ${TableNames.compras} c
      INNER JOIN ${TableNames.fornecedores} f
        ON f.id = c.fornecedor_id
      LEFT JOIN ${TableNames.syncRegistros} sync
        ON sync.feature_key = '$featureKey'
        AND sync.local_id = c.id
      LEFT JOIN ${TableNames.itensCompra} ic
        ON ic.compra_id = c.id
      WHERE 1 = 1
    ''';
  }

  static String purchaseGroupBy() {
    return '''
      c.id,
      c.uuid,
      c.fornecedor_id,
      c.numero_documento,
      c.observacao,
      c.data_compra,
      c.data_vencimento,
      c.forma_pagamento,
      c.status,
      c.subtotal_centavos,
      c.desconto_centavos,
      c.acrescimo_centavos,
      c.frete_centavos,
      c.valor_final_centavos,
      c.valor_pago_centavos,
      c.valor_pendente_centavos,
      c.cancelada_em,
      c.criado_em,
      c.atualizado_em,
      f.nome,
      sync.remote_id,
      sync.sync_status,
      sync.last_error,
      sync.last_error_type,
      sync.last_synced_at
    ''';
  }

  static String defaultGroupedOrderBy() {
    return 'c.data_compra DESC, c.id DESC';
  }

  static String selectPurchaseById({required String featureKey}) {
    return '${selectPurchaseBase(featureKey: featureKey)} AND c.id = ? GROUP BY ${purchaseGroupBy()} LIMIT 1';
  }

  static String selectPurchaseByRemoteId({required String featureKey}) {
    return '${selectPurchaseBase(featureKey: featureKey)} AND sync.remote_id = ? GROUP BY ${purchaseGroupBy()} LIMIT 1';
  }

  static String selectPurchasesForListing({required String featureKey}) {
    return '${selectPurchaseBase(featureKey: featureKey)} GROUP BY ${purchaseGroupBy()} ORDER BY ${defaultGroupedOrderBy()}';
  }
}
