import { randomUUID } from "node:crypto";

import { Prisma } from "@prisma/client";

import { prisma } from "../../database/prisma";
import { buildAdminListResponse } from "../../shared/http/api-response";
import { userAdminAuditActor } from "../admin/admin-audit-actor";
import { sanitizeOperationalActionPayload } from "../support-actions/support-actions.service";
import type { TenantDeletionPermissionKey } from "../admin-permissions/admin-permissions.types";
import { TenantDeletionRbacService } from "./tenant-deletion.rbac";
import type {
  TenantDeletionAction,
  TenantDeletionBlocker,
  TenantDeletionCompanySummary,
  TenantDeletionDryRun,
  TenantDeletionInventoryCategory,
  TenantDeletionOperationResult,
  TenantDeletionPersistedRequest,
  TenantDeletionRequestSummary,
  TenantDeletionStatus,
} from "./tenant-deletion.types";

type CountDelegate = {
  count(input: { where?: Record<string, unknown> }): Promise<number>;
};

type TenantDeletionClient = {
  company: {
    findUnique(input: Record<string, unknown>): Promise<unknown>;
  };
  adminAuditLog: {
    create(input: Record<string, unknown>): Promise<{ id: string }>;
  };
  tenantDeletionRequest: {
    findMany(input: Record<string, unknown>): Promise<TenantDeletionPersistedRequest[]>;
    findUnique(input: Record<string, unknown>): Promise<TenantDeletionPersistedRequest | null>;
    findFirst(input: Record<string, unknown>): Promise<TenantDeletionPersistedRequest | null>;
    create(input: Record<string, unknown>): Promise<TenantDeletionPersistedRequest>;
    update(input: Record<string, unknown>): Promise<TenantDeletionPersistedRequest>;
    updateMany(input: Record<string, unknown>): Promise<{ count: number }>;
  };
  tenantDeletionAuditEvent: {
    create(input: Record<string, unknown>): Promise<{
      id: string;
      eventType: string;
      reason: string | null;
      createdAt: Date;
    }>;
  };
  $transaction?<T>(
    operation: (client: TenantDeletionClient) => Promise<T>,
  ): Promise<T>;
};

type TenantDeletionRbac = Pick<TenantDeletionRbacService, "hasPermission">;

type ActorInput = {
  actorAdminId: string | null | undefined;
  ipAddress?: string | null;
  userAgent?: string | null;
};

export class TenantDeletionService {
  private readonly activeStatuses: TenantDeletionStatus[] = [
    "REQUESTED",
    "IDENTITY_PENDING",
    "VERIFIED",
    "DRY_RUN_READY",
    "FUTURE_PENDING_DELETION",
  ];

  private readonly requestInclude = {
    company: { include: { license: true } },
    auditEvents: { orderBy: { createdAt: "desc" }, take: 1 },
  };

  constructor(
    private readonly client: TenantDeletionClient =
      prisma as unknown as TenantDeletionClient,
    private readonly rbacService: TenantDeletionRbac =
      new TenantDeletionRbacService(),
    private readonly now: () => Date = () => new Date(),
  ) {}

  async listRequests(input: {
    actorAdminId: string | null | undefined;
    companyId?: string | null;
    status?: string | null;
  }): Promise<TenantDeletionOperationResult> {
    const actor = this.normalizeRequiredActor(input.actorAdminId);
    if (actor == null) {
      return this.actorRequired();
    }

    const companyId = this.normalizeOptional(input.companyId);
    const permission = await this.ensurePermission({
      actorAdminId: actor,
      permissionKey: "tenant.deletion.read",
      companyId,
      deniedAction: "tenant.deletion.list.denied",
      reason: null,
    });
    if (!permission.ok) {
      return permission;
    }

    const requests = await this.client.tenantDeletionRequest.findMany({
      where: {
        ...(companyId == null ? {} : { companyId }),
        ...(input.status == null
          ? {}
          : { status: input.status.trim().toUpperCase() }),
      },
      orderBy: { updatedAt: "desc" },
      take: 250,
      include: this.requestInclude,
    });
    const requestedStatus = this.normalizeOptional(input.status)?.toUpperCase();
    const items = requests.map((request) => this.toRequestSummary(request));
    const auditEventId = await this.recordAdminAudit(this.client, {
      actorAdminId: actor,
      companyId,
      action: "tenant.deletion.list",
      details: {
        filters: { companyId, status: requestedStatus ?? null },
        resultCount: items.length,
        persistenceMode: "tenant_deletion_request",
      },
    });

    return {
      ok: true,
      code: "TENANT_DELETION_REQUEST_LISTED",
      message: "Solicitacoes de exclusao de tenant listadas.",
      auditEventId,
      requests: items,
      details: buildAdminListResponse({
        items,
        page: 1,
        pageSize: items.length,
        total: items.length,
        filters: {
          companyId,
          status: requestedStatus ?? null,
          persistenceMode: "tenant_deletion_request",
        },
        sort: { by: "updatedAt", direction: "desc" },
      }),
    };
  }

  async getRequest(input: ActorInput & {
    requestId: string;
  }): Promise<TenantDeletionOperationResult> {
    const actor = this.normalizeRequiredActor(input.actorAdminId);
    if (actor == null) {
      return this.actorRequired();
    }
    const request = await this.findRequest(input.requestId);
    if (request == null) {
      return this.requestNotFound(input.requestId);
    }
    const permission = await this.ensurePermission({
      actorAdminId: actor,
      permissionKey: "tenant.deletion.read",
      companyId: request.companyId,
      deniedAction: "tenant.deletion.get.denied",
      reason: null,
    });
    if (!permission.ok) {
      return permission;
    }

    const audit = await this.recordWorkflowEvent(this.client, {
      request,
      actorAdminId: actor,
      eventType: "REQUEST_VIEWED",
      action: "tenant.deletion.viewed",
      reason: null,
      before: this.workflowState(request),
      after: this.workflowState(request),
      metadata: this.actorMetadata(input),
    });
    return {
      ok: true,
      code: "TENANT_DELETION_REQUEST_FOUND",
      message: "Solicitacao de exclusao de tenant encontrada.",
      auditEventId: audit.adminAuditEventId,
      request: this.toRequestSummary(request, audit.workflowEvent),
    };
  }

  async createRequest(input: ActorInput & {
    companyId: string;
    reason: string;
    requesterName?: string | null;
    requesterEmail?: string | null;
    requesterChannel?: string | null;
  }): Promise<TenantDeletionOperationResult> {
    const actor = this.normalizeRequiredActor(input.actorAdminId);
    if (actor == null) {
      return this.actorRequired();
    }
    const reason = this.normalizeReason(input.reason);
    if (reason == null) {
      return this.reasonRequired();
    }

    const company = await this.requireCompany(input.companyId);
    if (company == null) {
      return this.companyNotFound(input.companyId);
    }

    const permission = await this.ensurePermission({
      actorAdminId: actor,
      permissionKey: "tenant.deletion.request.manage",
      companyId: company.id,
      deniedAction: "tenant.deletion.requested.denied",
      reason,
    });
    if (!permission.ok) {
      return permission;
    }

    const existing = await this.client.tenantDeletionRequest.findFirst({
      where: {
        companyId: company.id,
        status: {
          in: this.activeStatuses,
        },
      },
      orderBy: { createdAt: "desc" },
      include: this.requestInclude,
    });
    if (existing != null) {
      return this.reuseActiveRequest(existing, input, actor, reason);
    }

    const requestId = randomUUID();
    const createdAt = this.now();
    const source =
      this.normalizeOptional(input.requesterChannel) ?? "admin_web";
    let result: {
      request: TenantDeletionPersistedRequest;
      audit: Awaited<ReturnType<TenantDeletionService["recordWorkflowEvent"]>>;
    };
    try {
      result = await this.inTransaction(async (client) => {
        const request = await client.tenantDeletionRequest.create({
          data: {
            id: requestId,
            companyId: company.id,
            activeCompanyGuard: company.id,
            status: "REQUESTED",
            requestedByAdminUserId: actor,
            requestedByEmail: this.normalizeOptional(input.requesterEmail),
            requestedCompanyNameSnapshot: company.name,
            source,
            reason,
            identityStatus: "NOT_STARTED",
            createdAt,
            updatedAt: createdAt,
          },
          include: this.requestInclude,
        });
        const audit = await this.recordWorkflowEvent(client, {
          request,
          actorAdminId: actor,
          eventType: "REQUEST_CREATED",
          action: "tenant.deletion.requested",
          reason,
          before: null,
          after: this.workflowState(request),
          metadata: {
            ...this.actorMetadata(input),
            source,
            requesterEmailProvided:
              this.normalizeOptional(input.requesterEmail) != null,
          },
        });
        return { request, audit };
      });
    } catch (error) {
      if (!this.isUniqueConstraintError(error)) {
        throw error;
      }
      const racedRequest = await this.client.tenantDeletionRequest.findFirst({
        where: {
          companyId: company.id,
          status: { in: this.activeStatuses },
        },
        orderBy: { createdAt: "desc" },
        include: this.requestInclude,
      });
      if (racedRequest == null) {
        throw error;
      }
      return this.reuseActiveRequest(racedRequest, input, actor, reason);
    }

    return {
      ok: true,
      code: "TENANT_DELETION_REQUEST_RECORDED",
      message:
        "Solicitacao registrada. Nenhuma exclusao, anonimizacao ou quarentena foi executada.",
      auditEventId: result.audit.adminAuditEventId,
      request: this.toRequestSummary(
        result.request,
        result.audit.workflowEvent,
      ),
    };
  }

  private async reuseActiveRequest(
    request: TenantDeletionPersistedRequest,
    input: ActorInput,
    actorAdminId: string,
    reason: string,
  ): Promise<TenantDeletionOperationResult> {
    const audit = await this.recordWorkflowEvent(this.client, {
      request,
      actorAdminId,
      eventType: "REQUEST_VIEWED",
      action: "tenant.deletion.request.idempotent_reuse",
      reason,
      before: this.workflowState(request),
      after: this.workflowState(request),
      metadata: {
        ...this.actorMetadata(input),
        idempotentReuse: true,
      },
    });
    return {
      ok: true,
      code: "TENANT_DELETION_REQUEST_RECORDED",
      message:
        "Solicitacao ativa existente reutilizada de forma idempotente. Nenhuma exclusao real foi executada.",
      auditEventId: audit.adminAuditEventId,
      request: this.toRequestSummary(request, audit.workflowEvent),
    };
  }

  async markIdentityPending(input: ActorInput & {
    requestId: string;
    companyId: string;
    reason: string;
    note?: string | null;
  }) {
    return this.recordStatusTransition({
      ...input,
      permissionKey: "tenant.deletion.request.manage",
      action: "tenant.deletion.identity_pending",
      eventType: "IDENTITY_PENDING_SET",
      status: "IDENTITY_PENDING",
      identityStatus: "PENDING",
      code: "TENANT_DELETION_IDENTITY_PENDING_RECORDED",
      message:
        "Pendencia de validacao de identidade registrada. Nenhuma exclusao real foi executada.",
    });
  }

  async verifyIdentity(input: ActorInput & {
    requestId: string;
    companyId: string;
    reason: string;
    note?: string | null;
  }) {
    return this.recordStatusTransition({
      ...input,
      permissionKey: "tenant.deletion.identity.verify",
      action: "tenant.deletion.verified",
      eventType: "IDENTITY_VERIFIED",
      status: "VERIFIED",
      identityStatus: "VERIFIED",
      code: "TENANT_DELETION_IDENTITY_VERIFIED",
      message:
        "Validacao de identidade registrada. Execucao, quarentena e anonimizacao continuam fora desta etapa.",
    });
  }

  async cancelRequest(input: ActorInput & {
    requestId: string;
    companyId: string;
    reason: string;
    note?: string | null;
  }) {
    return this.recordStatusTransition({
      ...input,
      permissionKey: "tenant.deletion.cancel",
      action: "tenant.deletion.cancelled",
      eventType: "REQUEST_CANCELLED",
      status: "CANCELLED",
      code: "TENANT_DELETION_CANCELLED",
      message:
        "Solicitacao cancelada por registro administrativo. Nenhum dado da empresa foi alterado.",
    });
  }

  async rejectRequest(input: ActorInput & {
    requestId: string;
    companyId: string;
    reason: string;
    note?: string | null;
  }) {
    return this.recordStatusTransition({
      ...input,
      permissionKey: "tenant.deletion.cancel",
      action: "tenant.deletion.rejected",
      eventType: "REQUEST_REJECTED",
      status: "REJECTED",
      code: "TENANT_DELETION_REJECTED",
      message:
        "Solicitacao rejeitada com motivo auditado. Nenhum dado da empresa foi alterado.",
    });
  }

  async dryRun(input: ActorInput & {
    companyId: string;
    reason: string;
    requestId: string;
  }): Promise<TenantDeletionOperationResult> {
    const actor = this.normalizeRequiredActor(input.actorAdminId);
    if (actor == null) {
      return this.actorRequired();
    }
    const reason = this.normalizeReason(input.reason);
    if (reason == null) {
      return this.reasonRequired();
    }

    const request = await this.findRequest(input.requestId);
    if (request == null) {
      return this.requestNotFound(input.requestId);
    }
    if (request.companyId !== input.companyId.trim()) {
      return this.stateConflict(
        "A solicitacao nao pertence a empresa informada.",
      );
    }

    const permission = await this.ensurePermission({
      actorAdminId: actor,
      permissionKey: "tenant.deletion.read",
      companyId: request.companyId,
      deniedAction: "tenant.deletion.dry_run.denied",
      reason,
    });
    if (!permission.ok) {
      return permission;
    }

    if (this.isTerminal(request.status)) {
      return this.stateConflict(
        "Solicitacao finalizada nao pode receber novo dry-run.",
      );
    }
    if (request.status !== "VERIFIED" && request.status !== "DRY_RUN_READY") {
      return this.stateConflict(
        "Dry-run exige solicitacao com identidade verificada.",
      );
    }

    const dryRun = await this.buildDryRun(
      this.toCompanySummary(request.company),
    );
    const generatedAt = this.now();
    const snapshot = this.persistedDryRunSnapshot(dryRun);
    const result = await this.inTransaction(async (client) => {
      const update = await client.tenantDeletionRequest.updateMany({
        where: {
          id: request.id,
          status: request.status,
          activeCompanyGuard: request.companyId,
        },
        data: {
          status: "DRY_RUN_READY",
          dryRunSnapshotJson: snapshot as Prisma.InputJsonValue,
          dryRunGeneratedAt: generatedAt,
          updatedAt: generatedAt,
        },
      });
      if (update.count !== 1) {
        return null;
      }
      const updated = await client.tenantDeletionRequest.findUnique({
        where: { id: request.id },
        include: this.requestInclude,
      });
      if (updated == null) {
        return null;
      }
      const audit = await this.recordWorkflowEvent(client, {
        request: updated,
        actorAdminId: actor,
        eventType: "DRY_RUN_GENERATED",
        action: "tenant.deletion.dry_run",
        reason,
        before: this.workflowState(request),
        after: this.workflowState(updated),
        metadata: {
          ...this.actorMetadata(input),
          categories: dryRun.categories.length,
          blockers: dryRun.blockers.length,
          blockerKeys: dryRun.blockers.map((blocker) => blocker.key),
        },
      });
      return { request: updated, audit };
    });
    if (result == null) {
      return this.stateConflict(
        "A solicitacao foi alterada por outra acao. Recarregue antes de gerar o dry-run.",
      );
    }

    return {
      ok: true,
      code: "TENANT_DELETION_DRY_RUN_READY",
      message:
        "Inventario dry-run gerado. Nenhuma exclusao, anonimizacao, desativacao ou cancelamento de billing foi executado.",
      auditEventId: result.audit.adminAuditEventId,
      request: this.toRequestSummary(
        result.request,
        result.audit.workflowEvent,
      ),
      dryRun,
    };
  }

  private async recordStatusTransition(input: ActorInput & {
    requestId: string;
    companyId: string;
    reason: string;
    note?: string | null;
    permissionKey: TenantDeletionPermissionKey;
    action: TenantDeletionAction;
    eventType:
      | "IDENTITY_PENDING_SET"
      | "IDENTITY_VERIFIED"
      | "REQUEST_CANCELLED"
      | "REQUEST_REJECTED";
    status: TenantDeletionStatus;
    identityStatus?: "PENDING" | "VERIFIED";
    code: TenantDeletionOperationResult["code"];
    message: string;
  }): Promise<TenantDeletionOperationResult> {
    const actor = this.normalizeRequiredActor(input.actorAdminId);
    if (actor == null) {
      return this.actorRequired();
    }
    const reason = this.normalizeReason(input.reason);
    if (reason == null) {
      return this.reasonRequired();
    }
    const requestId = this.normalizeOptional(input.requestId);
    if (requestId == null) {
      return this.requestRequired();
    }

    const request = await this.findRequest(requestId);
    if (request == null) {
      return this.requestNotFound(requestId);
    }
    if (request.companyId !== input.companyId.trim()) {
      return this.stateConflict(
        "A solicitacao nao pertence a empresa informada.",
      );
    }

    const permission = await this.ensurePermission({
      actorAdminId: actor,
      permissionKey: input.permissionKey,
      companyId: request.companyId,
      deniedAction: `${input.action}.denied`,
      reason,
    });
    if (!permission.ok) {
      return permission;
    }

    if (this.isTerminal(request.status)) {
      if (request.status !== input.status) {
        return this.stateConflict(
          "Solicitacao finalizada nao permite nova transicao.",
        );
      }
      const audit = await this.recordWorkflowEvent(this.client, {
        request,
        actorAdminId: actor,
        eventType: input.eventType,
        action: `${input.action}.idempotent`,
        reason,
        before: this.workflowState(request),
        after: this.workflowState(request),
        metadata: {
          ...this.actorMetadata(input),
          note: this.normalizeOptional(input.note),
          idempotent: true,
        },
      });
      return {
        ok: true,
        code: input.code,
        message: input.message,
        auditEventId: audit.adminAuditEventId,
        request: this.toRequestSummary(request, audit.workflowEvent),
      };
    }

    const transitionError = this.validateTransition(
      request.status,
      input.status,
    );
    if (transitionError != null) {
      return this.stateConflict(transitionError);
    }

    const changedAt = this.now();
    const result = await this.inTransaction(async (client) => {
      const update = await client.tenantDeletionRequest.updateMany({
        where: {
          id: request.id,
          status: request.status,
          activeCompanyGuard: request.companyId,
        },
        data: this.transitionData(input, actor, reason, changedAt),
      });
      if (update.count !== 1) {
        return null;
      }
      const updated = await client.tenantDeletionRequest.findUnique({
        where: { id: request.id },
        include: this.requestInclude,
      });
      if (updated == null) {
        return null;
      }
      const audit = await this.recordWorkflowEvent(client, {
        request: updated,
        actorAdminId: actor,
        eventType: input.eventType,
        action: input.action,
        reason,
        before: this.workflowState(request),
        after: this.workflowState(updated),
        metadata: {
          ...this.actorMetadata(input),
          note: this.normalizeOptional(input.note),
        },
      });
      return { request: updated, audit };
    });
    if (result == null) {
      return this.stateConflict(
        "A solicitacao foi alterada por outra acao. Recarregue antes de tentar novamente.",
      );
    }

    return {
      ok: true,
      code: input.code,
      message: input.message,
      auditEventId: result.audit.adminAuditEventId,
      request: this.toRequestSummary(
        result.request,
        result.audit.workflowEvent,
      ),
    };
  }

  private async buildDryRun(
    company: TenantDeletionCompanySummary,
  ): Promise<TenantDeletionDryRun> {
    const counts = await Promise.all([
      this.count("membership", { companyId: company.id }),
      this.count("employeeProfile", { companyId: company.id }),
      this.count("companyDevice", { companyId: company.id }),
      this.count("deviceSession", { companyId: company.id }),
      this.count("syncEvent", { companyId: company.id }),
      this.count("syncConflict", { companyId: company.id }),
      this.count("syncIncident", { companyId: company.id }),
      this.count("syncSupportCommand", { companyId: company.id }),
      this.count("deviceSyncDiagnostic", { companyId: company.id }),
      this.count("billingCheckoutSession", { companyId: company.id }),
      this.count("billingInvoice", { companyId: company.id }),
      this.count("billingProviderEvent", { companyId: company.id }),
      this.count("billingAdminAuditLog", { companyId: company.id }),
      this.count("adminAuditLog", { targetCompanyId: company.id }),
      this.count("customer", { companyId: company.id }),
      this.count("customerTag", { companyId: company.id }),
      this.count("customerNote", { companyId: company.id }),
      this.count("customerTask", { companyId: company.id }),
      this.count("customerTimelineEvent", { companyId: company.id }),
      this.count("category", { companyId: company.id }),
      this.count("product", { companyId: company.id }),
      this.count("supplier", { companyId: company.id }),
      this.count("supply", { companyId: company.id }),
      this.count("purchase", { companyId: company.id }),
      this.count("sale", { companyId: company.id }),
      this.count("financialEvent", { companyId: company.id }),
      this.count("cost", { companyId: company.id }),
      this.count("fiadoPayment", { companyId: company.id }),
      this.count("cashEvent", { companyId: company.id }),
      this.count("cashSession", { companyId: company.id }),
      this.count("operationalOrder", { companyId: company.id }),
      this.count("stockReservation", { companyId: company.id }),
      this.count("stockDeduction", { companyId: company.id }),
      this.count("supplyCostHistory", { companyId: company.id }),
      this.count("analyticsCompanyDailySnapshot", { companyId: company.id }),
      this.count("analyticsProductDailySnapshot", { companyId: company.id }),
      this.count("analyticsCustomerDailySnapshot", { companyId: company.id }),
    ]);

    const [
      memberships,
      employeeProfiles,
      companyDevices,
      deviceSessions,
      syncEvents,
      syncConflicts,
      syncIncidents,
      syncSupportCommands,
      deviceSyncDiagnostics,
      billingCheckoutSessions,
      billingInvoices,
      billingProviderEvents,
      billingAdminAuditLogs,
      adminAuditLogs,
      customers,
      customerTags,
      customerNotes,
      customerTasks,
      customerTimelineEvents,
      categories,
      products,
      suppliers,
      supplies,
      purchases,
      sales,
      financialEvents,
      costs,
      fiadoPayments,
      cashEvents,
      cashSessions,
      operationalOrders,
      stockReservations,
      stockDeductions,
      supplyCostHistory,
      analyticsCompanyDailySnapshots,
      analyticsProductDailySnapshots,
      analyticsCustomerDailySnapshots,
    ] = counts;

    const categoriesResult: TenantDeletionInventoryCategory[] = [
      this.category("tenant_identity", "Empresa e licenca", 1, "deactivate",
        "Company deve permanecer como tombstone minimo para billing, auditoria e comprovacao."),
      this.category("users", "Usuarios, vinculos e funcionarios", memberships + employeeProfiles, "anonymize",
        "Usuarios podem ser compartilhados entre empresas; remover vinculos exige avaliacao por escopo."),
      this.category("devices_sessions", "Dispositivos e sessoes", companyDevices + deviceSessions, "deactivate",
        "A fase futura deve revogar sessoes/dispositivos antes de bloquear sync."),
      this.category("sync", "Sync, comandos, conflitos e diagnosticos", syncEvents + syncConflicts + syncIncidents + syncSupportCommands + deviceSyncDiagnostics, "review_required",
        "Eventos e conflitos podem compor auditoria tecnica e comprovacao operacional."),
      this.category("billing", "Billing, invoices, provider events e auditoria financeira", billingCheckoutSessions + billingInvoices + billingProviderEvents + billingAdminAuditLogs, "retain_justified",
        "Retencao pode ser exigida por obrigacao legal, auditoria, seguranca e exercicio regular de direitos."),
      this.category("admin_audit", "Auditoria administrativa", adminAuditLogs, "retain_justified",
        "Logs administrativos devem preservar trilha before/after e comprovacao."),
      this.category("customers_crm", "Clientes e CRM", customers + customerTags + customerNotes + customerTasks + customerTimelineEvents, "anonymize",
        "Dados pessoais de clientes exigem avaliacao por categoria antes de anonimizar ou excluir elegiveis."),
      this.category("catalog_inventory", "Catalogo, estoque, fornecedores e compras", categories + products + suppliers + supplies + purchases + stockReservations + stockDeductions + supplyCostHistory, "review_required",
        "Parte dos dados pode ter valor fiscal, financeiro, estoque ou auditoria."),
      this.category("sales_financial_cash", "Vendas, fiado, contas, caixa e comandas", sales + financialEvents + costs + fiadoPayments + cashEvents + cashSessions + operationalOrders, "retain_justified",
        "Dados financeiros e caixa podem demandar retencao legal e defesa de direitos."),
      this.category("analytics", "Snapshots analiticos", analyticsCompanyDailySnapshots + analyticsProductDailySnapshots + analyticsCustomerDailySnapshots, "delete_eligible",
        "Snapshots derivados podem ser candidatos a exclusao ou recomputacao anonima em fase futura."),
    ];

    const blockers = await this.buildBlockers(company);

    return {
      company,
      generatedAt: this.now().toISOString(),
      dryRun: true,
      persistenceMode: "tenant_deletion_request",
      categories: categoriesResult,
      blockers,
      notes: [
        "Dry-run read-only: nenhuma exclusao, anonimizacao, desativacao, revogacao de sessao ou cancelamento de billing foi executado.",
        "O workflow esta persistido em TenantDeletionRequest/TenantDeletionAuditEvent; quarentena operacional continua fora desta fase.",
        "Mercado Pago nao deve ser cancelado automaticamente sem fluxo financeiro proprio.",
        "Limpeza local posterior no app pode ser necessaria para remover dados ainda armazenados no dispositivo.",
      ],
    };
  }

  private async buildBlockers(company: TenantDeletionCompanySummary) {
    const [
      activeDevices,
      activeSessions,
      openConflicts,
      pendingSyncEvents,
      openCashSessions,
      openOrders,
      pendingCosts,
      pendingCheckoutSessions,
      openInvoices,
    ] = await Promise.all([
      this.count("companyDevice", { companyId: company.id, status: "ACTIVE" }),
      this.count("deviceSession", { companyId: company.id, revokedAt: null }),
      this.count("syncConflict", { companyId: company.id, status: "OPEN" }),
      this.count("syncEvent", { companyId: company.id, status: "PENDING" }),
      this.count("cashSession", { companyId: company.id, status: "open" }),
      this.count("operationalOrder", { companyId: company.id, status: "open" }),
      this.count("cost", { companyId: company.id, status: "pending" }),
      this.count("billingCheckoutSession", {
        companyId: company.id,
        status: "PENDING",
      }),
      this.count("billingInvoice", {
        companyId: company.id,
        status: { in: ["open", "pending", "failed", "overdue"] },
      }),
    ]);

    const blockers: TenantDeletionBlocker[] = [
      {
        key: "company_physical_delete_forbidden",
        severity: "blocking",
        message:
          "Company nao deve ser excluida fisicamente; preservar tombstone minimo e evitar cascades destrutivos.",
      },
      {
        key: "billing_provider_not_cancelled",
        severity: "warning",
        message:
          "Nenhum cancelamento em Mercado Pago/provedor foi executado; billing exige fluxo proprio.",
      },
    ];

    if (company.license?.hasProviderSubscription === true) {
      blockers.push({
        key: "active_provider_subscription",
        severity: "blocking",
        message:
          "A empresa possui assinatura/providerSubscriptionId; cancelamento automatico fora do escopo.",
      });
    }
    this.pushCountBlocker(blockers, "active_devices", activeDevices,
      "Dispositivos ativos devem ser revogados/bloqueados em fase futura.");
    this.pushCountBlocker(blockers, "active_sessions", activeSessions,
      "Sessoes ativas devem ser revogadas em fase futura.");
    this.pushCountBlocker(blockers, "open_sync_conflicts", openConflicts,
      "Conflitos de sync abertos exigem triagem antes de quarentena.");
    this.pushCountBlocker(blockers, "pending_sync_events", pendingSyncEvents,
      "Eventos de sync pendentes podem indicar dados locais ainda nao conciliados.");
    this.pushCountBlocker(blockers, "open_cash_sessions", openCashSessions,
      "Caixas abertos devem ser fechados ou justificados antes da proxima fase.");
    this.pushCountBlocker(blockers, "open_operational_orders", openOrders,
      "Comandas/pedidos abertos exigem tratativa operacional.");
    this.pushCountBlocker(blockers, "pending_costs", pendingCosts,
      "Contas pendentes podem demandar retencao financeira ou baixa operacional.");
    this.pushCountBlocker(blockers, "pending_checkout_sessions",
      pendingCheckoutSessions,
      "Checkout pendente pode exigir conciliacao de billing.");
    this.pushCountBlocker(blockers, "open_invoices", openInvoices,
      "Invoices abertas/falhas/vencidas exigem decisao financeira.");

    return blockers;
  }

  private pushCountBlocker(
    blockers: TenantDeletionBlocker[],
    key: string,
    count: number,
    message: string,
  ) {
    if (count > 0) {
      blockers.push({ key, count, severity: "warning", message });
    }
  }

  private category(
    key: string,
    label: string,
    count: number,
    recommendedHandling: TenantDeletionInventoryCategory["recommendedHandling"],
    retentionReason: string | null,
  ): TenantDeletionInventoryCategory {
    return { key, label, count, recommendedHandling, retentionReason };
  }

  private async count(model: string, where: Record<string, unknown>) {
    const delegate = (this.client as unknown as Record<string, CountDelegate>)[
      model
    ];
    if (delegate?.count == null) {
      return 0;
    }
    return delegate.count({ where });
  }

  private async requireCompany(
    companyId: string,
  ): Promise<TenantDeletionCompanySummary | null> {
    const normalized = this.normalizeOptional(companyId);
    if (normalized == null) {
      return null;
    }
    const company = (await this.client.company.findUnique({
      where: { id: normalized },
      include: { license: true },
    })) as {
      id: string;
      name: string;
      legalName: string;
      documentNumber: string | null;
      slug: string;
      isActive: boolean;
      createdAt: Date;
      updatedAt: Date;
      license: {
        status: string;
        plan: string;
        syncEnabled: boolean;
        billingProvider: string | null;
        providerSubscriptionId: string | null;
        cancelAtPeriodEnd: boolean;
        cancelRequestedAt: Date | null;
        canceledAt: Date | null;
        billingSubscriptionStatus: string | null;
      } | null;
    } | null;

    return company == null ? null : this.toCompanySummary(company);
  }

  private toCompanySummary(company: {
    id: string;
    name: string;
    legalName: string;
    documentNumber: string | null;
    slug: string;
    isActive: boolean;
    createdAt: Date;
    updatedAt: Date;
    license: {
      status: string;
      plan: string;
      syncEnabled: boolean;
      billingProvider: string | null;
      providerSubscriptionId: string | null;
      cancelAtPeriodEnd: boolean;
      cancelRequestedAt: Date | null;
      canceledAt: Date | null;
      billingSubscriptionStatus: string | null;
    } | null;
  }): TenantDeletionCompanySummary {
    return {
      id: company.id,
      name: company.name,
      legalName: company.legalName,
      documentNumber: company.documentNumber,
      slug: company.slug,
      isActive: company.isActive,
      createdAt: company.createdAt.toISOString(),
      updatedAt: company.updatedAt.toISOString(),
      license:
        company.license == null
          ? null
          : {
              status: company.license.status.toLowerCase(),
              plan: company.license.plan,
              syncEnabled: company.license.syncEnabled,
              billingProvider: company.license.billingProvider,
              hasProviderSubscription:
                company.license.providerSubscriptionId != null &&
                company.license.providerSubscriptionId.trim() !== "",
              cancelAtPeriodEnd: company.license.cancelAtPeriodEnd,
              cancelRequestedAt:
                company.license.cancelRequestedAt?.toISOString() ?? null,
              canceledAt: company.license.canceledAt?.toISOString() ?? null,
              billingSubscriptionStatus:
                company.license.billingSubscriptionStatus,
            },
    };
  }

  private toRequestSummary(
    request: TenantDeletionPersistedRequest,
    latestEvent = request.auditEvents[0],
  ): TenantDeletionRequestSummary {
    const dryRun = this.readDryRunSummary(request.dryRunSnapshotJson);
    return {
      requestId: request.id,
      company: this.toCompanySummary(request.company),
      status: request.status,
      identityStatus: request.identityStatus,
      source: request.source,
      createdAt: request.createdAt.toISOString(),
      updatedAt: request.updatedAt.toISOString(),
      latestAuditEventId: latestEvent?.id ?? request.id,
      latestAction: this.actionForEvent(latestEvent?.eventType),
      reason:
        request.cancellationReason ??
        request.rejectionReason ??
        latestEvent?.reason ??
        request.reason,
      requester: {
        name: null,
        email: request.requestedByEmail,
        channel: request.source,
      },
      dryRunSummary: dryRun,
    };
  }

  private readDryRunSummary(value: unknown) {
    if (value == null || typeof value !== "object" || Array.isArray(value)) {
      return null;
    }
    const snapshot = value as {
      categories?: unknown;
      blockers?: unknown;
    };
    if (!Array.isArray(snapshot.categories) || !Array.isArray(snapshot.blockers)) {
      return null;
    }
    return {
      categories: snapshot.categories.length,
      blockers: snapshot.blockers.length,
    };
  }

  private async ensurePermission(input: {
    actorAdminId: string;
    permissionKey: TenantDeletionPermissionKey;
    companyId?: string | null;
    deniedAction: string;
    reason: string | null;
  }): Promise<TenantDeletionOperationResult> {
    const hasPermission = await this.rbacService.hasPermission({
      actorAdminId: input.actorAdminId,
      permissionKey: input.permissionKey,
      companyId: input.companyId,
    });

    if (hasPermission) {
      return {
        ok: true,
        code: "TENANT_DELETION_REQUEST_LISTED",
        message: "Permissao granular concedida.",
        auditEventId: null,
      };
    }

    const auditEventId = await this.recordAdminAudit(this.client, {
      actorAdminId: input.actorAdminId,
      companyId: input.companyId ?? null,
      action: input.deniedAction,
      details: {
        requestId: "denied",
        status: "REJECTED",
        reason: input.reason,
        metadata: {
          requiredPermission: input.permissionKey,
          result: "missing_permission",
        },
      },
    });

    return {
      ok: false,
      code: "TENANT_DELETION_PERMISSION_REQUIRED",
      message:
        "Permissao granular ausente. isPlatformAdmin sozinho nao libera fluxo de exclusao de tenant.",
      auditEventId,
      requiredPermission: input.permissionKey,
      details: { requiredPermission: input.permissionKey },
    };
  }

  private async recordWorkflowEvent(
    client: TenantDeletionClient,
    input: {
      request: TenantDeletionPersistedRequest;
      actorAdminId: string;
      eventType:
        | "REQUEST_CREATED"
        | "IDENTITY_PENDING_SET"
        | "IDENTITY_VERIFIED"
        | "DRY_RUN_GENERATED"
        | "REQUEST_CANCELLED"
        | "REQUEST_REJECTED"
        | "REQUEST_VIEWED";
      action: string;
      reason: string | null;
      before: Record<string, unknown> | null;
      after: Record<string, unknown> | null;
      metadata: Record<string, unknown>;
    },
  ) {
    const safeBefore =
      input.before == null
        ? {}
        : sanitizeOperationalActionPayload(input.before);
    const safeAfter =
      input.after == null ? {} : sanitizeOperationalActionPayload(input.after);
    const safeMetadata = sanitizeOperationalActionPayload(input.metadata);
    const workflowEvent = await client.tenantDeletionAuditEvent.create({
      data: {
        requestId: input.request.id,
        companyId: input.request.companyId,
        actorAdminUserId: input.actorAdminId,
        eventType: input.eventType,
        reason: input.reason,
        beforeJson: safeBefore as Prisma.InputJsonValue,
        afterJson: safeAfter as Prisma.InputJsonValue,
        metadataJson: safeMetadata as Prisma.InputJsonValue,
      },
      select: {
        id: true,
        eventType: true,
        reason: true,
        createdAt: true,
      },
    });
    const adminAuditEventId = await this.recordAdminAudit(client, {
      actorAdminId: input.actorAdminId,
      companyId: input.request.companyId,
      action: input.action,
      details: {
        requestId: input.request.id,
        status: input.request.status,
        identityStatus: input.request.identityStatus,
        reason: input.reason,
        before: safeBefore,
        after: safeAfter,
        metadata: safeMetadata,
        workflowAuditEventId: workflowEvent.id,
      },
    });
    return { workflowEvent, adminAuditEventId };
  }

  private async recordAdminAudit(
    client: TenantDeletionClient,
    input: {
      actorAdminId: string;
      companyId?: string | null;
      action: string;
      details: Record<string, unknown>;
    },
  ) {
    const audit = await client.adminAuditLog.create({
      data: {
        ...userAdminAuditActor(input.actorAdminId),
        targetCompanyId: input.companyId ?? null,
        action: input.action,
        details: sanitizeOperationalActionPayload(
          input.details,
        ) as Prisma.InputJsonValue,
      },
      select: { id: true },
    });
    return audit.id;
  }

  private actorMetadata(input: ActorInput) {
    return {
      ipAddress: input.ipAddress ?? null,
      userAgent: input.userAgent ?? null,
      persistenceMode: "tenant_deletion_request",
    };
  }

  private async findRequest(requestId: string) {
    const normalized = this.normalizeOptional(requestId);
    if (normalized == null) {
      return null;
    }
    return this.client.tenantDeletionRequest.findUnique({
      where: { id: normalized },
      include: this.requestInclude,
    });
  }

  private async inTransaction<T>(
    operation: (client: TenantDeletionClient) => Promise<T>,
  ) {
    if (this.client.$transaction != null) {
      return this.client.$transaction(operation);
    }
    return operation(this.client);
  }

  private workflowState(request: TenantDeletionPersistedRequest) {
    return {
      requestId: request.id,
      companyId: request.companyId,
      status: request.status,
      identityStatus: request.identityStatus,
      dryRunGeneratedAt: request.dryRunGeneratedAt?.toISOString() ?? null,
      cancelledAt: request.cancelledAt?.toISOString() ?? null,
      rejectedAt: request.rejectedAt?.toISOString() ?? null,
      updatedAt: request.updatedAt.toISOString(),
    };
  }

  private transitionData(
    input: {
      status: TenantDeletionStatus;
      identityStatus?: "PENDING" | "VERIFIED";
      note?: string | null;
    },
    actorAdminId: string,
    reason: string,
    changedAt: Date,
  ) {
    const common = {
      status: input.status,
      updatedAt: changedAt,
    };
    switch (input.status) {
      case "IDENTITY_PENDING":
        return {
          ...common,
          identityStatus: "PENDING",
          identityVerificationNotes: this.safeOptionalText(input.note),
        };
      case "VERIFIED":
        return {
          ...common,
          identityStatus: "VERIFIED",
          identityVerifiedByAdminUserId: actorAdminId,
          identityVerifiedAt: changedAt,
          identityVerificationNotes: this.safeOptionalText(input.note),
        };
      case "CANCELLED":
        return {
          ...common,
          activeCompanyGuard: null,
          cancelledByAdminUserId: actorAdminId,
          cancelledAt: changedAt,
          cancellationReason: reason,
        };
      case "REJECTED":
        return {
          ...common,
          activeCompanyGuard: null,
          rejectedByAdminUserId: actorAdminId,
          rejectedAt: changedAt,
          rejectionReason: reason,
          identityStatus: "FAILED",
          identityVerificationNotes: this.safeOptionalText(input.note),
        };
      default:
        return common;
    }
  }

  private validateTransition(
    current: TenantDeletionStatus,
    target: TenantDeletionStatus,
  ) {
    if (current === target) {
      return null;
    }
    if (target === "CANCELLED" || target === "REJECTED") {
      return null;
    }
    if (target === "IDENTITY_PENDING" && current !== "REQUESTED") {
      return "Identity pending exige solicitacao em REQUESTED.";
    }
    if (target === "VERIFIED" && current !== "IDENTITY_PENDING") {
      return "Verificacao exige solicitacao em IDENTITY_PENDING.";
    }
    return null;
  }

  private isTerminal(status: TenantDeletionStatus) {
    return status === "CANCELLED" || status === "REJECTED";
  }

  private isUniqueConstraintError(error: unknown) {
    return (
      error instanceof Prisma.PrismaClientKnownRequestError &&
      error.code === "P2002"
    ) || (
      typeof error === "object" &&
      error != null &&
      "code" in error &&
      error.code === "P2002"
    );
  }

  private persistedDryRunSnapshot(dryRun: TenantDeletionDryRun) {
    return {
      generatedAt: dryRun.generatedAt,
      persistenceMode: dryRun.persistenceMode,
      companyId: dryRun.company.id,
      categories: dryRun.categories,
      blockers: dryRun.blockers,
      notes: dryRun.notes,
    };
  }

  private actionForEvent(eventType: string | undefined) {
    const actions: Record<string, TenantDeletionAction | string> = {
      REQUEST_CREATED: "tenant.deletion.requested",
      IDENTITY_PENDING_SET: "tenant.deletion.identity_pending",
      IDENTITY_VERIFIED: "tenant.deletion.verified",
      DRY_RUN_GENERATED: "tenant.deletion.dry_run",
      REQUEST_CANCELLED: "tenant.deletion.cancelled",
      REQUEST_REJECTED: "tenant.deletion.rejected",
      REQUEST_VIEWED: "tenant.deletion.viewed",
    };
    return eventType == null ? "tenant.deletion.requested" : actions[eventType];
  }

  private normalizeRequiredActor(value: string | null | undefined) {
    const normalized = value?.trim();
    return normalized == null || normalized.length === 0 ? null : normalized;
  }

  private normalizeReason(value: string | null | undefined) {
    const normalized = value?.trim();
    if (normalized == null || normalized.length < 12) {
      return null;
    }
    const sanitized = sanitizeOperationalActionPayload({
      value: normalized,
    }).value;
    return typeof sanitized === "string" ? sanitized : "[redacted]";
  }

  private normalizeOptional(value: string | null | undefined) {
    const normalized = value?.trim();
    return normalized == null || normalized.length === 0 ? null : normalized;
  }

  private safeOptionalText(value: string | null | undefined) {
    const normalized = this.normalizeOptional(value);
    if (normalized == null) {
      return null;
    }
    const sanitized = sanitizeOperationalActionPayload({
      value: normalized,
    }).value;
    return typeof sanitized === "string" ? sanitized : "[redacted]";
  }

  private actorRequired(): TenantDeletionOperationResult {
    return {
      ok: false,
      code: "TENANT_DELETION_ACTOR_REQUIRED",
      message: "Ator administrativo obrigatorio.",
      auditEventId: null,
    };
  }

  private reasonRequired(): TenantDeletionOperationResult {
    return {
      ok: false,
      code: "TENANT_DELETION_REASON_REQUIRED",
      message: "Informe um motivo com pelo menos 12 caracteres.",
      auditEventId: null,
    };
  }

  private requestRequired(): TenantDeletionOperationResult {
    return {
      ok: false,
      code: "TENANT_DELETION_REQUEST_REQUIRED",
      message: "requestId obrigatorio.",
      auditEventId: null,
    };
  }

  private requestNotFound(requestId: string): TenantDeletionOperationResult {
    return {
      ok: false,
      code: "TENANT_DELETION_REQUEST_NOT_FOUND",
      message: "Solicitacao de exclusao de tenant nao encontrada.",
      auditEventId: null,
      details: { requestId },
    };
  }

  private stateConflict(message: string): TenantDeletionOperationResult {
    return {
      ok: false,
      code: "TENANT_DELETION_STATE_CONFLICT",
      message,
      auditEventId: null,
    };
  }

  private companyNotFound(companyId: string): TenantDeletionOperationResult {
    return {
      ok: false,
      code: "TENANT_DELETION_COMPANY_NOT_FOUND",
      message: "Empresa nao encontrada.",
      auditEventId: null,
      details: { companyId },
    };
  }
}
