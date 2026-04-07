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

export const saleItemInputSchema = z.object({
  productId: z.union([z.string().uuid(), z.null(), z.undefined()]).transform(
    (value) => value ?? null,
  ),
  productNameSnapshot: z.string().trim().min(1).max(160),
  quantityMil: z.coerce.number().int().positive(),
  unitPriceCents: z.coerce.number().int().min(0),
  totalPriceCents: z.coerce.number().int().min(0),
  unitCostCents: z.coerce.number().int().min(0),
  totalCostCents: z.coerce.number().int().min(0),
  unitMeasure: nullableTrimmedString(20),
  productType: nullableTrimmedString(30),
});

export const saleCreateSchema = z.object({
  localUuid: z.string().trim().min(1).max(80),
  customerId: z.union([z.string().uuid(), z.null(), z.undefined()]).transform(
    (value) => value ?? null,
  ),
  receiptNumber: nullableTrimmedString(60),
  paymentType: z.enum(['vista', 'fiado']),
  paymentMethod: z.enum(['dinheiro', 'pix', 'cartao', 'fiado']),
  status: z.enum(['active', 'canceled']).default('active'),
  totalAmountCents: z.coerce.number().int().min(0),
  totalCostCents: z.coerce.number().int().min(0),
  soldAt: z.string().datetime(),
  notes: nullableTrimmedString(1000),
  items: z.array(saleItemInputSchema).min(1),
});

export const saleCancelSchema = z.object({
  localUuid: z.string().trim().min(1).max(80),
  canceledAt: z.string().datetime(),
});

export type SaleCreateInput = z.infer<typeof saleCreateSchema>;
export type SaleItemInput = z.infer<typeof saleItemInputSchema>;
export type SaleCancelInput = z.infer<typeof saleCancelSchema>;
