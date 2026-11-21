import { z } from 'zod';
import { prisma } from '../../database/prisma';
import { AppError } from '../../shared/http/app-error';
import type { AppContext } from '../app/app-context.types';
import { hasEmployeePermission } from '../employees/employee-permissions';
import { asRecord } from '../sync/materializers/payload-utils';

export const divergenceReviewSchema = z.object({ requestId: z.string().uuid(), expectedRevision: z.number().int().min(0), status: z.enum(['PENDING','REVIEWED']), justification: z.string().trim().min(1).max(2000) }).strict();
export function canReviewCash(context: AppContext) {
  const role = context.employee?.role ?? (context.membership.role === 'ADMIN' ? 'MANAGER' : context.membership.role);
  return ['OWNER','MANAGER'].includes(role) && hasEmployeePermission(context.membership.permissions, 'reports.advanced') && hasEmployeePermission(context.membership.permissions, 'employees.manage');
}
function assertRead(context: AppContext) {
  if (!['OWNER','ADMIN'].includes(context.membership.role) || !hasEmployeePermission(context.membership.permissions,'reports.advanced')) throw new AppError('Sem permissao para relatorios de caixa.',403,'CASH_REVIEW_FORBIDDEN');
}
export class CashDivergenceReviewService {
  async get(context: AppContext, sessionId: string) {
    assertRead(context);
    const session = await prisma.cashSession.findFirst({where:{id:sessionId,companyId:context.company.id}});
    if (session == null) throw new AppError('Caixa nao encontrado.',404,'OWNER_CASH_SESSION_NOT_FOUND');
    const details = asRecord(asRecord(session.payload).closingDetails);
    if (details.version !== 2 || session.status !== 'closed' || details.differenceCents === 0) return null;
    const events = await prisma.cashDivergenceReviewEvent.findMany({where:{companyId:context.company.id,sessionId},orderBy:{revision:'asc'}});
    const comments = events.map(event => ({requestId:event.requestId,revision:event.revision,status:event.status,justification:event.justification,authorId:event.authorId,authorName:event.authorName,createdAt:event.createdAt.toISOString()}));
    const last = comments.at(-1);
    return {sessionId,revision:last?.revision ?? 0,status:last?.status ?? 'PENDING',comments};
  }
  async append(context: AppContext, sessionId: string, raw: unknown) {
    assertRead(context);
    if (!canReviewCash(context)) throw new AppError('Sem permissao para revisar caixa.',403,'CASH_REVIEW_FORBIDDEN');
    const input = divergenceReviewSchema.parse(raw);
    await prisma.$transaction(async tx => {
      // All case revisions serialize on the tenant-owned session row.
      await tx.$queryRaw`SELECT "id" FROM "CashSession" WHERE "id" = ${sessionId} AND "companyId" = ${context.company.id} FOR UPDATE`;
      const session = await tx.cashSession.findFirst({where:{id:sessionId,companyId:context.company.id}});
      if (session == null) throw new AppError('Caixa nao encontrado.',404,'OWNER_CASH_SESSION_NOT_FOUND');
      const closure = asRecord(asRecord(session.payload).closingDetails);
      if (session.status !== 'closed' || closure.version !== 2 || closure.differenceCents === 0) throw new AppError('Caixa nao possui divergencia V2 para revisao.',409,'CASH_REVIEW_NOT_APPLICABLE');
      const previous = await tx.cashDivergenceReviewEvent.findUnique({where:{companyId_requestId:{companyId:context.company.id,requestId:input.requestId}}});
      if (previous != null) {
        if (previous.sessionId !== sessionId || previous.status !== input.status || previous.justification !== input.justification || previous.revision !== input.expectedRevision+1 || previous.authorId !== context.user.id) throw new AppError('requestId ja utilizado com outro conteudo.',409,'CASH_REVIEW_REQUEST_CONFLICT');
        return;
      }
      const last = await tx.cashDivergenceReviewEvent.findFirst({where:{companyId:context.company.id,sessionId},orderBy:{revision:'desc'}});
      if ((last?.revision ?? 0) !== input.expectedRevision) throw new AppError('Revisao desatualizada. Atualize os dados.',409,'CASH_REVIEW_REVISION_CONFLICT');
      await tx.cashDivergenceReviewEvent.create({data:{companyId:context.company.id,sessionId,requestId:input.requestId,revision:input.expectedRevision+1,status:input.status,justification:input.justification,authorId:context.user.id,authorName:context.user.name}});
    });
    return {divergenceReview:await this.get(context,sessionId),canReview:canReviewCash(context)};
  }
}
