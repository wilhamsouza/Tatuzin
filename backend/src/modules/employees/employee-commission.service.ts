import { MembershipRole, SyncEventStatus } from "@prisma/client";

import { prisma } from "../../database/prisma";
import type { AppContext } from "../app/app-context.types";
import { AppError } from "../../shared/http/app-error";
import { EmployeeContextService } from "./employee-context.service";
import { hasEmployeePermission } from "./employee-permissions";
import {
  type EmployeeActivityQueryInput,
  type EmployeeCommissionBase,
  type EmployeeCommissionSettingsInput,
  type EmployeeCommissionType,
} from "./employees.schemas";
import { resolveSaleActorUserId } from "./employee-sale-attribution";

type CommissionSettings = {
  commissionEnabled: boolean;
  commissionType: EmployeeCommissionType;
  commissionBase: EmployeeCommissionBase;
  commissionRateBps: number | null;
  commissionFixedCents: number | null;
  commissionUpdatedAt: string | null;
};

type CommissionEmployee = {
  id: string;
  userId: string | null;
  name: string;
  role: string;
  status: string;
  commissionEnabled: boolean;
  commissionType: string | null;
  commissionBase: string | null;
  commissionRateBps: number | null;
  commissionFixedCents: number | null;
  commissionUpdatedAt: Date | null;
};

type SaleForCommission = {
  id: string;
  receiptNumber: string | null;
  status: string;
  totalAmountCents: number;
  soldAt: Date;
  canceledAt: Date | null;
  cashSession: { userId: string | null } | null;
  convertedOperationalOrder: {
    sellerUserId: string | null;
    subtotalCents: number;
    discountCents: number;
    totalCents: number;
  } | null;
  items: Array<{
    id: string;
    productNameSnapshot: string;
    quantityMil: number;
    totalPriceCents: number;
    unitCostCents: number;
    totalCostCents: number;
  }>;
};

type SaleCalculation = {
  saleId: string;
  employeeId: string | null;
  occurredAt: Date;
  receiptNumber: string | null;
  isCanceled: boolean;
  grossAmountCents: number;
  netAmountCents: number;
  discountAmountCents: number;
  grossProfitCents: number;
  hasReliableCost: boolean;
  itemsWithoutReliableCostCount: number;
};

const TRACKING_NOTES = [
  "A comissao e estimada e nao gera contas a pagar automaticamente.",
  "Vendas antigas sem vendedor identificado nao entram no calculo.",
  "Comissao sobre lucro usa custo salvo no item da venda; itens sem custo confiavel ficam fora do lucro.",
];

export class EmployeeCommissionService {
  private readonly employeeContextService = new EmployeeContextService();

  async getSettings(context: AppContext, employeeId: string) {
    await this.assertCanViewEmployee(context, employeeId);
    const employee = await this.findEmployeeOrThrow(
      context.company.id,
      employeeId,
    );
    return { settings: this.settingsDto(employee) };
  }

  async updateSettings(
    context: AppContext,
    employeeId: string,
    input: EmployeeCommissionSettingsInput,
  ) {
    this.assertCanManage(context);
    const existing = await this.findEmployeeOrThrow(
      context.company.id,
      employeeId,
    );

    const nextType = input.commissionEnabled
      ? input.commissionType ?? "NONE"
      : "NONE";
    const nextBase =
      nextType === "FIXED_PER_SALE"
        ? input.commissionBase ?? existing.commissionBase ?? "NET_SALES"
        : input.commissionBase ?? "NET_SALES";

    const employee = await prisma.employeeProfile.update({
      where: { id: existing.id },
      data: {
        commissionEnabled: input.commissionEnabled,
        commissionType: nextType,
        commissionBase: nextBase,
        commissionRateBps:
          nextType === "PERCENTAGE" ? input.commissionRateBps : null,
        commissionFixedCents:
          nextType === "FIXED_PER_SALE" ? input.commissionFixedCents : null,
        commissionUpdatedAt: new Date(),
        updatedByUserId: context.user.id,
      },
      select: this.employeeSelect,
    });

    return { settings: this.settingsDto(employee) };
  }

  async summary(context: AppContext, query: EmployeeActivityQueryInput) {
    this.assertCanViewAll(context);
    const result = await this.build(context.company.id, query);
    return {
      period: { from: query.from, to: query.to },
      totals: {
        employeesWithCommission: result.rows.filter(
          (row) => row.commissionEnabled,
        ).length,
        totalSalesAmountCents: sum(result.rows, (row) => row.salesAmountCents),
        totalEligibleSalesAmountCents: sum(
          result.rows,
          (row) => row.eligibleBaseAmountCents,
        ),
        totalGrossProfitCents: sum(result.rows, (row) => row.grossProfitCents),
        totalCommissionCents: sum(
          result.rows,
          (row) => row.commissionAmountCents,
        ),
        totalSalesCount: sum(result.rows, (row) => row.salesCount),
        salesWithoutReliableActorCount:
          result.salesWithoutReliableActorCount,
        salesWithoutReliableCostCount: sum(
          result.rows,
          (row) => row.salesWithoutReliableCostCount,
        ),
      },
      rows: result.rows,
      tracking: {
        partial: true,
        notes: this.notesForRows(result.rows),
      },
    };
  }

  async detail(
    context: AppContext,
    employeeId: string,
    query: EmployeeActivityQueryInput,
  ) {
    await this.assertCanViewEmployee(context, employeeId);
    const canViewProfitAmounts = this.canViewAll(context);
    const result = await this.build(context.company.id, query, employeeId);
    const row = result.rows.find((candidate) => candidate.employeeId === employeeId);
    const employee = result.employees.get(employeeId);
    if (row == null || employee == null) {
      throw new AppError(
        "Funcionario nao encontrado.",
        404,
        "EMPLOYEE_NOT_FOUND",
      );
    }

    const settings = this.settingsDto(employee);
    return {
      employee: {
        id: employee.id,
        name: employee.name,
        role: employee.role,
        status: employee.status,
      },
      settings,
      summary: this.rowDto(row, canViewProfitAmounts),
      sales: result.sales
        .filter((sale) => sale.employeeId === employeeId)
        .sort(
          (first, second) =>
            second.occurredAt.getTime() - first.occurredAt.getTime(),
        )
        .map((sale) => {
          const saleCommission = this.calculateCommissionForSale(
            sale,
            settings,
          );
          return {
            saleId: sale.saleId,
            occurredAt: sale.occurredAt.toISOString(),
            grossAmountCents: sale.grossAmountCents,
            netAmountCents: sale.netAmountCents,
            discountAmountCents: sale.discountAmountCents,
            baseAmountCents: this.responseBaseAmountCents(
              saleCommission.baseAmountCents,
              settings,
              canViewProfitAmounts,
            ),
            grossProfitCents:
              settings.commissionBase === "GROSS_PROFIT" &&
              canViewProfitAmounts
                ? sale.grossProfitCents
                : undefined,
            commissionAmountCents: saleCommission.commissionAmountCents,
            commissionBase: settings.commissionBase,
            status: sale.isCanceled ? "canceled" : "active",
            hasReliableCost: sale.hasReliableCost,
            ignoredReason: saleCommission.ignoredReason,
            description: this.saleDescription(sale.receiptNumber),
          };
        }),
      tracking: {
        partial: true,
        notes: this.notesForRows([row]),
      },
    };
  }

  async buildActivityCommissionByEmployee(
    companyId: string,
    query: EmployeeActivityQueryInput,
  ) {
    const result = await this.build(companyId, query);
    return new Map(
      result.rows.map((row) => [
        row.employeeId,
        {
          commissionEnabled: row.commissionEnabled,
          commissionType: row.commissionType,
          commissionBase: row.commissionBase,
          commissionRateBps: row.commissionRateBps,
          commissionFixedCents: row.commissionFixedCents,
          eligibleSalesCount: row.eligibleSalesCount,
          eligibleBaseAmountCents: row.eligibleBaseAmountCents,
          grossProfitCents: row.grossProfitCents,
          commissionAmountCents: row.commissionAmountCents,
          salesWithoutReliableCostCount: row.salesWithoutReliableCostCount,
        },
      ]),
    );
  }

  private async build(
    companyId: string,
    query: EmployeeActivityQueryInput,
    collectEmployeeId?: string,
  ) {
    await this.employeeContextService.ensureOwnerProfilesForCompany(companyId);
    const range = this.toDateRange(query);
    const employees = await prisma.employeeProfile.findMany({
      where: { companyId },
      select: this.employeeSelect,
      orderBy: [{ role: "asc" }, { name: "asc" }, { createdAt: "asc" }],
    });

    const employeesById = new Map(employees.map((employee) => [employee.id, employee]));
    const employeeIdByUserId = new Map<string, string>();
    for (const employee of employees) {
      if (employee.userId != null) {
        employeeIdByUserId.set(employee.userId, employee.id);
      }
    }

    const rows = new Map(
      employees.map((employee) => [
        employee.id,
        {
          employeeId: employee.id,
          employeeName: employee.name,
          role: employee.role,
          status: employee.status,
          ...this.settingsDto(employee),
          salesCount: 0,
          eligibleSalesCount: 0,
          salesAmountCents: 0,
          eligibleBaseAmountCents: 0,
          grossProfitCents: 0,
          commissionAmountCents: 0,
          canceledSalesCount: 0,
          salesWithoutReliableCostCount: 0,
          lastSaleAt: null as string | null,
        },
      ]),
    );

    const sales = await prisma.sale.findMany({
      where: {
        companyId,
        soldAt: { gte: range.start, lte: range.end },
      },
      select: {
        id: true,
        receiptNumber: true,
        status: true,
        totalAmountCents: true,
        soldAt: true,
        canceledAt: true,
        cashSession: { select: { userId: true } },
        convertedOperationalOrder: {
          select: {
            sellerUserId: true,
            subtotalCents: true,
            discountCents: true,
            totalCents: true,
          },
        },
        items: {
          select: {
            id: true,
            productNameSnapshot: true,
            quantityMil: true,
            totalPriceCents: true,
            unitCostCents: true,
            totalCostCents: true,
          },
        },
      },
    });
    const saleEventBySaleId = await this.saleEventBySaleId(
      companyId,
      sales.map((sale) => sale.id),
    );

    const calculatedSales: SaleCalculation[] = [];
    let salesWithoutReliableActorCount = 0;

    for (const sale of sales) {
      const event = saleEventBySaleId.get(sale.id);
      const actorUserId = resolveSaleActorUserId(sale, event);
      const employeeId =
        actorUserId == null ? null : (employeeIdByUserId.get(actorUserId) ?? null);

      if (employeeId == null) {
        salesWithoutReliableActorCount += 1;
        continue;
      }

      const row = rows.get(employeeId);
      const employee = employeesById.get(employeeId);
      if (row == null || employee == null) {
        continue;
      }

      const calculated = this.calculateSale(sale, employeeId);
      calculatedSales.push(calculated);
      row.lastSaleAt =
        row.lastSaleAt == null || calculated.occurredAt.toISOString() > row.lastSaleAt
          ? calculated.occurredAt.toISOString()
          : row.lastSaleAt;

      if (calculated.isCanceled) {
        row.canceledSalesCount += 1;
        continue;
      }

      row.salesCount += 1;
      row.salesAmountCents += calculated.netAmountCents;

      const settings = this.settingsDto(employee);
      const commission = this.calculateCommissionForSale(calculated, settings);
      if (commission.eligible) {
        row.eligibleSalesCount += 1;
        row.eligibleBaseAmountCents += commission.baseAmountCents;
        row.grossProfitCents +=
          settings.commissionBase === "GROSS_PROFIT"
            ? calculated.grossProfitCents
            : 0;
        row.commissionAmountCents += commission.commissionAmountCents;
      }
      if (
        settings.commissionEnabled &&
        settings.commissionType === "PERCENTAGE" &&
        settings.commissionBase === "GROSS_PROFIT" &&
        !calculated.hasReliableCost
      ) {
        row.salesWithoutReliableCostCount += 1;
      }
    }

    return {
      employees: employeesById,
      rows: [...rows.values()],
      sales:
        collectEmployeeId == null
          ? calculatedSales
          : calculatedSales.filter((sale) => sale.employeeId === collectEmployeeId),
      salesWithoutReliableActorCount,
    };
  }

  private calculateSale(
    sale: SaleForCommission,
    employeeId: string,
  ): SaleCalculation {
    const grossAmountCents =
      sale.convertedOperationalOrder?.subtotalCents != null &&
      sale.convertedOperationalOrder.subtotalCents > 0
        ? sale.convertedOperationalOrder.subtotalCents
        : Math.max(sale.totalAmountCents, 0);
    const netAmountCents = Math.max(
      sale.convertedOperationalOrder?.totalCents != null &&
        sale.convertedOperationalOrder.totalCents > 0
        ? sale.convertedOperationalOrder.totalCents
        : sale.totalAmountCents,
      0,
    );
    const discountAmountCents = Math.max(grossAmountCents - netAmountCents, 0);
    const itemTotalCents = sum(sale.items, (item) =>
      Math.max(item.totalPriceCents, 0),
    );

    let grossProfitCents = 0;
    let itemsWithoutReliableCostCount = 0;
    for (const item of sale.items) {
      const itemNetAmountCents = this.proportionalItemNetAmount(
        item.totalPriceCents,
        itemTotalCents,
        netAmountCents,
      );
      const costTotalCents = this.reliableItemCostCents(item);
      if (costTotalCents == null) {
        itemsWithoutReliableCostCount += 1;
        continue;
      }

      grossProfitCents += Math.max(itemNetAmountCents - costTotalCents, 0);
    }

    return {
      saleId: sale.id,
      employeeId,
      occurredAt: sale.soldAt,
      receiptNumber: sale.receiptNumber,
      isCanceled: sale.status === "canceled" || sale.canceledAt != null,
      grossAmountCents,
      netAmountCents,
      discountAmountCents,
      grossProfitCents,
      hasReliableCost:
        sale.items.length > 0 && itemsWithoutReliableCostCount === 0,
      itemsWithoutReliableCostCount,
    };
  }

  private async saleEventBySaleId(companyId: string, saleIds: string[]) {
    if (saleIds.length === 0) {
      return new Map<string, { userId: string | null; occurredAt: Date }>();
    }

    const saleEvents = await prisma.syncEvent.findMany({
      where: {
        companyId,
        entity: "sale",
        status: SyncEventStatus.ACCEPTED,
        entityServerId: { in: saleIds },
      },
      select: {
        entityServerId: true,
        userId: true,
        occurredAt: true,
      },
      orderBy: { occurredAt: "asc" },
    });

    const eventsBySaleId = new Map<
      string,
      { userId: string | null; occurredAt: Date }
    >();
    for (const event of saleEvents) {
      if (
        event.entityServerId != null &&
        !eventsBySaleId.has(event.entityServerId)
      ) {
        eventsBySaleId.set(event.entityServerId, {
          userId: event.userId,
          occurredAt: event.occurredAt,
        });
      }
    }
    return eventsBySaleId;
  }

  private calculateCommissionForSale(
    sale: SaleCalculation,
    settings: CommissionSettings,
  ) {
    if (sale.isCanceled) {
      return {
        eligible: false,
        baseAmountCents: 0,
        commissionAmountCents: 0,
        ignoredReason: "SALE_CANCELED",
      };
    }
    if (!settings.commissionEnabled || settings.commissionType === "NONE") {
      return {
        eligible: false,
        baseAmountCents: 0,
        commissionAmountCents: 0,
        ignoredReason: "COMMISSION_DISABLED",
      };
    }
    if (settings.commissionType === "FIXED_PER_SALE") {
      return {
        eligible: true,
        baseAmountCents: sale.netAmountCents,
        commissionAmountCents: settings.commissionFixedCents ?? 0,
        ignoredReason: undefined,
      };
    }

    const baseAmountCents = this.baseAmountForSale(sale, settings.commissionBase);
    if (settings.commissionBase === "GROSS_PROFIT" && !sale.hasReliableCost) {
      return {
        eligible: sale.grossProfitCents > 0,
        baseAmountCents,
        commissionAmountCents: Math.floor(
          (Math.max(baseAmountCents, 0) * (settings.commissionRateBps ?? 0)) /
            10000,
        ),
        ignoredReason:
          sale.grossProfitCents > 0 ? "PARTIAL_COST_MISSING" : "COST_MISSING",
      };
    }

    return {
      eligible: true,
      baseAmountCents,
      commissionAmountCents: Math.floor(
        (Math.max(baseAmountCents, 0) * (settings.commissionRateBps ?? 0)) /
          10000,
      ),
      ignoredReason: undefined,
    };
  }

  private baseAmountForSale(
    sale: SaleCalculation,
    base: EmployeeCommissionBase,
  ) {
    switch (base) {
      case "GROSS_SALES":
        return sale.grossAmountCents;
      case "GROSS_PROFIT":
        return sale.grossProfitCents;
      case "NET_SALES":
      default:
        return sale.netAmountCents;
    }
  }

  private rowDto<TRow extends { commissionBase: string; eligibleBaseAmountCents: number; grossProfitCents: number }>(
    row: TRow,
    canViewProfitAmounts: boolean,
  ) {
    if (canViewProfitAmounts || row.commissionBase !== "GROSS_PROFIT") {
      return row;
    }
    return {
      ...row,
      eligibleBaseAmountCents: 0,
      grossProfitCents: undefined,
    };
  }

  private responseBaseAmountCents(
    baseAmountCents: number,
    settings: CommissionSettings,
    canViewProfitAmounts: boolean,
  ) {
    if (canViewProfitAmounts || settings.commissionBase !== "GROSS_PROFIT") {
      return baseAmountCents;
    }
    return 0;
  }

  private proportionalItemNetAmount(
    itemTotalPriceCents: number,
    allItemsTotalCents: number,
    saleNetAmountCents: number,
  ) {
    if (allItemsTotalCents <= 0) {
      return Math.max(itemTotalPriceCents, 0);
    }
    if (saleNetAmountCents >= allItemsTotalCents) {
      return Math.max(itemTotalPriceCents, 0);
    }
    return Math.floor(
      (Math.max(itemTotalPriceCents, 0) * Math.max(saleNetAmountCents, 0)) /
        allItemsTotalCents,
    );
  }

  private reliableItemCostCents(item: {
    quantityMil: number;
    unitCostCents: number;
    totalCostCents: number;
  }) {
    if (item.totalCostCents > 0) {
      return item.totalCostCents;
    }
    if (item.unitCostCents > 0 && item.quantityMil > 0) {
      return Math.floor((item.unitCostCents * item.quantityMil) / 1000);
    }
    return null;
  }

  private async assertCanViewEmployee(context: AppContext, employeeId: string) {
    if (this.canViewAll(context) || context.employee?.id === employeeId) {
      return;
    }

    const employee = await prisma.employeeProfile.findFirst({
      where: { id: employeeId, companyId: context.company.id },
      select: { id: true },
    });
    if (employee == null) {
      throw new AppError(
        "Funcionario nao encontrado.",
        404,
        "EMPLOYEE_NOT_FOUND",
      );
    }

    throw new AppError(
      "Voce nao tem permissao para ver comissoes de funcionarios.",
      403,
      "EMPLOYEE_COMMISSION_PERMISSION_REQUIRED",
    );
  }

  private assertCanViewAll(context: AppContext) {
    if (this.canViewAll(context)) {
      return;
    }
    throw new AppError(
      "Voce nao tem permissao para ver comissoes de funcionarios.",
      403,
      "EMPLOYEE_COMMISSION_PERMISSION_REQUIRED",
    );
  }

  private assertCanManage(context: AppContext) {
    if (
      context.membership.role === MembershipRole.OWNER ||
      context.membership.role === MembershipRole.ADMIN ||
      hasEmployeePermission(context.membership.permissions, "employees.manage")
    ) {
      return;
    }
    throw new AppError(
      "Voce nao tem permissao para configurar comissoes.",
      403,
      "EMPLOYEE_COMMISSION_MANAGE_REQUIRED",
    );
  }

  private canViewAll(context: AppContext) {
    return (
      context.membership.role === MembershipRole.OWNER ||
      context.membership.role === MembershipRole.ADMIN ||
      hasEmployeePermission(context.membership.permissions, "employees.manage") ||
      hasEmployeePermission(context.membership.permissions, "reports.advanced")
    );
  }

  private async findEmployeeOrThrow(companyId: string, employeeId: string) {
    const employee = await prisma.employeeProfile.findFirst({
      where: { id: employeeId, companyId },
      select: this.employeeSelect,
    });
    if (employee == null) {
      throw new AppError(
        "Funcionario nao encontrado.",
        404,
        "EMPLOYEE_NOT_FOUND",
      );
    }
    return employee;
  }

  private settingsDto(employee: CommissionEmployee): CommissionSettings {
    const type = this.normalizeType(employee.commissionType);
    return {
      commissionEnabled: employee.commissionEnabled,
      commissionType: employee.commissionEnabled ? type : "NONE",
      commissionBase: this.normalizeBase(employee.commissionBase),
      commissionRateBps: employee.commissionRateBps,
      commissionFixedCents: employee.commissionFixedCents,
      commissionUpdatedAt: employee.commissionUpdatedAt?.toISOString() ?? null,
    };
  }

  private normalizeType(value: string | null): EmployeeCommissionType {
    return value === "PERCENTAGE" || value === "FIXED_PER_SALE"
      ? value
      : "NONE";
  }

  private normalizeBase(value: string | null): EmployeeCommissionBase {
    switch (value) {
      case "GROSS_SALES":
      case "GROSS_PROFIT":
        return value;
      case "NET_SALES":
      default:
        return "NET_SALES";
    }
  }

  private notesForRows(rows: Array<{ salesWithoutReliableCostCount: number }>) {
    const notes = [...TRACKING_NOTES];
    if (rows.some((row) => row.salesWithoutReliableCostCount > 0)) {
      notes.push(
        "Algumas vendas nao entraram integralmente no calculo por lucro porque produtos nao tinham custo cadastrado.",
      );
    }
    return notes;
  }

  private toDateRange(query: EmployeeActivityQueryInput) {
    return {
      start: new Date(`${query.from}T00:00:00.000Z`),
      end: new Date(`${query.to}T23:59:59.999Z`),
    };
  }

  private saleDescription(receiptNumber: string | null) {
    return receiptNumber == null
      ? "Venda registrada"
      : `Venda ${receiptNumber}`;
  }

  private get employeeSelect() {
    return {
      id: true,
      userId: true,
      name: true,
      role: true,
      status: true,
      commissionEnabled: true,
      commissionType: true,
      commissionBase: true,
      commissionRateBps: true,
      commissionFixedCents: true,
      commissionUpdatedAt: true,
    } satisfies Record<keyof CommissionEmployee, true>;
  }
}

function sum<TItem>(items: TItem[], selector: (item: TItem) => number) {
  return items.reduce((total, item) => total + selector(item), 0);
}
