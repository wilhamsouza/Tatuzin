import type { Prisma } from '@prisma/client';

import { prisma } from '../../database/prisma';
import { buildPaginatedResponse } from '../../shared/http/api-response';
import { toPaginationParams } from '../../shared/http/pagination';
import type { AppContext } from '../app/app-context.types';
import { EmployeeActivityService } from '../employees/employee-activity.service';
import { EmployeeCommissionService } from '../employees/employee-commission.service';
import { EmployeeContextService } from '../employees/employee-context.service';
import { effectivePermissionsForEmployee } from '../employees/employee-permissions';
import { getPlanEntitlements } from '../plans/plan-catalog.service';
import { OwnerReportingService } from './owner-reporting.service';
import type {
  OwnerCommissionsQueryInput,
  OwnerCrmCustomersQueryInput,
  OwnerCrmSummaryQueryInput,
  OwnerEmployeeActivityQueryInput,
  OwnerEmployeesReportQueryInput,
  OwnerInvoicesQueryInput,
  OwnerProductsReportQueryInput,
  OwnerReceivablesQueryInput,
  OwnerSalesSummaryQueryInput,
  OwnerStockSummaryQueryInput,
} from './owner.schemas';

export class OwnerService {
  private readonly reportingService = new OwnerReportingService();
  private readonly employeeContextService = new EmployeeContextService();
  private readonly employeeCommissionService = new EmployeeCommissionService();
  private readonly employeeActivityService = new EmployeeActivityService();

  async getCompanySummary(context: AppContext) {
    const company = await prisma.company.findUniqueOrThrow({
      where: { id: context.company.id },
      include: { license: true },
    });
    const entitlements = getPlanEntitlements(company.license?.plan);

    return {
      companyId: company.id,
      name: company.name,
      legalName: company.legalName,
      documentNumber: company.documentNumber,
      setupCompleted: context.company.setupCompleted,
      createdAt: company.createdAt.toISOString(),
      owner: {
        id: context.user.id,
        name: context.user.name,
        email: context.user.email,
      },
      membership: {
        id: context.membership.id,
        role: context.membership.role,
      },
      receiptSettings: serializeReceiptSettings(company),
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

  async listEmployees(context: AppContext) {
    await this.employeeContextService.ensureOwnerProfilesForCompany(
      context.company.id,
    );
    const employees = await prisma.employeeProfile.findMany({
      where: { companyId: context.company.id },
      include: {
        user: {
          select: {
            id: true,
            isActive: true,
            mustChangePassword: true,
            temporaryPasswordExpiresAt: true,
          },
        },
      },
      orderBy: [{ role: 'asc' }, { name: 'asc' }, { createdAt: 'asc' }],
    });
    const userIds = employees
      .map((employee) => employee.userId)
      .filter((value): value is string => value != null);
    const lastSessions =
      userIds.length === 0
        ? []
        : await prisma.deviceSession.groupBy({
            by: ['userId'],
            where: {
              companyId: context.company.id,
              userId: { in: userIds },
            },
            _max: { lastSeenAt: true },
          });
    const lastSessionByUserId = new Map(
      lastSessions.map((row) => [row.userId, row._max.lastSeenAt]),
    );
    const items = employees.map((employee) => {
      const permissions = effectivePermissionsForEmployee(employee);
      const accessStatus = resolveEmployeeAccessStatus(employee);
      return {
        id: employee.id,
        name: employee.name,
        email: employee.email,
        role: employee.role,
        status: employee.status,
        accessStatus,
        permissions: permissions.slice(0, 8),
        permissionsCount: permissions.length,
        commissionEnabled: employee.commissionEnabled,
        commissionType: employee.commissionEnabled
          ? employee.commissionType
          : 'NONE',
        commissionBase: employee.commissionBase,
        commissionRateBps: employee.commissionRateBps,
        commissionFixedCents: employee.commissionFixedCents,
        temporaryPasswordPending: accessStatus === 'TEMPORARY_PASSWORD_PENDING',
        temporaryPasswordExpiresAt:
          employee.user?.temporaryPasswordExpiresAt?.toISOString() ?? null,
        lastSeenAt:
          employee.userId == null
            ? null
            : lastSessionByUserId.get(employee.userId)?.toISOString() ?? null,
      };
    });

    return {
      available: true,
      summary: {
        total: items.length,
        active: items.filter((employee) => employee.status === 'ACTIVE').length,
        disabled: items.filter((employee) => employee.status === 'DISABLED')
          .length,
        invited: items.filter((employee) => employee.status === 'INVITED')
          .length,
        withActiveAccess: items.filter(
          (employee) => employee.accessStatus === 'ACTIVE',
        ).length,
        temporaryPasswordPending: items.filter(
          (employee) => employee.temporaryPasswordPending,
        ).length,
        commissionEnabled: items.filter((employee) => employee.commissionEnabled)
          .length,
        maxEmployees: context.limits.maxEmployees,
      },
      items,
      count: items.length,
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
      employees,
      deviceCounts,
      syncState,
      pendingSyncEvents,
      openSyncConflicts,
    ] = await Promise.all([
      this.getCompanySummary(context),
      this.getBillingStatus(context),
      this.listEmployees(context),
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
        active: employees.summary.active,
        invited: employees.summary.invited,
        disabled: employees.summary.disabled,
        withActiveAccess: employees.summary.withActiveAccess,
        temporaryPasswordPending: employees.summary.temporaryPasswordPending,
        commissionEnabled: employees.summary.commissionEnabled,
        maxEmployees: context.limits.maxEmployees,
        available: true,
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

  async getCommissions(
    context: AppContext,
    query: OwnerCommissionsQueryInput,
  ) {
    return this.employeeCommissionService.summary(
      context,
      ownerPeriodToEmployeePeriod(query),
    );
  }

  async getEmployeeActivity(
    context: AppContext,
    query: OwnerEmployeeActivityQueryInput,
  ) {
    return this.employeeActivityService.summary(
      context,
      ownerPeriodToEmployeePeriod(query),
    );
  }

  async getReceiptSettings(context: AppContext) {
    const company = await prisma.company.findUniqueOrThrow({
      where: { id: context.company.id },
    });
    return serializeReceiptSettings(company);
  }

  async getReportsCatalog(context: AppContext) {
    return this.reportingService.getReportsCatalog(context);
  }
}

function ownerPeriodToEmployeePeriod(query: {
  startDate?: string;
  endDate?: string;
}) {
  const today = new Date();
  const to = dateOnly(query.endDate == null ? today : new Date(query.endDate));
  const defaultFrom = new Date(`${to}T00:00:00.000Z`);
  defaultFrom.setUTCDate(defaultFrom.getUTCDate() - 29);
  const from = dateOnly(
    query.startDate == null ? defaultFrom : new Date(query.startDate),
  );
  return { from, to };
}

function resolveEmployeeAccessStatus(employee: {
  status: string;
  userId: string | null;
  membershipId: string | null;
  user?: { isActive: boolean; mustChangePassword: boolean } | null;
}) {
  if (employee.status === 'DISABLED') {
    return 'DISABLED';
  }
  if (employee.userId == null || employee.membershipId == null) {
    return 'NO_ACCESS';
  }
  if (employee.user == null || !employee.user.isActive) {
    return 'DISABLED';
  }
  if (employee.user.mustChangePassword) {
    return 'TEMPORARY_PASSWORD_PENDING';
  }
  return 'ACTIVE';
}

function serializeReceiptSettings(company: Prisma.CompanyGetPayload<{}>) {
  return {
    displayName: company.receiptDisplayName,
    document: company.receiptDocument,
    phone: company.receiptPhone,
    address: company.receiptAddress,
    footerMessage: company.receiptFooterMessage,
    showDocument: company.showDocumentOnReceipt,
    showPhone: company.showPhoneOnReceipt,
    showAddress: company.showAddressOnReceipt,
    showFooterMessage: company.showFooterMessageOnReceipt,
  };
}

function dateOnly(value: Date) {
  return value.toISOString().slice(0, 10);
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
