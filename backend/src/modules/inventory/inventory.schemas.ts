import { z } from 'zod';

import { paginationQuerySchema } from '../../shared/http/pagination';

const nullableSearch = z
  .union([z.string().trim().max(120), z.null(), z.undefined()])
  .transform((value) => {
    if (value == null) {
      return '';
    }
    return value.trim();
  });

export const inventoryListQuerySchema = paginationQuerySchema.extend({
  query: nullableSearch,
  filter: z.enum(['all', 'active', 'zeroed', 'belowMinimum', 'inactive']).default('all'),
  productId: z.string().uuid().optional(),
  productVariantId: z.string().uuid().optional(),
  companyId: z.never().optional(),
});

export const inventorySummaryQuerySchema = z.object({
  companyId: z.never().optional(),
});

export type InventoryListQueryInput = z.infer<typeof inventoryListQuerySchema>;


const uuid = z.string().uuid();
const revision = z.number().int().nonnegative();
const request = { requestId: uuid };
export const inventoryTargetQuerySchema = z.object({ productVariantId: uuid.optional(), companyId: z.never().optional() });
export const inventoryAdjustmentSchema = z.object({ ...request, productId: uuid, productVariantId: uuid.nullish(), expectedRevision: revision, quantityDeltaMil: z.number().int().min(-2147483647).max(2147483647).refine(v => v !== 0), reason: z.string().trim().min(3).max(180), notes: z.string().trim().max(2000).optional() }).strict();
export const inventorySettingsSchema = z.object({ expectedRevision: revision, minimumStockMil: z.number().int().nonnegative().max(2147483647), reorderPointMil: z.number().int().nonnegative().max(2147483647).nullish() }).strict();
const dateOnly = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(v => !Number.isNaN(Date.parse(v)) && new Date(v).toISOString().slice(0,10) === v);
export const inventoryMovementsQuerySchema = paginationQuerySchema.extend({ productId: uuid.optional(), productVariantId: uuid.optional(), startDate: dateOnly.optional(), endDate: dateOnly.optional(), type: z.string().trim().max(60).optional(), origin: z.string().trim().max(60).optional(), companyId: z.never().optional() });
export const inventoryCountListSchema = paginationQuerySchema.extend({ status: z.enum(['OPEN','COUNTING','REVIEWED','APPLIED','CANCELED']).optional(), companyId: z.never().optional() });
export const inventoryCountCreateSchema = z.object({ ...request, name: z.string().trim().min(1).max(120), productIds: z.array(uuid).max(500).optional() }).strict();
export const inventoryCountUpdateSchema = z.object({ expectedRevision: revision, name: z.string().trim().min(1).max(120).optional(), assigneeUserId: uuid.optional() }).strict();
export const inventoryCountItemsSchema = z.object({ expectedRevision: revision, items: z.array(z.object({ productId: uuid, productVariantId: uuid.nullish(), countedStockMil: z.number().int().nonnegative().max(2147483647).nullable().optional(), expectedStockRevision: revision.optional(), remove: z.boolean().optional() }).strict().superRefine((item,ctx) => { if(!item.remove && (item.countedStockMil === undefined || item.expectedStockRevision === undefined)) ctx.addIssue({code:z.ZodIssueCode.custom,message:'Informe quantidade (ou null) e revisão do estoque para contar.',path:['countedStockMil']}); })).min(1).max(500) }).strict();
export const inventoryCountActionSchema = z.object({ ...request, expectedRevision: revision }).strict();
export type InventoryAdjustmentInput = z.infer<typeof inventoryAdjustmentSchema>;
export type InventorySettingsInput = z.infer<typeof inventorySettingsSchema>;
export type InventoryMovementsQuery = z.infer<typeof inventoryMovementsQuerySchema>;
export type InventoryCountListQuery = z.infer<typeof inventoryCountListSchema>;
export type InventoryCountCreateInput = z.infer<typeof inventoryCountCreateSchema>;
export type InventoryCountUpdateInput = z.infer<typeof inventoryCountUpdateSchema>;
export type InventoryCountItemsInput = z.infer<typeof inventoryCountItemsSchema>;
export type InventoryCountActionInput = z.infer<typeof inventoryCountActionSchema>;
