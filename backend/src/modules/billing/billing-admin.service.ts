import { LicenseStatus, Prisma, type License } from "@prisma/client";

import { env } from "../../config/env";
import { prisma } from "../../database/prisma";
import { buildAdminListResponse } from "../../shared/http/api-response";
import { AppError } from "../../shared/http/app-error";
import { toPaginationParams } from "../../shared/http/pagination";
import { normalizePlan } from "../plans/plan-catalog.service";
import type {
  AdminBillingCancelLocalInput,
  AdminBillingCompaniesQueryInput,
  AdminBillingForcePlanInput,
  AdminBillingListQueryInput,
  AdminBillingReconcileDryRunInput,
  AdminBillingReconcileInput,
  AdminBillingRefreshInput,
  AdminBillingStatusInput,
  AdminLicenseEmergencyExtensionDryRunInput,
  AdminLicenseEmergencyExtensionInput,
  AdminLicenseStatusActionDryRunInput,
  AdminLicenseStatusActionInput,
} from "./billing-admin.schemas";
import {
  maskProviderSubscriptionId,
  maskUrl,
  sanitizeForAdmin,
} from "./billing-sanitizer";
import { BillingService } from "./billing.service";

type AdminActionContext = {
  actorUserId: string | null | undefined;
  companyId: string;
  reason: string;
  ipAddress?: string | null;
  userAgent?: string | null;
};

type CompanyIdentity = {
  id: string;
  name: string;
  legalName: string;
  slug: string;
  isActive: boolean;
};

const BILLING_PROVIDER = "mercadopago";
const BILLING_RECONCILE_CONFIRMATION = "RECONCILIAR";
const EMERGENCY_EXTENSION_CONFIRMATION = "ESTENDER";
const EMERGENCY_EXTENSION_MAX_DAYS = 7;
const LICENSE_SUSPEND_CONFIRMATION = "SUSPENDER";
const LICENSE_REACTIVATE_CONFIRMATION = "REATIVAR";

export class BillingAdminService {
  constructor(private readonly billingService = new BillingService()) {}

  async listCompanies(query: AdminBillingCompaniesQueryInput) {
    const where = this.buildCompanyWhere(query);
    const { skip, take } = toPaginationParams(query);

    const [total, companies] = await prisma.$transaction([
      prisma.company.count({ where }),
      prisma.company.findMany({
        where,
        skip,
        take,
        orderBy: this.resolveCompanyOrderBy(query),
        include: { license: true },
      }),
    ]);

    return buildAdminListResponse({
      items: companies.map((company) => ({
        companyId: company.id,
        companyName: company.name,
        plan: normalizePlan(company.license?.plan),
        rawPlan: company.license?.plan ?? null,
        licenseStatus: company.license?.status ?? null,
        billingProvider: company.license?.billingProvider ?? null,
        hasProviderSubscription:
          company.license?.providerSubscriptionId != null,
        maskedProviderSubscriptionId: maskProviderSubscriptionId(
          company.license?.providerSubscriptionId,
        ),
        currentPeriodEnd:
          company.license?.currentPeriodEnd?.toISOString() ?? null,
        nextPaymentDate:
          company.license?.nextPaymentDate?.toISOString() ?? null,
        cancelAtPeriodEnd: company.license?.cancelAtPeriodEnd ?? false,
        pendingPlan: company.license?.pendingPlan ?? null,
        billingSubscriptionStatus:
          company.license?.billingSubscriptionStatus ?? null,
        createdAt: company.license?.createdAt.toISOString() ?? null,
        updatedAt: company.license?.updatedAt.toISOString() ?? null,
      })),
      page: query.page,
      pageSize: query.pageSize,
      total,
      filters: {
        search: query.search ?? null,
        plan: query.plan ?? null,
        status: query.status ?? null,
        provider: query.provider ?? null,
        hasProviderSubscription: query.hasProviderSubscription ?? null,
      },
      sort: {
        by: query.sort,
        direction: query.sortDirection,
      },
    });
  }

  async getStatus(companyId: string) {
    const company = await this.getCompany(companyId);
    const [checkoutSessions, events, invoices] = await prisma.$transaction([
      prisma.billingCheckoutSession.findMany({
        where: { companyId },
        orderBy: { createdAt: "desc" },
        take: 5,
      }),
      prisma.billingProviderEvent.findMany({
        where: { companyId },
        orderBy: { createdAt: "desc" },
        take: 5,
      }),
      prisma.billingInvoice.findMany({
        where: { companyId },
        orderBy: { createdAt: "desc" },
        take: 5,
      }),
    ]);

    return {
      company: {
        id: company.id,
        name: company.name,
        legalName: company.legalName,
        slug: company.slug,
        isActive: company.isActive,
      },
      license:
        company.license == null
          ? null
          : this.serializeLicenseForEmergencyAudit(company.license),
      billing: {
        provider: company.license?.billingProvider ?? null,
        hasProviderSubscription:
          company.license?.providerSubscriptionId != null,
        maskedProviderSubscriptionId: maskProviderSubscriptionId(
          company.license?.providerSubscriptionId,
        ),
        currentPeriodStart:
          company.license?.currentPeriodStart?.toISOString() ?? null,
        currentPeriodEnd:
          company.license?.currentPeriodEnd?.toISOString() ?? null,
        nextPaymentDate:
          company.license?.nextPaymentDate?.toISOString() ?? null,
        cancelAtPeriodEnd: company.license?.cancelAtPeriodEnd ?? false,
        cancelRequestedAt:
          company.license?.cancelRequestedAt?.toISOString() ?? null,
        canceledAt: company.license?.canceledAt?.toISOString() ?? null,
        pendingPlan: company.license?.pendingPlan ?? null,
        pendingPlanRequestedAt:
          company.license?.pendingPlanRequestedAt?.toISOString() ?? null,
        billingSubscriptionStatus:
          company.license?.billingSubscriptionStatus ?? null,
      },
      checkoutSessions: checkoutSessions.map((session) =>
        this.serializeCheckoutSession(session),
      ),
      events: events.map((event) => this.serializeProviderEvent(event)),
      invoices: invoices.map((invoice) => this.serializeInvoice(invoice)),
    };
  }

  async listEvents(companyId: string, query: AdminBillingListQueryInput) {
    await this.assertCompanyExists(companyId);
    const { skip, take } = toPaginationParams(query);
    const where: Prisma.BillingProviderEventWhereInput = { companyId };
    const [total, events] = await prisma.$transaction([
      prisma.billingProviderEvent.count({ where }),
      prisma.billingProviderEvent.findMany({
        where,
        skip,
        take,
        orderBy: { createdAt: "desc" },
      }),
    ]);
    return buildAdminListResponse({
      items: events.map((event) => this.serializeProviderEvent(event)),
      page: query.page,
      pageSize: query.pageSize,
      total,
      filters: {},
      sort: { by: "createdAt", direction: "desc" },
    });
  }

  async listCheckoutSessions(
    companyId: string,
    query: AdminBillingListQueryInput,
  ) {
    await this.assertCompanyExists(companyId);
    const { skip, take } = toPaginationParams(query);
    const where: Prisma.BillingCheckoutSessionWhereInput = { companyId };
    const [total, sessions] = await prisma.$transaction([
      prisma.billingCheckoutSession.count({ where }),
      prisma.billingCheckoutSession.findMany({
        where,
        skip,
        take,
        orderBy: { createdAt: "desc" },
      }),
    ]);
    return buildAdminListResponse({
      items: sessions.map((session) => this.serializeCheckoutSession(session)),
      page: query.page,
      pageSize: query.pageSize,
      total,
      filters: {},
      sort: { by: "createdAt", direction: "desc" },
    });
  }

  async listAuditLogs(companyId: string, query: AdminBillingListQueryInput) {
    await this.assertCompanyExists(companyId);
    const { skip, take } = toPaginationParams(query);
    const where: Prisma.BillingAdminAuditLogWhereInput = { companyId };
    const [total, logs] = await prisma.$transaction([
      prisma.billingAdminAuditLog.count({ where }),
      prisma.billingAdminAuditLog.findMany({
        where,
        skip,
        take,
        orderBy: { createdAt: "desc" },
        include: {
          actorUser: {
            select: {
              id: true,
              name: true,
              email: true,
            },
          },
        },
      }),
    ]);

    return buildAdminListResponse({
      items: logs.map((log) => this.serializeBillingAdminAuditLog(log)),
      page: query.page,
      pageSize: query.pageSize,
      total,
      filters: { companyId },
      sort: { by: "createdAt", direction: "desc" },
    });
  }

  async refreshCompany(input: AdminActionContext & AdminBillingRefreshInput) {
    const context = this.assertAdminActionContext(input);
    const before = await this.getLicenseSnapshot(context.companyId);

    try {
      const status = await this.billingService.refreshCompanyFromProvider(
        context.companyId,
      );
      const after = await this.getLicenseSnapshot(context.companyId);
      await this.createAuditLog({
        ...context,
        action: "billing.refresh",
        before,
        after,
        metadata: { result: status },
      });
      return status;
    } catch (error) {
      const after = await this.getLicenseSnapshot(context.companyId);
      await this.createAuditLog({
        ...context,
        action: "billing.refresh.failed",
        before,
        after,
        metadata: {
          error:
            error instanceof AppError
              ? { code: error.code, statusCode: error.statusCode }
              : { code: "BILLING_REFRESH_FAILED" },
        },
      });
      throw new AppError(
        "Nao foi possivel reconciliar a assinatura com o Mercado Pago.",
        error instanceof AppError ? error.statusCode : 502,
        error instanceof AppError ? error.code : "BILLING_REFRESH_FAILED",
      );
    }
  }

  async dryRunBillingReconcile(
    input: AdminActionContext & AdminBillingReconcileDryRunInput,
  ) {
    const context = this.assertAdminActionContext(input);
    await this.assertCompanyExists(context.companyId);
    return this.buildBillingReconcileDryRun({
      companyId: context.companyId,
      note: input.note,
    });
  }

  async applyBillingReconcile(
    input: AdminActionContext & AdminBillingReconcileInput,
  ) {
    const context = this.assertAdminActionContext(input);
    if (input.confirmationText !== BILLING_RECONCILE_CONFIRMATION) {
      throw new AppError(
        "Digite RECONCILIAR para confirmar a reconciliacao de billing.",
        422,
        "BILLING_RECONCILE_CONFIRMATION_REQUIRED",
        { expectedConfirmationText: BILLING_RECONCILE_CONFIRMATION },
      );
    }

    await this.assertCompanyExists(context.companyId);
    const dryRun = await this.buildBillingReconcileDryRun({
      companyId: context.companyId,
      note: input.note,
    });
    if (!dryRun.allowed) {
      throw new AppError(
        "Reconciliacao de billing bloqueada.",
        409,
        "BILLING_RECONCILE_BLOCKED",
        { blockers: dryRun.blockers },
      );
    }

    const before = await this.getSafeLicenseSnapshot(context.companyId);
    const beforeCheckoutSessions = await this.listReconcileCheckoutSessions(
      context.companyId,
    );
    const beforeInvoicesCount = await prisma.billingInvoice.count({
      where: { companyId: context.companyId },
    });

    try {
      const status = await this.billingService.refreshCompanyFromProvider(
        context.companyId,
      );
      const after = await this.getSafeLicenseSnapshot(context.companyId);
      const afterCheckoutSessions = await this.listReconcileCheckoutSessions(
        context.companyId,
      );
      const afterInvoicesCount = await prisma.billingInvoice.count({
        where: { companyId: context.companyId },
      });
      const checkoutSessionsUpdated = this.countChangedCheckoutSessions(
        beforeCheckoutSessions,
        afterCheckoutSessions,
      );
      const invoicesReconciled = Math.max(
        0,
        afterInvoicesCount - beforeInvoicesCount,
      );
      const warnings = this.readWarnings(status);

      await this.createAuditLog({
        ...context,
        action: "billing.reconcile",
        before,
        after,
        metadata: {
          source: "admin_web",
          confirmationTextExpected: BILLING_RECONCILE_CONFIRMATION,
          checkoutSessionIds: beforeCheckoutSessions.map(
            (session) => session.id,
          ),
          providerStatus: this.buildProviderStatusSummary(status),
          warnings,
          invoicesReconciled,
          checkoutSessionsUpdated,
          note: input.note ?? null,
        },
      });

      return {
        success: true,
        message:
          "Billing reconciliado pelo fluxo seguro existente, sem forcar plano manualmente.",
        updatedStatus: this.sanitizeBillingStatus(status),
        invoicesReconciled,
        checkoutSessionsUpdated,
        warnings,
      };
    } catch (error) {
      const after = await this.getSafeLicenseSnapshot(context.companyId);
      await this.createAuditLog({
        ...context,
        action: "billing.reconcile.failed",
        before,
        after,
        metadata: {
          source: "admin_web",
          confirmationTextExpected: BILLING_RECONCILE_CONFIRMATION,
          checkoutSessionIds: beforeCheckoutSessions.map(
            (session) => session.id,
          ),
          error:
            error instanceof AppError
              ? { code: error.code, statusCode: error.statusCode }
              : { code: "BILLING_RECONCILE_FAILED" },
          note: input.note ?? null,
        },
      });
      throw new AppError(
        "Nao foi possivel reconciliar o billing com o Mercado Pago.",
        error instanceof AppError ? error.statusCode : 502,
        error instanceof AppError ? error.code : "BILLING_RECONCILE_FAILED",
      );
    }
  }

  async forcePlan(input: AdminActionContext & AdminBillingForcePlanInput) {
    const context = this.assertAdminActionContext(input);
    const before = await this.getLicenseSnapshot(context.companyId);
    const current = await prisma.license.findUnique({
      where: { companyId: context.companyId },
    });
    const company = await this.getCompanyIdentity(context.companyId);
    const plan = normalizePlan(input.plan);
    const status = this.resolveLicenseStatus(input.status, current);
    const providerStillLinked =
      input.clearProvider !== true && current?.providerSubscriptionId != null;

    const license = await prisma.license.upsert({
      where: { companyId: context.companyId },
      create: {
        companyId: context.companyId,
        plan,
        status,
        startsAt: new Date(),
        expiresAt: null,
        syncEnabled: true,
        currentPeriodEnd:
          input.clearProvider === true
            ? null
            : (input.currentPeriodEnd ?? null),
        billingSubscriptionStatus: input.status ?? null,
        cancelAtPeriodEnd: false,
        cancelRequestedAt: null,
        canceledAt: null,
        pendingPlan: null,
        pendingPlanRequestedAt: null,
      },
      update: {
        plan,
        status,
        ...(input.currentPeriodEnd === undefined || input.clearProvider === true
          ? {}
          : { currentPeriodEnd: input.currentPeriodEnd }),
        billingSubscriptionStatus:
          input.status ?? current?.billingSubscriptionStatus ?? null,
        cancelAtPeriodEnd: false,
        cancelRequestedAt: null,
        canceledAt: null,
        pendingPlan: null,
        pendingPlanRequestedAt: null,
        ...(input.clearProvider === true
          ? {
              billingProvider: null,
              providerSubscriptionId: null,
              currentPeriodStart: null,
              currentPeriodEnd: null,
              nextPaymentDate: null,
            }
          : {}),
      },
    });

    const after = this.serializeLicense(license);
    await this.createAuditLog({
      ...context,
      action: "billing.force_plan",
      before,
      after,
      metadata: {
        requestedStatus: input.status ?? null,
        clearProvider: input.clearProvider,
        ...(providerStillLinked ? { warning: "provider still linked" } : {}),
      },
    });

    return {
      company,
      license: after,
      metadata: {
        providerStillLinked,
      },
    };
  }

  async cancelLocal(input: AdminActionContext & AdminBillingCancelLocalInput) {
    const context = this.assertAdminActionContext(input);
    const before = await this.getLicenseSnapshot(context.companyId);
    const current = await prisma.license.findUnique({
      where: { companyId: context.companyId },
    });

    if (current == null) {
      throw new AppError("Licenca nao encontrada.", 404, "LICENSE_NOT_FOUND");
    }

    const now = new Date();
    const hasFuturePeriod =
      current.currentPeriodEnd != null && current.currentPeriodEnd > now;
    const shouldSchedule = input.effective === "period_end" && hasFuturePeriod;

    const license = await prisma.license.update({
      where: { companyId: context.companyId },
      data: shouldSchedule
        ? {
            cancelAtPeriodEnd: true,
            cancelRequestedAt: now,
            billingSubscriptionStatus: "CANCELLED_LOCAL_PERIOD_END",
          }
        : {
            plan: "FREE",
            status: LicenseStatus.ACTIVE,
            expiresAt: null,
            cancelAtPeriodEnd: false,
            cancelRequestedAt: now,
            canceledAt: now,
            pendingPlan: null,
            pendingPlanRequestedAt: null,
            billingSubscriptionStatus: "CANCELLED_LOCAL",
          },
    });
    const after = this.serializeLicense(license);

    await this.createAuditLog({
      ...context,
      action: "billing.cancel_local",
      before,
      after,
      metadata: {
        effective: input.effective,
        scheduled: shouldSchedule,
        providerCancelled: false,
      },
    });

    return {
      providerCancelled: false,
      message:
        "Cancelamento local aplicado. A assinatura no Mercado Pago não foi cancelada por este endpoint.",
      license: after,
    };
  }

  async dryRunEmergencyExtension(
    input: AdminActionContext & AdminLicenseEmergencyExtensionDryRunInput,
  ) {
    const context = this.assertAdminActionContext(input);
    await this.assertCompanyExists(context.companyId);
    const license = await prisma.license.findUnique({
      where: { companyId: context.companyId },
    });

    return this.buildEmergencyExtensionDryRun({
      license,
      days: input.days,
      note: input.note,
    });
  }

  async applyEmergencyExtension(
    input: AdminActionContext & AdminLicenseEmergencyExtensionInput,
  ) {
    const context = this.assertAdminActionContext(input);
    if (input.confirmationText !== EMERGENCY_EXTENSION_CONFIRMATION) {
      throw new AppError(
        "Digite ESTENDER para confirmar a extensao emergencial.",
        422,
        "LICENSE_EXTENSION_CONFIRMATION_REQUIRED",
        { expectedConfirmationText: EMERGENCY_EXTENSION_CONFIRMATION },
      );
    }

    await this.assertCompanyExists(context.companyId);
    const result = await prisma.$transaction(async (tx) => {
      const license = await tx.license.findUnique({
        where: { companyId: context.companyId },
      });
      const dryRun = this.buildEmergencyExtensionDryRun({
        license,
        days: input.days,
        note: input.note,
      });
      const proposedChange = dryRun.proposedChange;
      if (!dryRun.allowed || license == null || proposedChange == null) {
        throw new AppError(
          "Extensao emergencial bloqueada.",
          409,
          "LICENSE_EXTENSION_BLOCKED",
          { blockers: dryRun.blockers },
        );
      }

      const before = this.serializeLicenseForEmergencyAudit(license);
      const updated = await tx.license.update({
        where: { companyId: context.companyId },
        data: {
          status: proposedChange.statusAfter as LicenseStatus,
          expiresAt: new Date(proposedChange.expiresAtAfter),
        },
      });
      const after = this.serializeLicenseForEmergencyAudit(updated);

      await tx.billingAdminAuditLog.create({
        data: {
          actorUserId: context.actorUserId,
          companyId: context.companyId,
          action: "license.emergency_extension",
          reason: context.reason,
          before: toJsonInput(before),
          after: toJsonInput(after),
          metadata: toJsonInput(
            sanitizeForAdmin({
              days: input.days,
              note: input.note ?? null,
              source: "admin_web",
              expectedConfirmationText: EMERGENCY_EXTENSION_CONFIRMATION,
            }),
          ),
          ipAddress: context.ipAddress ?? null,
          userAgent: context.userAgent ?? null,
        },
      });

      return { before, after, proposedChange };
    });

    return {
      success: true,
      message:
        "Extensao emergencial aplicada sem alterar plano, pendingPlan ou Mercado Pago.",
      license: result.after,
      currentLicense: result.before,
      proposedChange: result.proposedChange,
    };
  }

  async dryRunLicenseSuspend(
    input: AdminActionContext & AdminLicenseStatusActionDryRunInput,
  ) {
    const context = this.assertAdminActionContext(input);
    await this.assertCompanyExists(context.companyId);
    const license = await prisma.license.findUnique({
      where: { companyId: context.companyId },
    });
    return this.buildLicenseStatusActionDryRun({
      license,
      action: "suspend",
      note: input.note,
    });
  }

  async applyLicenseSuspend(
    input: AdminActionContext & AdminLicenseStatusActionInput,
  ) {
    return this.applyLicenseStatusAction({
      input,
      action: "suspend",
      expectedConfirmationText: LICENSE_SUSPEND_CONFIRMATION,
      targetStatus: LicenseStatus.SUSPENDED,
      auditAction: "license.suspend",
      blockedCode: "LICENSE_SUSPEND_BLOCKED",
      confirmationCode: "LICENSE_SUSPEND_CONFIRMATION_REQUIRED",
      confirmationMessage:
        "Digite SUSPENDER para confirmar a suspensao da licenca.",
      successMessage:
        "Licenca suspensa sem alterar plano, pendingPlan ou Mercado Pago.",
    });
  }

  async dryRunLicenseReactivate(
    input: AdminActionContext & AdminLicenseStatusActionDryRunInput,
  ) {
    const context = this.assertAdminActionContext(input);
    await this.assertCompanyExists(context.companyId);
    const license = await prisma.license.findUnique({
      where: { companyId: context.companyId },
    });
    return this.buildLicenseStatusActionDryRun({
      license,
      action: "reactivate",
      note: input.note,
    });
  }

  async applyLicenseReactivate(
    input: AdminActionContext & AdminLicenseStatusActionInput,
  ) {
    return this.applyLicenseStatusAction({
      input,
      action: "reactivate",
      expectedConfirmationText: LICENSE_REACTIVATE_CONFIRMATION,
      targetStatus: LicenseStatus.ACTIVE,
      auditAction: "license.reactivate",
      blockedCode: "LICENSE_REACTIVATE_BLOCKED",
      confirmationCode: "LICENSE_REACTIVATE_CONFIRMATION_REQUIRED",
      confirmationMessage:
        "Digite REATIVAR para confirmar a reativacao da licenca.",
      successMessage:
        "Licenca reativada sem alterar plano, pendingPlan ou Mercado Pago.",
    });
  }

  private buildLicenseStatusActionDryRun(input: {
    license: License | null;
    action: "suspend" | "reactivate";
    note?: string;
  }) {
    const { license, action } = input;
    const blockers: string[] = [];
    const now = new Date();
    const isExpiredByDate =
      license?.expiresAt != null &&
      license.expiresAt.getTime() <= now.getTime();
    const expectedConfirmationText =
      action === "suspend"
        ? LICENSE_SUSPEND_CONFIRMATION
        : LICENSE_REACTIVATE_CONFIRMATION;
    const targetStatus =
      action === "suspend" ? LicenseStatus.SUSPENDED : LicenseStatus.ACTIVE;
    const risks =
      action === "suspend"
        ? [
            "A suspensao pode bloquear acesso operacional conforme regras de licenca.",
            "Esta acao nao cancela cobranca no Mercado Pago.",
            "Esta acao nao altera plano nem assinatura provider.",
            "pendingPlan continua sem liberar recursos.",
          ]
        : [
            "Reativar licenca restabelece acesso conforme plano ativo license.plan.",
            "Esta acao nao altera plano.",
            "Esta acao nao altera cobranca Mercado Pago.",
            "pendingPlan continua sem liberar recursos.",
          ];

    if (license == null) {
      blockers.push("Empresa sem licenca cadastrada.");
    } else if (action === "suspend") {
      if (license.status === LicenseStatus.SUSPENDED) {
        blockers.push("Licenca ja esta suspensa.");
      }
    } else {
      if (license.status === LicenseStatus.ACTIVE) {
        blockers.push("Licenca ja esta ativa.");
      } else if (license.status !== LicenseStatus.SUSPENDED) {
        blockers.push(
          "Reativacao administrativa permitida apenas para licenca SUSPENDED.",
        );
      }
      if (isExpiredByDate) {
        blockers.push(
          "Licenca vencida por expiresAt. Use Extensao emergencial ou Reconciliar billing antes de reativar.",
        );
      }
    }

    const statusBefore = license?.status ?? null;
    return {
      allowed: blockers.length === 0,
      expectedConfirmationText,
      summary:
        license == null
          ? "Nao foi possivel simular a acao porque a licenca nao existe."
          : action === "suspend"
            ? "Suspender estado administrativo da licenca sem trocar plano e sem acionar Mercado Pago."
            : "Reativar estado administrativo da licenca sem trocar plano e sem acionar Mercado Pago.",
      risks,
      blockers,
      currentLicense:
        license == null
          ? null
          : this.serializeLicenseForEmergencyAudit(license),
      proposedChange:
        license == null
          ? null
          : {
              field: "status",
              statusBefore,
              statusAfter: targetStatus,
              planBefore: license.plan,
              planAfter: license.plan,
              pendingPlanBefore: license.pendingPlan,
              pendingPlanAfter: license.pendingPlan,
              expiresAtBefore: license.expiresAt?.toISOString() ?? null,
              expiresAtAfter: license.expiresAt?.toISOString() ?? null,
              currentPeriodEndBefore:
                license.currentPeriodEnd?.toISOString() ?? null,
              currentPeriodEndAfter:
                license.currentPeriodEnd?.toISOString() ?? null,
              mercadoPagoTouched: false,
              providerSubscriptionTouched: false,
              note: input.note ?? null,
            },
    };
  }

  private async applyLicenseStatusAction(input: {
    input: AdminActionContext & AdminLicenseStatusActionInput;
    action: "suspend" | "reactivate";
    expectedConfirmationText: string;
    targetStatus: LicenseStatus;
    auditAction: string;
    blockedCode: string;
    confirmationCode: string;
    confirmationMessage: string;
    successMessage: string;
  }) {
    const context = this.assertAdminActionContext(input.input);
    if (input.input.confirmationText !== input.expectedConfirmationText) {
      throw new AppError(
        input.confirmationMessage,
        422,
        input.confirmationCode,
        {
          expectedConfirmationText: input.expectedConfirmationText,
        },
      );
    }

    await this.assertCompanyExists(context.companyId);
    const result = await prisma.$transaction(async (tx) => {
      const license = await tx.license.findUnique({
        where: { companyId: context.companyId },
      });
      const dryRun = this.buildLicenseStatusActionDryRun({
        license,
        action: input.action,
        note: input.input.note,
      });
      const proposedChange = dryRun.proposedChange;
      if (!dryRun.allowed || license == null || proposedChange == null) {
        throw new AppError(
          "Acao administrativa de licenca bloqueada.",
          409,
          input.blockedCode,
          { blockers: dryRun.blockers },
        );
      }

      const before = this.serializeLicenseForEmergencyAudit(license);
      const updated = await tx.license.update({
        where: { companyId: context.companyId },
        data: { status: input.targetStatus },
      });
      const after = this.serializeLicenseForEmergencyAudit(updated);

      await tx.billingAdminAuditLog.create({
        data: {
          actorUserId: context.actorUserId,
          companyId: context.companyId,
          action: input.auditAction,
          reason: context.reason,
          before: toJsonInput(before),
          after: toJsonInput(after),
          metadata: toJsonInput(
            sanitizeForAdmin({
              source: "admin_web",
              note: input.input.note ?? null,
              confirmationTextExpected: input.expectedConfirmationText,
              mercadoPagoTouched: false,
              providerSubscriptionTouched: false,
            }),
          ),
          ipAddress: context.ipAddress ?? null,
          userAgent: context.userAgent ?? null,
        },
      });

      return { before, after, proposedChange };
    });

    return {
      success: true,
      message: input.successMessage,
      license: result.after,
      currentLicense: result.before,
      proposedChange: result.proposedChange,
    };
  }

  private buildEmergencyExtensionDryRun(input: {
    license: License | null;
    days: number;
    note?: string;
  }) {
    const { license, days } = input;
    const blockers: string[] = [];
    const risks = [
      "Nao altera o plano da empresa.",
      "Nao altera pendingPlan e nao libera recursos pendentes.",
      "Nao chama Mercado Pago nem altera providerSubscriptionId.",
      "A extensao apenas ajusta expiresAt e pode reativar status EXPIRED/SUSPENDED durante a janela emergencial.",
    ];

    if (license == null) {
      blockers.push("Empresa sem licenca cadastrada.");
    }
    if (
      !Number.isInteger(days) ||
      days < 1 ||
      days > EMERGENCY_EXTENSION_MAX_DAYS
    ) {
      blockers.push(`Informe dias entre 1 e ${EMERGENCY_EXTENSION_MAX_DAYS}.`);
    }

    const now = new Date();
    const expiresAtBefore = license?.expiresAt ?? null;
    const canExtendActiveExpiration =
      expiresAtBefore != null && expiresAtBefore.getTime() > now.getTime();
    const requiresStatusRecovery =
      license?.status === LicenseStatus.EXPIRED ||
      license?.status === LicenseStatus.SUSPENDED ||
      (expiresAtBefore != null && expiresAtBefore.getTime() <= now.getTime());

    if (
      license != null &&
      !canExtendActiveExpiration &&
      !requiresStatusRecovery
    ) {
      blockers.push(
        "Licenca ativa sem expiresAt nao precisa de extensao emergencial.",
      );
    }

    const baseDate =
      expiresAtBefore != null && expiresAtBefore.getTime() > now.getTime()
        ? expiresAtBefore
        : now;
    const expiresAtAfter = new Date(
      baseDate.getTime() + days * 24 * 60 * 60 * 1000,
    );
    const statusBefore = license?.status ?? null;
    const statusAfter =
      license == null
        ? null
        : requiresStatusRecovery
          ? LicenseStatus.ACTIVE
          : license.status;

    return {
      allowed: blockers.length === 0,
      expectedConfirmationText: EMERGENCY_EXTENSION_CONFIRMATION,
      summary:
        license == null
          ? "Nao foi possivel simular a extensao porque a licenca nao existe."
          : `Extender acesso operacional por ${days} dia(s), sem trocar plano e sem acionar Mercado Pago.`,
      risks,
      blockers,
      currentLicense:
        license == null
          ? null
          : this.serializeLicenseForEmergencyAudit(license),
      proposedChange:
        license == null
          ? null
          : {
              field: "expiresAt",
              days,
              statusBefore,
              statusAfter,
              expiresAtBefore: expiresAtBefore?.toISOString() ?? null,
              expiresAtAfter: expiresAtAfter.toISOString(),
              planBefore: license.plan,
              planAfter: license.plan,
              pendingPlanBefore: license.pendingPlan,
              pendingPlanAfter: license.pendingPlan,
              mercadoPagoTouched: false,
              providerSubscriptionTouched: false,
              note: input.note ?? null,
            },
      maxAllowedDays: EMERGENCY_EXTENSION_MAX_DAYS,
      allowedDaysRange: { min: 1, max: EMERGENCY_EXTENSION_MAX_DAYS },
    };
  }

  private async buildBillingReconcileDryRun(input: {
    companyId: string;
    note?: string;
  }) {
    const license = await prisma.license.findUnique({
      where: { companyId: input.companyId },
    });
    const pendingCheckoutSessions = await this.listReconcileCheckoutSessions(
      input.companyId,
    );
    const blockers: string[] = [];
    const providerConfigured =
      env.MERCADO_PAGO_ACCESS_TOKEN != null &&
      env.MERCADO_PAGO_ACCESS_TOKEN.trim().length > 0;
    const hasProviderSubscription = license?.providerSubscriptionId != null;
    const hasPendingCheckout = pendingCheckoutSessions.length > 0;
    const unsupportedProvider =
      license?.billingProvider != null &&
      license.billingProvider !== BILLING_PROVIDER;

    if (license == null) {
      blockers.push("Empresa sem licenca cadastrada.");
    }
    if (unsupportedProvider) {
      blockers.push("Provider de billing nao suportado para reconciliacao.");
    }
    if (!providerConfigured) {
      blockers.push("Mercado Pago nao configurado para billing.");
    }
    if (license != null && !hasProviderSubscription && !hasPendingCheckout) {
      blockers.push(
        "Nao ha assinatura provider nem checkout pendente para reconciliar.",
      );
    }

    const likelyActions = [
      "Consultar Mercado Pago pelo fluxo BillingService.refreshCompanyFromProvider.",
      ...(hasPendingCheckout
        ? [
            "Verificar checkout pendente e atualizar sessao/licenca apenas se o provider confirmar.",
          ]
        : []),
      ...(hasProviderSubscription
        ? ["Reconciliar faturas por pagamentos autorizados da assinatura."]
        : []),
      "Aplicar transicoes agendadas ja previstas pelo billing.",
    ];
    const risks = [
      "Nao forca plano manualmente; license.plan so muda pela regra existente de refresh quando o provider confirma.",
      "Nao edita providerSubscriptionId manualmente.",
      "pendingPlan nao libera recursos ate confirmacao segura.",
      "O fluxo existente pode cancelar assinatura provider antiga substituida quando um novo checkout autorizado e confirmado.",
    ];

    return {
      allowed: blockers.length === 0,
      expectedConfirmationText: BILLING_RECONCILE_CONFIRMATION,
      summary:
        license == null
          ? "Nao foi possivel simular a reconciliacao porque a licenca nao existe."
          : "Reconciliar billing consultando Mercado Pago pelo fluxo seguro existente, sem force-plan manual.",
      risks,
      blockers,
      currentBillingStatus:
        license == null
          ? null
          : this.serializeLicenseForEmergencyAudit(license),
      pendingCheckoutSessions: pendingCheckoutSessions.map((session) =>
        this.serializeCheckoutSessionForReconcile(session),
      ),
      likelyActions,
      providerCheckSummary: {
        consulted: false,
        providerConfigured,
        provider: BILLING_PROVIDER,
        maskedProviderSubscriptionId: maskProviderSubscriptionId(
          license?.providerSubscriptionId,
        ),
        pendingProviderReferences: pendingCheckoutSessions.map((session) =>
          maskProviderSubscriptionId(session.providerReference),
        ),
        note: "Dry-run nao executa refresh nem altera Mercado Pago; a consulta efetiva ocorre somente apos confirmacao.",
      },
      note: input.note ?? null,
    };
  }

  private buildCompanyWhere(
    query: AdminBillingCompaniesQueryInput,
  ): Prisma.CompanyWhereInput {
    const filters: Prisma.CompanyWhereInput[] = [];

    if (query.search != null) {
      filters.push({
        OR: [
          { name: { contains: query.search, mode: "insensitive" } },
          { legalName: { contains: query.search, mode: "insensitive" } },
          { slug: { contains: query.search, mode: "insensitive" } },
        ],
      });
    }

    if (query.plan != null) {
      filters.push({
        license: {
          is: {
            plan: {
              in: [query.plan, query.plan.toLowerCase()],
            },
          },
        },
      });
    }

    if (query.status != null) {
      const status = query.status.toUpperCase();
      const licenseStatus = this.tryLicenseStatus(status);
      filters.push({
        license: {
          is: {
            OR: [
              ...(licenseStatus == null ? [] : [{ status: licenseStatus }]),
              { billingSubscriptionStatus: { equals: status } },
            ],
          },
        },
      });
    }

    if (query.provider != null) {
      filters.push({
        license: {
          is: {
            billingProvider: { equals: query.provider, mode: "insensitive" },
          },
        },
      });
    }

    if (query.hasProviderSubscription != null) {
      filters.push({
        license:
          query.hasProviderSubscription === true
            ? { is: { providerSubscriptionId: { not: null } } }
            : { is: { providerSubscriptionId: null } },
      });
    }

    return filters.length === 0 ? {} : { AND: filters };
  }

  private resolveCompanyOrderBy(
    query: AdminBillingCompaniesQueryInput,
  ): Prisma.CompanyOrderByWithRelationInput {
    switch (query.sort) {
      case "companyName":
        return { name: query.sortDirection };
      case "plan":
        return { license: { plan: query.sortDirection } };
      case "status":
        return { license: { status: query.sortDirection } };
      case "currentPeriodEnd":
        return { license: { currentPeriodEnd: query.sortDirection } };
      case "updatedAt":
        return { updatedAt: query.sortDirection };
    }
  }

  private assertAdminActionContext(input: AdminActionContext) {
    if (input.actorUserId == null || input.actorUserId.trim().length === 0) {
      throw new AppError(
        "Usuario administrativo obrigatorio para esta acao.",
        401,
        "ADMIN_ACTOR_REQUIRED",
      );
    }
    if (input.companyId.trim().length === 0) {
      throw new AppError(
        "Empresa obrigatoria para esta acao.",
        400,
        "ADMIN_COMPANY_REQUIRED",
      );
    }
    if (input.reason.trim().length === 0) {
      throw new AppError(
        "Informe o motivo da acao administrativa.",
        422,
        "ADMIN_REASON_REQUIRED",
      );
    }
    return {
      ...input,
      actorUserId: input.actorUserId.trim(),
      companyId: input.companyId.trim(),
      reason: input.reason.trim(),
    };
  }

  private async createAuditLog(
    input: AdminActionContext & {
      action: string;
      before: unknown;
      after: unknown;
      metadata?: unknown;
    },
  ) {
    const context = this.assertAdminActionContext(input);
    await prisma.billingAdminAuditLog.create({
      data: {
        actorUserId: context.actorUserId,
        companyId: context.companyId,
        action: input.action,
        reason: context.reason,
        before: toJsonInput(input.before),
        after: toJsonInput(input.after),
        metadata: toJsonInput(sanitizeForAdmin(input.metadata ?? {})),
        ipAddress: context.ipAddress ?? null,
        userAgent: context.userAgent ?? null,
      },
    });
  }

  private resolveLicenseStatus(
    status: AdminBillingStatusInput | undefined,
    current: License | null,
  ) {
    if (status == null) {
      return current?.status ?? LicenseStatus.ACTIVE;
    }
    switch (status) {
      case "ACTIVE":
        return LicenseStatus.ACTIVE;
      case "EXPIRED":
      case "CANCELLED":
        return LicenseStatus.EXPIRED;
      case "PAST_DUE":
        return LicenseStatus.SUSPENDED;
    }
  }

  private tryLicenseStatus(value: string) {
    if (value === "TRIAL") {
      return LicenseStatus.TRIAL;
    }
    if (value === "ACTIVE") {
      return LicenseStatus.ACTIVE;
    }
    if (value === "SUSPENDED") {
      return LicenseStatus.SUSPENDED;
    }
    if (value === "EXPIRED") {
      return LicenseStatus.EXPIRED;
    }
    return null;
  }

  private async getLicenseSnapshot(companyId: string) {
    const license = await prisma.license.findUnique({ where: { companyId } });
    return license == null ? null : this.serializeLicense(license);
  }

  private async getSafeLicenseSnapshot(companyId: string) {
    const license = await prisma.license.findUnique({ where: { companyId } });
    return license == null
      ? null
      : this.serializeLicenseForEmergencyAudit(license);
  }

  private async getCompany(companyId: string) {
    const company = await prisma.company.findUnique({
      where: { id: companyId },
      include: { license: true },
    });
    if (company == null) {
      throw new AppError(
        "Empresa nao encontrada.",
        404,
        "ADMIN_COMPANY_NOT_FOUND",
      );
    }
    return company;
  }

  private async getCompanyIdentity(
    companyId: string,
  ): Promise<CompanyIdentity> {
    const company = await prisma.company.findUnique({
      where: { id: companyId },
      select: {
        id: true,
        name: true,
        legalName: true,
        slug: true,
        isActive: true,
      },
    });
    if (company == null) {
      throw new AppError(
        "Empresa nao encontrada.",
        404,
        "ADMIN_COMPANY_NOT_FOUND",
      );
    }
    return company;
  }

  private async assertCompanyExists(companyId: string) {
    await this.getCompanyIdentity(companyId);
  }

  private serializeLicense(license: License) {
    return {
      id: license.id,
      companyId: license.companyId,
      plan: license.plan,
      normalizedPlan: normalizePlan(license.plan),
      status: license.status,
      startsAt: license.startsAt.toISOString(),
      expiresAt: license.expiresAt?.toISOString() ?? null,
      maxDevices: license.maxDevices,
      syncEnabled: license.syncEnabled,
      billingProvider: license.billingProvider,
      maskedProviderSubscriptionId: maskProviderSubscriptionId(
        license.providerSubscriptionId,
      ),
      currentPeriodStart: license.currentPeriodStart?.toISOString() ?? null,
      currentPeriodEnd: license.currentPeriodEnd?.toISOString() ?? null,
      nextPaymentDate: license.nextPaymentDate?.toISOString() ?? null,
      cancelAtPeriodEnd: license.cancelAtPeriodEnd,
      cancelRequestedAt: license.cancelRequestedAt?.toISOString() ?? null,
      canceledAt: license.canceledAt?.toISOString() ?? null,
      pendingPlan: license.pendingPlan,
      pendingPlanRequestedAt:
        license.pendingPlanRequestedAt?.toISOString() ?? null,
      billingSubscriptionStatus: license.billingSubscriptionStatus,
      createdAt: license.createdAt.toISOString(),
      updatedAt: license.updatedAt.toISOString(),
    };
  }

  private async listReconcileCheckoutSessions(companyId: string) {
    return prisma.billingCheckoutSession.findMany({
      where: {
        companyId,
        provider: BILLING_PROVIDER,
        providerReference: { not: null },
        status: { in: ["PENDING", "COMPLETED"] },
      },
      orderBy: { updatedAt: "desc" },
      take: 10,
      select: {
        id: true,
        plan: true,
        billingCycle: true,
        status: true,
        provider: true,
        providerReference: true,
        createdAt: true,
        updatedAt: true,
      },
    });
  }

  private serializeCheckoutSessionForReconcile(
    session: Awaited<
      ReturnType<BillingAdminService["listReconcileCheckoutSessions"]>
    >[number],
  ) {
    return {
      id: session.id,
      plan: session.plan,
      billingCycle: session.billingCycle,
      status: session.status,
      provider: session.provider,
      maskedProviderReference: maskProviderSubscriptionId(
        session.providerReference,
      ),
      createdAt: session.createdAt.toISOString(),
      updatedAt: session.updatedAt.toISOString(),
    };
  }

  private countChangedCheckoutSessions(
    before: Awaited<
      ReturnType<BillingAdminService["listReconcileCheckoutSessions"]>
    >,
    after: Awaited<
      ReturnType<BillingAdminService["listReconcileCheckoutSessions"]>
    >,
  ) {
    const afterById = new Map(after.map((session) => [session.id, session]));
    return before.filter((session) => {
      const updated = afterById.get(session.id);
      return (
        updated != null &&
        (updated.status !== session.status ||
          updated.updatedAt.getTime() !== session.updatedAt.getTime())
      );
    }).length;
  }

  private sanitizeBillingStatus(status: unknown) {
    if (status == null || typeof status !== "object") {
      return sanitizeForAdmin(status);
    }
    const sanitized = sanitizeForAdmin(status) as Record<string, unknown>;
    delete sanitized.providerSubscriptionId;
    return sanitized;
  }

  private buildProviderStatusSummary(status: unknown) {
    const sanitized = this.sanitizeBillingStatus(status) as Record<
      string,
      unknown
    >;
    return {
      provider: sanitized.provider ?? null,
      billingSubscriptionStatus: sanitized.billingSubscriptionStatus ?? null,
      hasProviderSubscription: sanitized.hasProviderSubscription ?? null,
      maskedProviderSubscriptionId:
        sanitized.maskedProviderSubscriptionId ?? null,
    };
  }

  private readWarnings(status: unknown) {
    if (status == null || typeof status !== "object") {
      return [];
    }
    const warnings = (status as { warnings?: unknown }).warnings;
    if (!Array.isArray(warnings)) {
      return [];
    }
    return warnings.flatMap((warning) =>
      typeof warning === "string" ? [warning] : [],
    );
  }

  private serializeLicenseForEmergencyAudit(license: License) {
    return {
      id: license.id,
      companyId: license.companyId,
      plan: license.plan,
      normalizedPlan: normalizePlan(license.plan),
      status: license.status,
      startsAt: license.startsAt.toISOString(),
      expiresAt: license.expiresAt?.toISOString() ?? null,
      maxDevices: license.maxDevices,
      syncEnabled: license.syncEnabled,
      billingProvider: license.billingProvider,
      maskedProviderSubscriptionId: maskProviderSubscriptionId(
        license.providerSubscriptionId,
      ),
      currentPeriodStart: license.currentPeriodStart?.toISOString() ?? null,
      currentPeriodEnd: license.currentPeriodEnd?.toISOString() ?? null,
      nextPaymentDate: license.nextPaymentDate?.toISOString() ?? null,
      cancelAtPeriodEnd: license.cancelAtPeriodEnd,
      cancelRequestedAt: license.cancelRequestedAt?.toISOString() ?? null,
      canceledAt: license.canceledAt?.toISOString() ?? null,
      pendingPlan: license.pendingPlan,
      pendingPlanRequestedAt:
        license.pendingPlanRequestedAt?.toISOString() ?? null,
      billingSubscriptionStatus: license.billingSubscriptionStatus,
      createdAt: license.createdAt.toISOString(),
      updatedAt: license.updatedAt.toISOString(),
    };
  }

  private serializeCheckoutSession(
    session: Prisma.BillingCheckoutSessionGetPayload<{}>,
  ) {
    return {
      id: session.id,
      companyId: session.companyId,
      userId: session.userId,
      plan: session.plan,
      billingCycle: session.billingCycle,
      status: session.status,
      provider: session.provider,
      providerReference: maskProviderSubscriptionId(session.providerReference),
      checkoutUrl: maskUrl(session.checkoutUrl),
      sandboxCheckoutUrl: maskUrl(session.sandboxCheckoutUrl),
      expiresAt: session.expiresAt?.toISOString() ?? null,
      createdAt: session.createdAt.toISOString(),
      updatedAt: session.updatedAt.toISOString(),
    };
  }

  private serializeProviderEvent(
    event: Prisma.BillingProviderEventGetPayload<{}>,
  ) {
    return {
      id: event.id,
      companyId: event.companyId,
      provider: event.provider,
      eventType: event.eventType,
      providerEventId: maskProviderSubscriptionId(event.providerEventId),
      dedupeKey: event.dedupeKey,
      payload: sanitizeForAdmin(event.payload),
      status: event.status,
      processedAt: event.processedAt?.toISOString() ?? null,
      errorMessage: event.errorMessage,
      createdAt: event.createdAt.toISOString(),
      updatedAt: event.updatedAt.toISOString(),
    };
  }

  private serializeInvoice(invoice: Prisma.BillingInvoiceGetPayload<{}>) {
    return {
      id: invoice.id,
      companyId: invoice.companyId,
      provider: invoice.provider,
      providerInvoiceId: invoice.providerInvoiceId,
      providerSubscriptionId: maskProviderSubscriptionId(
        invoice.providerSubscriptionId,
      ),
      plan: invoice.plan,
      status: invoice.status,
      amountCents: invoice.amountCents,
      currency: invoice.currency,
      periodStart: invoice.periodStart?.toISOString() ?? null,
      periodEnd: invoice.periodEnd?.toISOString() ?? null,
      dueAt: invoice.dueAt?.toISOString() ?? null,
      paidAt: invoice.paidAt?.toISOString() ?? null,
      failedAt: invoice.failedAt?.toISOString() ?? null,
      invoiceUrl: maskUrl(invoice.invoiceUrl),
      payload: sanitizeForAdmin(invoice.payload),
      createdAt: invoice.createdAt.toISOString(),
      updatedAt: invoice.updatedAt.toISOString(),
    };
  }

  private serializeBillingAdminAuditLog(
    log: Prisma.BillingAdminAuditLogGetPayload<{
      include: { actorUser: { select: { id: true; name: true; email: true } } };
    }>,
  ) {
    return {
      id: log.id,
      action: log.action,
      reason: log.reason,
      actorUserId: log.actorUserId,
      actorName: log.actorUser.name,
      actorEmail: log.actorUser.email,
      companyId: log.companyId,
      before: this.sanitizeBillingAuditPayload(log.before),
      after: this.sanitizeBillingAuditPayload(log.after),
      metadata: this.sanitizeBillingAuditPayload(log.metadata),
      ipAddress: log.ipAddress,
      userAgent: sanitizeForAdmin(log.userAgent),
      createdAt: log.createdAt.toISOString(),
    };
  }

  private sanitizeBillingAuditPayload(value: unknown): unknown {
    const sanitized = sanitizeForAdmin(value);
    return maskBillingAuditProviderIdentifiers(sanitized);
  }
}

function toJsonInput(value: unknown) {
  if (value == null) {
    return Prisma.JsonNull;
  }
  return JSON.parse(JSON.stringify(value)) as Prisma.InputJsonValue;
}

function maskBillingAuditProviderIdentifiers(value: unknown): unknown {
  if (value == null) {
    return value;
  }
  if (Array.isArray(value)) {
    return value.map(maskBillingAuditProviderIdentifiers);
  }
  if (typeof value !== "object") {
    return value;
  }

  const output: Record<string, unknown> = {};
  for (const [key, rawValue] of Object.entries(
    value as Record<string, unknown>,
  )) {
    if (isProviderIdentifierKey(key)) {
      output[key] =
        typeof rawValue === "string"
          ? maskProviderSubscriptionId(rawValue)
          : "[redacted]";
      continue;
    }
    output[key] = maskBillingAuditProviderIdentifiers(rawValue);
  }
  return output;
}

function isProviderIdentifierKey(key: string) {
  const normalized = key
    .trim()
    .toLowerCase()
    .replace(/[\s_-]/g, "");
  return (
    normalized.includes("providersubscriptionid") ||
    normalized.includes("providerreference") ||
    normalized.includes("providereventid")
  );
}
