import { z } from "zod";

import { paginationQuerySchema } from "../../shared/http/pagination";
import {
  EMPLOYEE_PERMISSIONS,
  EMPLOYEE_ROLES,
  EMPLOYEE_STATUSES,
} from "./employee-permissions";

const employeeRoleSchema = z.enum(EMPLOYEE_ROLES);
const employeeStatusSchema = z.enum(EMPLOYEE_STATUSES);
const employeePermissionSchema = z.enum(EMPLOYEE_PERMISSIONS);

const editableEmployeeRoleSchema = employeeRoleSchema.refine(
  (role) => role !== "OWNER",
  {
    message: "OWNER nao pode ser criado ou promovido manualmente.",
  },
);

const optionalStringSchema = z.preprocess((value) => {
  if (typeof value === "string" && value.trim().length === 0) {
    return null;
  }
  return value;
}, z.string().trim().max(160).nullable().optional());

const optionalEmailSchema = z.preprocess((value) => {
  if (typeof value === "string" && value.trim().length === 0) {
    return null;
  }
  return value;
}, z.string().trim().email().max(254).nullable().optional());

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
  status: employeeStatusSchema.optional().default("ACTIVE"),
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
    message: "Informe ao menos um campo para atualizar.",
  });

const MAX_EMPLOYEE_ACTIVITY_RANGE_DAYS = 93;

const dateOnlySchema = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, {
    message: "Use datas no formato YYYY-MM-DD.",
  })
  .refine((value) => parseDateOnly(value) != null, {
    message: "Informe uma data valida.",
  });

export const employeeActivityQuerySchema = z
  .object({
    from: dateOnlySchema,
    to: dateOnlySchema,
  })
  .refine((input) => input.from <= input.to, {
    message: "A data inicial deve ser menor ou igual a data final.",
    path: ["from"],
  })
  .refine(
    (input) => {
      const from = parseDateOnly(input.from);
      const to = parseDateOnly(input.to);
      if (from == null || to == null) {
        return false;
      }
      const days =
        Math.floor((to.getTime() - from.getTime()) / (24 * 60 * 60 * 1000)) + 1;
      return days <= MAX_EMPLOYEE_ACTIVITY_RANGE_DAYS;
    },
    {
      message: `Escolha um periodo de ate ${MAX_EMPLOYEE_ACTIVITY_RANGE_DAYS} dias.`,
      path: ["to"],
    },
  );

function parseDateOnly(value: string) {
  const [year, month, day] = value.split("-").map(Number);
  if (year == null || month == null || day == null) {
    return null;
  }
  const date = new Date(Date.UTC(year, month - 1, day));
  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  ) {
    return null;
  }
  return date;
}

export type EmployeeListQueryInput = z.infer<typeof employeeListQuerySchema>;
export type EmployeeCreateInput = z.infer<typeof employeeCreateSchema>;
export type EmployeeUpdateInput = z.infer<typeof employeeUpdateSchema>;
export type EmployeeActivityQueryInput = z.infer<
  typeof employeeActivityQuerySchema
>;
