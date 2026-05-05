abstract final class OperationalSyncPolicy {
  static const entityNotLocalFirstCode = 'ENTITY_NOT_LOCAL_FIRST';
  static const invalidOperationCode = 'INVALID_OPERATION';

  static const allowedLocalFirstEntities = <String>{
    'cashSession',
    'cashMovement',
    'operationalOrder',
    'operationalOrderItem',
    'sale',
    'saleItem',
    'payment',
    'receipt',
    'stockReservation',
    'stockDeduction',
    'offlineOperationLog',
  };

  static const blockedServerFirstEntities = <String>{
    'product',
    'category',
    'customer',
    'supplier',
    'purchase',
    'supply',
    'cost',
    'report',
    'fiado',
  };

  static const blockedServerFirstFeatureKeys = <String>{
    'products',
    'categories',
    'customers',
    'suppliers',
    'purchases',
    'supplies',
    'supply_inventory_movements',
    'product_recipes',
    'fiado',
    'fiado_payments',
    'financial_events',
    'costs',
    'reports',
  };

  static const allowedOperations = <String>{
    'create',
    'update',
    'delete',
    'upsert',
    'append',
  };

  static bool isLocalFirstEntity(String entity) {
    return allowedLocalFirstEntities.contains(entity.trim());
  }

  static bool isAllowedOperation(String operation) {
    return allowedOperations.contains(operation.trim().toLowerCase());
  }

  static bool isBlockedServerFirstFeature(String featureKey) {
    return blockedServerFirstFeatureKeys.contains(featureKey.trim());
  }
}
