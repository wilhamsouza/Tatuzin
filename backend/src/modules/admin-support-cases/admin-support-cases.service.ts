import { Prisma } from '@prisma/client';
import { prisma } from '../../database/prisma';
import { AppError } from '../../shared/http/app-error';
import { userAdminAuditActor } from '../admin/admin-audit-actor';
import { getAdminPlatformAccess } from '../admin-platform/admin-platform.access';
import type { SupportCaseCreateInput, SupportCaseListInput, SupportCaseNoteInput, SupportCaseUpdateInput } from './admin-support-cases.schemas';

const relations = {
  company: { select: { id: true, name: true } },
  assignee: { select: { id: true, name: true } },
} satisfies Prisma.AdminSupportCaseInclude;
type CaseRow = Prisma.AdminSupportCaseGetPayload<{ include: typeof relations }>;
const eventRelations = { author: { select: { id: true, name: true } } } satisfies Prisma.AdminSupportCaseEventInclude;
const statusLabels: Record<string, string> = { OPEN: 'Aberto', IN_PROGRESS: 'Em atendimento', WAITING: 'Aguardando', RESOLVED: 'Resolvido' };

export class AdminSupportCasesService {
  async list(actorId: string, query: SupportCaseListInput) {
    const access = await getAdminPlatformAccess(actorId);
    const companyIds = access.companyIds('admin.support.read');
    if (companyIds?.length === 0) this.denied();
    if (query.companyId && !access.has('admin.support.read', query.companyId)) this.denied();
    const where: Prisma.AdminSupportCaseWhereInput = {
      ...(companyIds == null ? {} : { companyId: { in: companyIds } }),
      ...(query.companyId ? { companyId: query.companyId } : {}),
      ...(query.status ? { status: query.status === 'active' ? { not: 'RESOLVED' } : query.status } : {}),
      ...(query.mine === 'true' ? { assigneeId: actorId } : query.assigneeId ? { assigneeId: query.assigneeId } : {}),
      ...(query.search ? { OR: [
        { subject: { contains: query.search, mode: 'insensitive' } },
        { company: { name: { contains: query.search, mode: 'insensitive' } } },
        { id: query.search },
      ] } : {}),
    };
    const [total, rows] = await prisma.$transaction([
      prisma.adminSupportCase.count({ where }),
      prisma.adminSupportCase.findMany({ where, include: relations, orderBy: [{ updatedAt: 'desc' }, { id: 'desc' }], skip: (query.page - 1) * query.pageSize, take: query.pageSize }),
    ]);
    return { items: rows.map(row => this.summary(row)), total, page: query.page, pageSize: query.pageSize };
  }

  async detail(actorId: string, caseId: string) {
    const row = await this.accessibleCase(actorId, caseId, 'admin.support.read');
    return { item: await this.detailDto(prisma, row) };
  }

  async assignees(actorId: string, companyId?: string) {
    const access = await getAdminPlatformAccess(actorId);
    if (companyId ? !access.has('admin.support.read', companyId) : access.companyIds('admin.support.read')?.length === 0) this.denied();
    const candidates = await prisma.user.findMany({
      where: { isActive: true, isPlatformAdmin: true, adminUserPermissions: { some: {
        permissionKey: 'admin.support.manage', isActive: true,
        OR: [{ scope: 'platform', scopeId: '*' }, ...(companyId ? [{ scope: 'company', scopeId: companyId }] : [{ scope: 'company' }])],
      } } },
      select: { id: true, name: true }, orderBy: [{ name: 'asc' }, { id: 'asc' }], take: 100,
    });
    return { items: candidates };
  }

  async create(actorId: string, input: SupportCaseCreateInput) {
    await this.assertPermission(actorId, 'admin.support.manage', input.companyId);
    if (!await prisma.company.findUnique({ where: { id: input.companyId }, select: { id: true } })) {
      throw new AppError('Empresa não encontrada.', 404, 'SUPPORT_CASE_COMPANY_NOT_FOUND');
    }
    const prior = await prisma.adminSupportCase.findUnique({ where: { companyId_requestKey: { companyId: input.companyId, requestKey: input.requestKey } }, include: relations });
    if (prior) return this.reused(actorId, prior);
    await this.assertAssignee(input.assigneeId, input.companyId);
    await this.assertEvidence(input.companyId, input.evidence);
    const evidenceKey = input.evidence ? `${input.evidence.type}:${input.evidence.id}` : null;
    const activeEvidenceKey = evidenceKey ? `${input.companyId}:${evidenceKey}` : null;
    if (activeEvidenceKey) {
      const existing = await prisma.adminSupportCase.findUnique({ where: { activeEvidenceKey }, include: relations });
      if (existing) return this.reused(actorId, existing);
    }
    try {
      return await prisma.$transaction(async tx => {
        const row = await tx.adminSupportCase.create({ data: {
          companyId: input.companyId, creatorId: actorId, subject: input.subject, description: input.description,
          priority: input.priority, assigneeId: input.assigneeId, requestKey: input.requestKey,
          evidenceType: input.evidence?.type, evidenceId: input.evidence?.id, evidenceKey, activeEvidenceKey,
        }, include: relations });
        await this.record(tx, row, actorId, 'CREATED', 'Chamado criado.', { evidenceKey });
        return { item: await this.detailDto(tx, row), reused: false };
      });
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        const existing = await prisma.adminSupportCase.findFirst({ where: { companyId: input.companyId, OR: [
          { requestKey: input.requestKey }, ...(activeEvidenceKey ? [{ activeEvidenceKey }] : []),
        ] }, include: relations });
        if (existing) return this.reused(actorId, existing);
      }
      throw error;
    }
  }

  async update(actorId: string, caseId: string, input: SupportCaseUpdateInput) {
    const existing = await this.accessibleCase(actorId, caseId, 'admin.support.manage');
    if (input.assigneeId !== undefined) await this.assertAssignee(input.assigneeId, existing.companyId);
    const nextStatus = input.status ?? existing.status;
    if (nextStatus === 'RESOLVED' && !(input.resolution ?? existing.resolution)?.trim()) {
      throw new AppError('Descreva o resultado para resolver o chamado.', 422, 'SUPPORT_CASE_RESOLUTION_REQUIRED');
    }
    if (input.resolution && nextStatus !== 'RESOLVED') {
      throw new AppError('O resultado de resolução exige o status Resolvido.', 422, 'SUPPORT_CASE_RESOLUTION_STATUS_REQUIRED');
    }
    const activeEvidenceKey = nextStatus !== 'RESOLVED' && existing.evidenceKey ? `${existing.companyId}:${existing.evidenceKey}` : null;
    try {
      return await prisma.$transaction(async tx => {
        const changed = await tx.adminSupportCase.updateMany({ where: { id: caseId, companyId: existing.companyId, revision: input.expectedRevision }, data: {
          ...(input.subject === undefined ? {} : { subject: input.subject }),
          ...(input.description === undefined ? {} : { description: input.description }),
          ...(input.priority === undefined ? {} : { priority: input.priority }),
          ...(input.assigneeId === undefined ? {} : { assigneeId: input.assigneeId }),
          status: nextStatus, activeEvidenceKey,
          resolution: nextStatus === 'RESOLVED' ? input.resolution ?? existing.resolution : null,
          revision: { increment: 1 },
        } });
        if (changed.count !== 1) this.conflict();
        const row = await tx.adminSupportCase.findUniqueOrThrow({ where: { id: caseId }, include: relations });
        const type = nextStatus === 'RESOLVED' && existing.status !== 'RESOLVED' ? 'RESOLVED'
          : existing.status === 'RESOLVED' && nextStatus !== 'RESOLVED' ? 'REOPENED'
          : input.assigneeId !== undefined && input.assigneeId !== existing.assigneeId ? 'REASSIGNED' : 'UPDATED';
        const body = type === 'RESOLVED' ? row.resolution! : type === 'REOPENED' ? `Chamado reaberto. Situação: ${statusLabels[nextStatus]}.`
          : type === 'REASSIGNED' ? `Responsável: ${row.assignee?.name ?? 'Não atribuído'}. Situação: ${statusLabels[nextStatus]}.`
          : `Chamado atualizado. Situação: ${statusLabels[nextStatus]}.`;
        await this.record(tx, row, actorId, type, body, {
          before: { status: existing.status, priority: existing.priority, assigneeId: existing.assigneeId, revision: existing.revision },
          after: { status: row.status, priority: row.priority, assigneeId: row.assigneeId, revision: row.revision },
        });
        return { item: await this.detailDto(tx, row) };
      });
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        throw new AppError('Já existe um chamado ativo vinculado à mesma evidência. Consulte a fila antes de reabrir.', 409, 'SUPPORT_CASE_ACTIVE_EVIDENCE_EXISTS');
      }
      throw error;
    }
  }

  async addNote(actorId: string, caseId: string, input: SupportCaseNoteInput) {
    const existing = await this.accessibleCase(actorId, caseId, 'admin.support.manage');
    return prisma.$transaction(async tx => {
      const changed = await tx.adminSupportCase.updateMany({ where: { id: caseId, companyId: existing.companyId, revision: input.expectedRevision }, data: { revision: { increment: 1 } } });
      if (changed.count !== 1) this.conflict();
      const row = await tx.adminSupportCase.findUniqueOrThrow({ where: { id: caseId }, include: relations });
      await this.record(tx, row, actorId, 'NOTE', input.body, { revision: row.revision });
      return { item: await this.detailDto(tx, row) };
    });
  }

  private async reused(actorId: string, row: CaseRow) {
    // Manage is checked by create; don't require a second, unrelated permission to acknowledge a retry.
    await this.assertPermission(actorId, 'admin.support.manage', row.companyId);
    return { item: await this.detailDto(prisma, row), reused: true };
  }

  private async accessibleCase(actorId: string, caseId: string, permission: string) {
    const access = await getAdminPlatformAccess(actorId);
    const companyIds = access.companyIds(permission);
    if (companyIds?.length === 0) this.denied();
    const row = await prisma.adminSupportCase.findFirst({ where: { id: caseId, ...(companyIds == null ? {} : { companyId: { in: companyIds } }) }, include: relations });
    if (!row) throw new AppError('Chamado não encontrado.', 404, 'SUPPORT_CASE_NOT_FOUND');
    return row;
  }

  private async assertPermission(actorId: string, permission: string, companyId: string) {
    if (!(await getAdminPlatformAccess(actorId)).has(permission, companyId)) this.denied();
  }

  private async assertAssignee(assigneeId: string | null | undefined, companyId: string) {
    if (!assigneeId) return;
    const user = await prisma.user.findFirst({ where: { id: assigneeId, isPlatformAdmin: true, isActive: true }, select: { id: true } });
    if (!user || !(await getAdminPlatformAccess(assigneeId)).has('admin.support.manage', companyId)) {
      throw new AppError('O responsável precisa ser administrador ativo com permissão de suporte para esta empresa.', 422, 'SUPPORT_CASE_ASSIGNEE_INVALID');
    }
  }

  private async assertEvidence(companyId: string, evidence: SupportCaseCreateInput['evidence']) {
    if (!evidence) return;
    let found: { id: string } | null = null;
    const where = { id: evidence.id, companyId };
    switch (evidence.type) {
      case 'SYNC_EVENT': found = await prisma.syncEvent.findFirst({ where, select: { id: true } }); break;
      case 'SYNC_CONFLICT': found = await prisma.syncConflict.findFirst({ where, select: { id: true } }); break;
      case 'DEVICE': found = await prisma.companyDevice.findFirst({ where, select: { id: true } }); break;
      case 'BILLING_INVOICE': found = await prisma.billingInvoice.findFirst({ where, select: { id: true } }); break;
      case 'AUDIT_EVENT': found = await prisma.adminAuditLog.findFirst({ where: { id: evidence.id, targetCompanyId: companyId }, select: { id: true } }); break;
    }
    if (!found) throw new AppError('Evidência não encontrada nesta empresa.', 422, 'SUPPORT_CASE_EVIDENCE_INVALID');
  }

  private async record(tx: Prisma.TransactionClient, row: CaseRow, actorId: string, type: string, body: string, details: Prisma.InputJsonValue) {
    const event = await tx.adminSupportCaseEvent.create({ data: { caseId: row.id, companyId: row.companyId, authorId: actorId, type, body, details } });
    await tx.adminAuditLog.create({ data: { ...userAdminAuditActor(actorId), targetCompanyId: row.companyId,
      action: `admin.support.case.${type.toLowerCase()}`, details: { caseId: row.id, eventId: event.id, revision: row.revision, ...details as Record<string, Prisma.InputJsonValue> },
    } });
  }

  private summary(row: CaseRow) {
    return { id: row.id, companyId: row.companyId, companyName: row.company.name, subject: row.subject, priority: row.priority,
      status: row.status, assignee: row.assignee, revision: row.revision, createdAt: row.createdAt.toISOString(), updatedAt: row.updatedAt.toISOString(),
      evidenceKey: row.evidenceKey, evidence: row.evidenceType && row.evidenceId ? { type: row.evidenceType, id: row.evidenceId } : null };
  }

  private async detailDto(tx: Pick<Prisma.TransactionClient, 'adminSupportCaseEvent'>, row: CaseRow) {
    const events = await tx.adminSupportCaseEvent.findMany({ where: { caseId: row.id, companyId: row.companyId }, include: eventRelations, orderBy: [{ createdAt: 'asc' }, { id: 'asc' }] });
    return { ...this.summary(row), description: row.description, resolution: row.resolution,
      events: events.map(event => ({ id: event.id, type: event.type, body: event.body, author: event.author, createdAt: event.createdAt.toISOString() })) };
  }

  private denied(): never { throw new AppError('Você não tem permissão para acessar estes chamados.', 403, 'ADMIN_SUPPORT_PERMISSION_REQUIRED'); }
  private conflict(): never { throw new AppError('Este chamado foi alterado por outra pessoa. Atualize os dados antes de tentar novamente.', 409, 'SUPPORT_CASE_REVISION_CONFLICT'); }
}
