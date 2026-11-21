import type { RequestHandler } from 'express';
import { prisma } from '../../database/prisma';
import { requireAdminPlatformPermission } from '../admin-platform/admin-platform.access';

/** Existing administrative mutations keep their business validation and gain
 * exact company-scoped grants. New APIs authorize themselves before this guard. */
export const adminLegacyActionGuard: RequestHandler = (request, _response, next) => {
  void (async () => {
    if (!['POST', 'PUT', 'PATCH', 'DELETE'].includes(request.method)) return next();
    const path = request.path;
    if (/^\/(permissions|tenant-deletion)(\/|$)/.test(path)) return next();
    const match = path.match(/^\/companies\/([^/]+)/) ?? path.match(/^\/sync\/companies\/([^/]+)/);
    let companyId = match?.[1] ?? (typeof request.body?.companyId === 'string' ? request.body.companyId : undefined);
    let key: string | undefined;
    if (/\/access\/[^/]+\/block/.test(path)) key = 'support.user.block';
    else if (/\/access\/[^/]+\/reactivate/.test(path)) key = 'support.user.unblock';
    else if (/\/license/.test(path)) key = 'support.license.update';
    else if (/\/billing\/(force-plan|cancel-local|reconcile)(\/|$)/.test(path)) key = 'admin.billing.exception';
    else if (/\/billing\//.test(path)) key = 'admin.billing.manage';
    else if (/^\/licenses\//.test(path)) { key = 'support.license.update'; companyId = path.split('/')[2]; }
    else if (/^\/sessions\/[^/]+\/revoke$/.test(path)) {
      key = 'support.session.revoke';
      const target = await prisma.deviceSession.findUnique({ where: { id: path.split('/')[2] }, select: { companyId: true } });
      companyId = target?.companyId;
    } else if (path.startsWith('/support-actions')) {
      const actionKeys: Record<string, string> = { revoke_session: 'support.session.revoke', block_user: 'support.user.block', unblock_user: 'support.user.unblock', force_sync: 'support.sync.force', resolve_conflict: 'support.sync.conflict.resolve', update_license: 'support.license.update', update_android_version_policy: 'support.androidVersionPolicy.update', send_push_notification: 'support.push.send' };
      key = actionKeys[request.body?.actionType] ?? 'support.session.revoke';
    } else if (/\/support-actions/.test(path)) key = 'support.sync.force';
    else if (/^\/sync\/(events|conflicts)\//.test(path)) {
      key = 'support.sync.conflict.resolve';
      const id = path.split('/')[3];
      const target = path.startsWith('/sync/events/')
        ? await prisma.syncEvent.findUnique({ where: { id }, select: { companyId: true } })
        : await prisma.syncConflict.findUnique({ where: { id }, select: { companyId: true } });
      companyId = target?.companyId;
    }
    if (key) await requireAdminPlatformPermission(request.auth!.userId, key, companyId);
    next();
  })().catch(next);
};
