import { Router } from 'express';
import { Prisma } from '@prisma/client';
import { z } from 'zod';
import { prisma } from '../../database/prisma';
import { asyncHandler } from '../../shared/http/async-handler';
import { validateBody, validateQuery } from '../../shared/http/validate';
import { logger } from '../../shared/observability/logger';
import { AppError } from '../../shared/http/app-error';
import { env } from '../../config/env';
import { getAdminPlatformAccess, requireAdminPlatformPermission, type AdminPlatformAccess } from './admin-platform.access';
import { getAdminPermissionDefinition } from '../admin-permissions/admin-permissions.catalog';

const sections = { overview: 'admin.overview.read', companies: 'admin.companies.read', support: 'admin.support.read', sync: 'admin.sync.read', billing: 'admin.billing.read', devices: 'admin.devices.read', usage: 'admin.usage.read', audit: 'admin.audit.read', administration: 'admin-permissions.manage' };
export const platformActionPermissions = { 'admin.support.manage': 'admin.support.manage', 'access.block': 'support.user.block', 'access.reactivate': 'support.user.unblock', 'license.extend': 'support.license.update', 'license.suspend': 'support.license.update', 'license.reactivate': 'support.license.update', 'billing.refresh': 'admin.billing.manage', 'device.diagnostics': 'support.sync.force', 'session.revoke': 'support.session.revoke' };
const readKeys = Object.values(sections).filter(key => key !== 'admin-permissions.manage');
const templates = [
  { key: 'management', label: 'Gestão da plataforma', permissions: [...readKeys, 'admin.support.manage'] },
  { key: 'support', label: 'Suporte', permissions: ['admin.overview.read', 'admin.companies.read', 'admin.support.read', 'admin.support.manage', 'admin.sync.read', 'admin.devices.read', 'admin.audit.read', 'support.session.revoke'] },
  { key: 'finance', label: 'Financeiro', permissions: ['admin.overview.read', 'admin.companies.read', 'admin.billing.read', 'admin.billing.manage', 'admin.audit.read', 'support.license.update'] },
  { key: 'audit', label: 'Auditoria', permissions: ['admin.overview.read', 'admin.companies.read', 'admin.audit.read'] },
];
const paging = { page: z.coerce.number().int().min(1).default(1), pageSize: z.coerce.number().int().min(1).max(100).default(20) };
const dateOnly = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(s => !Number.isNaN(Date.parse(s)) && new Date(s).toISOString().slice(0, 10) === s, 'Data inválida.');
const periodSchema = z.object({ startDate: dateOnly.optional(), endDate: dateOnly.optional() }).refine(q => {
  let p; try { p = period(q); } catch { return false; } return p.end.getTime() > p.start.getTime() && p.end.getTime() - p.start.getTime() <= 90 * 86400000;
}, 'Selecione até 90 dias em ordem cronológica.');
function period(q: { startDate?: string; endDate?: string }) {
  const today = new Date().toISOString().slice(0, 10);
  const end = new Date((q.endDate ?? today) + 'T00:00:00Z');
  const start = q.startDate ? new Date(q.startDate + 'T00:00:00Z') : new Date(end.getTime() - 29 * 86400000);
  return { start, end: new Date(end.getTime() + 86400000), dto: { startDate: start.toISOString().slice(0, 10), endDate: end.toISOString().slice(0, 10), timezone: 'UTC' } };
}
async function section(access: AdminPlatformAccess, key: string, load: () => Promise<object>) {
  if (!access.has(key)) return { available: false, reason: 'FORBIDDEN' };
  try { return { available: true, ...await load() }; } catch { logger.warn('admin.platform.section.unavailable', { section: key }); return { available: false, reason: 'SOURCE_UNAVAILABLE' }; }
}
function series(rows: Array<{ date: string; count?: bigint; amountCents?: bigint }>) { return rows.map(row => ({ ...row, count: Number(row.count ?? 0), ...(row.amountCents != null ? { amountCents: Number(row.amountCents) } : {}) })); }
function sqlScope(access: AdminPlatformAccess, key: string, column: Prisma.Sql) {
  const ids = access.companyIds(key);
  return ids == null ? Prisma.empty : ids.length ? Prisma.sql`AND ${column} IN (${Prisma.join(ids)})` : Prisma.sql`AND false`;
}
const failedEvents: Prisma.SyncEventWhereInput = { status: { in: ['FAILED', 'REJECTED'] }, OR: [{ conflict: null }, { conflict: { status: { notIn: ['RESOLVED','IGNORED'] } } }] };
export async function platformTriage(access: AdminPlatformAccess, companyId?: string) {
  const key = 'admin.support.read';
  const rows = await prisma.company.findMany({ where: {
    ...access.companyWhere(key), ...(companyId ? { id: companyId } : {}), OR: [{ syncConflicts: { some: { status: 'OPEN' } } }, { syncEvents: { some: failedEvents } }],
  }, select: { id: true, name: true, _count: { select: { syncConflicts: { where: { status: 'OPEN' } }, syncEvents: { where: failedEvents } } }, syncConflicts: { where: { status: 'OPEN' }, select: { id: true, createdAt: true }, orderBy: { createdAt: 'asc' }, take: 1 }, syncEvents: { where: failedEvents, select: { id: true, createdAt: true }, orderBy: { createdAt: 'asc' }, take: 1 } } });
  return rows.map(row => {
    const failed = row._count.syncEvents;
    const conflict = row._count.syncConflicts;
    const source = failed ? row.syncEvents[0] : row.syncConflicts[0];
    return { companyId: row.id, companyName: row.name, severity: failed ? 'critical' : 'warning', reason: `${failed} eventos com falha ou rejeição · ${conflict} conflitos abertos`, occurredAt: source?.createdAt.toISOString() ?? null, href: `/companies/${row.id}/sync`, evidence: source ? { type: failed ? 'SYNC_EVENT' : 'SYNC_CONFLICT', id: source.id } : null };
  }).sort((a,b) => (a.severity === b.severity ? (a.occurredAt ?? '').localeCompare(b.occurredAt ?? '') : a.severity === 'critical' ? -1 : 1));
}
export const adminPlatformRouter = Router();
adminPlatformRouter.get('/capabilities', asyncHandler(async (req, res) => {
  const access = await getAdminPlatformAccess(req.auth!.userId);
  res.json({ experienceEnabled: (process.env.ADMIN_PLATFORM_PILOT_USER_IDS ?? '').split(',').map(s => s.trim()).includes(req.auth!.userId),
    sections: Object.entries(sections).map(([key,permission]) => ({ key, allowed: access.has(permission), globalAllowed: access.companyIds(permission) === null, companyIds: access.companyIds(permission) })),
    actions: Object.entries(platformActionPermissions).map(([key,permission]) => ({ key, allowed: access.has(permission) && (key !== 'session.revoke' || env.SUPPORT_ACTION_REVOKE_SESSION_EXECUTION_ENABLED), requiresDryRun: key !== 'admin.support.manage', scopes: access.grants.filter(g => g.permissionKey === permission && g.isActive).map(g => ({ scope: g.scope, scopeId: g.scopeId })) })),
    templates: access.has('admin-permissions.manage') ? templates : [],
  });
}));
adminPlatformRouter.get('/platform-companies', validateQuery(z.object({ ...paging, search: z.string().trim().max(120).optional(), sortBy: z.enum(['createdAt','updatedAt','name']).default('createdAt'), sortDirection: z.enum(['asc','desc']).default('desc'), licenseStatus: z.enum(['active','trial','expired','suspended','without_license']).optional(), isActive: z.enum(['true','false']).optional() })), asyncHandler(async(req,res)=>{
 const access=await requireAdminPlatformPermission(req.auth!.userId,'admin.companies.read');
 const q=req.query as unknown as {page:number;pageSize:number;search?:string;sortBy:'createdAt'|'updatedAt'|'name';sortDirection:'asc'|'desc';licenseStatus?:string;isActive?:string};
 const where:Prisma.CompanyWhereInput={...access.companyWhere('admin.companies.read'),...(q.search?{OR:[{name:{contains:q.search,mode:'insensitive'}},{slug:{contains:q.search,mode:'insensitive'}},{documentNumber:{contains:q.search}}]}:{}),...(q.isActive?{isActive:q.isActive==='true'}:{}),...(q.licenseStatus?{license:q.licenseStatus==='without_license'?null:{status:q.licenseStatus.toUpperCase() as 'ACTIVE'|'TRIAL'|'EXPIRED'|'SUSPENDED'}}:{})};
 const [total,items]=await Promise.all([prisma.company.count({where}),prisma.company.findMany({where,select:{id:true,name:true,slug:true,isActive:true,createdAt:true,license:{select:{plan:true,status:true,expiresAt:true}}},orderBy:[{[q.sortBy]:q.sortDirection},{id:'asc'}],skip:(q.page-1)*q.pageSize,take:q.pageSize})]);
 res.json({items,pagination:{page:q.page,pageSize:q.pageSize,total}});
}));
adminPlatformRouter.get('/subscriptions',validateQuery(z.object({...paging,search:z.string().trim().max(120).optional(),status:z.enum(['ACTIVE','TRIAL','EXPIRED','SUSPENDED','active','trial','expired','suspended']).optional(),hasProviderSubscription:z.enum(['true','false']).optional()})),asyncHandler(async(req,res)=>{
 const access=await requireAdminPlatformPermission(req.auth!.userId,'admin.billing.read');const q=req.query as unknown as {page:number;pageSize:number;search?:string;status?:string;hasProviderSubscription?:string};
 const where:Prisma.LicenseWhereInput={...access.companyIdWhere('admin.billing.read'),...(q.status?{status:q.status.toUpperCase() as 'ACTIVE'|'TRIAL'|'EXPIRED'|'SUSPENDED'}:{}),...(q.hasProviderSubscription?{providerSubscriptionId:q.hasProviderSubscription==='true'?{not:null}:null}:{}),...(q.search?{company:{name:{contains:q.search,mode:'insensitive'}}}:{})};
 const [total,rows]=await Promise.all([prisma.license.count({where}),prisma.license.findMany({where,select:{companyId:true,plan:true,status:true,expiresAt:true,company:{select:{name:true}}},orderBy:[{updatedAt:'desc'},{id:'asc'}],skip:(q.page-1)*q.pageSize,take:q.pageSize})]);res.json({items:rows.map(r=>({...r,companyName:r.company.name})),total,page:q.page,pageSize:q.pageSize});
}));
adminPlatformRouter.get('/overview', validateQuery(periodSchema), asyncHandler(async (req, res) => {
  const actor = req.auth!.userId;
  const access = await requireAdminPlatformPermission(actor, 'admin.overview.read');
  const p = period(req.query as { startDate?: string; endDate?: string });
  const [companies, subscriptions, billing, operations, support, audit] = await Promise.all([
    section(access, 'admin.companies.read', async () => {
      const scope = access.companyWhere('admin.companies.read');
      const [total, newInPeriod, rows] = await Promise.all([prisma.company.count({ where: scope }), prisma.company.count({ where: { ...scope, createdAt: { gte: p.start, lt: p.end } } }), prisma.$queryRaw<Array<{ date: string; count: bigint }>>`SELECT to_char("createdAt" AT TIME ZONE 'UTC','YYYY-MM-DD') AS date, count(*) AS count FROM "Company" WHERE "createdAt">=${p.start} AND "createdAt"<${p.end} ${sqlScope(access, 'admin.companies.read', Prisma.sql`id`)} GROUP BY 1 ORDER BY 1`]);
      return { total, newInPeriod, series: series(rows) };
    }),
    section(access, 'admin.billing.read', async () => ({ activePaid: await prisma.license.count({ where: { ...access.companyIdWhere('admin.billing.read'), plan: { in: ['BASIC', 'PRO', 'basic', 'pro'] }, status: 'ACTIVE', billingSubscriptionStatus: { in: ['authorized', 'AUTHORIZED', 'active', 'ACTIVE'] }, OR: [{ expiresAt: null }, { expiresAt: { gt: new Date() } }], providerSubscriptionId: { not: null } } }) })),
    section(access, 'admin.billing.read', async () => {
      const scope = access.companyIdWhere('admin.billing.read');
      const [paid, overdueCount, rows] = await Promise.all([
        prisma.billingInvoice.aggregate({ where: { ...scope, status: { in: ['PAID', 'paid', 'approved'] }, currency: 'BRL', paidAt: { gte: p.start, lt: p.end } }, _sum: { amountCents: true }, _count: true }),
        prisma.billingInvoice.count({ where: { ...scope, status: { in: ['PENDING', 'pending', 'OPEN', 'open', 'PAST_DUE', 'past_due'] }, dueAt: { lt: new Date() }, paidAt: null } }),
        prisma.$queryRaw<Array<{ date: string; count: bigint; amountCents: bigint }>>`SELECT to_char("paidAt" AT TIME ZONE 'UTC','YYYY-MM-DD') AS date, count(*) AS count, sum("amountCents") AS "amountCents" FROM "BillingInvoice" WHERE status IN ('PAID','paid','approved') AND currency='BRL' AND "paidAt">=${p.start} AND "paidAt"<${p.end} ${sqlScope(access, 'admin.billing.read', Prisma.sql`"companyId"`)} GROUP BY 1 ORDER BY 1`,
      ]);
      return { paidAmountCents: paid._sum.amountCents ?? 0, paidCount: paid._count, overdueCount, currency: 'BRL', series: series(rows) };
    }),
    section(access, 'admin.support.read', async () => { const items = await platformTriage(access); return { problemCompanies: items.length, items: items.slice(0, 5) }; }),
    section(access, 'admin.support.read', async () => {
      const where = { ...access.companyIdWhere('admin.support.read'), status: { not: 'RESOLVED' } };
      const [openCount, mine] = await Promise.all([prisma.adminSupportCase.count({ where }), prisma.adminSupportCase.findMany({ where: { ...where, assigneeId: actor }, include: { company: { select: { name: true } }, assignee: { select: { id: true, name: true } } }, orderBy: { updatedAt: 'desc' }, take: 5 })]);
      return { openCount, mine: mine.map(row => ({ ...row, companyName: row.company.name })) };
    }),
    section(access, 'admin.audit.read', async () => ({ items: await prisma.adminAuditLog.findMany({ where: { ...(() => { const ids = access.companyIds('admin.audit.read'); return ids == null ? {} : { targetCompanyId: { in: ids } }; })() }, select: { id: true, action: true, createdAt: true, actorLabel: true }, orderBy: { createdAt: 'desc' }, take: 5 }) })),
  ]);
  res.json({ generatedAt: new Date().toISOString(), period: p.dto, companies, subscriptions, billing, operations, support, audit });
}));
adminPlatformRouter.get('/triage', validateQuery(z.object({ ...paging, companyId: z.string().uuid().optional() })), asyncHandler(async (req, res) => {
  const access = await requireAdminPlatformPermission(req.auth!.userId, 'admin.support.read');
  const q = req.query as unknown as { page: number; pageSize: number; companyId?: string };
  if(q.companyId && !access.has('admin.support.read',q.companyId))throw new AppError('Empresa fora do escopo.',403,'ADMIN_PLATFORM_PERMISSION_REQUIRED');
  const rows = await platformTriage(access,q.companyId); res.json({ items: rows.slice((q.page-1)*q.pageSize,q.page*q.pageSize), total: rows.length, ...q, generatedAt: new Date().toISOString() });
}));
adminPlatformRouter.get('/search', validateQuery(z.object({ q: z.string().trim().max(120).default(''), ...paging })), asyncHandler(async (req, res) => {
  const access = await requireAdminPlatformPermission(req.auth!.userId, 'admin.companies.read');
  const q = req.query as unknown as { q: string; page: number; pageSize: number };
  const where: Prisma.CompanyWhereInput = { ...access.companyWhere('admin.companies.read'), ...(q.q ? { OR: [{ name: { contains: q.q, mode: 'insensitive' } }, { slug: { contains: q.q, mode: 'insensitive' } }, { id: { contains: q.q } }, { documentNumber: { contains: q.q } }, { memberships: { some: { user: { email: { contains: q.q, mode: 'insensitive' } } } } }] } : {}) };
  const [total, rows] = await Promise.all([prisma.company.count({ where }), prisma.company.findMany({ where, select: { id: true, name: true, slug: true }, orderBy: [{ name: 'asc' }, { id: 'asc' }], skip: (q.page-1)*q.pageSize, take: q.pageSize })]);
  const users = access.has('admin.devices.read') && q.q.length >= 2 ? await prisma.membership.findMany({ where: { ...access.companyIdWhere('admin.devices.read'), company: where, user: { email: { contains: q.q, mode: 'insensitive' } } }, select: { companyId: true, user: { select: { id: true, name: true, email: true } } }, take: q.pageSize, skip: (q.page-1)*q.pageSize, orderBy: { id: 'asc' } }) : [];
  res.json({ page: q.page, pageSize: q.pageSize, total, groups: [{ type: 'company', items: rows.map(row => ({ id: row.id, companyId: row.id, label: row.name, subtitle: row.slug, href: `/companies/${row.id}` })) }, { type: 'user', items: users.map(row => ({ id: row.user.id, companyId: row.companyId, label: row.user.name, subtitle: row.user.email, href: `/companies/${row.companyId}/users` })) }] });
}));
adminPlatformRouter.get('/invoices', validateQuery(z.object({ ...paging, status: z.enum(['paid','overdue','all']).optional(), startDate: dateOnly.optional(), endDate: dateOnly.optional() })), asyncHandler(async (req,res) => {
  const access = await requireAdminPlatformPermission(req.auth!.userId, 'admin.billing.read');
  const q = req.query as unknown as { page:number;pageSize:number;status?:string;startDate?:string;endDate?:string };
  const where: Prisma.BillingInvoiceWhereInput = { ...access.companyIdWhere('admin.billing.read'),
    ...(q.status === 'paid' ? {status:{in:['PAID','paid','approved']},currency:'BRL'} : q.status === 'overdue' ? {status:{in:['PENDING','pending','OPEN','open','PAST_DUE','past_due']},dueAt:{lt:new Date()},paidAt:null}:{}),
    ...(q.startDate || q.endDate ? {paidAt:{gte:period(q).start,lt:period(q).end}} : {}),
  };
  const [total,rows]=await Promise.all([prisma.billingInvoice.count({where}),prisma.billingInvoice.findMany({where,select:{id:true,companyId:true,status:true,amountCents:true,currency:true,dueAt:true,paidAt:true,company:{select:{name:true}}},orderBy:[{createdAt:'desc'},{id:'asc'}],skip:(q.page-1)*q.pageSize,take:q.pageSize})]);
  res.json({items:rows.map(row=>({...row,companyName:row.company.name})),total,page:q.page,pageSize:q.pageSize});
}));
adminPlatformRouter.get('/usage', validateQuery(periodSchema), asyncHandler(async (req, res) => {
  const access = await requireAdminPlatformPermission(req.auth!.userId, 'admin.usage.read');
  const p = period(req.query as { startDate?: string; endDate?: string });
  const [events, versions, companies] = await Promise.all([
    prisma.productJourneyEvent.groupBy({ by: ['name'], where: { ...access.companyIdWhere('admin.usage.read'), occurredAt: { gte: p.start, lt: p.end } }, _count: { _all: true }, orderBy: { _count: { name: 'desc' } } }),
    prisma.productJourneyEvent.groupBy({ by: ['appVersion'], where: { ...access.companyIdWhere('admin.usage.read'), occurredAt: { gte: p.start, lt: p.end } }, _count: { _all: true } }),
    prisma.productJourneyEvent.findMany({ where: { ...access.companyIdWhere('admin.usage.read'), occurredAt: { gte: p.start, lt: p.end } }, distinct: ['companyId'], select: { companyId: true } }),
  ]);
  res.json({ available: true, period: p.dto, activeCompanies: companies.length, events: events.map(row => ({ name: row.name, count: row._count._all })), versions: versions.map(row => ({ appVersion: row.appVersion, count: row._count._all })), generatedAt: new Date().toISOString(), definition: 'Empresas com eventos de uso recebidos no período. Ausência de eventos não comprova inatividade.' });
}));
adminPlatformRouter.get('/administrators', asyncHandler(async (req, res) => {
  await requireAdminPlatformPermission(req.auth!.userId, 'admin-permissions.manage');
  res.json({ items: await prisma.user.findMany({ where: { isPlatformAdmin: true, isActive: true }, select: { id: true, name: true, email: true }, orderBy: { name: 'asc' }, take: 100 }) });
}));
adminPlatformRouter.post('/permission-templates/:key/apply', validateBody(z.object({ adminUserId: z.string().uuid(), reason: z.string().trim().min(12).max(1000), scope: z.enum(['platform','company']), scopeId: z.string().min(1), confirmationText: z.literal('APLICAR_PERFIL') }).strict()), asyncHandler(async (req, res) => {
  const actor = req.auth!.userId; const input = req.body;
  const access = await requireAdminPlatformPermission(actor, 'admin-permissions.manage', input.scope === 'company' ? input.scopeId : undefined);
  if (input.scope === 'platform' && access.companyIds('admin-permissions.manage') !== null) throw new AppError('Concessão fora do seu escopo.', 403, 'ADMIN_PERMISSION_SCOPE_DENIED');
  if (actor === input.adminUserId) throw new AppError('Não é permitido conceder permissões a si mesmo.', 403, 'ADMIN_PERMISSION_SELF_GRANT_BLOCKED');
  if (input.scope === 'platform' && input.scopeId !== '*') throw new AppError('Escopo de plataforma inválido.', 422, 'INVALID_SCOPE');
  if (input.scope === 'company' && !await prisma.company.findUnique({ where: { id: input.scopeId } })) throw new AppError('Empresa não encontrada.', 404, 'COMPANY_NOT_FOUND');
  const template = templates.find(t => t.key === req.params.key);
  if (!template || template.permissions.some(key => !getAdminPermissionDefinition(key))) throw new AppError('Perfil não encontrado.', 404, 'TEMPLATE_NOT_FOUND');
  if (!await prisma.user.findFirst({ where: { id: input.adminUserId, isPlatformAdmin: true, isActive: true } })) throw new AppError('Administrador não encontrado.', 404, 'ADMIN_NOT_FOUND');
  await prisma.$transaction(async tx => {
    for (const permissionKey of template.permissions) await tx.adminUserPermission.upsert({ where: { actorUserId_permissionKey_scope_scopeId: { actorUserId: input.adminUserId, permissionKey, scope: input.scope, scopeId: input.scopeId } }, create: { actorUserId: input.adminUserId, permissionKey, scope: input.scope, scopeId: input.scopeId, isActive: true }, update: { isActive: true } });
    await tx.adminAuditLog.create({ data: { actorUserId: actor, targetCompanyId: input.scope === 'company' ? input.scopeId : null, action: 'admin.platform.permission-template.applied', details: { targetAdminId: input.adminUserId, template: template.key, permissions: template.permissions, scope: input.scope, scopeId: input.scopeId, reason: input.reason } } });
  });
  res.json({ ok: true, permissions: template.permissions });
}));
