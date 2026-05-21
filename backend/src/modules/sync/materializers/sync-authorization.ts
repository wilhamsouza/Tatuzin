import type { EmployeePermission } from '../../employees/employee-permissions';
import { hasEmployeePermission } from '../../employees/employee-permissions';
import type {
  SyncMaterializerInput,
  SyncMaterializerResult,
} from './materializer.types';

export function requireSyncPermission(
  input: SyncMaterializerInput,
  permission: EmployeePermission,
  message: string,
  code = 'SYNC_PERMISSION_REQUIRED',
): SyncMaterializerResult | null {
  if (isPrivilegedSyncRole(input)) {
    return null;
  }

  if (hasEmployeePermission(input.context.membership.permissions, permission)) {
    return null;
  }

  return {
    outcome: 'rejected',
    code,
    message,
    details: { permission },
  };
}

export function canManageOtherCashSessions(input: SyncMaterializerInput) {
  if (isPrivilegedSyncRole(input)) {
    return true;
  }

  const role = input.context.membership.role.trim().toUpperCase();
  return role === 'OWNER' || role === 'ADMIN';
}

function isPrivilegedSyncRole(input: SyncMaterializerInput) {
  const role = input.context.membership.role.trim().toUpperCase();
  return role === 'PLATFORM_ADMIN';
}
