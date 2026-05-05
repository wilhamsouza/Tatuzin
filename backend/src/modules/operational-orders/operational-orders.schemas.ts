import { z } from 'zod';

const optionalTrimmedString = (maxLength: number) =>
  z
    .union([z.string(), z.undefined()])
    .transform((value) => {
      if (value == null) {
        return undefined;
      }

      const normalized = value.trim();
      return normalized.length === 0
        ? undefined
        : normalized.slice(0, maxLength);
    });

const optionalDateQuery = z
  .union([z.string(), z.undefined()])
  .transform((value) => {
    if (value == null) {
      return undefined;
    }

    const normalized = value.trim();
    return normalized.length === 0 ? undefined : normalized;
  })
  .refine(
    (value) => value === undefined || !Number.isNaN(new Date(value).getTime()),
    { message: 'Data invalida para filtro de pedidos operacionais.' },
  )
  .transform((value) => (value === undefined ? undefined : new Date(value)));

export const operationalOrderListQuerySchema = z.object({
  status: optionalTrimmedString(40),
  cashSessionId: optionalTrimmedString(80),
  customerId: optionalTrimmedString(80),
  deviceId: optionalTrimmedString(80),
  sellerUserId: optionalTrimmedString(80),
  convertedSaleId: optionalTrimmedString(80),
  from: optionalDateQuery,
  to: optionalDateQuery,
  limit: z.coerce.number().int().min(1).max(100).default(20),
  page: z.coerce.number().int().min(1).default(1),
});

export const operationalOrderIdParamSchema = z.object({
  id: z.string().trim().min(1).max(120),
});

export const operationalOrderLocalUuidParamSchema = z.object({
  localUuid: z.string().trim().min(1).max(160),
});

export type OperationalOrderListQueryInput = z.infer<
  typeof operationalOrderListQuerySchema
>;
