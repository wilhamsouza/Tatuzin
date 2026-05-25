import { z } from "zod";

import {
  booleanQuerySchema,
  paginationQuerySchema,
  sortDirectionSchema,
} from "../../shared/http/pagination";

const optionalQueryString = (maxLength: number) =>
  z.union([z.string(), z.undefined()]).transform((value) => {
    if (value == null) {
      return undefined;
    }
    const normalized = value.trim();
    return normalized.length === 0 ? undefined : normalized.slice(0, maxLength);
  });

const requiredReason = z
  .string()
  .trim()
  .min(1, "Informe o motivo da acao administrativa.")
  .max(1000);

const adminPlanSchema = z
  .enum(["FREE", "BASIC", "PRO", "free", "basic", "pro"])
  .transform((value) => value.toUpperCase() as "FREE" | "BASIC" | "PRO");

const adminBillingStatusSchema = z
  .enum([
    "ACTIVE",
    "EXPIRED",
    "CANCELLED",
    "PAST_DUE",
    "active",
    "expired",
    "cancelled",
    "past_due",
  ])
  .transform((value) => value.toUpperCase() as AdminBillingStatusInput)
  .optional();

const optionalIsoDate = z
  .union([z.string().datetime(), z.null(), z.undefined()])
  .transform((value) => {
    if (value == null) {
      return value;
    }
    return new Date(value);
  });

export const adminBillingCompaniesQuerySchema = paginationQuerySchema.extend({
  search: optionalQueryString(120),
  plan: adminPlanSchema.optional(),
  status: optionalQueryString(60),
  provider: optionalQueryString(60),
  hasProviderSubscription: booleanQuerySchema.optional(),
  sort: z
    .enum(["companyName", "plan", "status", "updatedAt", "currentPeriodEnd"])
    .default("updatedAt"),
  sortDirection: sortDirectionSchema,
});

export const adminBillingListQuerySchema = paginationQuerySchema;

export const adminBillingRefreshSchema = z.object({
  reason: requiredReason,
});

export const adminBillingForcePlanSchema = z.object({
  plan: adminPlanSchema,
  status: adminBillingStatusSchema,
  reason: requiredReason,
  currentPeriodEnd: optionalIsoDate,
  clearProvider: z.boolean().optional().default(false),
});

export const adminBillingCancelLocalSchema = z.object({
  reason: requiredReason,
  effective: z.enum(["now", "period_end"]),
});

const emergencyExtensionDays = z
  .number({ required_error: "Informe a quantidade de dias." })
  .int("Dias deve ser um numero inteiro.")
  .min(1, "Extensao minima de 1 dia.")
  .max(7, "Extensao emergencial limitada a 7 dias.");

export const adminLicenseEmergencyExtensionDryRunSchema = z.object({
  days: emergencyExtensionDays,
  reason: requiredReason,
  note: z.string().trim().max(1000).optional(),
});

export const adminLicenseEmergencyExtensionSchema =
  adminLicenseEmergencyExtensionDryRunSchema.extend({
    confirmationText: z.string().trim(),
  });

export const adminBillingReconcileDryRunSchema = z.object({
  reason: requiredReason,
  note: z.string().trim().max(1000).optional(),
});

export const adminBillingReconcileSchema =
  adminBillingReconcileDryRunSchema.extend({
    confirmationText: z.string().trim(),
  });

export const adminLicenseStatusActionDryRunSchema = z.object({
  reason: requiredReason,
  note: z.string().trim().max(1000).optional(),
});

export const adminLicenseStatusActionSchema =
  adminLicenseStatusActionDryRunSchema.extend({
    confirmationText: z.string().trim(),
  });

export type AdminBillingCompaniesQueryInput = z.infer<
  typeof adminBillingCompaniesQuerySchema
>;
export type AdminBillingListQueryInput = z.infer<
  typeof adminBillingListQuerySchema
>;
export type AdminBillingRefreshInput = z.infer<
  typeof adminBillingRefreshSchema
>;
export type AdminBillingForcePlanInput = z.infer<
  typeof adminBillingForcePlanSchema
>;
export type AdminBillingCancelLocalInput = z.infer<
  typeof adminBillingCancelLocalSchema
>;
export type AdminLicenseEmergencyExtensionDryRunInput = z.infer<
  typeof adminLicenseEmergencyExtensionDryRunSchema
>;
export type AdminLicenseEmergencyExtensionInput = z.infer<
  typeof adminLicenseEmergencyExtensionSchema
>;
export type AdminBillingReconcileDryRunInput = z.infer<
  typeof adminBillingReconcileDryRunSchema
>;
export type AdminBillingReconcileInput = z.infer<
  typeof adminBillingReconcileSchema
>;
export type AdminLicenseStatusActionDryRunInput = z.infer<
  typeof adminLicenseStatusActionDryRunSchema
>;
export type AdminLicenseStatusActionInput = z.infer<
  typeof adminLicenseStatusActionSchema
>;
export type AdminBillingStatusInput =
  | "ACTIVE"
  | "EXPIRED"
  | "CANCELLED"
  | "PAST_DUE";
