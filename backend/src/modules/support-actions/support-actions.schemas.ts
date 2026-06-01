import { z } from "zod";

import {
  operationalActionTargetTypes,
  operationalActionTypes,
  supportActionPermissionKeys,
  type SupportActionPermissionKey,
  type OperationalActionTargetType,
  type OperationalActionType,
} from "./support-actions.types";

export const operationalActionTypeSchema = z.enum(operationalActionTypes);

export const operationalActionTargetTypeSchema = z.enum(
  operationalActionTargetTypes,
);

export const supportActionPermissionKeySchema = z.enum(
  supportActionPermissionKeys,
);

export const operationalActionReasonSchema = z
  .string({
    required_error: "Informe o motivo da acao operacional.",
    invalid_type_error: "Informe o motivo da acao operacional.",
  })
  .trim()
  .min(12, "Informe um motivo com pelo menos 12 caracteres.")
  .max(1000, "Motivo deve ter no maximo 1000 caracteres.");

const requiredIdentifier = (field: string) =>
  z
    .string({
      required_error: `${field} obrigatorio.`,
      invalid_type_error: `${field} obrigatorio.`,
    })
    .trim()
    .min(1, `${field} obrigatorio.`)
    .max(120, `${field} deve ter no maximo 120 caracteres.`);

export const operationalActionDryRunRequestSchema = z.object({
  actionType: operationalActionTypeSchema,
  companyId: requiredIdentifier("companyId"),
  targetType: operationalActionTargetTypeSchema,
  targetId: requiredIdentifier("targetId"),
  actorAdminId: requiredIdentifier("actorAdminId"),
  reason: operationalActionReasonSchema,
  dryRun: z.literal(true).default(true),
  metadata: z.record(z.unknown()).optional().default({}),
});

export const unsupportedOperationalActionProbeSchema = z.object({
  actionType: z.string().trim().min(1, "actionType obrigatorio."),
  companyId: requiredIdentifier("companyId").optional(),
  targetType: z.string().trim().min(1, "targetType obrigatorio.").optional(),
  targetId: requiredIdentifier("targetId").optional(),
  actorAdminId: requiredIdentifier("actorAdminId").optional(),
  reason: z.string().trim().optional(),
  dryRun: z.boolean().optional(),
  metadata: z.record(z.unknown()).optional(),
});

export const supportActionDryRunHttpBodySchema = z.object({
  actionType: z.string().trim().min(1, "actionType obrigatorio."),
  companyId: z.string().trim().min(1, "companyId obrigatorio.").max(120),
  targetType: z.string().trim().min(1, "targetType obrigatorio."),
  targetId: z.string().trim().min(1, "targetId obrigatorio.").max(120),
  reason: z.string().trim().optional(),
  dryRun: z.literal(true).optional().default(true),
  metadata: z.record(z.unknown()).optional().default({}),
});

export type OperationalActionDryRunRequest = z.infer<
  typeof operationalActionDryRunRequestSchema
>;

export type UnsupportedOperationalActionProbe = z.infer<
  typeof unsupportedOperationalActionProbeSchema
>;

export type SupportActionDryRunHttpBody = z.infer<
  typeof supportActionDryRunHttpBodySchema
>;

export function isOperationalActionType(
  value: string,
): value is OperationalActionType {
  return (operationalActionTypes as readonly string[]).includes(value);
}

export function isOperationalActionTargetType(
  value: string,
): value is OperationalActionTargetType {
  return (operationalActionTargetTypes as readonly string[]).includes(value);
}

export function isSupportActionPermissionKey(
  value: string,
): value is SupportActionPermissionKey {
  return (supportActionPermissionKeys as readonly string[]).includes(value);
}
