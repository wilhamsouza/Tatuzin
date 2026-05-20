import { MembershipRole, SyncEventStatus } from "@prisma/client";

import { prisma } from "../../database/prisma";
import type { AppContext } from "../app/app-context.types";
import { AppError } from "../../shared/http/app-error";
import { EmployeeContextService } from "./employee-context.service";
import { hasEmployeePermission } from "./employee-permissions";
import type { EmployeeActivityQueryInput } from "./employees.schemas";

type EmployeeActivityType =
  | "SALE"
  | "DISCOUNT"
  | "CANCELLATION"
  | "CASH_OPEN"
  | "CASH_CLOSE"
  | "CASH_MOVEMENT"
  | "STOCK_ADJUSTMENT";

type EmployeeActivityRow = {
  employeeId: string;
  name: string;
  role: string;
  status: string;
  salesCount: number;
  salesAmountCents: number;
  discountAmountCents: number;
  canceledSalesCount: number;
  stockAdjustmentsCount: number;
  cashActionsCount: number;
  lastActivityAt: string | null;
};

type EmployeeActivityTimelineItem = {
  id: string;
  occurredAt: string;
  type: EmployeeActivityType;
  title: string;
  description: string;
  amountCents?: number;
};

type MutableRow = Omit<EmployeeActivityRow, "lastActivityAt"> & {
  lastActivityAt: Date | null;
};

type MutableTimelineItem = Omit<EmployeeActivityTimelineItem, "occurredAt"> & {
  employeeId: string;
  occurredAt: Date;
};

type ActivityBuildResult = {
  rows: EmployeeActivityRow[];
  timeline: MutableTimelineItem[];
};

const TRACKING_NOTES = [
  "Vendas, caixa, descontos e ajustes feitos pelo aplicativo sincronizado usam o usuario do evento sincronizado.",
  "Vendas ou movimentos legados sem usuario/cash session identificavel nao entram no ranking por funcionario.",
  "Ajustes de estoque contam apenas baixas sem venda vinculada para evitar duplicar baixa automatica de venda.",
];
const MAX_TIMELINE_ITEMS = 200;

export class EmployeeActivityService {
  private readonly employeeContextService = new EmployeeContextService();

  async summary(context: AppContext, query: EmployeeActivityQueryInput) {
    this.assertCanViewAll(context);
    const range = this.toDateRange(query);
    const activity = await this.buildActivity(context.company.id, range);

    const rowsWithActivity = activity.rows.filter((row) =>
      this.hasActivity(row),
    );

    return {
      totalEmployees: activity.rows.length,
      activeEmployees: activity.rows.filter((row) => row.status === "ACTIVE")
        .length,
      employeesWithActivity: rowsWithActivity.length,
      totalSalesCount: sum(activity.rows, (row) => row.salesCount),
      totalSalesAmountCents: sum(activity.rows, (row) => row.salesAmountCents),
      totalDiscountAmountCents: sum(
        activity.rows,
        (row) => row.discountAmountCents,
      ),
      totalCanceledCount: sum(activity.rows, (row) => row.canceledSalesCount),
      totalStockAdjustments: sum(
        activity.rows,
        (row) => row.stockAdjustmentsCount,
      ),
      rows: activity.rows,
      tracking: this.trackingInfo,
    };
  }

  async detail(
    context: AppContext,
    employeeId: string,
    query: EmployeeActivityQueryInput,
  ) {
    await this.assertCanViewEmployee(context, employeeId);
    const range = this.toDateRange(query);
    const activity = await this.buildActivity(context.company.id, range, {
      collectTimelineForEmployeeId: employeeId,
    });
    const row = activity.rows.find(
      (candidate) => candidate.employeeId === employeeId,
    );

    if (row == null) {
      throw new AppError(
        "Funcionario nao encontrado.",
        404,
        "EMPLOYEE_NOT_FOUND",
      );
    }

    return {
      employee: {
        id: row.employeeId,
        name: row.name,
        role: row.role,
        status: row.status,
      },
      summary: {
        salesCount: row.salesCount,
        salesAmountCents: row.salesAmountCents,
        discountAmountCents: row.discountAmountCents,
        canceledSalesCount: row.canceledSalesCount,
        stockAdjustmentsCount: row.stockAdjustmentsCount,
        cashActionsCount: row.cashActionsCount,
        lastActivityAt: row.lastActivityAt,
      },
      timeline: activity.timeline
        .filter((item) => item.employeeId === employeeId)
        .sort(
          (first, second) =>
            second.occurredAt.getTime() - first.occurredAt.getTime(),
        )
        .slice(0, MAX_TIMELINE_ITEMS)
        .map(({ employeeId: _employeeId, occurredAt, ...item }) => ({
          ...item,
          occurredAt: occurredAt.toISOString(),
        })),
      tracking: this.trackingInfo,
    };
  }

  private async buildActivity(
    companyId: string,
    range: { start: Date; end: Date },
    options: { collectTimelineForEmployeeId?: string } = {},
  ): Promise<ActivityBuildResult> {
    await this.employeeContextService.ensureOwnerProfilesForCompany(companyId);

    const employees = await prisma.employeeProfile.findMany({
      where: { companyId },
      select: {
        id: true,
        userId: true,
        name: true,
        role: true,
        status: true,
      },
      orderBy: [{ role: "asc" }, { name: "asc" }, { createdAt: "asc" }],
    });

    const rows = new Map<string, MutableRow>();
    const employeeIdByUserId = new Map<string, string>();

    for (const employee of employees) {
      rows.set(employee.id, {
        employeeId: employee.id,
        name: employee.name,
        role: employee.role,
        status: employee.status,
        salesCount: 0,
        salesAmountCents: 0,
        discountAmountCents: 0,
        canceledSalesCount: 0,
        stockAdjustmentsCount: 0,
        cashActionsCount: 0,
        lastActivityAt: null,
      });

      if (employee.userId != null) {
        employeeIdByUserId.set(employee.userId, employee.id);
      }
    }

    const timeline: MutableTimelineItem[] = [];
    const actorForUser = (userId: string | null | undefined) =>
      userId == null ? null : (employeeIdByUserId.get(userId) ?? null);

    const addTimeline = (
      employeeId: string | null,
      item: Omit<MutableTimelineItem, "employeeId">,
    ) => {
      if (employeeId == null) {
        return;
      }
      const row = rows.get(employeeId);
      if (row == null) {
        return;
      }
      this.markLastActivity(row, item.occurredAt);
      if (options.collectTimelineForEmployeeId !== employeeId) {
        return;
      }
      timeline.push({ ...item, employeeId });
    };

    const saleEvents = await prisma.syncEvent.findMany({
      where: {
        companyId,
        entity: "sale",
        status: SyncEventStatus.ACCEPTED,
        occurredAt: { gte: range.start, lte: range.end },
        entityServerId: { not: null },
      },
      select: {
        entityServerId: true,
        userId: true,
        occurredAt: true,
      },
      orderBy: { occurredAt: "asc" },
    });

    const saleEventBySaleId = new Map<
      string,
      { userId: string; occurredAt: Date }
    >();
    for (const event of saleEvents) {
      if (
        event.entityServerId != null &&
        !saleEventBySaleId.has(event.entityServerId)
      ) {
        saleEventBySaleId.set(event.entityServerId, {
          userId: event.userId,
          occurredAt: event.occurredAt,
        });
      }
    }

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
          select: { sellerUserId: true },
        },
      },
    });

    for (const sale of sales) {
      const event = saleEventBySaleId.get(sale.id);
      const employeeId = actorForUser(
        sale.convertedOperationalOrder?.sellerUserId ??
          event?.userId ??
          sale.cashSession?.userId,
      );
      if (employeeId == null) {
        continue;
      }
      const row = rows.get(employeeId);
      if (row == null) {
        continue;
      }

      const isCanceled = sale.status === "canceled" || sale.canceledAt != null;
      if (isCanceled) {
        row.canceledSalesCount += 1;
        addTimeline(employeeId, {
          id: `sale-cancelled:${sale.id}`,
          occurredAt: sale.canceledAt ?? sale.soldAt,
          type: "CANCELLATION",
          title: "Venda cancelada",
          description: this.saleDescription(sale.receiptNumber),
          amountCents: sale.totalAmountCents,
        });
      } else {
        row.salesCount += 1;
        row.salesAmountCents += sale.totalAmountCents;
        addTimeline(employeeId, {
          id: `sale:${sale.id}`,
          occurredAt: sale.soldAt,
          type: "SALE",
          title: "Venda realizada",
          description: this.saleDescription(sale.receiptNumber),
          amountCents: sale.totalAmountCents,
        });
      }
    }

    const discountedOrders = await prisma.operationalOrder.findMany({
      where: {
        companyId,
        discountCents: { gt: 0 },
        sellerUserId: { not: null },
        updatedAt: { gte: range.start, lte: range.end },
      },
      select: {
        id: true,
        sellerUserId: true,
        discountCents: true,
        updatedAt: true,
      },
    });

    for (const order of discountedOrders) {
      const employeeId = actorForUser(order.sellerUserId);
      const row = employeeId == null ? null : rows.get(employeeId);
      if (employeeId == null || row == null) {
        continue;
      }
      row.discountAmountCents += order.discountCents;
      addTimeline(employeeId, {
        id: `discount:${order.id}`,
        occurredAt: order.updatedAt,
        type: "DISCOUNT",
        title: "Desconto aplicado",
        description: "Desconto em venda/atendimento",
        amountCents: order.discountCents,
      });
    }

    const cancelledOrders = await prisma.operationalOrder.findMany({
      where: {
        companyId,
        sellerUserId: { not: null },
        OR: [{ status: "cancelled" }, { cancelledAt: { not: null } }],
        updatedAt: { gte: range.start, lte: range.end },
      },
      select: {
        id: true,
        sellerUserId: true,
        cancelledAt: true,
        updatedAt: true,
        totalCents: true,
      },
    });

    for (const order of cancelledOrders) {
      const employeeId = actorForUser(order.sellerUserId);
      const row = employeeId == null ? null : rows.get(employeeId);
      if (employeeId == null || row == null) {
        continue;
      }
      row.canceledSalesCount += 1;
      addTimeline(employeeId, {
        id: `order-cancelled:${order.id}`,
        occurredAt: order.cancelledAt ?? order.updatedAt,
        type: "CANCELLATION",
        title: "Atendimento cancelado",
        description: "Cancelamento registrado no atendimento",
        amountCents: order.totalCents,
      });
    }

    const cashSessions = await prisma.cashSession.findMany({
      where: {
        companyId,
        userId: { not: null },
        OR: [
          { openedAt: { gte: range.start, lte: range.end } },
          { closedAt: { gte: range.start, lte: range.end } },
        ],
      },
      select: {
        id: true,
        userId: true,
        openedAt: true,
        closedAt: true,
        openingBalanceCents: true,
        closingBalanceCents: true,
      },
    });

    for (const session of cashSessions) {
      const employeeId = actorForUser(session.userId);
      const row = employeeId == null ? null : rows.get(employeeId);
      if (employeeId == null || row == null) {
        continue;
      }

      if (this.isInsideRange(session.openedAt, range)) {
        row.cashActionsCount += 1;
        addTimeline(employeeId, {
          id: `cash-open:${session.id}`,
          occurredAt: session.openedAt!,
          type: "CASH_OPEN",
          title: "Caixa aberto",
          description: "Abertura de caixa",
          amountCents: session.openingBalanceCents,
        });
      }

      if (this.isInsideRange(session.closedAt, range)) {
        row.cashActionsCount += 1;
        addTimeline(employeeId, {
          id: `cash-close:${session.id}`,
          occurredAt: session.closedAt!,
          type: "CASH_CLOSE",
          title: "Caixa fechado",
          description: "Fechamento de caixa",
          amountCents: session.closingBalanceCents ?? undefined,
        });
      }
    }

    await this.addCashMovementActivity(
      companyId,
      range,
      actorForUser,
      rows,
      addTimeline,
    );
    await this.addStockAdjustmentActivity(
      companyId,
      range,
      actorForUser,
      rows,
      addTimeline,
    );

    return {
      rows: [...rows.values()].map((row) => ({
        ...row,
        lastActivityAt: row.lastActivityAt?.toISOString() ?? null,
      })),
      timeline,
    };
  }

  private async addCashMovementActivity(
    companyId: string,
    range: { start: Date; end: Date },
    actorForUser: (userId: string | null | undefined) => string | null,
    rows: Map<string, MutableRow>,
    addTimeline: (
      employeeId: string | null,
      item: Omit<MutableTimelineItem, "employeeId">,
    ) => void,
  ) {
    const events = await prisma.syncEvent.findMany({
      where: {
        companyId,
        entity: "cashMovement",
        status: SyncEventStatus.ACCEPTED,
        occurredAt: { gte: range.start, lte: range.end },
        entityServerId: { not: null },
      },
      select: {
        entityServerId: true,
        userId: true,
        occurredAt: true,
      },
      orderBy: { occurredAt: "asc" },
    });

    const eventByCashEventId = new Map<
      string,
      { userId: string; occurredAt: Date }
    >();
    for (const event of events) {
      if (
        event.entityServerId != null &&
        !eventByCashEventId.has(event.entityServerId)
      ) {
        eventByCashEventId.set(event.entityServerId, {
          userId: event.userId,
          occurredAt: event.occurredAt,
        });
      }
    }

    if (eventByCashEventId.size === 0) {
      return;
    }

    const cashEvents = await prisma.cashEvent.findMany({
      where: {
        companyId,
        id: { in: [...eventByCashEventId.keys()] },
      },
      select: {
        id: true,
        eventType: true,
        amountCents: true,
        createdAt: true,
      },
    });

    for (const cashEvent of cashEvents) {
      const event = eventByCashEventId.get(cashEvent.id);
      const employeeId = actorForUser(event?.userId);
      const row = employeeId == null ? null : rows.get(employeeId);
      if (employeeId == null || row == null) {
        continue;
      }
      row.cashActionsCount += 1;
      addTimeline(employeeId, {
        id: `cash-movement:${cashEvent.id}`,
        occurredAt: event?.occurredAt ?? cashEvent.createdAt,
        type: "CASH_MOVEMENT",
        title: this.cashMovementTitle(cashEvent.eventType),
        description: "Movimentacao de caixa",
        amountCents: cashEvent.amountCents,
      });
    }
  }

  private async addStockAdjustmentActivity(
    companyId: string,
    range: { start: Date; end: Date },
    actorForUser: (userId: string | null | undefined) => string | null,
    rows: Map<string, MutableRow>,
    addTimeline: (
      employeeId: string | null,
      item: Omit<MutableTimelineItem, "employeeId">,
    ) => void,
  ) {
    const events = await prisma.syncEvent.findMany({
      where: {
        companyId,
        entity: "stockDeduction",
        status: SyncEventStatus.ACCEPTED,
        occurredAt: { gte: range.start, lte: range.end },
        entityServerId: { not: null },
      },
      select: {
        entityServerId: true,
        userId: true,
        occurredAt: true,
      },
      orderBy: { occurredAt: "asc" },
    });

    const eventByDeductionId = new Map<
      string,
      { userId: string; occurredAt: Date }
    >();
    for (const event of events) {
      if (
        event.entityServerId != null &&
        !eventByDeductionId.has(event.entityServerId)
      ) {
        eventByDeductionId.set(event.entityServerId, {
          userId: event.userId,
          occurredAt: event.occurredAt,
        });
      }
    }

    if (eventByDeductionId.size === 0) {
      return;
    }

    const deductions = await prisma.stockDeduction.findMany({
      where: {
        companyId,
        id: { in: [...eventByDeductionId.keys()] },
        saleId: null,
      },
      select: {
        id: true,
        productId: true,
        quantityMil: true,
        createdAt: true,
      },
    });

    for (const deduction of deductions) {
      const event = eventByDeductionId.get(deduction.id);
      const employeeId = actorForUser(event?.userId);
      const row = employeeId == null ? null : rows.get(employeeId);
      if (employeeId == null || row == null) {
        continue;
      }
      row.stockAdjustmentsCount += 1;
      addTimeline(employeeId, {
        id: `stock-adjustment:${deduction.id}`,
        occurredAt: event?.occurredAt ?? deduction.createdAt,
        type: "STOCK_ADJUSTMENT",
        title: "Ajuste de estoque",
        description: "Baixa manual de estoque",
      });
    }
  }

  private async assertCanViewEmployee(context: AppContext, employeeId: string) {
    if (this.canViewAll(context)) {
      return;
    }

    if (context.employee?.id === employeeId) {
      return;
    }

    const employee = await prisma.employeeProfile.findFirst({
      where: {
        id: employeeId,
        companyId: context.company.id,
      },
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
      "Voce nao tem permissao para ver atividade de funcionarios.",
      403,
      "EMPLOYEE_ACTIVITY_PERMISSION_REQUIRED",
    );
  }

  private assertCanViewAll(context: AppContext) {
    if (this.canViewAll(context)) {
      return;
    }
    throw new AppError(
      "Voce nao tem permissao para ver atividade de funcionarios.",
      403,
      "EMPLOYEE_ACTIVITY_PERMISSION_REQUIRED",
    );
  }

  private canViewAll(context: AppContext) {
    if (this.isDisabledEmployeeContext(context)) {
      return false;
    }
    return (
      context.membership.role === MembershipRole.OWNER ||
      context.membership.role === MembershipRole.ADMIN ||
      hasEmployeePermission(
        context.membership.permissions,
        "employees.manage",
      ) ||
      hasEmployeePermission(context.membership.permissions, "reports.advanced")
    );
  }

  private isDisabledEmployeeContext(context: AppContext) {
    const status = context.employee?.status.trim().toUpperCase();
    return status != null && status !== "ACTIVE" && status !== "INVITED";
  }

  private toDateRange(query: EmployeeActivityQueryInput) {
    return {
      start: new Date(`${query.from}T00:00:00.000Z`),
      end: new Date(`${query.to}T23:59:59.999Z`),
    };
  }

  private markLastActivity(row: MutableRow, occurredAt: Date) {
    if (row.lastActivityAt == null || occurredAt > row.lastActivityAt) {
      row.lastActivityAt = occurredAt;
    }
  }

  private hasActivity(row: EmployeeActivityRow) {
    return (
      row.salesCount > 0 ||
      row.salesAmountCents > 0 ||
      row.discountAmountCents > 0 ||
      row.canceledSalesCount > 0 ||
      row.stockAdjustmentsCount > 0 ||
      row.cashActionsCount > 0 ||
      row.lastActivityAt != null
    );
  }

  private isInsideRange(
    value: Date | null,
    range: { start: Date; end: Date },
  ): value is Date {
    return value != null && value >= range.start && value <= range.end;
  }

  private saleDescription(receiptNumber: string | null) {
    return receiptNumber == null
      ? "Venda registrada"
      : `Venda ${receiptNumber}`;
  }

  private cashMovementTitle(eventType: string) {
    switch (eventType) {
      case "cash_withdrawal":
      case "withdrawal":
        return "Sangria registrada";
      case "cash_supply":
      case "supply":
        return "Suprimento registrado";
      default:
        return "Movimentacao de caixa";
    }
  }

  private get trackingInfo() {
    return {
      partial: true,
      notes: TRACKING_NOTES,
    };
  }
}

function sum<TItem>(items: TItem[], selector: (item: TItem) => number) {
  return items.reduce((total, item) => total + selector(item), 0);
}
