import { z } from "zod";

import { operationalActionReasonSchema } from "./support-actions.schemas";
import {
  revokeSessionConfirmationText,
  revokeSessionExecutionActionType,
  revokeSessionExecutionTargetType,
} from "./support-actions.execution.types";

const requiredIdentifier = (field: string, max = 160) =>
  z
    .string({
      required_error: `${field} obrigatorio.`,
      invalid_type_error: `${field} obrigatorio.`,
    })
    .trim()
    .min(1, `${field} obrigatorio.`)
    .max(max, `${field} deve ter no maximo ${max} caracteres.`);

export const supportActionExecutionProbeSchema = z.object({
  actionType: z.string().trim().min(1, "actionType obrigatorio."),
});

export const revokeSessionExecutionRequestSchema = z.object({
  actionType: z.literal(revokeSessionExecutionActionType),
  companyId: requiredIdentifier("companyId", 120),
  targetType: z.literal(revokeSessionExecutionTargetType),
  targetId: requiredIdentifier("targetId", 120),
  actorAdminId: requiredIdentifier("actorAdminId", 120),
  reason: operationalActionReasonSchema,
  dryRunAuditEventId: requiredIdentifier("dryRunAuditEventId", 120),
  idempotencyKey: requiredIdentifier("idempotencyKey", 200),
  explicitConfirmation: z.literal(true, {
    errorMap: () => ({
      message: "Confirmacao explicita obrigatoria.",
    }),
  }),
  confirmationText: z.literal(revokeSessionConfirmationText, {
    errorMap: () => ({
      message: `Digite ${revokeSessionConfirmationText} para confirmar.`,
    }),
  }),
  metadata: z.record(z.unknown()).optional().default({}),
});

export type RevokeSessionExecutionRequest = z.infer<
  typeof revokeSessionExecutionRequestSchema
>;
