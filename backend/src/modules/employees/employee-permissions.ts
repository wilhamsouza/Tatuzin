import type { Prisma } from '@prisma/client';

export const EMPLOYEE_ROLES = [
  'OWNER',
  'MANAGER',
  'CASHIER',
  'SELLER',
  'STOCK_OPERATOR',
  'READ_ONLY',
] as const;

export type EmployeeRole = (typeof EMPLOYEE_ROLES)[number];

export const EMPLOYEE_STATUSES = ['ACTIVE', 'INVITED', 'DISABLED'] as const;

export type EmployeeStatus = (typeof EMPLOYEE_STATUSES)[number];

export const EMPLOYEE_PERMISSIONS = [
  'sales.create',
  'sales.cancel',
  'sales.discount',
  'cash.open',
  'cash.close',
  'cash.withdraw',
  'products.read',
  'products.write',
  'stock.adjust',
  'customers.read',
  'customers.write',
  'fiado.read',
  'fiado.receive',
  'reports.basic',
  'reports.advanced',
  'employees.manage',
  'devices.manage',
  'subscription.manage',
] as const;

export type EmployeePermission = (typeof EMPLOYEE_PERMISSIONS)[number];

const ROLE_DEFAULT_PERMISSIONS: Record<EmployeeRole, EmployeePermission[]> = {
  OWNER: [...EMPLOYEE_PERMISSIONS],
  MANAGER: [
    'sales.create',
    'sales.cancel',
    'sales.discount',
    'cash.open',
    'cash.close',
    'cash.withdraw',
    'products.read',
    'products.write',
    'stock.adjust',
    'customers.read',
    'customers.write',
    'fiado.read',
    'fiado.receive',
    'reports.basic',
    'reports.advanced',
    'employees.manage',
  ],
  CASHIER: [
    'sales.create',
    'cash.open',
    'cash.close',
    'cash.withdraw',
    'products.read',
    'customers.read',
    'fiado.read',
    'fiado.receive',
  ],
  SELLER: ['sales.create', 'customers.read', 'customers.write'],
  STOCK_OPERATOR: ['products.read', 'stock.adjust'],
  READ_ONLY: ['products.read', 'customers.read', 'fiado.read', 'reports.basic'],
};

const EMPLOYEE_ROLE_SET = new Set<string>(EMPLOYEE_ROLES);
const EMPLOYEE_STATUS_SET = new Set<string>(EMPLOYEE_STATUSES);
const EMPLOYEE_PERMISSION_SET = new Set<string>(EMPLOYEE_PERMISSIONS);

export function isEmployeeRole(value: string): value is EmployeeRole {
  return EMPLOYEE_ROLE_SET.has(value);
}

export function isEmployeeStatus(value: string): value is EmployeeStatus {
  return EMPLOYEE_STATUS_SET.has(value);
}

export function isEmployeePermission(
  value: string,
): value is EmployeePermission {
  return EMPLOYEE_PERMISSION_SET.has(value);
}

export function normalizeEmployeeRole(value: string): EmployeeRole | null {
  const normalized = value.trim().toUpperCase();
  return isEmployeeRole(normalized) ? normalized : null;
}

export function normalizeEmployeeStatus(value: string): EmployeeStatus | null {
  const normalized = value.trim().toUpperCase();
  return isEmployeeStatus(normalized) ? normalized : null;
}

export function roleFromMembershipRole(membershipRole: string): EmployeeRole {
  switch (membershipRole) {
    case 'OWNER':
      return 'OWNER';
    case 'ADMIN':
      return 'MANAGER';
    case 'OPERATOR':
    default:
      return 'CASHIER';
  }
}

export function membershipRoleFromEmployeeRole(role: string) {
  switch (normalizeEmployeeRole(role)) {
    case 'OWNER':
      return 'OWNER';
    case 'MANAGER':
      return 'ADMIN';
    default:
      return 'OPERATOR';
  }
}

export function defaultPermissionsForRole(role: EmployeeRole) {
  return [...ROLE_DEFAULT_PERMISSIONS[role]];
}

export function normalizePermissions(
  rawPermissions: readonly string[],
): EmployeePermission[] {
  const normalized = new Set<EmployeePermission>();
  for (const permission of rawPermissions) {
    const value = permission.trim();
    if (isEmployeePermission(value)) {
      normalized.add(value);
    }
  }
  return [...normalized];
}

export function parseStoredPermissions(
  permissions: Prisma.JsonValue | null | undefined,
): EmployeePermission[] | null {
  if (!Array.isArray(permissions)) {
    return null;
  }

  return normalizePermissions(
    permissions.filter((permission): permission is string => {
      return typeof permission === 'string';
    }),
  );
}

export function effectivePermissionsForEmployee(input: {
  role: string;
  status: string;
  permissions?: Prisma.JsonValue | null;
}) {
  const role = normalizeEmployeeRole(input.role) ?? 'READ_ONLY';
  const status = normalizeEmployeeStatus(input.status) ?? 'DISABLED';

  if (status === 'DISABLED') {
    return [];
  }

  if (role === 'OWNER') {
    return defaultPermissionsForRole('OWNER');
  }

  const savedPermissions = parseStoredPermissions(input.permissions);
  return savedPermissions ?? defaultPermissionsForRole(role);
}

export function hasEmployeePermission(
  permissions: readonly string[],
  permission: EmployeePermission,
) {
  return permissions.includes('*') || permissions.includes(permission);
}
