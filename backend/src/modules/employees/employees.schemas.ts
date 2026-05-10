import { z } from 'zod';

import { paginationQuerySchema } from '../../shared/http/pagination';
import {
  EMPLOYEE_PERMISSIONS,
  EMPLOYEE_ROLES,
  EMPLOYEE_STATUSES,
} from './employee-permissions';

const employeeRoleSchema = z.enum(EMPLOYEE_ROLES);
const employeeStatusSchema = z.enum(EMPLOYEE_STATUSES);
const employeePermissionSchema = z.enum(EMPLOYEE_PERMISSIONS);

const editableEmployeeRoleSchema = employeeRoleSchema.refine(
  (role) => role !== 'OWNER',
  {
    message: 'OWNER nao pode ser criado ou promovido manualmente.',
  },
);

const optionalStringSchema = z.preprocess(
  (value) => {
    if (typeof value === 'string' && value.trim().length === 0) {
      return null;
    }
    return value;
  },
  z.string().trim().max(160).nullable().optional(),
);

const optionalEmailSchema = z.preprocess(
  (value) => {
    if (typeof value === 'string' && value.trim().length === 0) {
      return null;
    }
    return value;
  },
  z.string().trim().email().max(254).nullable().optional(),
);

const permissionsSchema = z
  .array(employeePermissionSchema)
  .max(EMPLOYEE_PERMISSIONS.length)
  .transform((permissions) => [...new Set(permissions)]);

export const employeeListQuerySchema = paginationQuerySchema.extend({
  status: employeeStatusSchema.optional(),
  role: employeeRoleSchema.optional(),
  search: z
    .string()
    .trim()
    .max(120)
    .optional()
    .transform((value) =>
      value == null || value.length === 0 ? undefined : value,
    ),
});

export const employeeCreateSchema = z.object({
  name: z.string().trim().min(1).max(160),
  email: optionalEmailSchema,
  phone: optionalStringSchema,
  role: editableEmployeeRoleSchema,
  status: employeeStatusSchema.optional().default('ACTIVE'),
  permissions: permissionsSchema.optional().nullable(),
});

export const employeeUpdateSchema = z
  .object({
    name: z.string().trim().min(1).max(160).optional(),
    email: optionalEmailSchema,
    phone: optionalStringSchema,
    role: editableEmployeeRoleSchema.optional(),
    status: employeeStatusSchema.optional(),
    permissions: permissionsSchema.optional().nullable(),
  })
  .refine((input) => Object.keys(input).length > 0, {
    message: 'Informe ao menos um campo para atualizar.',
  });

export type EmployeeListQueryInput = z.infer<typeof employeeListQuerySchema>;
export type EmployeeCreateInput = z.infer<typeof employeeCreateSchema>;
export type EmployeeUpdateInput = z.infer<typeof employeeUpdateSchema>;
