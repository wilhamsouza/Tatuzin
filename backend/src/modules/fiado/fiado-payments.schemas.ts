import { z } from 'zod';

const nullableTrimmedString = (maxLength: number) =>
  z
    .union([z.string().trim().max(maxLength), z.null(), z.undefined()])
    .transform((value) => {
      if (value == null) {
        return null;
      }

      const trimmed = value.trim();
      return trimmed.length == 0 ? null : trimmed;
    });

export const fiadoPaymentCreateSchema = z.object({
  saleId: z.string().uuid(),
  localUuid: z.string().trim().min(1).max(80),
  amountCents: z.coerce.number().int().positive(),
  paymentMethod: z.enum(['dinheiro', 'pix', 'cartao']),
  createdAt: z.string().datetime(),
  notes: nullableTrimmedString(1000),
});

export type FiadoPaymentCreateInput = z.infer<typeof fiadoPaymentCreateSchema>;
