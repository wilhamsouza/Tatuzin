import { z } from "zod";

const optionalClientMetadata = (max: number) =>
  z.string().trim().min(1).max(max).optional();

export const tenantDeletionAcknowledgementSchema = z.object({
  acknowledgementToken: z.string().trim().min(32).max(4096),
  companyId: z.string().uuid(),
  clientInstanceId: z.string().trim().min(8).max(120),
  deviceLabel: optionalClientMetadata(120),
  platform: optionalClientMetadata(40),
  appVersion: optionalClientMetadata(40),
  acknowledgedAt: z.string().datetime({ offset: true }).optional(),
});

export type TenantDeletionAcknowledgementInput = z.infer<
  typeof tenantDeletionAcknowledgementSchema
>;
