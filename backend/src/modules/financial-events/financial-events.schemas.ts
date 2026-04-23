import { z } from 'zod';

import { createListQuerySchema } from '../../shared/http/pagination';

const nullableUuid = z
  .union([z.string().uuid(), z.null(), z.undefined()])
  .transform((value) => value ?? null);

const nullableTrimmedString = (maxLength: number) =>
  z
    .union([z.string().trim().max(maxLength), z.null(), z.undefined()])
    .transform((value) => {
      if (value == null) {
        return null;
      }

      const trimmed = value.trim();
      return trimmed.length === 0 ? null : trimmed;
    });

export const financialEventCreateSchema = z.object({
  saleId: nullableUuid,
  fiadoId: nullableTrimmedString(120),
  eventType: z.enum(['sale_canceled', 'fiado_payment']),
  localUuid: z.string().trim().min(1).max(120),
  amountCents: z.coerce.number().int().min(0),
  paymentType: nullableTrimmedString(40),
  createdAt: z.string().datetime(),
  metadata: z
    .union([z.record(z.string(), z.unknown()), z.null(), z.undefined()])
    .transform((value) => value ?? null),
});

export const financialEventListQuerySchema = createListQuerySchema();

export type FinancialEventCreateInput = z.infer<
  typeof financialEventCreateSchema
>;
export type FinancialEventListQueryInput = z.infer<
  typeof financialEventListQuerySchema
>;
