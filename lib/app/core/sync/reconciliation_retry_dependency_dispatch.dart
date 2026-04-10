import 'sync_feature_keys.dart';

enum RetryDependencyDispatchTarget {
  productDependencyChain,
  purchaseDependencyChain,
  saleDependencyChain,
  canceledSaleFinancialEventChain,
  fiadoPaymentFinancialEventChain,
  directRepair,
  unsupported,
}

class ReconciliationRetryDependencyDispatch {
  const ReconciliationRetryDependencyDispatch._();

  static RetryDependencyDispatchTarget resolve({
    required String featureKey,
    required String entityType,
  }) {
    switch (featureKey) {
      case SyncFeatureKeys.products:
        return RetryDependencyDispatchTarget.productDependencyChain;
      case SyncFeatureKeys.purchases:
        return RetryDependencyDispatchTarget.purchaseDependencyChain;
      case SyncFeatureKeys.sales:
        return RetryDependencyDispatchTarget.saleDependencyChain;
      case SyncFeatureKeys.financialEvents:
        switch (entityType) {
          case 'sale_canceled_event':
            return RetryDependencyDispatchTarget
                .canceledSaleFinancialEventChain;
          case 'fiado_payment_event':
            return RetryDependencyDispatchTarget
                .fiadoPaymentFinancialEventChain;
          default:
            return RetryDependencyDispatchTarget.unsupported;
        }
      default:
        return RetryDependencyDispatchTarget.directRepair;
    }
  }
}
