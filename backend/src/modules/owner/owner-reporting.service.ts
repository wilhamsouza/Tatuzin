import type { Prisma } from '@prisma/client';

import { prisma } from '../../database/prisma';
import { buildPaginatedResponse } from '../../shared/http/api-response';
import { AppError } from '../../shared/http/app-error';
import { toPaginationParams } from '../../shared/http/pagination';
import type { AppContext } from '../app/app-context.types';
import type {
  OwnerCrmCustomersQueryInput,
  OwnerCrmSummaryQueryInput,
  OwnerCashSessionsQueryInput,
  OwnerEmployeesReportQueryInput,
  OwnerSaleCancelInput,
  OwnerSaleReturnInput,
  OwnerProductsReportQueryInput,
  OwnerReceivablesQueryInput,
  OwnerSalesSummaryQueryInput,
  OwnerStockSummaryQueryInput,
} from './owner.schemas';

const DEFAULT_DAYS = 30;
const MAX_DAYS = 90;
const INACTIVE_CUSTOMER_DAYS = 90;
const LOW_STOCK_THRESHOLD_MIL = 1000;
const OWNER_REPORT_TIMEZONE = 'UTC';
const CATEGORY_PRODUCT_SCAN_LIMIT = 250;

type OwnerDateRange = {
  start: Date;
  endExclusive: Date;
  startDate: string;
  endDate: string;
  timezone: string;
};

type ReceivableCustomerItem = {
  id: string;
  customerId: string | null;
  customerName: string;
  openAmountCents: number;
  overdueAmountCents: number;
  paidAmountCents: number;
  totalAmountCents: number;
  salesCount: number;
  dueDate: string | null;
  status: 'open' | 'paid';
};

type CustomerCommercialSummary = {
  customerId: string;
  totalPurchasedCents: number;
  purchasesCount: number;
  averageTicketCents: number;
  lastPurchaseAt: Date | null;
  openReceivableAmountCents: number;
};

type CustomerWithCommercialSummary = {
  id: string;
  name: string;
  phone: string | null;
  createdAt: Date;
  crmTagAssignments: Array<{
    tag: {
      id: string;
      label: string;
      color: string | null;
    };
  }>;
  summary: CustomerCommercialSummary;
};

type StockReportItem = {
  id: string;
  productId: string;
  productVariantId: string | null;
  name: string;
  variantName: string | null;
  sku: string | null;
  currentStockMil: number;
  costPriceCents: number;
  salePriceCents: number;
  estimatedCostCents: number;
};

export class OwnerReportingService {
  async getBusinessDashboard(context: AppContext) {
    const today = startOfUtcDay(new Date());
    const tomorrow = addDays(today, 1);
    const monthStart = startOfUtcMonth(today);
    const period = {
      startDate: formatDateOnly(monthStart),
      endDate: formatDateOnly(addDays(tomorrow, -1)),
      timezone: OWNER_REPORT_TIMEZONE,
    };

    const [
      todaySales,
      monthSales,
      receivables,
      customers,
      products,
      employees,
    ] = await Promise.all([
      this.aggregateSales(context.company.id, today, tomorrow),
      this.aggregateSales(context.company.id, monthStart, tomorrow),
      this.buildReceivablesSummary(context.company.id),
      this.getCrmSummary(context, { limit: 5 }),
      this.getStockSummary(context, { page: 1, pageSize: 10, limit: 5 }),
      this.getEmployeeReports(context, {
        startDate: formatDateOnly(monthStart),
        endDate: formatDateOnly(addDays(tomorrow, -1)),
        limit: 5,
      }),
    ]);

    const alerts = [
      ...(products.outOfStockCount > 0
        ? [
            {
              key: 'OUT_OF_STOCK_PRODUCTS',
              severity: 'warning',
              title: 'Produtos sem estoque',
              message: 'Existem produtos cadastrados sem saldo em estoque.',
              count: products.outOfStockCount,
            },
          ]
        : []),
      ...(receivables.openAmountCents > 0
        ? [
            {
              key: 'OPEN_RECEIVABLES',
              severity: 'info',
              title: 'Contas a receber',
              message: 'Ha valores em aberto no fiado para acompanhar.',
              count: receivables.openCount,
            },
          ]
        : []),
    ];

    return {
      period,
      sales: {
        todayAmountCents: todaySales.amountCents,
        monthAmountCents: monthSales.amountCents,
        todayCount: todaySales.count,
        monthCount: monthSales.count,
        averageTicketCents: averageCents(monthSales.amountCents, monthSales.count),
      },
      receivables: {
        openAmountCents: receivables.openAmountCents,
        overdueAmountCents: receivables.overdueAmountCents,
        openCount: receivables.openCount,
        overdueCount: receivables.overdueCount,
      },
      customers: {
        total: customers.totalCustomers,
        active: customers.activeCustomers,
        inactive: customers.inactiveCustomers,
        newThisMonth: customers.newCustomersThisMonth,
        topCustomers: customers.topCustomers,
      },
      products: {
        total: products.totalProducts,
        lowStock: products.lowStockCount,
        outOfStock: products.outOfStockCount,
        topSelling: await this.getTopSellingProducts(
          context.company.id,
          { start: monthStart, endExclusive: tomorrow },
          5,
        ),
      },
      employees: {
        available: employees.available,
        topPerformers: employees.available ? employees.topEmployees : [],
        reason: employees.available ? null : employees.reason,
      },
      alerts,
    };
  }

  async getSalesSummary(
    context: AppContext,
    query: OwnerSalesSummaryQueryInput,
  ) {
    const period = this.resolveDateRange(query);
    const where: Prisma.SaleWhereInput = {
      companyId: context.company.id,
      status: 'active',
      soldAt: {
        gte: period.start,
        lt: period.endExclusive,
      },
    };
    const { skip, take } = toPaginationParams({
      page: query.page,
      pageSize: query.pageSize,
    });

    const [aggregate, paymentMethods, seriesSales, recentTotal, recentSales] =
      await prisma.$transaction([
        prisma.sale.aggregate({
          where,
          _count: { id: true },
          _sum: { totalAmountCents: true },
        }),
        prisma.sale.groupBy({
          by: ['paymentMethod'],
          where,
          _count: { id: true },
          _sum: { totalAmountCents: true },
          orderBy: { _sum: { totalAmountCents: 'desc' } },
        }),
        prisma.sale.findMany({
          where,
          select: {
            soldAt: true,
            totalAmountCents: true,
          },
          orderBy: { soldAt: 'asc' },
        }),
        prisma.sale.count({
          where: {
            companyId: context.company.id,
            soldAt: {
              gte: period.start,
              lt: period.endExclusive,
            },
          },
        }),
        prisma.sale.findMany({
          where: {
            companyId: context.company.id,
            soldAt: {
              gte: period.start,
              lt: period.endExclusive,
            },
          },
          select: {
            receiptNumber: true,
            paymentMethod: true,
            status: true,
            totalAmountCents: true,
            soldAt: true,
            canceledAt: true,
            customer: {
              select: {
                name: true,
              },
            },
          },
          skip,
          take,
          orderBy: [{ soldAt: 'desc' }, { updatedAt: 'desc' }],
        }),
      ]);

    const totalAmountCents = aggregate._sum.totalAmountCents ?? 0;
    const totalCount = aggregate._count.id;

    return {
      period: this.serializePeriod(period),
      totalAmountCents,
      totalCount,
      averageTicketCents: averageCents(totalAmountCents, totalCount),
      series: this.groupSalesSeries(seriesSales, query.groupBy),
      byPaymentMethod: paymentMethods.map((item) => ({
        key: normalizePaymentKey(item.paymentMethod),
        label: friendlyPaymentMethod(item.paymentMethod),
        totalAmountCents: item._sum?.totalAmountCents ?? 0,
        count: readGroupedCount(item._count),
      })),
      recentSales: buildPaginatedResponse({
        items: recentSales.map((sale) => ({
          title: sale.status === 'canceled' ? 'Venda cancelada' : 'Venda recebida',
          receiptNumber: safeReceiptNumber(sale.receiptNumber),
          customerName: safeName(sale.customer?.name) ?? null,
          paymentMethod: friendlyPaymentMethod(sale.paymentMethod),
          totalAmountCents: sale.totalAmountCents,
          status: sale.status === 'canceled' ? 'canceled' : 'active',
          soldAt: sale.soldAt.toISOString(),
          canceledAt: sale.canceledAt?.toISOString() ?? null,
        })),
        page: query.page,
        pageSize: query.pageSize,
        total: recentTotal,
      }),
    };
  }

  async getProductsReport(
    context: AppContext,
    query: OwnerProductsReportQueryInput,
  ) {
    const period = this.resolveDateRange(query);
    const topSellingProducts = await this.getTopSellingProducts(
      context.company.id,
      period,
      query.limit,
    );
    const stockSummary = await this.getStockSummary(context, {
      page: 1,
      pageSize: 10,
      limit: 10,
    });
    const lowSellingProducts = await this.getLowSellingProducts(
      context.company.id,
      topSellingProducts.map((item) => item.productId).filter(isString),
      query.limit,
    );
    const byCategory = await this.getProductSalesByCategory(
      context.company.id,
      period,
      query.limit,
    );

    return {
      period: this.serializePeriod(period),
      topSellingProducts,
      lowSellingProducts,
      byCategory,
      stockSummary: {
        totalProducts: stockSummary.totalProducts,
        lowStockCount: stockSummary.lowStockCount,
        outOfStockCount: stockSummary.outOfStockCount,
        totalEstimatedCostCents: stockSummary.totalEstimatedCostCents,
      },
    };
  }

  async getStockSummary(
    context: AppContext,
    query: OwnerStockSummaryQueryInput,
  ) {
    const items = await this.loadStockItems(context.company.id);
    const outOfStockItems = items
      .filter((item) => item.currentStockMil <= 0)
      .sort(compareStockItems)
      .slice(0, query.limit);
    const lowStockItems = items
      .filter(
        (item) =>
          item.currentStockMil > 0 &&
          item.currentStockMil <= LOW_STOCK_THRESHOLD_MIL,
      )
      .sort(compareStockItems)
      .slice(0, query.limit);

    return {
      totalProducts: items.length,
      lowStockCount: items.filter(
        (item) =>
          item.currentStockMil > 0 &&
          item.currentStockMil <= LOW_STOCK_THRESHOLD_MIL,
      ).length,
      outOfStockCount: items.filter((item) => item.currentStockMil <= 0).length,
      totalEstimatedCostCents: items.reduce(
        (total, item) => total + item.estimatedCostCents,
        0,
      ),
      lowStockThresholdMil: LOW_STOCK_THRESHOLD_MIL,
      itemsLowStock: lowStockItems,
      itemsOutOfStock: outOfStockItems,
    };
  }

  async getCrmSummary(context: AppContext, query: OwnerCrmSummaryQueryInput) {
    const customers = await this.loadCustomerCommercialSummaries(
      context.company.id,
    );
    const monthStart = startOfUtcMonth(new Date());
    const inactiveCutoff = addDays(startOfUtcDay(new Date()), -INACTIVE_CUSTOMER_DAYS);
    const activeCustomers = customers.filter((customer) =>
      isCustomerActive(customer.summary, inactiveCutoff),
    );
    const customersWithReceivables = customers.filter(
      (customer) => customer.summary.openReceivableAmountCents > 0,
    );
    const topCustomers = [...customers]
      .sort(
        (left, right) =>
          right.summary.totalPurchasedCents - left.summary.totalPurchasedCents,
      )
      .slice(0, query.limit)
      .map((customer) => this.toOwnerCustomerListItem(customer, inactiveCutoff));

    return {
      inactiveAfterDays: INACTIVE_CUSTOMER_DAYS,
      totalCustomers: customers.length,
      activeCustomers: activeCustomers.length,
      inactiveCustomers: customers.length - activeCustomers.length,
      newCustomersThisMonth: customers.filter(
        (customer) => customer.createdAt >= monthStart,
      ).length,
      customersWithReceivables: customersWithReceivables.length,
      topCustomers,
      customersAtRisk: customers
        .filter((customer) => !isCustomerActive(customer.summary, inactiveCutoff))
        .slice(0, query.limit)
        .map((customer) => this.toOwnerCustomerListItem(customer, inactiveCutoff)),
    };
  }

  async listCrmCustomers(
    context: AppContext,
    query: OwnerCrmCustomersQueryInput,
  ) {
    const inactiveCutoff = addDays(startOfUtcDay(new Date()), -INACTIVE_CUSTOMER_DAYS);
    const search = query.search.trim().toLocaleLowerCase('pt-BR');
    const customers = (await this.loadCustomerCommercialSummaries(
      context.company.id,
      search,
    )).filter((customer) => {
      const active = isCustomerActive(customer.summary, inactiveCutoff);
      if (query.status === 'active') {
        return active;
      }
      if (query.status === 'inactive') {
        return !active;
      }
      if (query.status === 'with_receivables') {
        return customer.summary.openReceivableAmountCents > 0;
      }
      return true;
    });
    customers.sort(
      (left, right) =>
        right.summary.totalPurchasedCents - left.summary.totalPurchasedCents ||
        left.name.localeCompare(right.name, 'pt-BR'),
    );
    const page = query.page ?? 1;
    const pageSize = query.pageSize ?? 20;
    const { skip, take } = toPaginationParams({ page, pageSize });
    const items = customers
      .slice(skip, skip + take)
      .map((customer) => this.toOwnerCustomerListItem(customer, inactiveCutoff));

    return buildPaginatedResponse({
      items,
      page: query.page,
      pageSize: query.pageSize,
      total: customers.length,
    });
  }

  async getCrmCustomerDetail(context: AppContext, customerId: string) {
    const inactiveCutoff = addDays(startOfUtcDay(new Date()), -INACTIVE_CUSTOMER_DAYS);
    const customer = await this.loadSingleCustomerCommercialSummary(
      context.company.id,
      customerId,
    );
    if (customer == null) {
      throw new AppError('Cliente nao encontrado.', 404, 'OWNER_CUSTOMER_NOT_FOUND');
    }

    const [recentSales, saleItems, receivables] = await Promise.all([
      prisma.sale.findMany({
        where: {
          companyId: context.company.id,
          customerId,
        },
        select: {
          receiptNumber: true,
          paymentMethod: true,
          paymentType: true,
          status: true,
          totalAmountCents: true,
          soldAt: true,
          canceledAt: true,
        },
        orderBy: [{ soldAt: 'desc' }, { updatedAt: 'desc' }],
        take: 10,
      }),
      prisma.saleItem.findMany({
        where: {
          sale: {
            companyId: context.company.id,
            customerId,
            status: 'active',
          },
        },
        select: {
          productId: true,
          productNameSnapshot: true,
          quantityMil: true,
          totalPriceCents: true,
        },
      }),
      this.buildReceivableItems(context.company.id, customerId),
    ]);

    return {
      customer: this.toOwnerCustomerListItem(customer, inactiveCutoff),
      topProducts: aggregateSaleItemsByProduct(saleItems).slice(0, 5),
      recentPurchases: recentSales.map((sale) => ({
        title: sale.status === 'canceled' ? 'Venda cancelada' : 'Venda recebida',
        receiptNumber: safeReceiptNumber(sale.receiptNumber),
        paymentMethod: friendlyPaymentMethod(sale.paymentMethod),
        paymentType: sale.paymentType === 'fiado' ? 'Fiado' : 'A vista',
        totalAmountCents: sale.totalAmountCents,
        status: sale.status === 'canceled' ? 'canceled' : 'active',
        soldAt: sale.soldAt.toISOString(),
        canceledAt: sale.canceledAt?.toISOString() ?? null,
      })),
      receivables: summarizeReceivableItems(receivables),
      timeline: [
        ...recentSales.map((sale) => ({
          type: sale.status === 'canceled' ? 'sale_canceled' : 'sale',
          title: sale.status === 'canceled' ? 'Venda cancelada' : 'Venda recebida',
          occurredAt: (sale.canceledAt ?? sale.soldAt).toISOString(),
          amountCents: sale.totalAmountCents,
        })),
      ].slice(0, 10),
    };
  }

  async listReceivables(
    context: AppContext,
    query: OwnerReceivablesQueryInput,
  ) {
    const items = await this.buildReceivableItems(context.company.id);
    const receivedThisMonthCents = await this.sumFiadoPaymentsSince(
      context.company.id,
      startOfUtcMonth(new Date()),
    );
    const filtered = items.filter((item) => {
      if (query.status === 'all') {
        return true;
      }
      if (query.status === 'overdue') {
        return item.overdueAmountCents > 0;
      }
      return item.status === query.status;
    });
    filtered.sort(
      (left, right) =>
        right.openAmountCents - left.openAmountCents ||
        left.customerName.localeCompare(right.customerName, 'pt-BR'),
    );
    const page = query.page ?? 1;
    const pageSize = query.pageSize ?? 20;
    const { skip, take } = toPaginationParams({ page, pageSize });

    return {
      summary: {
        ...summarizeReceivableItems(items),
        receivedThisMonthCents,
      },
      items: buildPaginatedResponse({
        items: filtered.slice(skip, skip + take),
        page,
        pageSize,
        total: filtered.length,
      }),
    };
  }

  async getEmployeeReports(
    context: AppContext,
    query: OwnerEmployeesReportQueryInput,
  ) {
    const period = this.resolveDateRange(query);
    const sessionRows = await prisma.sale.groupBy({
      by: ['cashSessionId'],
      where: {
        companyId: context.company.id,
        status: 'active',
        soldAt: {
          gte: period.start,
          lt: period.endExclusive,
        },
        cashSession: {
          is: {
            userId: {
              not: null,
            },
          },
        },
      },
      _sum: {
        totalAmountCents: true,
      },
      _count: {
        id: true,
      },
      _max: {
        soldAt: true,
      },
      orderBy: { _sum: { totalAmountCents: 'desc' } },
      take: Math.max(query.limit, 25),
    });
    const cashSessionIds = sessionRows
      .map((row) => row.cashSessionId)
      .filter((value): value is string => value != null);

    if (cashSessionIds.length === 0) {
      return {
        available: false,
        reason: 'EMPLOYEE_REPORTS_NOT_AVAILABLE',
        period: this.serializePeriod(period),
        topEmployees: [],
      };
    }

    const sessions = await prisma.cashSession.findMany({
      where: {
        companyId: context.company.id,
        id: {
          in: cashSessionIds,
        },
        userId: {
          not: null,
        },
        user: {
          memberships: {
            some: {
              companyId: context.company.id,
            },
          },
        },
      },
      select: {
        id: true,
        userId: true,
        user: {
          select: {
            id: true,
            name: true,
            email: true,
          },
        },
      },
    });
    const sessionById = new Map(sessions.map((session) => [session.id, session]));
    const userIds = Array.from(
      new Set(
        sessions
          .map((session) => session.userId)
          .filter((value): value is string => value != null),
      ),
    );

    if (userIds.length === 0) {
      return {
        available: false,
        reason: 'EMPLOYEE_REPORTS_NOT_AVAILABLE',
        period: this.serializePeriod(period),
        topEmployees: [],
      };
    }

    const profiles = await prisma.employeeProfile.findMany({
      where: {
        companyId: context.company.id,
        userId: {
          in: userIds,
        },
      },
      select: {
        id: true,
        userId: true,
        name: true,
        role: true,
        status: true,
      },
    });
    const profilesByUserId = new Map(
      profiles
        .filter((profile) => profile.userId != null)
        .map((profile) => [profile.userId!, profile]),
    );
    const aggregates = new Map<
      string,
      {
        employeeId: string;
        userId: string;
        name: string;
        role: string | null;
        status: string | null;
        salesAmountCents: number;
        salesCount: number;
        lastSaleAt: Date | null;
      }
    >();

    for (const row of sessionRows) {
      const session =
        row.cashSessionId == null ? null : sessionById.get(row.cashSessionId);
      const userId = session?.userId;
      if (userId == null) {
        continue;
      }
      const profile = profilesByUserId.get(userId);
      const user = session?.user;
      const current = aggregates.get(userId) ?? {
        employeeId: profile?.id ?? userId,
        userId,
        name: safeName(profile?.name) ?? safeName(user?.name) ?? user?.email ?? 'Funcionario',
        role: profile?.role ?? null,
        status: profile?.status ?? null,
        salesAmountCents: 0,
        salesCount: 0,
        lastSaleAt: null,
      };
      current.salesAmountCents += row._sum.totalAmountCents ?? 0;
      current.salesCount += readGroupedCount(row._count);
      if (
        row._max.soldAt != null &&
        (current.lastSaleAt == null || row._max.soldAt > current.lastSaleAt)
      ) {
        current.lastSaleAt = row._max.soldAt;
      }
      aggregates.set(userId, current);
    }

    const topEmployees = [...aggregates.values()]
      .sort((left, right) => right.salesAmountCents - left.salesAmountCents)
      .slice(0, query.limit)
      .map((item) => ({
        employeeId: item.employeeId,
        userId: item.userId,
        name: item.name,
        role: item.role,
        status: item.status,
        salesAmountCents: item.salesAmountCents,
        salesCount: item.salesCount,
        averageTicketCents: averageCents(item.salesAmountCents, item.salesCount),
        lastSaleAt: item.lastSaleAt?.toISOString() ?? null,
      }));

    return {
      available: topEmployees.length > 0,
      reason:
        topEmployees.length > 0 ? null : 'EMPLOYEE_REPORTS_NOT_AVAILABLE',
      period: this.serializePeriod(period),
      topEmployees,
    };
  }

  async listCashSessions(
    context: AppContext,
    query: OwnerCashSessionsQueryInput,
  ) {
    const period = this.resolveDateRange(query);
    const sessions = await this.loadCashSessions(context.company.id, period, {
      employeeId: safeName(query.employeeId),
      search: query.search,
    });
    const filtered = filterCashSessionsByStatus(sessions, query.status);
    const page = query.page ?? 1;
    const pageSize = query.pageSize ?? 20;
    const { skip, take } = toPaginationParams({ page, pageSize });
    const items = filtered.slice(skip, skip + take).map(serializeCashSessionRow);

    return {
      period: this.serializePeriod(period),
      summary: buildCashSessionsSummary(filtered),
      items: buildPaginatedResponse({
        items,
        page,
        pageSize,
        total: filtered.length,
      }),
    };
  }

  async getCashSessionDetail(context: AppContext, cashSessionId: string) {
    const session = await prisma.cashSession.findFirst({
      where: {
        id: cashSessionId,
        companyId: context.company.id,
      },
      include: cashSessionDetailInclude,
    });
    if (session == null) {
      throw new AppError('Caixa nao encontrado.', 404, 'OWNER_CASH_SESSION_NOT_FOUND');
    }

    const sales = await this.loadCashSessionSales(context.company.id, cashSessionId);
    const saleIds = sales.map((sale) => sale.id);
    const postSaleActions =
      saleIds.length === 0
        ? []
        : await prisma.financialEvent.findMany({
            where: {
              companyId: context.company.id,
              saleId: { in: saleIds },
              eventType: { in: ['sale_return_admin', 'sale_canceled_admin'] },
            },
            orderBy: [{ createdAt: 'desc' }, { updatedAt: 'desc' }],
          });

    return {
      session: serializeCashSessionRow(session),
      employee: serializeCashSessionEmployee(session.user),
      values: serializeCashSessionValues(session),
      movements: [
        ...session.cashEvents.map(serializeCashEvent),
        ...postSaleActions.map(serializePostSaleFinancialEvent),
      ].sort((left, right) => right.createdAt.localeCompare(left.createdAt)),
      sales: buildPaginatedResponse({
        items: sales.slice(0, 25).map((sale) => serializeCashSessionSale(sale, context)),
        page: 1,
        pageSize: 25,
        total: sales.length,
      }),
    };
  }

  async listCashSessionSales(context: AppContext, cashSessionId: string) {
    await this.ensureCashSessionForCompany(context.company.id, cashSessionId);
    const sales = await this.loadCashSessionSales(context.company.id, cashSessionId);
    return buildPaginatedResponse({
      items: sales.map((sale) => serializeCashSessionSale(sale, context)),
      page: 1,
      pageSize: Math.max(sales.length, 1),
      total: sales.length,
    });
  }

  async registerSaleReturn(
    context: AppContext,
    cashSessionId: string,
    saleId: string,
    input: OwnerSaleReturnInput,
  ) {
    const now = new Date();
    const result = await prisma.$transaction(async (tx) => {
      const sale = await tx.sale.findFirst({
        where: {
          id: saleId,
          companyId: context.company.id,
          cashSessionId,
        },
        include: {
          items: { orderBy: { createdAt: 'asc' } },
        },
      });
      if (sale == null) {
        throw new AppError('Venda nao encontrada neste caixa.', 404, 'OWNER_SALE_NOT_FOUND');
      }
      if (sale.status === 'canceled' || sale.status === 'refunded') {
        throw new AppError(
          'Esta venda ja foi cancelada ou devolvida integralmente.',
          409,
          'OWNER_SALE_ALREADY_CLOSED',
        );
      }

      const existingReturns = await tx.financialEvent.aggregate({
        where: {
          companyId: context.company.id,
          saleId,
          eventType: 'sale_return_admin',
        },
        _sum: { amountCents: true },
      });
      const alreadyReturnedCents = Math.abs(existingReturns._sum.amountCents ?? 0);
      const selected = resolveReturnItems(sale.items, input.items);
      const returnAmountCents = selected.reduce(
        (total, item) => total + item.returnAmountCents,
        0,
      );
      if (returnAmountCents <= 0) {
        throw new AppError('Selecione itens validos para devolucao.', 422, 'OWNER_RETURN_INVALID');
      }
      if (alreadyReturnedCents + returnAmountCents > sale.totalAmountCents) {
        throw new AppError(
          'A devolucao excede o valor original da venda.',
          409,
          'OWNER_RETURN_EXCEEDS_SALE',
        );
      }

      if (input.returnToStock) {
        for (const item of selected) {
          if (item.productId == null) {
            continue;
          }
          await tx.product.updateMany({
            where: { id: item.productId, companyId: context.company.id },
            data: { stockMil: { increment: item.quantityMil } },
          });
        }
      }

      const fullReturn =
        alreadyReturnedCents + returnAmountCents >= sale.totalAmountCents;
      const updatedSale = fullReturn
        ? await tx.sale.update({
            where: { id: sale.id },
            data: { status: 'refunded' },
            include: { items: { orderBy: { createdAt: 'asc' } } },
          })
        : sale;

      const event = await tx.financialEvent.create({
        data: {
          companyId: context.company.id,
          saleId: sale.id,
          eventType: 'sale_return_admin',
          localUuid: `owner-return:${sale.id}:${now.getTime()}`,
          amountCents: -returnAmountCents,
          paymentType: sale.paymentType,
          metadata: {
            source: 'owner_web',
            actorUserId: context.user.id,
            cashSessionId,
            reason: input.reason,
            returnToStock: input.returnToStock,
            items: selected.map((item) => ({
              saleItemId: item.id,
              productId: item.productId,
              productName: item.productNameSnapshot,
              quantityMil: item.quantityMil,
              amountCents: item.returnAmountCents,
            })),
          } satisfies Prisma.InputJsonValue,
          createdAt: now,
        },
      });

      return { sale: updatedSale, event };
    });

    return {
      sale: serializeOwnerSaleDetail(result.sale),
      action: serializePostSaleFinancialEvent(result.event),
      message: 'Troca/devolucao registrada com auditoria.',
    };
  }

  async cancelCashSessionSale(
    context: AppContext,
    cashSessionId: string,
    saleId: string,
    input: OwnerSaleCancelInput,
  ) {
    const now = new Date();
    const result = await prisma.$transaction(async (tx) => {
      const sale = await tx.sale.findFirst({
        where: {
          id: saleId,
          companyId: context.company.id,
          cashSessionId,
        },
        include: { items: { orderBy: { createdAt: 'asc' } } },
      });
      if (sale == null) {
        throw new AppError('Venda nao encontrada neste caixa.', 404, 'OWNER_SALE_NOT_FOUND');
      }
      if (sale.status === 'canceled') {
        throw new AppError('Esta venda ja esta cancelada.', 409, 'OWNER_SALE_ALREADY_CANCELED');
      }

      const canceled = await tx.sale.update({
        where: { id: sale.id },
        data: { status: 'canceled', canceledAt: now },
        include: { items: { orderBy: { createdAt: 'asc' } } },
      });
      const event = await tx.financialEvent.create({
        data: {
          companyId: context.company.id,
          saleId: sale.id,
          eventType: 'sale_canceled_admin',
          localUuid: `owner-cancel:${sale.id}:${now.getTime()}`,
          amountCents: -sale.totalAmountCents,
          paymentType: sale.paymentType,
          metadata: {
            source: 'owner_web',
            actorUserId: context.user.id,
            cashSessionId,
            reason: input.reason,
          } satisfies Prisma.InputJsonValue,
          createdAt: now,
        },
      });
      return { sale: canceled, event };
    });

    return {
      sale: serializeOwnerSaleDetail(result.sale),
      action: serializePostSaleFinancialEvent(result.event),
      message: 'Venda cancelada com auditoria.',
    };
  }

  async getReportsCatalog(context: AppContext) {
    const [productCount, customerCount, saleCount, employeeReports] =
      await Promise.all([
        prisma.product.count({
          where: { companyId: context.company.id, deletedAt: null },
        }),
        prisma.customer.count({
          where: { companyId: context.company.id, deletedAt: null },
        }),
        prisma.sale.count({
          where: { companyId: context.company.id, status: 'active' },
        }),
        this.getEmployeeReports(context, { limit: 1 }),
      ]);

    return {
      items: [
        reportCatalogItem('sales', 'Vendas', 'Resumo de vendas, formas de pagamento e vendas recentes.', true),
        reportCatalogItem('products', 'Produtos', 'Produtos mais vendidos e itens com pouca saida.', true),
        reportCatalogItem('cash', 'Caixa', 'Resumo financeiro gerencial a partir das vendas e recebimentos.', true),
        reportCatalogItem('stock', 'Estoque', 'Produtos zerados, baixo estoque e valor estimado do estoque.', productCount > 0, 'NO_PRODUCTS_REGISTERED'),
        reportCatalogItem('customers', 'Clientes', 'CRM, clientes ativos, inativos e melhores clientes.', customerCount > 0 || saleCount > 0, 'NO_CUSTOMER_DATA'),
        reportCatalogItem(
          'employees',
          'Funcionarios',
          'Desempenho de vendas por funcionario.',
          employeeReports.available,
          employeeReports.reason ?? 'EMPLOYEE_REPORTS_NOT_AVAILABLE',
        ),
        reportCatalogItem(
          'commissions',
          'Comissoes',
          'Comissao total, vendas elegiveis e regras por funcionario.',
          true,
        ),
      ],
    };
  }

  private async aggregateSales(companyId: string, start: Date, endExclusive: Date) {
    const aggregate = await prisma.sale.aggregate({
      where: {
        companyId,
        status: 'active',
        soldAt: {
          gte: start,
          lt: endExclusive,
        },
      },
      _count: { id: true },
      _sum: { totalAmountCents: true },
    });

    return {
      count: aggregate._count.id,
      amountCents: aggregate._sum.totalAmountCents ?? 0,
    };
  }

  private resolveDateRange(input: {
    startDate?: string;
    endDate?: string;
  }): OwnerDateRange {
    const today = startOfUtcDay(new Date());
    const defaultEndExclusive = addDays(today, 1);
    const defaultStart = addDays(defaultEndExclusive, -DEFAULT_DAYS);
    const start =
      input.startDate == null ? defaultStart : startOfUtcDay(parseDate(input.startDate));
    const endExclusive =
      input.endDate == null
        ? defaultEndExclusive
        : addDays(startOfUtcDay(parseDate(input.endDate)), 1);

    if (start >= endExclusive) {
      throw new AppError(
        'Periodo invalido para o relatorio.',
        422,
        'OWNER_REPORT_DATE_RANGE_INVALID',
      );
    }

    const days = Math.ceil(
      (endExclusive.getTime() - start.getTime()) / (24 * 60 * 60 * 1000),
    );
    if (days > MAX_DAYS) {
      throw new AppError(
        'Periodo maximo de relatorio excedido.',
        422,
        'OWNER_REPORT_DATE_RANGE_TOO_LONG',
      );
    }

    return {
      start,
      endExclusive,
      startDate: formatDateOnly(start),
      endDate: formatDateOnly(addDays(endExclusive, -1)),
      timezone: OWNER_REPORT_TIMEZONE,
    };
  }

  private serializePeriod(period: OwnerDateRange) {
    return {
      startDate: period.startDate,
      endDate: period.endDate,
      timezone: period.timezone,
    };
  }

  private groupSalesSeries(
    sales: Array<{ soldAt: Date; totalAmountCents: number }>,
    groupBy: 'day' | 'week' | 'month',
  ) {
    const series = new Map<string, { amountCents: number; count: number }>();

    for (const sale of sales) {
      const key = groupDateKey(sale.soldAt, groupBy);
      const current = series.get(key) ?? { amountCents: 0, count: 0 };
      current.amountCents += sale.totalAmountCents;
      current.count += 1;
      series.set(key, current);
    }

    return [...series.entries()]
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([date, value]) => ({
        date,
        totalAmountCents: value.amountCents,
        totalCount: value.count,
        averageTicketCents: averageCents(value.amountCents, value.count),
      }));
  }

  private async getTopSellingProducts(
    companyId: string,
    period: Pick<OwnerDateRange, 'start' | 'endExclusive'>,
    limit: number,
  ) {
    const rows = await prisma.saleItem.groupBy({
      by: ['productId', 'productNameSnapshot'],
      where: {
        sale: {
          companyId,
          status: 'active',
          soldAt: {
            gte: period.start,
            lt: period.endExclusive,
          },
        },
      },
      _sum: {
        quantityMil: true,
        totalPriceCents: true,
      },
      _count: {
        id: true,
      },
      orderBy: [
        { _sum: { totalPriceCents: 'desc' } },
        { productNameSnapshot: 'asc' },
      ],
      take: limit,
    });

    return rows.map((row) => ({
      productId: row.productId,
      productName: row.productNameSnapshot,
      quantityMil: row._sum.quantityMil ?? 0,
      salesCount: readGroupedCount(row._count),
      amountCents: row._sum.totalPriceCents ?? 0,
    }));
  }

  private async getLowSellingProducts(
    companyId: string,
    topProductIds: string[],
    limit: number,
  ) {
    const products = await prisma.product.findMany({
      where: {
        companyId,
        deletedAt: null,
        ...(topProductIds.length === 0 ? {} : { id: { notIn: topProductIds } }),
      },
      select: {
        id: true,
        name: true,
        salePriceCents: true,
      },
      orderBy: [{ updatedAt: 'asc' }, { name: 'asc' }],
      take: limit,
    });

    return products.map((product) => ({
      productId: product.id,
      productName: product.name,
      quantityMil: 0,
      salesCount: 0,
      amountCents: 0,
      salePriceCents: product.salePriceCents,
    }));
  }

  private async getProductSalesByCategory(
    companyId: string,
    period: Pick<OwnerDateRange, 'start' | 'endExclusive'>,
    limit: number,
  ) {
    const productRows = await prisma.saleItem.groupBy({
      by: ['productId'],
      where: {
        sale: {
          companyId,
          status: 'active',
          soldAt: {
            gte: period.start,
            lt: period.endExclusive,
          },
        },
      },
      _sum: {
        quantityMil: true,
        totalPriceCents: true,
      },
      _count: {
        id: true,
      },
      orderBy: { _sum: { totalPriceCents: 'desc' } },
      take: Math.max(limit, CATEGORY_PRODUCT_SCAN_LIMIT),
    });
    const productIds = productRows
      .map((row) => row.productId)
      .filter((value): value is string => value != null);
    const products =
      productIds.length === 0
        ? []
        : await prisma.product.findMany({
            where: {
              companyId,
              id: {
                in: productIds,
              },
            },
            select: {
              id: true,
              categoryId: true,
              category: {
                select: {
                  name: true,
                },
              },
            },
          });
    const productById = new Map(products.map((product) => [product.id, product]));
    const categories = new Map<
      string,
      {
        categoryId: string | null;
        categoryName: string;
        quantityMil: number;
        amountCents: number;
        salesCount: number;
      }
    >();

    for (const item of productRows) {
      const product =
        item.productId == null ? null : productById.get(item.productId);
      const categoryId = product?.categoryId ?? null;
      const key = categoryId ?? 'uncategorized';
      const current = categories.get(key) ?? {
        categoryId,
        categoryName: product?.category?.name ?? 'Sem categoria',
        quantityMil: 0,
        amountCents: 0,
        salesCount: 0,
      };
      current.quantityMil += item._sum.quantityMil ?? 0;
      current.amountCents += item._sum.totalPriceCents ?? 0;
      current.salesCount += readGroupedCount(item._count);
      categories.set(key, current);
    }

    return [...categories.values()]
      .sort((left, right) => right.amountCents - left.amountCents)
      .slice(0, limit);
  }

  private async loadStockItems(companyId: string): Promise<StockReportItem[]> {
    const products = await prisma.product.findMany({
      where: {
        companyId,
        deletedAt: null,
      },
      select: {
        id: true,
        name: true,
        barcode: true,
        unitMeasure: true,
        stockMil: true,
        costPriceCents: true,
        salePriceCents: true,
        isActive: true,
        variants: {
          select: {
            id: true,
            sku: true,
            colorLabel: true,
            sizeLabel: true,
            stockMil: true,
            priceAdditionalCents: true,
            isActive: true,
          },
          orderBy: [{ sortOrder: 'asc' }, { id: 'asc' }],
        },
      },
      orderBy: [{ name: 'asc' }, { id: 'asc' }],
    });

    const items: StockReportItem[] = [];
    for (const product of products) {
      if (!product.isActive) {
        continue;
      }
      if (product.variants.length === 0) {
        items.push({
          id: product.id,
          productId: product.id,
          productVariantId: null,
          name: product.name,
          variantName: null,
          sku: safeName(product.barcode),
          currentStockMil: product.stockMil,
          costPriceCents: product.costPriceCents,
          salePriceCents: product.salePriceCents,
          estimatedCostCents: stockValueCents(
            product.stockMil,
            product.costPriceCents,
          ),
        });
        continue;
      }
      for (const variant of product.variants) {
        if (!variant.isActive) {
          continue;
        }
        const salePriceCents =
          product.salePriceCents + variant.priceAdditionalCents;
        items.push({
          id: variant.id,
          productId: product.id,
          productVariantId: variant.id,
          name: product.name,
          variantName: variantName(variant.colorLabel, variant.sizeLabel),
          sku: safeName(variant.sku) ?? safeName(product.barcode),
          currentStockMil: variant.stockMil,
          costPriceCents: product.costPriceCents,
          salePriceCents,
          estimatedCostCents: stockValueCents(
            variant.stockMil,
            product.costPriceCents,
          ),
        });
      }
    }

    return items;
  }

  private async ensureCashSessionForCompany(companyId: string, cashSessionId: string) {
    const session = await prisma.cashSession.findFirst({
      where: { id: cashSessionId, companyId },
      select: { id: true },
    });
    if (session == null) {
      throw new AppError('Caixa nao encontrado.', 404, 'OWNER_CASH_SESSION_NOT_FOUND');
    }
  }

  private async loadCashSessions(
    companyId: string,
    period: Pick<OwnerDateRange, 'start' | 'endExclusive'>,
    filters: { employeeId: string | null; search: string },
  ) {
    const search = filters.search.trim().toLocaleLowerCase('pt-BR');
    const rows = await prisma.cashSession.findMany({
      where: {
        companyId,
        ...(filters.employeeId == null ? {} : { userId: filters.employeeId }),
        OR: [
          { openedAt: { gte: period.start, lt: period.endExclusive } },
          { closedAt: { gte: period.start, lt: period.endExclusive } },
          { createdAt: { gte: period.start, lt: period.endExclusive } },
        ],
      },
      include: cashSessionDetailInclude,
      orderBy: [{ openedAt: 'desc' }, { createdAt: 'desc' }],
      take: 250,
    });

    if (search.length === 0) {
      return rows;
    }
    return rows.filter((session) => {
      const haystack = [
        session.localId,
        session.localUuid,
        session.notes,
        session.user?.name,
        session.user?.email,
      ]
        .filter((value): value is string => value != null)
        .join(' ')
        .toLocaleLowerCase('pt-BR');
      return haystack.includes(search);
    });
  }

  private async loadCashSessionSales(companyId: string, cashSessionId: string) {
    return prisma.sale.findMany({
      where: { companyId, cashSessionId },
      include: {
        customer: { select: { id: true, name: true } },
        items: { orderBy: { createdAt: 'asc' } },
        financialEvents: {
          where: {
            eventType: { in: ['sale_return_admin', 'sale_canceled_admin'] },
          },
          orderBy: { createdAt: 'desc' },
        },
      },
      orderBy: [{ soldAt: 'desc' }, { updatedAt: 'desc' }],
      take: 100,
    });
  }

  private async buildReceivablesSummary(companyId: string) {
    return summarizeReceivableItems(await this.buildReceivableItems(companyId));
  }

  private async sumFiadoPaymentsSince(companyId: string, start: Date) {
    const aggregate = await prisma.fiadoPayment.aggregate({
      where: {
        companyId,
        createdAt: {
          gte: start,
        },
      },
      _sum: {
        amountCents: true,
      },
    });
    return aggregate._sum.amountCents ?? 0;
  }

  private async buildReceivableItems(
    companyId: string,
    customerId?: string,
  ): Promise<ReceivableCustomerItem[]> {
    const sales = await prisma.sale.findMany({
      where: {
        companyId,
        status: 'active',
        paymentType: 'fiado',
        ...(customerId == null ? {} : { customerId }),
      },
      select: {
        id: true,
        customerId: true,
        totalAmountCents: true,
        customer: {
          select: {
            name: true,
          },
        },
      },
    });
    const saleIds = sales.map((sale) => sale.id);
    const payments =
      saleIds.length === 0
        ? []
        : await prisma.fiadoPayment.groupBy({
            by: ['saleId'],
            where: {
              companyId,
              saleId: {
                in: saleIds,
              },
            },
            _sum: {
              amountCents: true,
            },
          });
    const paidBySaleId = new Map(
      payments.map((payment) => [
        payment.saleId,
        payment._sum.amountCents ?? 0,
      ]),
    );
    const byCustomer = new Map<string, ReceivableCustomerItem>();

    for (const sale of sales) {
      const key = sale.customerId ?? 'without-customer';
      const paidAmountCents = paidBySaleId.get(sale.id) ?? 0;
      const openAmountCents = Math.max(
        sale.totalAmountCents - paidAmountCents,
        0,
      );
      const current = byCustomer.get(key) ?? {
        id: key,
        customerId: sale.customerId,
        customerName: safeName(sale.customer?.name) ?? 'Cliente nao identificado',
        openAmountCents: 0,
        overdueAmountCents: 0,
        paidAmountCents: 0,
        totalAmountCents: 0,
        salesCount: 0,
        dueDate: null,
        status: 'paid' as const,
      };
      current.totalAmountCents += sale.totalAmountCents;
      current.paidAmountCents += Math.min(paidAmountCents, sale.totalAmountCents);
      current.openAmountCents += openAmountCents;
      current.salesCount += 1;
      current.status = current.openAmountCents > 0 ? 'open' : 'paid';
      byCustomer.set(key, current);
    }

    return [...byCustomer.values()];
  }

  private async loadCustomerCommercialSummaries(
    companyId: string,
    search?: string,
  ) {
    const customers = await prisma.customer.findMany({
      where: {
        companyId,
        deletedAt: null,
        ...(search == null || search.length === 0
          ? {}
          : {
              OR: [
                { name: { contains: search, mode: 'insensitive' } },
                { phone: { contains: search, mode: 'insensitive' } },
              ],
            }),
      },
      select: customerSummarySelect,
      orderBy: [{ name: 'asc' }, { createdAt: 'asc' }],
    });
    const summaries = await this.buildCustomerSummaryMap(
      companyId,
      customers.map((customer) => customer.id),
    );

    return customers.map((customer) => ({
      ...customer,
      summary: summaries.get(customer.id) ?? emptyCustomerSummary(customer.id),
    }));
  }

  private async loadSingleCustomerCommercialSummary(
    companyId: string,
    customerId: string,
  ) {
    const customer = await prisma.customer.findFirst({
      where: {
        companyId,
        id: customerId,
        deletedAt: null,
      },
      select: customerSummarySelect,
    });
    if (customer == null) {
      return null;
    }
    const summaries = await this.buildCustomerSummaryMap(companyId, [customer.id]);
    return {
      ...customer,
      summary: summaries.get(customer.id) ?? emptyCustomerSummary(customer.id),
    };
  }

  private async buildCustomerSummaryMap(companyId: string, customerIds: string[]) {
    if (customerIds.length === 0) {
      return new Map<string, CustomerCommercialSummary>();
    }

    const [sales, payments] = await prisma.$transaction([
      prisma.sale.groupBy({
        by: ['customerId'],
        where: {
          companyId,
          status: 'active',
          customerId: {
            in: customerIds,
          },
        },
        _count: { id: true },
        _sum: { totalAmountCents: true },
        _max: { soldAt: true },
        orderBy: { customerId: 'asc' },
      }),
      prisma.fiadoPayment.findMany({
        where: {
          companyId,
          sale: {
            companyId,
            status: 'active',
            paymentType: 'fiado',
            customerId: {
              in: customerIds,
            },
          },
        },
        select: {
          amountCents: true,
          sale: {
            select: {
              customerId: true,
              totalAmountCents: true,
            },
          },
        },
      }),
    ]);

    const summaries = new Map(
      customerIds.map((id) => [id, emptyCustomerSummary(id)]),
    );
    for (const sale of sales) {
      if (sale.customerId == null) {
        continue;
      }
      const current = summaries.get(sale.customerId) ?? emptyCustomerSummary(sale.customerId);
      current.totalPurchasedCents = sale._sum?.totalAmountCents ?? 0;
      current.purchasesCount = readGroupedCount(sale._count);
      current.averageTicketCents = averageCents(
        current.totalPurchasedCents,
        current.purchasesCount,
      );
      current.lastPurchaseAt = sale._max?.soldAt ?? null;
      summaries.set(sale.customerId, current);
    }

    const paidByCustomer = new Map<string, number>();
    const fiadoTotalByCustomer = new Map<string, number>();
    for (const payment of payments) {
      const customerId = payment.sale.customerId;
      if (customerId == null) {
        continue;
      }
      paidByCustomer.set(
        customerId,
        (paidByCustomer.get(customerId) ?? 0) + payment.amountCents,
      );
    }
    const fiadoSales = await prisma.sale.groupBy({
      by: ['customerId'],
      where: {
        companyId,
        status: 'active',
        paymentType: 'fiado',
        customerId: {
          in: customerIds,
        },
      },
      _sum: { totalAmountCents: true },
    });
    for (const sale of fiadoSales) {
      if (sale.customerId == null) {
        continue;
      }
      fiadoTotalByCustomer.set(sale.customerId, sale._sum.totalAmountCents ?? 0);
    }
    for (const [id, total] of fiadoTotalByCustomer.entries()) {
      const current = summaries.get(id) ?? emptyCustomerSummary(id);
      current.openReceivableAmountCents = Math.max(
        total - (paidByCustomer.get(id) ?? 0),
        0,
      );
      summaries.set(id, current);
    }

    return summaries;
  }

  private toOwnerCustomerListItem(
    customer: CustomerWithCommercialSummary,
    inactiveCutoff: Date,
  ) {
    const active = isCustomerActive(customer.summary, inactiveCutoff);
    return {
      id: customer.id,
      name: customer.name,
      phone: customer.phone,
      totalPurchasedCents: customer.summary.totalPurchasedCents,
      purchasesCount: customer.summary.purchasesCount,
      averageTicketCents: customer.summary.averageTicketCents,
      lastPurchaseAt: customer.summary.lastPurchaseAt?.toISOString() ?? null,
      openReceivableAmountCents: customer.summary.openReceivableAmountCents,
      status: active ? 'active' : 'inactive',
      statusLabel: active ? 'Ativo' : 'Inativo',
      tags: customer.crmTagAssignments.map((assignment) => ({
        id: assignment.tag.id,
        label: assignment.tag.label,
        color: assignment.tag.color,
      })),
    };
  }
}

const customerSummarySelect = {
  id: true,
  name: true,
  phone: true,
  createdAt: true,
  crmTagAssignments: {
    select: {
      tag: {
        select: {
          id: true,
          label: true,
          color: true,
        },
      },
    },
    orderBy: { createdAt: 'asc' },
  },
} satisfies Prisma.CustomerSelect;

const cashSessionDetailInclude = {
  user: {
    select: {
      id: true,
      name: true,
      email: true,
    },
  },
  sales: {
    select: {
      id: true,
      status: true,
      paymentMethod: true,
      paymentType: true,
      totalAmountCents: true,
      soldAt: true,
    },
  },
  cashEvents: {
    orderBy: { createdAt: 'desc' },
    take: 50,
  },
} satisfies Prisma.CashSessionInclude;

type OwnerCashSessionRow = Prisma.CashSessionGetPayload<{
  include: typeof cashSessionDetailInclude;
}>;

type OwnerCashSessionSale = Prisma.SaleGetPayload<{
  include: {
    customer: { select: { id: true; name: true } };
    items: true;
    financialEvents: true;
  };
}>;

type OwnerSaleWithItems = Prisma.SaleGetPayload<{
  include: { items: true };
}>;

function aggregateSaleItemsByProduct(
  saleItems: Array<{
    productId: string | null;
    productNameSnapshot: string;
    quantityMil: number;
    totalPriceCents: number;
  }>,
) {
  const products = new Map<
    string,
    {
      productId: string | null;
      productName: string;
      quantityMil: number;
      salesCount: number;
      amountCents: number;
    }
  >();

  for (const item of saleItems) {
    const key = item.productId ?? item.productNameSnapshot;
    const current = products.get(key) ?? {
      productId: item.productId,
      productName: item.productNameSnapshot,
      quantityMil: 0,
      salesCount: 0,
      amountCents: 0,
    };
    current.quantityMil += item.quantityMil;
    current.salesCount += 1;
    current.amountCents += item.totalPriceCents;
    products.set(key, current);
  }

  return [...products.values()].sort((left, right) => {
    return right.amountCents - left.amountCents ||
      left.productName.localeCompare(right.productName, 'pt-BR');
  });
}

function summarizeReceivableItems(items: ReceivableCustomerItem[]) {
  return {
    openAmountCents: items.reduce(
      (total, item) => total + item.openAmountCents,
      0,
    ),
    overdueAmountCents: items.reduce(
      (total, item) => total + item.overdueAmountCents,
      0,
    ),
    openCount: items.filter((item) => item.openAmountCents > 0).length,
    overdueCount: items.filter((item) => item.overdueAmountCents > 0).length,
    paidCount: items.filter((item) => item.status === 'paid').length,
  };
}

function reportCatalogItem(
  key: string,
  title: string,
  description: string,
  available: boolean,
  reason?: string | null,
) {
  return {
    key,
    title,
    description,
    available,
    reason: available ? null : reason ?? 'REPORT_NOT_AVAILABLE',
  };
}

function filterCashSessionsByStatus(
  sessions: OwnerCashSessionRow[],
  status: 'all' | 'open' | 'closed' | 'with_difference',
) {
  if (status === 'all') {
    return sessions;
  }
  return sessions.filter((session) => {
    if (status === 'with_difference') {
      return cashDifferenceCents(session) !== 0;
    }
    return normalizeCashSessionStatus(session) === status;
  });
}

function buildCashSessionsSummary(sessions: OwnerCashSessionRow[]) {
  const paymentTotals = new Map<string, { label: string; amountCents: number; count: number }>();
  let totalSoldCents = 0;
  let salesCount = 0;
  let cashInflowCents = 0;
  let cashOutflowCents = 0;

  for (const session of sessions) {
    for (const sale of session.sales) {
      if (sale.status !== 'active') {
        continue;
      }
      totalSoldCents += sale.totalAmountCents;
      salesCount += 1;
      const key = normalizePaymentKey(sale.paymentMethod);
      const current = paymentTotals.get(key) ?? {
        label: friendlyPaymentMethod(sale.paymentMethod),
        amountCents: 0,
        count: 0,
      };
      current.amountCents += sale.totalAmountCents;
      current.count += 1;
      paymentTotals.set(key, current);
    }
    for (const event of session.cashEvents) {
      if (event.amountCents >= 0) {
        cashInflowCents += event.amountCents;
      } else {
        cashOutflowCents += Math.abs(event.amountCents);
      }
    }
  }

  return {
    totalSoldCents,
    totalSessions: sessions.length,
    sessionsWithDifference: sessions.filter((session) => cashDifferenceCents(session) !== 0).length,
    totalCashInflowCents: cashInflowCents,
    totalCashOutflowCents: cashOutflowCents,
    averageTicketCents: averageCents(totalSoldCents, salesCount),
    salesCount,
    byPaymentMethod: [...paymentTotals.entries()].map(([key, value]) => ({
      key,
      ...value,
    })),
  };
}

function serializeCashSessionRow(session: OwnerCashSessionRow) {
  const totals = buildCashSessionsSummary([session]);
  return {
    id: session.id,
    shortId: shortIdentifier(session.localId ?? session.localUuid ?? session.id),
    localId: safeName(session.localId),
    openedAt: session.openedAt?.toISOString() ?? session.createdAt.toISOString(),
    closedAt: session.closedAt?.toISOString() ?? null,
    employee: serializeCashSessionEmployee(session.user),
    status: normalizeCashSessionStatus(session),
    statusLabel: cashStatusLabel(session),
    totalSoldCents: totals.totalSoldCents,
    totalCashCents: totals.byPaymentMethod.find((item) => item.key === 'dinheiro')?.amountCents ?? 0,
    totalCardCents: totals.byPaymentMethod
      .filter((item) => item.key.includes('cartao'))
      .reduce((total, item) => total + item.amountCents, 0),
    totalPixCents: totals.byPaymentMethod.find((item) => item.key === 'pix')?.amountCents ?? 0,
    totalOtherCents: totals.byPaymentMethod
      .filter((item) => !['dinheiro', 'pix'].includes(item.key) && !item.key.includes('cartao'))
      .reduce((total, item) => total + item.amountCents, 0),
    cashInflowCents: totals.totalCashInflowCents,
    cashOutflowCents: totals.totalCashOutflowCents,
    differenceCents: cashDifferenceCents(session),
    salesCount: totals.salesCount,
    notes: safeName(session.notes),
  };
}

function serializeCashSessionEmployee(
  user: { id: string; name: string | null; email: string } | null,
) {
  return {
    id: user?.id ?? null,
    name: safeName(user?.name) ?? user?.email ?? 'Funcionario nao identificado',
    email: user?.email ?? null,
  };
}

function serializeCashSessionValues(session: OwnerCashSessionRow) {
  return {
    openingBalanceCents: session.openingBalanceCents,
    closingBalanceCents: session.closingBalanceCents,
    expectedBalanceCents: session.expectedBalanceCents,
    differenceCents: cashDifferenceCents(session),
  };
}

function serializeCashEvent(event: Prisma.CashEventGetPayload<{}>) {
  return {
    id: event.id,
    type: event.eventType,
    title: cashEventTitle(event.eventType),
    amountCents: event.amountCents,
    paymentMethod: friendlyPaymentMethod(event.paymentMethod),
    notes: safeName(event.notes),
    createdAt: event.createdAt.toISOString(),
  };
}

function serializePostSaleFinancialEvent(event: Prisma.FinancialEventGetPayload<{}>) {
  return {
    id: event.id,
    type: event.eventType,
    title:
      event.eventType === 'sale_canceled_admin'
        ? 'Cancelamento administrativo'
        : 'Troca/devolucao administrativa',
    amountCents: event.amountCents,
    paymentMethod: friendlyPaymentMethod(event.paymentType),
    notes: safeMetadataReason(event.metadata),
    createdAt: event.createdAt.toISOString(),
  };
}

function serializeCashSessionSale(sale: OwnerCashSessionSale, context: AppContext) {
  const returnedAmountCents = sale.financialEvents
    .filter((event) => event.eventType === 'sale_return_admin')
    .reduce((total, event) => total + Math.abs(event.amountCents), 0);
  return {
    id: sale.id,
    shortId: shortIdentifier(sale.receiptNumber ?? sale.localUuid ?? sale.id),
    receiptNumber: safeReceiptNumber(sale.receiptNumber),
    customerName: safeName(sale.customer?.name),
    sellerName: null,
    totalAmountCents: sale.totalAmountCents,
    returnedAmountCents,
    status: sale.status,
    statusLabel: saleStatusLabel(sale.status),
    paymentMethod: friendlyPaymentMethod(sale.paymentMethod),
    soldAt: sale.soldAt.toISOString(),
    canceledAt: sale.canceledAt?.toISOString() ?? null,
    canCancel: canPerformPostSaleAction(context, sale.status),
    canReturn: canPerformPostSaleAction(context, sale.status),
    actions: sale.financialEvents.map(serializePostSaleFinancialEvent),
    items: sale.items.map((item) => ({
      id: item.id,
      productId: item.productId,
      productName: item.productNameSnapshot,
      quantityMil: item.quantityMil,
      unitPriceCents: item.unitPriceCents,
      totalPriceCents: item.totalPriceCents,
      unitMeasure: item.unitMeasure,
    })),
  };
}

function serializeOwnerSaleDetail(sale: OwnerSaleWithItems) {
  return {
    id: sale.id,
    receiptNumber: safeReceiptNumber(sale.receiptNumber),
    status: sale.status,
    statusLabel: saleStatusLabel(sale.status),
    totalAmountCents: sale.totalAmountCents,
    soldAt: sale.soldAt.toISOString(),
    canceledAt: sale.canceledAt?.toISOString() ?? null,
    items: sale.items.map((item) => ({
      id: item.id,
      productId: item.productId,
      productName: item.productNameSnapshot,
      quantityMil: item.quantityMil,
      totalPriceCents: item.totalPriceCents,
    })),
  };
}

function resolveReturnItems(
  saleItems: OwnerSaleWithItems['items'],
  inputItems: OwnerSaleReturnInput['items'],
) {
  const saleItemById = new Map(saleItems.map((item) => [item.id, item]));
  return inputItems.map((input) => {
    const item = saleItemById.get(input.saleItemId);
    if (item == null) {
      throw new AppError('Item da venda nao encontrado.', 404, 'OWNER_SALE_ITEM_NOT_FOUND');
    }
    if (input.quantityMil > item.quantityMil) {
      throw new AppError('Quantidade maior que a venda original.', 422, 'OWNER_RETURN_QUANTITY_INVALID');
    }
    return {
      ...item,
      quantityMil: input.quantityMil,
      returnAmountCents: Math.round((item.unitPriceCents * input.quantityMil) / 1000),
    };
  });
}

function cashDifferenceCents(session: {
  closingBalanceCents: number | null;
  expectedBalanceCents: number | null;
  payload: Prisma.JsonValue | null;
}) {
  if (session.closingBalanceCents != null && session.expectedBalanceCents != null) {
    return session.closingBalanceCents - session.expectedBalanceCents;
  }
  if (session.payload != null && typeof session.payload === 'object' && !Array.isArray(session.payload)) {
    const value = (session.payload as Record<string, unknown>).differenceCents;
    if (typeof value === 'number' && Number.isFinite(value)) {
      return Math.trunc(value);
    }
  }
  return 0;
}

function normalizeCashSessionStatus(session: { status: string; closedAt: Date | null }) {
  if (session.closedAt != null || session.status === 'closed') {
    return 'closed';
  }
  return 'open';
}

function cashStatusLabel(session: OwnerCashSessionRow) {
  if (cashDifferenceCents(session) !== 0) {
    return 'Com diferenca';
  }
  return normalizeCashSessionStatus(session) === 'closed' ? 'Fechado' : 'Aberto';
}

function saleStatusLabel(status: string) {
  switch (status) {
    case 'canceled':
      return 'Cancelada';
    case 'refunded':
      return 'Devolvida';
    default:
      return 'Ativa';
  }
}

function cashEventTitle(type: string) {
  const normalized = type.toLowerCase();
  if (normalized.includes('sangria') || normalized.includes('withdraw')) {
    return 'Sangria';
  }
  if (normalized.includes('supply') || normalized.includes('suprimento')) {
    return 'Suprimento';
  }
  if (normalized.includes('sale')) {
    return 'Venda';
  }
  return 'Movimento de caixa';
}

function canPerformPostSaleAction(context: AppContext, status: string) {
  if (status === 'canceled' || status === 'refunded') {
    return false;
  }
  return (
    context.membership.role === 'OWNER' ||
    hasPermission(context.membership.permissions, 'sales.cancel') ||
    hasPermission(context.membership.permissions, 'reports.advanced')
  );
}

function hasPermission(permissions: string[], permission: string) {
  return permissions.includes(permission);
}

function safeMetadataReason(metadata: Prisma.JsonValue | null) {
  if (metadata == null || typeof metadata !== 'object' || Array.isArray(metadata)) {
    return null;
  }
  const value = (metadata as Record<string, unknown>).reason;
  return typeof value === 'string' ? safeName(value) : null;
}

function shortIdentifier(value: string) {
  const trimmed = value.trim();
  if (trimmed.length <= 12) {
    return trimmed;
  }
  return `${trimmed.slice(0, 4)}...${trimmed.slice(-4)}`;
}

function emptyCustomerSummary(customerId: string): CustomerCommercialSummary {
  return {
    customerId,
    totalPurchasedCents: 0,
    purchasesCount: 0,
    averageTicketCents: 0,
    lastPurchaseAt: null,
    openReceivableAmountCents: 0,
  };
}

function isCustomerActive(
  summary: Pick<CustomerCommercialSummary, 'lastPurchaseAt'>,
  inactiveCutoff: Date,
) {
  return summary.lastPurchaseAt != null && summary.lastPurchaseAt >= inactiveCutoff;
}

function averageCents(amountCents: number, count: number) {
  return count <= 0 ? 0 : Math.round(amountCents / count);
}

function readGroupedCount(value: unknown) {
  if (typeof value === 'number') {
    return value;
  }
  if (value != null && typeof value === 'object') {
    const counts = value as { id?: number; _all?: number };
    return counts.id ?? counts._all ?? 0;
  }
  return 0;
}

function parseDate(value: string) {
  const normalized = value.trim();
  const parsed = new Date(
    /^\d{4}-\d{2}-\d{2}$/.test(normalized)
      ? `${normalized}T00:00:00.000Z`
      : normalized,
  );
  if (Number.isNaN(parsed.getTime())) {
    throw new AppError('Data invalida.', 422, 'OWNER_REPORT_DATE_INVALID');
  }
  return parsed;
}

function startOfUtcDay(date: Date) {
  return new Date(
    Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()),
  );
}

function startOfUtcMonth(date: Date) {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), 1));
}

function addDays(date: Date, days: number) {
  return new Date(date.getTime() + days * 24 * 60 * 60 * 1000);
}

function formatDateOnly(date: Date) {
  return date.toISOString().slice(0, 10);
}

function groupDateKey(date: Date, groupBy: 'day' | 'week' | 'month') {
  const day = startOfUtcDay(date);
  if (groupBy === 'day') {
    return formatDateOnly(day);
  }
  if (groupBy === 'month') {
    return `${day.getUTCFullYear()}-${String(day.getUTCMonth() + 1).padStart(2, '0')}`;
  }
  const dayOfWeek = day.getUTCDay();
  const mondayOffset = dayOfWeek === 0 ? -6 : 1 - dayOfWeek;
  return formatDateOnly(addDays(day, mondayOffset));
}

function friendlyPaymentMethod(value: string | null | undefined) {
  const normalized = normalizePaymentKey(value);
  switch (normalized) {
    case 'dinheiro':
      return 'Dinheiro';
    case 'pix':
      return 'Pix';
    case 'cartao':
    case 'cartao_credito':
    case 'cartao_debito':
      return 'Cartao';
    case 'fiado':
      return 'Fiado';
    default:
      return 'Outro';
  }
}

function normalizePaymentKey(value: string | null | undefined) {
  const normalized = value?.trim().toLowerCase() ?? '';
  return normalized.length === 0 ? 'outro' : normalized;
}

function safeReceiptNumber(value: string | null) {
  const trimmed = value?.trim();
  if (trimmed == null || trimmed.length === 0 || trimmed.length > 20) {
    return null;
  }
  return trimmed;
}

function safeName(value: string | null | undefined) {
  const trimmed = value?.trim();
  return trimmed == null || trimmed.length === 0 ? null : trimmed;
}

function variantName(color: string, size: string) {
  return [safeName(color), safeName(size)]
    .filter((value): value is string => value != null)
    .join(' / ') || null;
}

function stockValueCents(stockMil: number, costPriceCents: number) {
  return Math.max(0, Math.round((stockMil * costPriceCents) / 1000));
}

function compareStockItems(left: StockReportItem, right: StockReportItem) {
  return left.currentStockMil - right.currentStockMil ||
    left.name.localeCompare(right.name, 'pt-BR');
}

function isString(value: string | null): value is string {
  return value != null;
}
