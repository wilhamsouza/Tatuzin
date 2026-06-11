import { z } from "zod";

import { tenantDeletionStatuses } from "./tenant-deletion.types";

export const tenantDeletionListQuerySchema = z.object({
  companyId: z.string().trim().min(1).optional(),
  status: z
    .string()
    .trim()
    .transform((value) => value.toUpperCase())
    .pipe(z.enum(tenantDeletionStatuses))
    .optional(),
});

const reasonSchema = z
  .string()
  .trim()
  .min(12, "Informe um motivo com pelo menos 12 caracteres.")
  .max(1000, "O motivo deve ter no maximo 1000 caracteres.");

export const tenantDeletionCreateRequestSchema = z.object({
  companyId: z.string().trim().min(1, "Empresa obrigatoria."),
  reason: reasonSchema,
  requesterName: z.string().trim().max(160).optional(),
  requesterEmail: z.string().trim().email().max(254).optional(),
  requesterChannel: z.string().trim().max(80).optional(),
});

export const tenantDeletionReasonSchema = z.object({
  companyId: z.string().trim().min(1, "Empresa obrigatoria."),
  reason: reasonSchema,
  note: z.string().trim().max(1000).optional(),
});

export const tenantDeletionDryRunSchema = z.object({
  reason: reasonSchema,
  requestId: z.string().uuid("requestId deve ser um UUID valido."),
});

export const tenantDeletionExecutionSchema = tenantDeletionReasonSchema.extend({
  confirmation: z.literal("ANONIMIZAR TENANT", {
    errorMap: () => ({
      message: 'Confirme a operacao informando "ANONIMIZAR TENANT".',
    }),
  }),
});

export const tenantDeletionQuarantineSchema = tenantDeletionReasonSchema.extend(
  {
    confirmation: z.literal("QUARENTENA", {
      errorMap: () => ({
        message: 'Confirme a operacao informando "QUARENTENA".',
      }),
    }),
  },
);

export type TenantDeletionListQueryInput = z.infer<
  typeof tenantDeletionListQuerySchema
>;
export type TenantDeletionCreateRequestInput = z.infer<
  typeof tenantDeletionCreateRequestSchema
>;
export type TenantDeletionReasonInput = z.infer<
  typeof tenantDeletionReasonSchema
>;
export type TenantDeletionDryRunInput = z.infer<
  typeof tenantDeletionDryRunSchema
>;
export type TenantDeletionQuarantineInput = z.infer<
  typeof tenantDeletionQuarantineSchema
>;
export type TenantDeletionExecutionInput = z.infer<
  typeof tenantDeletionExecutionSchema
>;
