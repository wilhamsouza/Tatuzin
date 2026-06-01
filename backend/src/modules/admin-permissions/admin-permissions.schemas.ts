import { z } from "zod";

export const adminPermissionMutationBodySchema = z.object({
  permissionKey: z
    .string({ required_error: "permissionKey obrigatoria." })
    .trim()
    .min(1, "permissionKey obrigatoria.")
    .max(160, "permissionKey muito longa."),
  reason: z
    .string({ required_error: "Motivo obrigatorio." })
    .trim()
    .min(12, "Informe um motivo com pelo menos 12 caracteres.")
    .max(1000, "Motivo muito longo."),
  scope: z.string().trim().min(1).max(80).optional(),
  scopeId: z.string().trim().min(1).max(120).optional(),
});

export type AdminPermissionMutationBodyInput = z.infer<
  typeof adminPermissionMutationBodySchema
>;
