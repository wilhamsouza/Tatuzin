import { z } from 'zod';

export const supportCaseStatuses = ['OPEN', 'IN_PROGRESS', 'WAITING', 'RESOLVED'] as const;
export const supportCasePriorities = ['CRITICAL', 'HIGH', 'NORMAL', 'LOW'] as const;
export const supportCaseEvidenceTypes = ['SYNC_EVENT', 'SYNC_CONFLICT', 'DEVICE', 'BILLING_INVOICE', 'AUDIT_EVENT'] as const;
const id = z.string().trim().min(1).max(120);
const subject = z.string().trim().min(3).max(180);
const body = z.string().trim().min(1).max(8000);

export const supportCaseCreateSchema = z.object({
  companyId: id,
  subject,
  description: body,
  priority: z.enum(supportCasePriorities).default('NORMAL'),
  assigneeId: id.nullable().optional(),
  evidence: z.object({ type: z.enum(supportCaseEvidenceTypes), id }).strict().optional(),
  requestKey: z.string().uuid(),
}).strict();

export const supportCaseUpdateSchema = z.object({
  expectedRevision: z.number().int().nonnegative(),
  subject: subject.optional(),
  description: body.optional(),
  priority: z.enum(supportCasePriorities).optional(),
  status: z.enum(supportCaseStatuses).optional(),
  assigneeId: id.nullable().optional(),
  resolution: body.optional(),
}).strict().refine(value => Object.keys(value).some(key => key !== 'expectedRevision'), 'Informe uma alteração.');

export const supportCaseNoteSchema = z.object({
  expectedRevision: z.number().int().nonnegative(),
  body,
}).strict();

export const supportCaseListSchema = z.object({
  companyId: id.optional(),
  status: z.enum([...supportCaseStatuses, 'active']).optional(),
  assigneeId: id.optional(),
  mine: z.enum(['true', 'false']).optional(),
  search: z.string().trim().max(180).optional(),
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(20),
}).strict();

export type SupportCaseCreateInput = z.infer<typeof supportCaseCreateSchema>;
export type SupportCaseUpdateInput = z.infer<typeof supportCaseUpdateSchema>;
export type SupportCaseNoteInput = z.infer<typeof supportCaseNoteSchema>;
export type SupportCaseListInput = z.infer<typeof supportCaseListSchema>;
