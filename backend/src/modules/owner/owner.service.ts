import type { Prisma } from '@prisma/client';

import { prisma } from '../../database/prisma';
import { buildPaginatedResponse } from '../../shared/http/api-response';
import { toPaginationParams } from '../../shared/http/pagination';
import type { AppContext } from '../app/app-context.types';
import { getPlanEntitlements } from '../plans/plan-catalog.service';
import { OwnerReportingService } from './owner-reporting.service';
import type {
  OwnerCrmCustomersQueryInput,
  OwnerCrmSummaryQueryInput,
  OwnerEmployeesReportQueryInput,
  OwnerInvoicesQueryInput,
  OwnerProductsReportQueryInput,
  OwnerReceivablesQueryInput,
  OwnerSalesSummaryQueryInput,
  OwnerStockSummaryQueryInput,
} from './owner.schemas';

export class OwnerService {
  private readonly reportingService = new OwnerReportingService();

  async getCompanySummary(context: AppContext) {
    const company = await prisma.company.findUniqueOrThrow({
      where: { id: context.company.id },
      include: { license: true },
    });
    const entitlements = getPlanEntitlements(company.license?.plan);

    return {
      companyId: company.id,
      name: company.name,
      setupCompleted: context.company.setupCompleted,
      createdAt: company.createdAt.toISOString(),
      membership: {
        id: context.membership.id,
        role: context.membership.role,
      },
      license: serializeLicenseSummary(company.license),
      limits: entitlements.limits,
      features: entitlements.features,
    };
  }

  async getBillingStatus(context: AppContext) {
    const license = await prisma.license.findUnique({
      where: { companyId: context.company.id },
    });
    const entitlements = getPlanEntitlements(license?.plan);
    const providerSubscriptionId = license?.providerSubscriptionId ?? null;

    return {
      companyId: context.company.id,
      plan: entitlements.plan,
      status: license?.status?.toString() ?? 'ACTIVE',
      currentPeriodStart: license?.currentPeriodStart?.toISOString() ?? null,
      currentPeriodEnd: license?.currentPeriodEnd?.toISOString() ?? null,
      expiresAt: license?.expiresAt?.toISOString() ?? null,
      provider: license?.billingProvider === 'mercadopago' ? 'mercadopago' : null,
      hasProviderSubscription: providerSubscriptionId != null,
      maskedProviderSubscriptionId: maskIdentifier(providerSubscriptionId),
      canManageBilling: context.membership.role === 'OWNER',
      nextPaymentDate: license?.nextPaymentDate?.toISOString() ?? null,
      cancelAtPeriodEnd: license?.cancelAtPeriodEnd ?? false,
      cancelRequestedAt: license?.cancelRequestedAt?.toISOString() ?? null,
      canceledAt: license?.canceledAt?.toISOString() ?? null,
      pendingPlan: license?.pendingPlan ?? null,
      pendingPlanRequestedAt:
        license?.pendingPlanRequestedAt?.toISOString() ?? null,
      billingSubscriptionStatus: license?.billingSubscriptionStatus ?? null,
      features: entitlements.features,
      limits: entitlements.limits,
    };
  }

  async listBillingInvoices(
    context: AppContext,
    query: OwnerInvoicesQueryInput,
  ) {
    const { skip, take } = toPaginationParams(query);
    const where: Prisma.BillingInvoiceWhereInput = {
      companyId: context.company.id,
      ...(query.status == null ? {} : { status: query.status }),
    };
    const [total, invoices] = await prisma.$transaction([
      prisma.billingInvoice.count({ where }),
      prisma.billingInvoice.findMany({
        where,
        skip,
        take,
        orderBy: { createdAt: 'desc' },
      }),
    ]);

    return buildPaginatedResponse({
      items: invoices.map(serializeInvoice),
      page: query.page,
      pageSize: query.pageSize,
      total,
    });
  }

  getEmployeesPlaceholder() {
    return {
      items: [],
      count: 0,
      available: false,
      reason: 'EMPLOYEES_NOT_IMPLEMENTED',
    };
  }

  async listDevices(context: AppContext) {
    const devices = await prisma.companyDevice.findMany({
      where: { companyId: context.company.id },
      orderBy: [{ lastSeenAt: 'desc' }, { createdAt: 'desc' }],
    });

    return {
      items: devices.map((device) => ({
        id: device.id,
        maskedClientInstanceId: maskIdentifier(device.clientInstanceId),
        deviceLabel: device.deviceLabel,
        platform: device.platform,
        appVersion: device.appVersion,
        status: device.status,
        createdAt: device.createdAt.toISOString(),
        updatedAt: device.updatedAt.toISOString(),
        lastSeenAt: device.lastSeenAt?.toISOString() ?? null,
      })),
      count: devices.length,
      limits: {
        maxDevices: context.limits.maxDevices,
      },
    };
  }

  async getDashboard(context: AppContext) {
    const [
      company,
      billing,
      deviceCounts,
      syncState,
      pendingSyncEvents,
      openSyncConflicts,
    ] = await Promise.all([
      this.getCompanySummary(context),
      this.getBillingStatus(context),
      prisma.companyDevice.groupBy({
        by: ['status'],
        where: { companyId: context.company.id },
        _count: { _all: true },
      }),
      prisma.companySyncState.findUnique({
        where: { companyId: context.company.id },
      }),
      prisma.syncEvent.count({
        where: { companyId: context.company.id, status: 'PENDING' },
      }),
      prisma.syncConflict.count({
        where: { companyId: context.company.id, status: 'OPEN' },
      }),
    ]);

    return {
      company: {
        companyId: company.companyId,
        name: company.name,
        setupCompleted: company.setupCompleted,
      },
      billing: {
        plan: billing.plan,
        status: billing.status,
        nextPaymentDate: billing.nextPaymentDate,
        cancelAtPeriodEnd: billing.cancelAtPeriodEnd,
        pendingPlan: billing.pendingPlan,
      },
      employees: {
        active: 0,
        invited: 0,
        disabled: 0,
        maxEmployees: context.limits.maxEmployees,
        available: false,
        reason: 'EMPLOYEES_NOT_IMPLEMENTED',
      },
      devices: {
        ...deviceCounts.reduce(
          (accumulator, item) => ({
            ...accumulator,
            [item.status.toLowerCase()]: item._count._all,
          }),
          { active: 0, blocked: 0, pending: 0, revoked: 0 },
        ),
        maxDevices: context.limits.maxDevices,
      },
      sync: {
        lastSyncAt: syncState?.updatedAt.toISOString() ?? null,
        pendingEvents: pendingSyncEvents,
        openConflicts: openSyncConflicts,
      },
      reports: null,
    };
  }

  async getBusinessDashboard(context: AppContext) {
    return this.reportingService.getBusinessDashboard(context);
  }

  async getSalesSummary(
    context: AppContext,
    query: OwnerSalesSummaryQueryInput,
  ) {
    return this.reportingService.getSalesSummary(context, query);
  }

  async getProductsReport(
    context: AppContext,
    query: OwnerProductsReportQueryInput,
  ) {
    return this.reportingService.getProductsReport(context, query);
  }

  async getStockSummary(
    context: AppContext,
    query: OwnerStockSummaryQueryInput,
  ) {
    return this.reportingService.getStockSummary(context, query);
  }

  async getCrmSummary(
    context: AppContext,
    query: OwnerCrmSummaryQueryInput,
  ) {
    return this.reportingService.getCrmSummary(context, query);
  }

  async listCrmCustomers(
    context: AppContext,
    query: OwnerCrmCustomersQueryInput,
  ) {
    return this.reportingService.listCrmCustomers(context, query);
  }

  async getCrmCustomerDetail(context: AppContext, customerId: string) {
    return this.reportingService.getCrmCustomerDetail(context, customerId);
  }

  async listReceivables(
    context: AppContext,
    query: OwnerReceivablesQueryInput,
  ) {
    return this.reportingService.listReceivables(context, query);
  }

  async getEmployeeReports(
    context: AppContext,
    query: OwnerEmployeesReportQueryInput,
  ) {
    return this.reportingService.getEmployeeReports(context, query);
  }

  async getReportsCatalog(context: AppContext) {
    return this.reportingService.getReportsCatalog(context);
  }
}

function serializeLicenseSummary(
  license:
    | Prisma.LicenseGetPayload<{}>
    | null,
) {
  const entitlements = getPlanEntitlements(license?.plan);
  return {
    plan: entitlements.plan,
    rawPlan: license?.plan ?? null,
    status: license?.status?.toString() ?? null,
    currentPeriodEnd: license?.currentPeriodEnd?.toISOString() ?? null,
    nextPaymentDate: license?.nextPaymentDate?.toISOString() ?? null,
    cancelAtPeriodEnd: license?.cancelAtPeriodEnd ?? false,
    pendingPlan: license?.pendingPlan ?? null,
    billingSubscriptionStatus: license?.billingSubscriptionStatus ?? null,
  };
}

function serializeInvoice(invoice: Prisma.BillingInvoiceGetPayload<{}>) {
  return {
    id: invoice.id,
    provider: invoice.provider,
    status: invoice.status,
    amountCents: invoice.amountCents,
    currency: invoice.currency,
    periodStart: invoice.periodStart?.toISOString() ?? null,
    periodEnd: invoice.periodEnd?.toISOString() ?? null,
    dueAt: invoice.dueAt?.toISOString() ?? null,
    paidAt: invoice.paidAt?.toISOString() ?? null,
    failedAt: invoice.failedAt?.toISOString() ?? null,
    invoiceUrl: safeInvoiceUrl(invoice.invoiceUrl),
    createdAt: invoice.createdAt.toISOString(),
  };
}

function safeInvoiceUrl(value: string | null) {
  if (value == null || value.trim().length === 0) {
    return null;
  }
  const trimmed = value.trim();
  if (/token|access_token|authorization|signature|secret|credential/i.test(trimmed)) {
    return null;
  }
  try {
    const parsed = new URL(trimmed);
    if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') {
      return null;
    }
    if (parsed.search.length > 0 || parsed.hash.length > 0) {
      return null;
    }
    return parsed.toString();
  } catch {
    return null;
  }
}

function maskIdentifier(value: string | null | undefined) {
  if (value == null || value.trim().length === 0) {
    return null;
  }
  const trimmed = value.trim();
  if (trimmed.length <= 8) {
    return '****';
  }
  return `${trimmed.slice(0, 4)}...${trimmed.slice(-4)}`;
}
