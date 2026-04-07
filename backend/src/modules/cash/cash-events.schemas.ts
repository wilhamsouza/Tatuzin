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

export const cashEventCreateSchema = z.object({
  localUuid: z.string().trim().min(1).max(80),
  eventType: z.enum(['entrada', 'saida', 'retirada', 'fiado_pagamento']),
  amountCents: z.coerce.number().int().positive(),
  paymentMethod: z
    .union([
      z.enum(['dinheiro', 'pix', 'cartao', 'fiado']),
      z.null(),
      z.undefined(),
    ])
    .transform((value) => value ?? null),
  referenceType: nullableTrimmedString(40),
  referenceId: nullableTrimmedString(80),
  notes: nullableTrimmedString(1000),
  createdAt: z.string().datetime(),
});

export type CashEventCreateInput = z.infer<typeof cashEventCreateSchema>;
