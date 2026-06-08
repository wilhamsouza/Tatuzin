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
  TenantDeletionAdminAuditEvent,
  TenantDeletionAuditDetails,
  TenantDeletionBlocker,
  TenantDeletionCompanySummary,
  TenantDeletionDryRun,
  TenantDeletionInventoryCategory,
  TenantDeletionOperationResult,
  TenantDeletionRequestSummary,
  TenantDeletionStatus,
} from "./tenant-deletion.types";

const tenantDeletionActions: TenantDeletionAction[] = [
  "tenant.deletion.requested",
  "tenant.deletion.identity_pending",
  "tenant.deletion.verified",
  "tenant.deletion.dry_run",
  "tenant.deletion.cancelled",
  "tenant.deletion.rejected",
];

type CountDelegate = {
  count(input: { where?: Record<string, unknown> }): Promise<number>;
};

type TenantDeletionClient = {
  company: {
    findUnique(input: Record<string, unknown>): Promise<unknown>;
  };
  adminAuditLog: {
    create(input: Record<string, unknown>): Promise<{ id: string }>;
    findMany(input: Record<string, unknown>): Promise<TenantDeletionAdminAuditEvent[]>;
  };
};

type TenantDeletionRbac = Pick<TenantDeletionRbacService, "hasPermission">;

type ActorInput = {
  actorAdminId: string | null | undefined;
  ipAddress?: string | null;
  userAgent?: string | null;
};

export class TenantDeletionService {
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

    const events = await this.client.adminAuditLog.findMany({
      where: {
        action: { in: tenantDeletionActions },
        ...(companyId == null ? {} : { targetCompanyId: companyId }),
      },
      orderBy: { createdAt: "desc" },
      take: 250,
      include: { targetCompany: { include: { license: true } } },
    });

    const byRequestId = new Map<string, TenantDeletionAdminAuditEvent[]>();
    for (const event of events) {
      const details = this.readDetails(event.details);
      if (details?.requestId == null) {
        continue;
      }
      const list = byRequestId.get(details.requestId) ?? [];
      list.push(event);
      byRequestId.set(details.requestId, list);
    }

    const requestedStatus = this.normalizeOptional(input.status)?.toUpperCase();
    const requests = [...byRequestId.values()]
      .map((requestEvents) => this.toRequestSummary(requestEvents))
      .filter((request) =>
        requestedStatus == null ? true : request.status === requestedStatus,
      );

    return {
      ok: true,
      code: "TENANT_DELETION_REQUEST_LISTED",
      message: "Solicitacoes de exclusao de tenant listadas.",
      auditEventId: null,
      requests,
      details: buildAdminListResponse({
        items: requests,
        page: 1,
        pageSize: requests.length,
        total: requests.length,
        filters: {
          companyId,
          status: requestedStatus ?? null,
          persistenceMode: "admin_audit_log_foundation",
        },
        sort: { by: "updatedAt", direction: "desc" },
      }),
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

    const requestId = `tdr_${randomUUID()}`;
    const auditEventId = await this.recordAudit({
      actorAdminId: actor,
      companyId: company.id,
      action: "tenant.deletion.requested",
      reason,
      details: {
        requestId,
        status: "REQUESTED",
        reason,
        requester: {
          name: this.normalizeOptional(input.requesterName),
          email: this.normalizeOptional(input.requesterEmail),
          channel: this.normalizeOptional(input.requesterChannel),
        },
        metadata: this.actorMetadata(input),
      },
    });

    return {
      ok: true,
      code: "TENANT_DELETION_REQUEST_RECORDED",
      message:
        "Solicitacao registrada. Nenhuma exclusao, anonimizacao ou quarentena foi executada.",
      auditEventId,
      request: {
        requestId,
        company,
        status: "REQUESTED",
        createdAt: this.now().toISOString(),
        updatedAt: this.now().toISOString(),
        latestAuditEventId: auditEventId,
        latestAction: "tenant.deletion.requested",
        reason,
        requester: {
          name: this.normalizeOptional(input.requesterName),
          email: this.normalizeOptional(input.requesterEmail),
          channel: this.normalizeOptional(input.requesterChannel),
        },
        dryRunSummary: null,
      },
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
      status: "IDENTITY_PENDING",
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
      status: "VERIFIED",
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
      permissionKey: "tenant.deletion.request.manage",
      action: "tenant.deletion.rejected",
      status: "REJECTED",
      code: "TENANT_DELETION_REJECTED",
      message:
        "Solicitacao rejeitada com motivo auditado. Nenhum dado da empresa foi alterado.",
    });
  }

  async dryRun(input: ActorInput & {
    companyId: string;
    reason: string;
    requestId?: string | null;
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
      permissionKey: "tenant.deletion.read",
      companyId: company.id,
      deniedAction: "tenant.deletion.dry_run.denied",
      reason,
    });
    if (!permission.ok) {
      return permission;
    }

    const dryRun = await this.buildDryRun(company);
    const requestId =
      this.normalizeOptional(input.requestId) ?? `tdr_dry_${randomUUID()}`;
    const auditEventId = await this.recordAudit({
      actorAdminId: actor,
      companyId: company.id,
      action: "tenant.deletion.dry_run",
      reason,
      details: {
        requestId,
        status: "DRY_RUN_READY",
        reason,
        dryRun: {
          categories: dryRun.categories.length,
          blockers: dryRun.blockers.length,
          blockerKeys: dryRun.blockers.map((blocker) => blocker.key),
        },
        metadata: this.actorMetadata(input),
      },
    });

    return {
      ok: true,
      code: "TENANT_DELETION_DRY_RUN_READY",
      message:
        "Inventario dry-run gerado. Nenhuma exclusao, anonimizacao, desativacao ou cancelamento de billing foi executado.",
      auditEventId,
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
    status: TenantDeletionStatus;
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

    const company = await this.requireCompany(input.companyId);
    if (company == null) {
      return this.companyNotFound(input.companyId);
    }

    const permission = await this.ensurePermission({
      actorAdminId: actor,
      permissionKey: input.permissionKey,
      companyId: company.id,
      deniedAction: `${input.action}.denied`,
      reason,
    });
    if (!permission.ok) {
      return permission;
    }

    const auditEventId = await this.recordAudit({
      actorAdminId: actor,
      companyId: company.id,
      action: input.action,
      reason,
      details: {
        requestId,
        status: input.status,
        reason,
        metadata: {
          ...this.actorMetadata(input),
          note: this.normalizeOptional(input.note),
        },
      },
    });

    return {
      ok: true,
      code: input.code,
      message: input.message,
      auditEventId,
      request: {
        requestId,
        company,
        status: input.status,
        createdAt: this.now().toISOString(),
        updatedAt: this.now().toISOString(),
        latestAuditEventId: auditEventId,
        latestAction: input.action,
        reason,
        requester: { name: null, email: null, channel: null },
        dryRunSummary: null,
      },
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
      persistenceMode: "admin_audit_log_foundation",
      categories: categoriesResult,
      blockers,
      notes: [
        "Dry-run read-only: nenhuma exclusao, anonimizacao, desativacao, revogacao de sessao ou cancelamento de billing foi executado.",
        "A persistencia definitiva requer migration para TenantDeletionRequest/TenantDeletionAuditEvent antes de quarentena real.",
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
        key: "no_tenant_deletion_table",
        severity: "warning",
        message:
          "Ainda nao existe tabela dedicada TenantDeletionRequest; esta etapa usa AdminAuditLog como fundacao temporaria.",
      },
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
    events: TenantDeletionAdminAuditEvent[],
  ): TenantDeletionRequestSummary {
    const sorted = [...events].sort(
      (left, right) => right.createdAt.getTime() - left.createdAt.getTime(),
    );
    const latest = sorted[0];
    const oldest = sorted[sorted.length - 1];
    const latestDetails = this.readDetails(latest.details);
    const oldestDetails = this.readDetails(oldest.details);
    const dryRunDetails = sorted
      .map((event) => this.readDetails(event.details))
      .find((details) => details?.dryRun != null);

    return {
      requestId:
        latestDetails?.requestId ?? oldestDetails?.requestId ?? "unknown",
      company:
        latest.targetCompany == null
          ? null
          : this.toCompanySummary(latest.targetCompany),
      status: latestDetails?.status ?? "REQUESTED",
      createdAt: oldest.createdAt.toISOString(),
      updatedAt: latest.createdAt.toISOString(),
      latestAuditEventId: latest.id,
      latestAction: latest.action,
      reason: latestDetails?.reason ?? null,
      requester: {
        name: oldestDetails?.requester?.name ?? null,
        email: oldestDetails?.requester?.email ?? null,
        channel: oldestDetails?.requester?.channel ?? null,
      },
      dryRunSummary:
        dryRunDetails?.dryRun == null
          ? null
          : {
              categories: dryRunDetails.dryRun.categories,
              blockers: dryRunDetails.dryRun.blockers,
            },
    };
  }

  private readDetails(value: unknown): TenantDeletionAuditDetails | null {
    if (value == null || typeof value !== "object" || Array.isArray(value)) {
      return null;
    }
    const details = value as Partial<TenantDeletionAuditDetails>;
    if (
      typeof details.requestId !== "string" ||
      typeof details.status !== "string"
    ) {
      return null;
    }
    return details as TenantDeletionAuditDetails;
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

    const auditEventId = await this.recordAudit({
      actorAdminId: input.actorAdminId,
      companyId: input.companyId ?? null,
      action: input.deniedAction,
      reason: input.reason,
      details: {
        requestId: "denied",
        status: "REJECTED",
        reason:
          input.reason ??
          "Tentativa bloqueada por ausencia de permissao granular.",
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

  private async recordAudit(input: {
    actorAdminId: string;
    companyId?: string | null;
    action: string;
    reason: string | null;
    details: TenantDeletionAuditDetails;
  }) {
    const audit = await this.client.adminAuditLog.create({
      data: {
        ...userAdminAuditActor(input.actorAdminId),
        targetCompanyId: input.companyId ?? null,
        action: input.action,
        details: sanitizeOperationalActionPayload({
          ...input.details,
          reason: input.reason ?? input.details.reason,
        }) as Prisma.InputJsonValue,
      },
      select: { id: true },
    });
    return audit.id;
  }

  private actorMetadata(input: ActorInput) {
    return {
      ipAddress: input.ipAddress ?? null,
      userAgent: input.userAgent ?? null,
      persistenceMode: "admin_audit_log_foundation",
    };
  }

  private normalizeRequiredActor(value: string | null | undefined) {
    const normalized = value?.trim();
    return normalized == null || normalized.length === 0 ? null : normalized;
  }

  private normalizeReason(value: string | null | undefined) {
    const normalized = value?.trim();
    return normalized == null || normalized.length < 12 ? null : normalized;
  }

  private normalizeOptional(value: string | null | undefined) {
    const normalized = value?.trim();
    return normalized == null || normalized.length === 0 ? null : normalized;
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
