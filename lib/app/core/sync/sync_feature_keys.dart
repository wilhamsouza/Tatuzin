abstract final class SyncFeatureKeys {
  static const suppliers = 'suppliers';
  static const categories = 'categories';
  static const products = 'products';
  static const customers = 'customers';
  static const purchases = 'purchases';
  static const sales = 'sales';
  static const financialEvents = 'financial_events';
  static const saleCancellations = 'sale_cancellations';
  static const fiadoPayments = 'fiado_payments';
  static const cashEvents = 'cash_events';
  static const fiado = 'fiado';
  static const cashMovements = 'cash_movements';
}

String syncFeatureDisplayName(String featureKey) {
  return switch (featureKey) {
    SyncFeatureKeys.suppliers => 'Fornecedores',
    SyncFeatureKeys.categories => 'Categorias',
    SyncFeatureKeys.products => 'Produtos',
    SyncFeatureKeys.customers => 'Clientes',
    SyncFeatureKeys.purchases => 'Compras',
    SyncFeatureKeys.sales => 'Vendas',
    SyncFeatureKeys.financialEvents => 'Eventos financeiros',
    SyncFeatureKeys.saleCancellations => 'Cancelamentos de venda',
    SyncFeatureKeys.fiadoPayments => 'Pagamentos de fiado',
    SyncFeatureKeys.cashEvents => 'Eventos de caixa',
    SyncFeatureKeys.fiado => 'Fiado',
    SyncFeatureKeys.cashMovements => 'Movimentos de caixa',
    _ => featureKey,
  };
}
