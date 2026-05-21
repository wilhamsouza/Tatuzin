import { hasEmployeePermission } from '../employees/employee-permissions';
import type { AppContext } from '../app/app-context.types';

export function canViewSensitiveProductData(context: AppContext) {
  const permissions = context.membership.permissions;
  return (
    hasEmployeePermission(permissions, 'products.write') ||
    hasEmployeePermission(permissions, 'stock.adjust') ||
    hasEmployeePermission(permissions, 'reports.advanced')
  );
}
