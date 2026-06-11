import { randomUUID } from "node:crypto";

import { Prisma } from "@prisma/client";

import { env } from "../../config/env";
import { prisma } from "../../database/prisma";
import { userAdminAuditActor } from "../admin/admin-audit-actor";
import { sanitizeOperationalActionPayload } from "../support-actions/support-actions.service";
import { TenantDeletionRbacService } from "./tenant-deletion.rbac";
import type { TenantDeletionOperationResult } from "./tenant-deletion.types";

const executionPlan = [
  "access_revocation",
  "personal_data_anonymization",
  "sync_data_deletion",
  "analytics_deletion",
  "catalog_anonymization",
  "financial_text_minimization",
  "membership_cleanup",
  "company_tombstone",
  "retained_legal_records",
] as const;

type ExecutionCategory = (typeof executionPlan)[number];
type ExecutionProgress = {
  completedCategories: ExecutionCategory[];
  failedCategory: ExecutionCategory | null;
  lastError: string | null;
};

type ExecutionInput = {
  actorAdminId: string | null | undefined;
  requestId: string;
  companyId: string;
  reason: string;
  confirmation: string;
  ipAddress?: string | null;
  userAgent?: string | null;
};

type ExecutionOptions = {
  enabled?: boolean;
  now?: () => Date;
  onLockAcquired?: () => Promise<void>;
};

export class TenantDeletionExecutionService {
  private readonly enabled: boolean;
  private readonly now: () => Date;
  private readonly onLockAcquired?: () => Promise<void>;

  constructor(
    private readonly client: typeof prisma = prisma,
    private readonly rbacService: Pick<TenantDeletionRbacService, "hasPermission"> =
      new TenantDeletionRbacService(),
    options: ExecutionOptions = {},
  ) {
    this.enabled = options.enabled ?? env.TENANT_DELETION_EXECUTION_ENABLED;
    this.now = options.now ?? (() => new Date());
    this.onLockAcquired = options.onLockAcquired;
  }

  async execute(input: ExecutionInput): Promise<TenantDeletionOperationResult> {
    const actorAdminId = input.actorAdminId?.trim();
    const companyId = input.companyId.trim();
    const rawReason = input.reason.trim();
    const sanitizedReason = sanitizeOperationalActionPayload({ value: rawReason }).value;
    const reason = typeof sanitizedReason === "string" ? sanitizedReason : "[redacted]";
    if (!actorAdminId) {
      return this.error("TENANT_DELETION_ACTOR_REQUIRED", "Ator administrativo obrigatorio.");
    }
    if (!companyId) {
      return this.error("TENANT_DELETION_COMPANY_REQUIRED", "Empresa obrigatoria.");
    }
    if (rawReason.length < 12) {
      return this.error("TENANT_DELETION_REASON_REQUIRED", "Informe um motivo com pelo menos 12 caracteres.");
    }
    if (input.confirmation.trim() !== "ANONIMIZAR TENANT") {
      return this.error(
        "TENANT_DELETION_VALIDATION_ERROR",
        'Confirmacao explicita obrigatoria: informe "ANONIMIZAR TENANT".',
      );
    }

    let request = await this.client.tenantDeletionRequest.findUnique({
      where: { id: input.requestId.trim() },
    });
    if (request == null) {
      return this.error("TENANT_DELETION_REQUEST_NOT_FOUND", "Solicitacao de exclusao nao encontrada.");
    }
    if (request.companyId !== companyId) {
      return this.error("TENANT_DELETION_STATE_CONFLICT", "A solicitacao nao pertence a empresa informada.");
    }

    const permitted = await this.rbacService.hasPermission({
      actorAdminId,
      permissionKey: "tenant.deletion.execute",
      companyId,
    });
    if (!permitted) {
      const auditEventId = await this.adminAudit({
        actorAdminId,
        companyId,
        action: "tenant.deletion.execution.denied",
        details: { requestId: request.id, requiredPermission: "tenant.deletion.execute" },
      });
      return {
        ...this.error("TENANT_DELETION_PERMISSION_REQUIRED", "Permissao granular obrigatoria para executar a exclusao seletiva."),
        auditEventId,
        requiredPermission: "tenant.deletion.execute",
      };
    }

    if (!this.enabled) {
      const auditEventId = await this.adminAudit({
        actorAdminId,
        companyId,
        action: "tenant.deletion.execution.disabled",
        details: { requestId: request.id, featureFlag: "TENANT_DELETION_EXECUTION_ENABLED" },
      });
      return {
        ...this.error("TENANT_DELETION_EXECUTION_DISABLED", "Execucao definitiva indisponivel: feature flag desabilitada."),
        auditEventId,
      };
    }

    if (request.status === "DELETION_EXECUTED") {
      return {
        ok: true,
        code: "TENANT_DELETION_EXECUTED",
        message: "Exclusao seletiva ja concluida; retorno idempotente.",
        auditEventId: null,
        details: request.executionReceiptJson,
      };
    }
    if (request.identityStatus !== "VERIFIED" || request.identityVerifiedAt == null) {
      return this.error("TENANT_DELETION_STATE_CONFLICT", "Execucao exige identidade verificada.");
    }
    if (request.status !== "FUTURE_PENDING_DELETION" && request.status !== "EXECUTION_IN_PROGRESS") {
      return this.error("TENANT_DELETION_STATE_CONFLICT", "Execucao exige tenant em quarentena operacional.");
    }
    if (request.dryRunSnapshotJson == null || request.dryRunGeneratedAt == null) {
      return this.error("TENANT_DELETION_STATE_CONFLICT", "Execucao exige dry-run persistido.");
    }

    const attemptId = randomUUID();
    const lockAcquiredAt = this.now();
    const staleBefore = new Date(lockAcquiredAt.getTime() - 30 * 60 * 1000);
    const lock = await this.client.tenantDeletionRequest.updateMany({
      where: {
        id: request.id,
        status: { in: ["FUTURE_PENDING_DELETION", "EXECUTION_IN_PROGRESS"] },
        OR: [
          { executionAttemptId: null },
          { executionLockedAt: { lt: staleBefore } },
        ],
      },
      data: {
        executionAttemptId: attemptId,
        executionLockedAt: lockAcquiredAt,
      },
    });
    if (lock.count !== 1) {
      return this.error(
        "TENANT_DELETION_STATE_CONFLICT",
        "Outra execucao desta solicitacao ja esta em andamento.",
      );
    }

    try {
      await this.onLockAcquired?.();
      request = await this.client.tenantDeletionRequest.findUnique({
        where: { id: request.id },
      });
      if (request == null || request.executionAttemptId !== attemptId) {
        return this.error(
          "TENANT_DELETION_STATE_CONFLICT",
          "Lock de execucao perdido antes do inicio.",
        );
      }
      const executionRequest = request;

      const currentBlockers = await this.currentCriticalBlockers(executionRequest.companyId);
      const revalidatedAt = this.now();
      const revalidatedSnapshot = this.revalidatedSnapshot(
        executionRequest.dryRunSnapshotJson,
        revalidatedAt,
        currentBlockers,
      );
      const snapshotUpdated = await this.client.tenantDeletionRequest.updateMany({
        where: { id: executionRequest.id, executionAttemptId: attemptId },
        data: { dryRunSnapshotJson: revalidatedSnapshot },
      });
      if (snapshotUpdated.count !== 1) {
        return this.error(
          "TENANT_DELETION_STATE_CONFLICT",
          "Lock de execucao perdido durante a revalidacao.",
        );
      }
      if (currentBlockers.length > 0) {
        return {
          ...this.error(
            "TENANT_DELETION_STATE_CONFLICT",
            "Blockers criticos atuais impedem a execucao.",
          ),
          details: { blockers: currentBlockers, revalidatedAt: revalidatedAt.toISOString() },
        };
      }

      let progress = this.readProgress(executionRequest.executionProgressJson);
    if (executionRequest.status === "FUTURE_PENDING_DELETION") {
      progress = { completedCategories: [], failedCategory: null, lastError: null };
      const startedAt = this.now();
      const started = await this.client.$transaction(async (tx) => {
        const updated = await tx.tenantDeletionRequest.updateMany({
          where: { id: executionRequest.id, status: "FUTURE_PENDING_DELETION", executionAttemptId: attemptId },
          data: {
            status: "EXECUTION_IN_PROGRESS",
            executionPlanJson: [...executionPlan],
            executionProgressJson: progress,
            executionStartedAt: startedAt,
            executedByAdminUserId: actorAdminId,
          },
        });
        if (updated.count !== 1) return null;
        return this.audit(tx, {
          requestId: executionRequest.id,
          companyId,
          actorAdminId,
          eventType: "EXECUTION_STARTED",
          action: "tenant.deletion.execution_started",
          reason,
          before: { status: "FUTURE_PENDING_DELETION", completedCategories: [] },
          after: { status: "EXECUTION_IN_PROGRESS", completedCategories: [] },
          metadata: { plan: executionPlan, featureFlagEnabled: true },
        });
      });
      if (started == null) {
        return this.error("TENANT_DELETION_STATE_CONFLICT", "A solicitacao foi alterada por outra execucao.");
      }
    }

    for (const category of executionPlan) {
      if (progress.completedCategories.includes(category)) continue;
      try {
        const categoryResult = await this.client.$transaction(async (tx) => {
          const fresh = await tx.tenantDeletionRequest.findUnique({ where: { id: executionRequest.id } });
          if (fresh == null || fresh.status !== "EXECUTION_IN_PROGRESS" || fresh.executionAttemptId !== attemptId) {
            throw new Error("execution_state_changed");
          }
          const freshProgress = this.readProgress(fresh.executionProgressJson);
          if (freshProgress.completedCategories.includes(category)) {
            return { progress: freshProgress, result: { idempotent: true } };
          }
          const beforeCounts = await this.categoryCounts(tx, category, companyId);
          const result = await this.executeCategory(tx, category, companyId, actorAdminId);
          const afterCounts = await this.categoryCounts(tx, category, companyId);
          const nextProgress: ExecutionProgress = {
            completedCategories: [...freshProgress.completedCategories, category],
            failedCategory: null,
            lastError: null,
          };
          const checkpoint = await tx.tenantDeletionRequest.updateMany({
            where: { id: executionRequest.id, executionAttemptId: attemptId },
            data: {
              executionProgressJson: nextProgress,
              executionLockedAt: this.now(),
            },
          });
          if (checkpoint.count !== 1) {
            throw new Error("execution_lock_lost");
          }
          await this.audit(tx, {
            requestId: executionRequest.id,
            companyId,
            actorAdminId,
            eventType: "EXECUTION_CATEGORY_COMPLETED",
            action: "tenant.deletion.execution_category_completed",
            reason,
            before: { category, status: "pending", counts: beforeCounts },
            after: { category, status: "completed", counts: afterCounts },
            metadata: { category, result },
          });
          return { progress: nextProgress, result };
        });
        progress = categoryResult.progress;
      } catch (error) {
        const message = error instanceof Error ? error.message : "unknown_execution_error";
        progress = { ...progress, failedCategory: category, lastError: message };
        await this.client.tenantDeletionRequest.updateMany({
          where: { id: executionRequest.id, executionAttemptId: attemptId },
          data: { executionProgressJson: progress },
        });
        const auditEventId = await this.audit(this.client, {
          requestId: executionRequest.id,
          companyId,
          actorAdminId,
          eventType: "EXECUTION_FAILED",
          action: "tenant.deletion.execution_failed",
          reason,
          before: { category, status: "running" },
          after: { category, status: "failed" },
          metadata: { category, error: message },
        });
        return {
          ...this.error("TENANT_DELETION_STATE_CONFLICT", "Execucao interrompida; o progresso persistido permite nova tentativa."),
          auditEventId,
          details: progress,
        };
      }
    }

    const completedAt = this.now();
    const receipt = {
      requestId: executionRequest.id,
      companyId,
      completedAt: completedAt.toISOString(),
      completedCategories: progress.completedCategories,
      companyPhysicallyDeleted: false,
      billingChanged: false,
      mercadoPagoCalled: false,
      retained: ["Company tombstone", "License", "billing invoices/events", "admin and deletion audit", "financial records"],
    };
    const auditEventId = await this.client.$transaction(async (tx) => {
      const completed = await tx.tenantDeletionRequest.updateMany({
        where: { id: executionRequest.id, executionAttemptId: attemptId },
        data: {
          status: "DELETION_EXECUTED",
          executionProgressJson: progress,
          executionReceiptJson: receipt,
          executionCompletedAt: completedAt,
          executedByAdminUserId: actorAdminId,
        },
      });
      if (completed.count !== 1) {
        throw new Error("execution_lock_lost_before_completion");
      }
      return this.audit(tx, {
        requestId: executionRequest.id,
        companyId,
        actorAdminId,
        eventType: "EXECUTION_COMPLETED",
        action: "tenant.deletion.execution_completed",
        reason,
        before: { status: "EXECUTION_IN_PROGRESS", completedCategories: progress.completedCategories },
        after: { status: "DELETION_EXECUTED", completedCategories: progress.completedCategories },
        metadata: receipt,
      });
    });

      return {
        ok: true,
        code: "TENANT_DELETION_EXECUTED",
        message: "Anonimizacao e exclusao seletiva concluidas; Company preservada como tombstone.",
        auditEventId,
        details: receipt,
      };
    } finally {
      await this.client.tenantDeletionRequest.updateMany({
        where: { id: input.requestId.trim(), executionAttemptId: attemptId },
        data: { executionAttemptId: null, executionLockedAt: null },
      });
    }
  }

  private async executeCategory(
    tx: Prisma.TransactionClient,
    category: ExecutionCategory,
    companyId: string,
    actorAdminId: string,
  ) {
    const now = this.now();
    switch (category) {
      case "access_revocation": {
        const [sessions, devices, employees] = await Promise.all([
          tx.deviceSession.updateMany({ where: { companyId, revokedAt: null, NOT: { clientType: "ADMIN_WEB", user: { isPlatformAdmin: true } } }, data: { revokedAt: now, revokedReason: "tenant_deletion_execution" } }),
          tx.companyDevice.updateMany({ where: { companyId }, data: { status: "REVOKED", revokedAt: now, revokedReason: "tenant_deletion_execution", deviceLabel: null, platform: null, appVersion: null } }),
          tx.employeeProfile.updateMany({ where: { companyId }, data: { name: "Funcionario anonimizado", email: null, emailNormalized: null, phone: null, permissions: Prisma.DbNull, inviteTokenHash: null, inviteExpiresAt: null, status: "DISABLED", disabledAt: now, userId: null, membershipId: null } }),
        ]);
        return { sessions: sessions.count, devices: devices.count, employees: employees.count };
      }
      case "personal_data_anonymization": {
        const deleted = await Promise.all([
          tx.customerTagAssignment.deleteMany({ where: { companyId } }),
          tx.customerNote.deleteMany({ where: { companyId } }),
          tx.customerTask.deleteMany({ where: { companyId } }),
          tx.customerTimelineEvent.deleteMany({ where: { companyId } }),
          tx.customerTag.deleteMany({ where: { companyId } }),
        ]);
        const [customers, suppliers] = await Promise.all([
          tx.customer.updateMany({ where: { companyId }, data: { name: "Cliente anonimizado", phone: null, address: null, notes: null, isActive: false, deletedAt: now } }),
          tx.supplier.updateMany({ where: { companyId }, data: { name: "Fornecedor anonimizado", tradeName: null, phone: null, email: null, address: null, document: null, contactPerson: null, notes: null, isActive: false, deletedAt: now } }),
        ]);
        return { crmDeleted: deleted.reduce((sum, item) => sum + item.count, 0), customers: customers.count, suppliers: suppliers.count };
      }
      case "sync_data_deletion": {
        const results = await Promise.all([
          tx.syncSupportCommand.deleteMany({ where: { companyId } }),
          tx.deviceSyncDiagnostic.deleteMany({ where: { companyId } }),
          tx.syncConflict.deleteMany({ where: { companyId } }),
          tx.syncIncident.deleteMany({ where: { companyId } }),
          tx.syncCheckpoint.deleteMany({ where: { companyId } }),
        ]);
        const events = await tx.syncEvent.deleteMany({ where: { companyId } });
        const state = await tx.companySyncState.deleteMany({ where: { companyId } });
        return { deleted: results.reduce((sum, item) => sum + item.count, 0) + events.count + state.count };
      }
      case "analytics_deletion": {
        const results = await Promise.all([
          tx.analyticsCompanyDailySnapshot.deleteMany({ where: { companyId } }),
          tx.analyticsProductDailySnapshot.deleteMany({ where: { companyId } }),
          tx.analyticsCustomerDailySnapshot.deleteMany({ where: { companyId } }),
        ]);
        return { deleted: results.reduce((sum, item) => sum + item.count, 0) };
      }
      case "catalog_anonymization": {
        const results = await Promise.all([
          tx.category.updateMany({ where: { companyId }, data: { name: "Categoria anonimizada", description: null, isActive: false, deletedAt: now } }),
          tx.product.updateMany({ where: { companyId }, data: { name: "Produto anonimizado", description: null, barcode: null, modelName: null, variantLabel: null, isActive: false, deletedAt: now } }),
          tx.supply.updateMany({ where: { companyId }, data: { name: "Insumo anonimizado", sku: null, isActive: false, deletedAt: now } }),
          tx.productRecipeItem.updateMany({ where: { companyId }, data: { notes: null } }),
        ]);
        return { anonymized: results.reduce((sum, item) => sum + item.count, 0), historicalSaleSnapshotsPreserved: true };
      }
      case "financial_text_minimization": {
        const results = await Promise.all([
          tx.sale.updateMany({ where: { companyId }, data: { notes: null } }),
          tx.cost.updateMany({ where: { companyId }, data: { notes: null } }),
          tx.fiadoPayment.updateMany({ where: { companyId }, data: { notes: null } }),
          tx.cashEvent.updateMany({ where: { companyId }, data: { notes: null } }),
          tx.cashSession.updateMany({ where: { companyId }, data: { notes: null, payload: Prisma.DbNull } }),
          tx.financialEvent.updateMany({ where: { companyId }, data: { metadata: Prisma.DbNull } }),
        ]);
        return { minimized: results.reduce((sum, item) => sum + item.count, 0) };
      }
      case "membership_cleanup": {
        const memberships = await tx.membership.deleteMany({
          where: { companyId, user: { isPlatformAdmin: false } },
        });
        return { membershipsRemoved: memberships.count, platformAdminMembershipsPreserved: true };
      }
      case "company_tombstone": {
        await tx.company.update({
          where: { id: companyId },
          data: {
            name: "Empresa excluida",
            legalName: "Empresa excluida",
            documentNumber: null,
            receiptDisplayName: null,
            receiptDocument: null,
            receiptPhone: null,
            receiptAddress: null,
            receiptFooterMessage: null,
            showDocumentOnReceipt: false,
            showPhoneOnReceipt: false,
            showAddressOnReceipt: false,
            showFooterMessageOnReceipt: false,
            slug: `deleted-${companyId}`,
            isActive: false,
          },
        });
        return { companyPhysicallyDeleted: false, tombstone: true };
      }
      case "retained_legal_records": {
        const [billingInvoices, billingEvents, adminAudits, deletionAudits] = await Promise.all([
          tx.billingInvoice.count({ where: { companyId } }),
          tx.billingProviderEvent.count({ where: { companyId } }),
          tx.adminAuditLog.count({ where: { targetCompanyId: companyId } }),
          tx.tenantDeletionAuditEvent.count({ where: { companyId } }),
        ]);
        return { billingInvoices, billingEvents, adminAudits, deletionAudits, mercadoPagoCalled: false };
      }
    }
  }

  private async currentCriticalBlockers(companyId: string) {
    const [company, pendingCheckouts, openInvoices, disputeEvents] =
      await Promise.all([
        this.client.company.findUnique({
          where: { id: companyId },
          select: {
            license: {
              select: {
                providerSubscriptionId: true,
                billingSubscriptionStatus: true,
              },
            },
          },
        }),
        this.client.billingCheckoutSession.count({
          where: { companyId, status: { in: ["PENDING", "PROCESSING"] } },
        }),
        this.client.billingInvoice.count({
          where: {
            companyId,
            status: { in: ["open", "pending", "failed", "overdue"], mode: "insensitive" },
          },
        }),
        this.client.billingProviderEvent.count({
          where: {
            companyId,
            OR: [
              { eventType: { contains: "chargeback", mode: "insensitive" } },
              { eventType: { contains: "charged_back", mode: "insensitive" } },
              { eventType: { contains: "dispute", mode: "insensitive" } },
            ],
          },
        }),
      ]);

    const blockers: Array<{ key: string; count?: number }> = [];
    const subscriptionId = company?.license?.providerSubscriptionId?.trim();
    const subscriptionStatus = company?.license?.billingSubscriptionStatus
      ?.trim()
      .toLowerCase();
    if (
      subscriptionId &&
      !["cancelled", "canceled", "terminated"].includes(subscriptionStatus ?? "")
    ) {
      blockers.push({ key: "active_provider_subscription", count: 1 });
    }
    if (pendingCheckouts > 0) {
      blockers.push({ key: "pending_checkout_sessions", count: pendingCheckouts });
    }
    if (openInvoices > 0) {
      blockers.push({ key: "open_invoices", count: openInvoices });
    }
    if (disputeEvents > 0) {
      blockers.push({ key: "provider_disputes_or_chargebacks", count: disputeEvents });
    }
    return blockers;
  }

  private revalidatedSnapshot(
    value: Prisma.JsonValue,
    revalidatedAt: Date,
    blockers: Array<{ key: string; count?: number }>,
  ): Prisma.InputJsonValue {
    const base =
      value != null && typeof value === "object" && !Array.isArray(value)
        ? value as Prisma.JsonObject
        : {};
    return {
      ...base,
      executionRevalidation: {
        revalidatedAt: revalidatedAt.toISOString(),
        criticalBlockers: blockers,
      },
    } as Prisma.InputJsonValue;
  }

  private async categoryCounts(
    tx: Prisma.TransactionClient,
    category: ExecutionCategory,
    companyId: string,
  ) {
    switch (category) {
      case "access_revocation":
        return {
          activeOperationalSessions: await tx.deviceSession.count({
            where: {
              companyId,
              revokedAt: null,
              NOT: { clientType: "ADMIN_WEB", user: { isPlatformAdmin: true } },
            },
          }),
          preservedPlatformAdminSessions: await tx.deviceSession.count({
            where: {
              companyId,
              revokedAt: null,
              clientType: "ADMIN_WEB",
              user: { isPlatformAdmin: true },
            },
          }),
          nonRevokedDevices: await tx.companyDevice.count({
            where: { companyId, status: { not: "REVOKED" } },
          }),
          identifiableEmployees: await tx.employeeProfile.count({
            where: { companyId, status: { not: "DISABLED" } },
          }),
        };
      case "personal_data_anonymization":
        return {
          activeCustomers: await tx.customer.count({ where: { companyId, isActive: true } }),
          activeSuppliers: await tx.supplier.count({ where: { companyId, isActive: true } }),
          crmFreeContent: await this.sumCounts([
            tx.customerTagAssignment.count({ where: { companyId } }),
            tx.customerNote.count({ where: { companyId } }),
            tx.customerTask.count({ where: { companyId } }),
            tx.customerTimelineEvent.count({ where: { companyId } }),
            tx.customerTag.count({ where: { companyId } }),
          ]),
        };
      case "sync_data_deletion":
        return {
          syncRecords: await this.sumCounts([
            tx.syncSupportCommand.count({ where: { companyId } }),
            tx.deviceSyncDiagnostic.count({ where: { companyId } }),
            tx.syncConflict.count({ where: { companyId } }),
            tx.syncIncident.count({ where: { companyId } }),
            tx.syncCheckpoint.count({ where: { companyId } }),
            tx.syncEvent.count({ where: { companyId } }),
            tx.companySyncState.count({ where: { companyId } }),
          ]),
        };
      case "analytics_deletion":
        return {
          analyticsRecords: await this.sumCounts([
            tx.analyticsCompanyDailySnapshot.count({ where: { companyId } }),
            tx.analyticsProductDailySnapshot.count({ where: { companyId } }),
            tx.analyticsCustomerDailySnapshot.count({ where: { companyId } }),
          ]),
        };
      case "catalog_anonymization":
        return {
          activeCatalogRecords: await this.sumCounts([
            tx.category.count({ where: { companyId, isActive: true } }),
            tx.product.count({ where: { companyId, isActive: true } }),
            tx.supply.count({ where: { companyId, isActive: true } }),
          ]),
          recipeItemsWithNotes: await tx.productRecipeItem.count({
            where: { companyId, notes: { not: null } },
          }),
        };
      case "financial_text_minimization":
        return {
          recordsWithFreeText: await this.sumCounts([
            tx.sale.count({ where: { companyId, notes: { not: null } } }),
            tx.cost.count({ where: { companyId, notes: { not: null } } }),
            tx.fiadoPayment.count({ where: { companyId, notes: { not: null } } }),
            tx.cashEvent.count({ where: { companyId, notes: { not: null } } }),
            tx.cashSession.count({ where: { companyId, OR: [{ notes: { not: null } }, { payload: { not: Prisma.DbNull } }] } }),
            tx.financialEvent.count({ where: { companyId, metadata: { not: Prisma.DbNull } } }),
          ]),
        };
      case "membership_cleanup":
        return {
          removableMemberships: await tx.membership.count({
            where: { companyId, user: { isPlatformAdmin: false } },
          }),
          preservedPlatformAdminMemberships: await tx.membership.count({
            where: { companyId, user: { isPlatformAdmin: true } },
          }),
        };
      case "company_tombstone": {
        const company = await tx.company.findUnique({
          where: { id: companyId },
          select: { isActive: true, documentNumber: true },
        });
        return {
          activeCompany: company?.isActive === true ? 1 : 0,
          companyDocumentPresent: company?.documentNumber == null ? 0 : 1,
        };
      }
      case "retained_legal_records":
        return {
          billingInvoices: await tx.billingInvoice.count({ where: { companyId } }),
          billingCheckouts: await tx.billingCheckoutSession.count({ where: { companyId } }),
          billingEvents: await tx.billingProviderEvent.count({ where: { companyId } }),
          adminAudits: await tx.adminAuditLog.count({ where: { targetCompanyId: companyId } }),
          deletionAudits: await tx.tenantDeletionAuditEvent.count({ where: { companyId } }),
        };
    }
  }

  private async sumCounts(counts: Array<Promise<number>>) {
    return (await Promise.all(counts)).reduce((sum, count) => sum + count, 0);
  }

  private readProgress(value: Prisma.JsonValue | null): ExecutionProgress {
    if (value == null || typeof value !== "object" || Array.isArray(value)) {
      return { completedCategories: [], failedCategory: null, lastError: null };
    }
    const candidate = value as { completedCategories?: unknown; failedCategory?: unknown; lastError?: unknown };
    const completedCategories = Array.isArray(candidate.completedCategories)
      ? candidate.completedCategories.filter((item): item is ExecutionCategory => executionPlan.includes(item as ExecutionCategory))
      : [];
    return {
      completedCategories,
      failedCategory: executionPlan.includes(candidate.failedCategory as ExecutionCategory) ? candidate.failedCategory as ExecutionCategory : null,
      lastError: typeof candidate.lastError === "string" ? candidate.lastError : null,
    };
  }

  private async audit(
    db: Prisma.TransactionClient | typeof prisma,
    input: {
      requestId: string;
      companyId: string;
      actorAdminId: string;
      eventType: "EXECUTION_STARTED" | "EXECUTION_CATEGORY_COMPLETED" | "EXECUTION_FAILED" | "EXECUTION_COMPLETED";
      action: string;
      reason: string;
      before: unknown;
      after: unknown;
      metadata: unknown;
    },
  ) {
    const before = sanitizeOperationalActionPayload(input.before);
    const after = sanitizeOperationalActionPayload(input.after);
    const metadata = sanitizeOperationalActionPayload(input.metadata);
    const event = await db.tenantDeletionAuditEvent.create({
      data: {
        requestId: input.requestId,
        companyId: input.companyId,
        actorAdminUserId: input.actorAdminId,
        eventType: input.eventType,
        reason: input.reason,
        beforeJson: before as Prisma.InputJsonValue,
        afterJson: after as Prisma.InputJsonValue,
        metadataJson: metadata as Prisma.InputJsonValue,
      },
    });
    await db.adminAuditLog.create({
      data: { ...userAdminAuditActor(input.actorAdminId), targetCompanyId: input.companyId, action: input.action, details: { requestId: input.requestId, tenantDeletionAuditEventId: event.id, reason: input.reason, metadata } as Prisma.InputJsonValue },
    });
    return event.id;
  }

  private async adminAudit(input: { actorAdminId: string; companyId: string; action: string; details: unknown }) {
    const event = await this.client.adminAuditLog.create({
      data: { ...userAdminAuditActor(input.actorAdminId), targetCompanyId: input.companyId, action: input.action, details: sanitizeOperationalActionPayload(input.details) as Prisma.InputJsonValue },
    });
    return event.id;
  }

  private error(code: TenantDeletionOperationResult["code"], message: string): TenantDeletionOperationResult {
    return { ok: false, code, message, auditEventId: null };
  }
}
