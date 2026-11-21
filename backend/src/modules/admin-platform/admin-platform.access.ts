import type { RequestHandler } from 'express';
import { prisma } from '../../database/prisma';
import { AppError } from '../../shared/http/app-error';

export type AdminPlatformGrant = { permissionKey: string; scope: string; scopeId: string; isActive: boolean };

/** No platform-admin fallback: all company scopes are checked on the server. */
export class AdminPlatformAccess {
  constructor(readonly grants: readonly AdminPlatformGrant[]) {}
  companyIds(permission: string): string[] | null {
    const rows = this.grants.filter(row => row.isActive && row.permissionKey === permission);
    if (rows.some(row => row.scope === 'platform' && row.scopeId === '*')) return null;
    return [...new Set(rows.filter(row => row.scope === 'company' && row.scopeId !== '*').map(row => row.scopeId))];
  }
  has(permission: string, companyId?: string): boolean {
    const ids = this.companyIds(permission);
    return ids === null || (companyId == null ? ids.length > 0 : ids.includes(companyId));
  }
  companyWhere(permission: string) {
    const ids = this.companyIds(permission);
    return ids === null ? {} : { id: { in: ids } };
  }
  companyIdWhere(permission: string) {
    const ids = this.companyIds(permission);
    return ids === null ? {} : { companyId: { in: ids } };
  }
}

export async function getAdminPlatformAccess(actorId: string) {
  const grants = await prisma.adminUserPermission.findMany({
    where: { actorUserId: actorId, isActive: true },
    select: { permissionKey: true, scope: true, scopeId: true, isActive: true },
  });
  return new AdminPlatformAccess(grants);
}

export async function requireAdminPlatformPermission(actorId: string, permission: string, companyId?: string) {
  const access = await getAdminPlatformAccess(actorId);
  if (!access.has(permission, companyId)) {
    throw new AppError('Seu acesso não permite esta operação neste escopo.', 403, 'ADMIN_PLATFORM_PERMISSION_REQUIRED');
  }
  return access;
}

/** Mount after requirePlatformAdmin and before legacy GET routes. Mutations retain their action gates. */
export const adminPlatformReadGuard: RequestHandler = (request, _response, next) => {
  void (async () => {
    if (request.method !== 'GET') return next();
    const path = request.path;
    if (/^\/(overview|capabilities|search|usage|triage|support\/cases|operations)(\/|$)/.test(path)) return next();
    if (/^\/(permissions|tenant-deletion)(\/|$)/.test(path)) return next();
    let key: string | null = null;
    let companyId: string | undefined;
    const companyMatch = /^\/companies\/([^/]+)(?:\/(.*))?$/.exec(path);
    const syncCompanyMatch = /^\/sync\/companies\/([^/]+)(?:\/|$)/.exec(path);
    const licenseCompanyMatch = /^\/licenses\/([^/]+)$/.exec(path);
    if (companyMatch) {
      companyId = companyMatch[1];
      const suffix = companyMatch[2] ?? '';
      key = /^(billing|license)(\/|$)/.test(suffix) ? 'admin.billing.read'
        : /^sync(\/|$)/.test(suffix) ? 'admin.sync.read'
        : /^(devices|sessions)(\/|$)/.test(suffix) ? 'admin.devices.read'
        : /^support(\/|$)/.test(suffix) ? 'admin.support.read' : 'admin.companies.read';
    } else if (syncCompanyMatch) {
      companyId = syncCompanyMatch[1]; key = 'admin.sync.read';
    } else if (licenseCompanyMatch) {
      companyId = licenseCompanyMatch[1]; key = 'admin.billing.read';
    } else if (path.startsWith('/sync/events/') || path.startsWith('/sync/conflicts/')) {
      const id = path.split('/')[3];
      const record = path.startsWith('/sync/events/')
        ? await prisma.syncEvent.findUnique({ where: { id }, select: { companyId: true } })
        : await prisma.syncConflict.findUnique({ where: { id }, select: { companyId: true } });
      if (record == null) throw new AppError('Registro não encontrado.', 404, 'ADMIN_RECORD_NOT_FOUND');
      companyId = record.companyId; key = 'admin.sync.read';
    } else if (path === '/companies') key = 'admin.companies.read';
    else if (/^\/(billing|licenses|plans)(\/|$)/.test(path)) key = 'admin.billing.read';
    else if (/^\/(sync|sync-health)(\/|$)/.test(path)) key = 'admin.sync.read';
    else if (/^\/devices(\/|$)/.test(path)) key = 'admin.devices.read';
    else if (/^\/audit(\/|$)/.test(path)) key = 'admin.audit.read';
    if (companyId == null && (path === '/devices' || path.startsWith('/audit')) && typeof request.query.companyId === 'string') companyId=request.query.companyId;
    if (key != null) {
      const access = await getAdminPlatformAccess(request.auth!.userId);
      // Legacy global list contracts cannot safely represent a restricted company scope.
      if (companyId == null ? access.companyIds(key) !== null : !access.has(key, companyId)) {
        throw new AppError('Consulta indisponível para este escopo administrativo.', 403, 'ADMIN_PLATFORM_PERMISSION_REQUIRED');
      }
    }
    next();
  })().catch(next);
};
