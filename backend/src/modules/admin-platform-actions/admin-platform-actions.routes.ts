import { createHash } from 'node:crypto';
import { Prisma } from '@prisma/client';
import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../../database/prisma';
import { AppError } from '../../shared/http/app-error';
import { asyncHandler } from '../../shared/http/async-handler';
import { validateBody } from '../../shared/http/validate';
import { AdminService } from '../admin/admin.service';
import { BillingAdminService } from '../billing/billing-admin.service';
import { SyncSupportService } from '../sync/sync-support.service';
import { buildOperationalActionDryRun } from '../support-actions/support-actions.service';
import { SupportActionAuditPersistenceService } from '../support-actions/support-actions.audit-persistence';
import { SupportActionExecutionService } from '../support-actions/support-actions.execution.service';

const permissions = {
  'access.block': 'support.user.block',
  'access.reactivate': 'support.user.unblock',
  'license.extend': 'support.license.update',
  'license.suspend': 'support.license.update',
  'license.reactivate': 'support.license.update',
  'billing.refresh': 'admin.billing.manage',
  'device.diagnostics': 'support.sync.force',
  'session.revoke': 'support.session.revoke',
} as const;
const actionNames = Object.keys(permissions) as [keyof typeof permissions, ...(keyof typeof permissions)[]];
const previewSchema = z.object({
  action: z.enum(actionNames), companyId: z.string().uuid(), targetId: z.string().uuid().optional(),
  reason: z.string().trim().min(12).max(1000), days: z.number().int().min(1).max(7).optional(),
}).strict().superRefine((value, ctx) => {
  if ((value.action.startsWith('access.') || value.action.startsWith('session.') || value.action.startsWith('device.')) && !value.targetId)
    ctx.addIssue({ code: 'custom', path: ['targetId'], message: 'Informe o alvo da operação.' });
  if (value.action === 'license.extend' && !value.days)
    ctx.addIssue({ code: 'custom', path: ['days'], message: 'Informe de 1 a 7 dias.' });
});
const executeSchema = z.object({ previewId: z.string().uuid(), confirmationText: z.string().trim().min(1).max(80), idempotencyKey: z.string().trim().min(12).max(160) }).strict();
type Input = z.infer<typeof previewSchema>;
const billing = new BillingAdminService();
const admin = new AdminService();
const sync = new SyncSupportService();
const hash = (data: unknown) => createHash('sha256').update(JSON.stringify(data)).digest('hex');
const json = (data: unknown) => JSON.parse(JSON.stringify(data)) as Prisma.InputJsonValue;

async function authorize(actor: string, input: Input) {
  const grants = await prisma.adminUserPermission.count({ where: {
    actorUserId: actor, permissionKey: permissions[input.action], isActive: true,
    OR: [{ scope: 'platform', scopeId: '*' }, { scope: 'company', scopeId: input.companyId }],
  } });
  if (!grants) throw new AppError('Sem permissão para esta operação nesta empresa.', 403, 'ADMIN_OPERATION_FORBIDDEN');
  const company = await prisma.company.findUnique({ where: { id: input.companyId }, select: { id: true } });
  if (!company) throw new AppError('Empresa não encontrada.', 404, 'COMPANY_NOT_FOUND');
}

async function baseline(input: Input) {
  let target: unknown;
  if (input.action.startsWith('access.')) target = await prisma.employeeProfile.findFirst({ where: { id: input.targetId, companyId: input.companyId }, select: { id: true, updatedAt: true, status: true, role: true } });
  else if (input.action === 'session.revoke') target = await prisma.deviceSession.findFirst({ where: { id: input.targetId, companyId: input.companyId }, select: { id: true, revokedAt: true, refreshTokenExpiresAt: true } });
  else if (input.action === 'device.diagnostics') target = await prisma.companyDevice.findFirst({ where: { id: input.targetId, companyId: input.companyId }, select: { id: true, status: true } });
  else target = await prisma.license.findUnique({ where: { companyId: input.companyId } });
  if (!target) throw new AppError('Alvo não encontrado nesta empresa.', 404, 'ADMIN_OPERATION_TARGET_NOT_FOUND');
  return hash(target);
}

async function simulate(actorUserId: string, input: Input) {
  const context = { companyId: input.companyId, actorUserId, reason: input.reason, ipAddress: null, userAgent: null };
  if (input.action === 'license.extend') return billing.dryRunEmergencyExtension({ ...context, days: input.days! });
  if (input.action === 'license.suspend') return billing.dryRunLicenseSuspend(context);
  if (input.action === 'license.reactivate') return billing.dryRunLicenseReactivate(context);
  if (input.action === 'access.block') return admin.dryRunAccessBlock({ ...context, targetId: input.targetId!, targetType: 'EMPLOYEE' });
  if (input.action === 'access.reactivate') return admin.dryRunAccessReactivate({ ...context, targetId: input.targetId!, targetType: 'EMPLOYEE' });
  if (input.action === 'device.diagnostics') return sync.adminDryRun(input.companyId, input.targetId!, { command: 'REFRESH_SYNC_STATUS', reason: input.reason });
  if (input.action === 'session.revoke') {
    const result = buildOperationalActionDryRun({ actionType: 'revoke_session', companyId: input.companyId, targetType: 'session', targetId: input.targetId!, actorAdminId: actorUserId, reason: input.reason, dryRun: true }, new Date(), { actorAdminId: actorUserId, permissionKeys: ['support.session.revoke'], allowPlatformAdminFallback: false });
    if (!result.ok || !result.action) throw new AppError(result.message, 409, result.code);
    const sourceAuditEventId = await new SupportActionAuditPersistenceService().recordDryRun(result.action);
    return { allowed: true, expectedConfirmationText: 'REVOGAR_SESSAO', summary: 'Revogar esta sessão. O usuário precisará entrar novamente.', risks: ['A sessão perde o acesso imediatamente.'], sourceAuditEventId };
  }
  return { allowed: true, expectedConfirmationText: 'ATUALIZAR_COBRANCA', summary: 'Consultar o provedor e atualizar o estado local da assinatura, preservando suas regras atuais.', risks: ['O estado local poderá refletir alterações já confirmadas pelo provedor.'] };
}

async function apply(actorUserId: string, input: Input, confirmationText: string) {
  const context = { companyId: input.companyId, actorUserId, reason: input.reason, confirmationText, ipAddress: null, userAgent: null };
  switch (input.action) {
    case 'license.extend': return billing.applyEmergencyExtension({ ...context, days: input.days! });
    case 'license.suspend': return billing.applyLicenseSuspend(context);
    case 'license.reactivate': return billing.applyLicenseReactivate(context);
    case 'access.block': return admin.applyAccessBlock({ ...context, targetId: input.targetId!, targetType: 'EMPLOYEE' });
    case 'access.reactivate': return admin.applyAccessReactivate({ ...context, targetId: input.targetId!, targetType: 'EMPLOYEE' });
    case 'billing.refresh': return billing.refreshCompany(context);
    case 'device.diagnostics': return sync.createAdminCommand(input.companyId, input.targetId!, { command: 'REFRESH_SYNC_STATUS', reason: input.reason, confirmationText, payload: {} }, { actorUserId, ipAddress: null, userAgent: null });
    default: throw new AppError('Operação não suportada.', 422, 'ADMIN_OPERATION_UNSUPPORTED');
  }
}

export const adminPlatformActionsRouter = Router();
adminPlatformActionsRouter.post('/preview', validateBody(previewSchema), asyncHandler(async (req, res) => {
  const input = req.body as Input;
  const actor = req.auth!.userId;
  await authorize(actor, input);
  const fingerprint = await baseline(input);
  const impact = await simulate(actor, input);
  const expiresAt = new Date(Date.now() + 10 * 60_000).toISOString();
  const audit = await prisma.adminAuditLog.create({ data: { actorUserId: actor, targetCompanyId: input.companyId, action: 'platform.operation.preview', details: json({ input, fingerprint, expiresAt, impact }) } });
  res.json({ previewId: audit.id, expiresAt, ...impact });
}));

adminPlatformActionsRouter.post('/execute', validateBody(executeSchema), asyncHandler(async (req, res) => {
  const request = req.body as z.infer<typeof executeSchema>;
  const actor = req.auth!.userId;
  const audit = await prisma.adminAuditLog.findFirst({ where: { id: request.previewId, actorUserId: actor, action: 'platform.operation.preview' } });
  if (!audit) throw new AppError('Prévia não encontrada para este administrador.', 404, 'ADMIN_PREVIEW_NOT_FOUND');
  const saved = audit.details as unknown as { input: Input; fingerprint: string; expiresAt: string; impact: { allowed: boolean; expectedConfirmationText: string; sourceAuditEventId?: string } };
  const input = previewSchema.parse(saved.input);
  await authorize(actor, input);
  if (saved.impact.allowed !== true || request.confirmationText !== saved.impact.expectedConfirmationText)
    throw new AppError('Confirme o texto solicitado em uma prévia permitida.', 422, 'ADMIN_CONFIRMATION_INVALID');
  if (input.action === 'session.revoke') {
    const receipt = await prisma.supportActionExecution.findUnique({ where: { idempotencyKey: `platform:${actor}:${request.idempotencyKey}` } });
    if (!receipt && new Date(saved.expiresAt).getTime() <= Date.now()) throw new AppError('Prévia expirada. Gere uma nova prévia.', 409, 'ADMIN_PREVIEW_EXPIRED');
    const result = await new SupportActionExecutionService().executeRevokeSession({ actionType: 'revoke_session', companyId: input.companyId, targetType: 'session', targetId: input.targetId!, actorAdminId: actor, reason: input.reason, dryRunAuditEventId: saved.impact.sourceAuditEventId, idempotencyKey: `platform:${actor}:${request.idempotencyKey}`, explicitConfirmation: true, confirmationText: request.confirmationText }, { actorAdminId: actor, permissionKeys: ['support.session.revoke'], allowPlatformAdminFallback: false, isPlatformAdmin: true });
    if (!result.ok) throw new AppError(result.message, 409, result.code);
    res.json(result); return;
  }
  const key = `platform:${actor}:${request.idempotencyKey}`;
  const fingerprint = hash({ previewId: audit.id, input });
  const replay = await prisma.supportActionExecution.findUnique({ where: { idempotencyKey: key } });
  if (replay) {
    if (replay.requestFingerprint !== fingerprint) throw new AppError('Chave de reenvio pertence a outra operação.', 409, 'ADMIN_OPERATION_KEY_MISMATCH');
    if (replay.status === 'SUCCEEDED') { res.json({ ok: true, status: 'replayed', result: replay.result }); return; }
    throw new AppError('Operação em processamento ou com resultado não confirmado. Consulte a auditoria antes de uma nova tentativa.', 409, 'ADMIN_OPERATION_INDETERMINATE');
  }
  if (new Date(saved.expiresAt).getTime() <= Date.now()) throw new AppError('Prévia expirada. Gere uma nova prévia.', 409, 'ADMIN_PREVIEW_EXPIRED');
  if (await baseline(input) !== saved.fingerprint) throw new AppError('O alvo mudou após a prévia. Revise uma nova prévia.', 409, 'ADMIN_PREVIEW_STALE');
  const current = await simulate(actor, input);
  if (!current.allowed) throw new AppError('As condições da operação mudaram.', 409, 'ADMIN_OPERATION_BLOCKED');
  let claim;
  try {
    claim = await prisma.supportActionExecution.create({ data: { idempotencyKey: key, requestFingerprint: fingerprint, dryRunAuditEventId: audit.id, actionType: input.action, targetCompanyId: input.companyId, targetType: input.action.split('.')[0], targetId: input.targetId ?? input.companyId, actorUserId: actor, reason: input.reason } });
  } catch (error) {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') throw new AppError('Operação já recebida. Consulte o resultado.', 409, 'ADMIN_OPERATION_IN_PROGRESS');
    throw error;
  }
  try {
    const result = await apply(actor, input, request.confirmationText);
    await prisma.$transaction(async tx => {
      const after = await tx.adminAuditLog.create({ data: { actorUserId: actor, targetCompanyId: input.companyId, action: 'platform.operation.executed', details: json({ action: input.action, previewId: audit.id, executionId: claim.id, targetId: input.targetId ?? input.companyId, reason: input.reason }) } });
      await tx.supportActionExecution.update({ where: { id: claim.id }, data: { status: 'SUCCEEDED', result: json(result), executedAt: new Date(), beforeAuditEventId: audit.id, afterAuditEventId: after.id } });
    });
    res.json({ ok: true, status: input.action === 'device.diagnostics' ? 'requested' : 'succeeded', result });
  } catch (error) {
    await prisma.supportActionExecution.update({ where: { id: claim.id }, data: { status: 'FAILED', result: json({ code: error instanceof AppError ? error.code : 'UNCONFIRMED', message: 'Consulte a auditoria antes de repetir a operação.' }) } });
    throw error;
  }
}));
