import { z } from 'zod';

export const journeyEventNames = [
  'registration_completed', 'product_created', 'cash_opened',
  'checkout_started', 'checkout_completed', 'checkout_exited', 'checkout_failed',
  'plans_viewed', 'subscription_started',
] as const;

const identifier = z.string().min(1).max(120).regex(/^[a-zA-Z0-9_-]+$/);
export const journeyEventSchema = z.object({
  eventId: identifier,
  name: z.enum(journeyEventNames),
  occurredAt: z.string().datetime(),
  appVersion: z.string().min(1).max(40).regex(/^[a-zA-Z0-9.+_-]+$/),
  plan: z.enum(['FREE', 'BASIC', 'PRO']),
  experienceProfile: z.enum(['moda', 'alimentacao', 'misto']),
  attemptId: identifier.optional(),
  durationMs: z.number().int().min(0).max(2147483647).optional(),
}).strict().superRefine((event, context) => {
  if (event.name.startsWith('checkout_') && !event.attemptId) {
    context.addIssue({ code: z.ZodIssueCode.custom, path: ['attemptId'], message: 'Tentativa obrigatoria.' });
  }
  if (event.name === 'checkout_completed' && event.durationMs === undefined) {
    context.addIssue({ code: z.ZodIssueCode.custom, path: ['durationMs'], message: 'Duracao obrigatoria.' });
  }
});

export const journeyBatchSchema = z.object({
  companyId: z.string().min(1).max(120),
  events: z.array(journeyEventSchema).min(1).max(50),
}).strict();

export const journeyReportQuerySchema = z.object({
  days: z.coerce.number().int().min(1).max(90).default(30),
  companyId: z.string().min(1).max(120).optional(),
  appVersion: z.string().max(40).optional(),
  plan: z.enum(['FREE', 'BASIC', 'PRO']).optional(),
  experienceProfile: z.enum(['moda', 'alimentacao', 'misto']).optional(),
}).strict();

export type JourneyBatch = z.infer<typeof journeyBatchSchema>;
export type JourneyReportQuery = z.infer<typeof journeyReportQuerySchema>;
