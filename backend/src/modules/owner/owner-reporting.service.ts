import type { Prisma } from '@prisma/client';

import { prisma } from '../../database/prisma';
import { buildPaginatedResponse } from '../../shared/http/api-response';
import { AppError } from '../../shared/http/app-error';
import { toPaginationParams } from '../../shared/http/pagination';
import type { AppContext } from '../app/app-context.types';
import type {
  OwnerCrmCustomersQueryInput,
  OwnerCrmSummaryQueryInput,
  OwnerEmployeesReportQueryInput,
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
    const { skip, take } = toPaginationParams(query);
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
    const { skip, take } = toPaginationParams(query);

    return {
      summary: {
        ...summarizeReceivableItems(items),
        receivedThisMonthCents,
      },
      items: buildPaginatedResponse({
        items: filtered.slice(skip, skip + take),
        page: query.page,
        pageSize: query.pageSize,
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
