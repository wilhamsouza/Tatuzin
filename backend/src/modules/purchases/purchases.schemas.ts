import { z } from 'zod';

import { createListQuerySchema } from '../../shared/http/pagination';

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

const nullableUuid = z
  .union([z.string().uuid(), z.null(), z.undefined()])
  .transform((value) => value ?? null);

const paymentMethodSchema = z
  .enum(['dinheiro', 'pix', 'cartao'])
  .nullable()
  .optional()
  .transform((value) => value ?? null);

const purchaseItemSchema = z
  .object({
    localUuid: z.string().trim().min(1).max(80),
    itemType: z.enum(['product', 'supply']).default('product'),
    productId: nullableUuid,
    productVariantId: nullableUuid,
    supplyId: nullableUuid,
    productNameSnapshot: z.string().trim().min(1).max(180),
    variantSkuSnapshot: nullableTrimmedString(80),
    variantColorLabelSnapshot: nullableTrimmedString(80),
    variantSizeLabelSnapshot: nullableTrimmedString(80),
    unitMeasureSnapshot: z.string().trim().min(1).max(20),
    quantityMil: z.coerce.number().int().positive(),
    unitCostCents: z.coerce.number().int().min(0),
    subtotalCents: z.coerce.number().int().min(0),
  })
  .superRefine((value, ctx) => {
    const hasProduct = value.productId != null;
    const hasSupply = value.supplyId != null;

    if (value.itemType === 'product') {
      if (!hasProduct || hasSupply) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          path: ['productId'],
          message: 'Itens de compra do tipo product exigem productId e nao aceitam supplyId.',
        });
      }
      return;
    }

    if (!hasSupply || hasProduct || value.productVariantId != null) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['supplyId'],
        message:
          'Itens de compra do tipo supply exigem supplyId e nao aceitam productId nem productVariantId.',
      });
    }
  });

const purchasePaymentSchema = z.object({
  localUuid: z.string().trim().min(1).max(80),
  amountCents: z.coerce.number().int().positive(),
  paymentMethod: z.enum(['dinheiro', 'pix', 'cartao']),
  paidAt: z.string().datetime(),
  notes: nullableTrimmedString(800),
});

export const purchaseUpsertSchema = z.object({
  localUuid: z.string().trim().min(1).max(80),
  supplierId: z.string().uuid(),
  documentNumber: nullableTrimmedString(80),
  notes: nullableTrimmedString(1200),
  purchasedAt: z.string().datetime(),
  dueDate: z
    .union([z.string().datetime(), z.null(), z.undefined()])
    .transform((value) => (value == null ? null : value)),
  paymentMethod: paymentMethodSchema,
  status: z.enum([
    'rascunho',
    'aberta',
    'recebida',
    'parcialmente_paga',
    'paga',
    'cancelada',
  ]),
  subtotalCents: z.coerce.number().int().min(0),
  discountCents: z.coerce.number().int().min(0).default(0),
  surchargeCents: z.coerce.number().int().min(0).default(0),
  freightCents: z.coerce.number().int().min(0).default(0),
  finalAmountCents: z.coerce.number().int().min(0),
  paidAmountCents: z.coerce.number().int().min(0).default(0),
  pendingAmountCents: z.coerce.number().int().min(0),
  canceledAt: z
    .union([z.string().datetime(), z.null(), z.undefined()])
    .transform((value) => (value == null ? null : value)),
  items: z.array(purchaseItemSchema).min(1),
  payments: z.array(purchasePaymentSchema).default([]),
});

export const purchaseListQuerySchema = createListQuerySchema();

export type PurchaseUpsertInput = z.infer<typeof purchaseUpsertSchema>;
export type PurchaseItemInput = z.infer<typeof purchaseItemSchema>;
export type PurchasePaymentInput = z.infer<typeof purchasePaymentSchema>;
export type PurchaseListQueryInput = z.infer<typeof purchaseListQuerySchema>;
