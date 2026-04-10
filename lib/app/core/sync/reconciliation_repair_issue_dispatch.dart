import 'sync_feature_keys.dart';

enum RepairIssueDispatchTarget {
  repairSupplier,
  repairCategory,
  repairProduct,
  repairCustomer,
  repairPurchase,
  repairSale,
  repairFinancialEvent,
  unsupported,
}

class ReconciliationRepairIssueDispatch {
  const ReconciliationRepairIssueDispatch._();

  static RepairIssueDispatchTarget resolve(String featureKey) {
    switch (featureKey) {
      case SyncFeatureKeys.suppliers:
        return RepairIssueDispatchTarget.repairSupplier;
      case SyncFeatureKeys.categories:
        return RepairIssueDispatchTarget.repairCategory;
      case SyncFeatureKeys.products:
        return RepairIssueDispatchTarget.repairProduct;
      case SyncFeatureKeys.customers:
        return RepairIssueDispatchTarget.repairCustomer;
      case SyncFeatureKeys.purchases:
        return RepairIssueDispatchTarget.repairPurchase;
      case SyncFeatureKeys.sales:
        return RepairIssueDispatchTarget.repairSale;
      case SyncFeatureKeys.financialEvents:
        return RepairIssueDispatchTarget.repairFinancialEvent;
      default:
        return RepairIssueDispatchTarget.unsupported;
    }
  }
}
