import { z } from 'zod';

const cents = z.number().int().min(0).max(2147483647);
const policy = { version: z.literal(2), blindClosureEnabled: z.boolean(), policyRevision: cents };
const count = { denominations: z.array(z.object({ valueCents: cents.positive(), quantity: cents })).max(100).optional(), coinsCents: cents.optional() };
export const openingDetailsSchema = z.object({ ...policy, ...count, countedAmountCents: cents }).strict();
export const closingDetailsSchema = z.object({ ...policy, ...count, sessionUuid: z.string().min(1).max(120), expectedBalanceCents: z.number().int().min(-2147483648).max(2147483647), countedBalanceCents: cents, differenceCents: z.number().int().min(-2147483648).max(2147483647), reason: z.string().trim().max(500).optional(), notes: z.string().trim().max(2000).optional() }).strict();
export function validateCashV2Count(details: { denominations?: {valueCents:number;quantity:number}[]; coinsCents?:number }, total: number) {
  if (details.denominations === undefined && details.coinsCents === undefined) return true;
  const values = details.denominations ?? [];
  return new Set(values.map(item => item.valueCents)).size === values.length &&
    values.reduce((sum, item) => sum + item.valueCents * item.quantity, details.coinsCents ?? 0) === total;
}
export function cashMetadataEqual(a: unknown, b: unknown): boolean {
  const canonical = (value: unknown): unknown => Array.isArray(value) ? value.map(canonical) : value && typeof value === 'object' ? Object.fromEntries(Object.entries(value).sort(([a], [b]) => a.localeCompare(b)).map(([k,v]) => [k,canonical(v)])) : value;
  return JSON.stringify(canonical(a)) === JSON.stringify(canonical(b));
}
