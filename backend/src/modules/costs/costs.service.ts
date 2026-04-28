import type { Cost, Prisma } from '@prisma/client';

import { prisma } from '../../database/prisma';
import { AppError } from '../../shared/http/app-error';
import { toPaginationParams } from '../../shared/http/pagination';
import type {
  CostCancelInput,
  CostCreateInput,
  CostListQueryInput,
  CostPayInput,
  CostSummaryQueryInput,
  CostUpdateInput,
} from './costs.schemas';

export class CostsService {
  async listForCompany(companyId: string, query: CostListQueryInput) {
    const where = this.buildListWhere(companyId, query);
    const { skip, take } = toPaginationParams(query);

    const [total, items] = await prisma.$transaction([
      prisma.cost.count({ where }),
      prisma.cost.findMany({
        where,
        skip,
        take,
        orderBy: [{ referenceDate: 'desc' }, { updatedAt: 'desc' }],
      }),
    ]);

    return {
      items: items.map((item) => this.toDto(item)),
      total,
    };
  }

  async summaryForCompany(companyId: string, query: CostSummaryQueryInput) {
    const { start, end } = this.resolveRange(query);
    const today = this.startOfDay(new Date());

    const costs = await prisma.cost.findMany({
      where: {
        companyId,
        OR: [
          {
            referenceDate: {
              gte: start,
              lt: end,
            },
          },
          {
            paidAt: {
              gte: start,
              lt: end,
            },
          },
        ],
      },
    });

    return costs.reduce(
      (summary, cost) => {
        if (cost.status === 'pending') {
          if (cost.type === 'fixed') {
            summary.pendingFixedCents += cost.amountCents;
            summary.openFixedCount += 1;
            if (cost.referenceDate < today) {
              summary.overdueFixedCents += cost.amountCents;
            }
          } else {
            summary.pendingVariableCents += cost.amountCents;
            summary.openVariableCount += 1;
            if (cost.referenceDate < today) {
              summary.overdueVariableCents += cost.amountCents;
            }
          }
        }

        if (
          cost.status === 'paid' &&
          cost.paidAt != null &&
          cost.paidAt >= start &&
          cost.paidAt < end
        ) {
          if (cost.type === 'fixed') {
            summary.paidFixedThisMonthCents += cost.amountCents;
          } else {
            summary.paidVariableThisMonthCents += cost.amountCents;
          }
        }

        return summary;
      },
      {
        pendingFixedCents: 0,
        pendingVariableCents: 0,
        overdueFixedCents: 0,
        overdueVariableCents: 0,
        paidFixedThisMonthCents: 0,
        paidVariableThisMonthCents: 0,
        openFixedCount: 0,
        openVariableCount: 0,
      },
    );
  }

  async create(companyId: string, input: CostCreateInput) {
    const existing = await prisma.cost.findFirst({
      where: { companyId, localUuid: input.localUuid },
    });

    if (existing) {
      return this.toDto(existing);
    }

    const cost = await prisma.cost.create({
      data: {
        companyId,
        localUuid: input.localUuid,
        description: input.description,
        type: input.type,
        category: input.category,
        amountCents: input.amountCents,
        referenceDate: input.referenceDate,
        notes: input.notes,
        isRecurring: input.isRecurring,
        status: 'pending',
      },
    });

    return this.toDto(cost);
  }

  async update(companyId: string, id: string, input: CostUpdateInput) {
    const existing = await this.findOwned(companyId, id);

    if (existing.status === 'canceled') {
      throw new AppError(
        'Custos cancelados nao podem ser editados.',
        409,
        'COST_CANCELED',
      );
    }
    if (existing.status === 'paid') {
      throw new AppError(
        'Custos pagos nao podem ser editados nesta etapa.',
        409,
        'COST_PAID_EDIT_BLOCKED',
      );
    }

    const data: Prisma.CostUpdateInput = {
      ...(input.description === undefined
        ? {}
        : { description: input.description }),
      ...(input.type === undefined ? {} : { type: input.type }),
      ...(input.category === undefined ? {} : { category: input.category }),
      ...(input.amountCents === undefined
        ? {}
        : { amountCents: input.amountCents }),
      ...(input.referenceDate === undefined
        ? {}
        : { referenceDate: input.referenceDate }),
      ...(input.notes === undefined ? {} : { notes: input.notes }),
      ...(input.isRecurring === undefined
        ? {}
        : { isRecurring: input.isRecurring }),
    };

    const cost = await prisma.cost.update({
      where: { id: existing.id },
      data,
    });

    return this.toDto(cost);
  }

  async cancel(companyId: string, id: string, input: CostCancelInput) {
    const existing = await this.findOwned(companyId, id);
    if (existing.status === 'paid') {
      throw new AppError(
        'Custos pagos nao podem ser cancelados nesta etapa.',
        409,
        'COST_PAID_CANCEL_BLOCKED',
      );
    }
    if (existing.status === 'canceled') {
      return this.toDto(existing);
    }

    const canceledAt = input.canceledAt ?? new Date();
    const cost = await prisma.cost.update({
      where: { id: existing.id },
      data: {
        status: 'canceled',
        canceledAt,
        notes: this.mergeNotes(existing.notes, input.notes),
      },
    });

    return this.toDto(cost);
  }

  async pay(companyId: string, id: string, input: CostPayInput) {
    const existing = await this.findOwned(companyId, id);
    if (existing.status === 'canceled') {
      throw new AppError(
        'Custos cancelados nao podem ser pagos.',
        409,
        'COST_CANCELED_PAY_BLOCKED',
      );
    }
    if (existing.status === 'paid') {
      return this.toDto(existing);
    }

    const cost = await prisma.cost.update({
      where: { id: existing.id },
      data: {
        status: 'paid',
        paidAt: input.paidAt,
        paymentMethod: input.paymentMethod,
        notes: this.mergeNotes(existing.notes, input.notes),
      },
    });

    return this.toDto(cost);
  }

  private async findOwned(companyId: string, id: string) {
    const cost = await prisma.cost.findFirst({
      where: { id, companyId },
    });
    if (!cost) {
      throw new AppError('Custo nao encontrado.', 404, 'COST_NOT_FOUND');
    }
    return cost;
  }

  private buildListWhere(
    companyId: string,
    query: CostListQueryInput,
  ): Prisma.CostWhereInput {
    const where: Prisma.CostWhereInput = { companyId };
    if (query.type != null) {
      where.type = query.type;
    }
    if (query.status != null) {
      where.status = query.status;
    }

    const startDate = query.startDate == null ? null : new Date(query.startDate);
    const endDate = query.endDate == null ? null : new Date(query.endDate);
    if (startDate != null || endDate != null) {
      where.referenceDate = {
        ...(startDate == null ? {} : { gte: startDate }),
        ...(endDate == null ? {} : { lte: endDate }),
      };
    }

    if (query.overdueOnly) {
      where.status = 'pending';
      where.referenceDate = {
        ...((where.referenceDate as Prisma.DateTimeFilter | undefined) ?? {}),
        lt: this.startOfDay(new Date()),
      };
    }

    return where;
  }

  private resolveRange(query: CostSummaryQueryInput) {
    const now = new Date();
    const start =
      query.startDate == null
        ? new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1))
        : new Date(query.startDate);
    const end =
      query.endDate == null
        ? new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1))
        : new Date(query.endDate);
    return { start, end };
  }

  private startOfDay(date: Date) {
    return new Date(
      Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()),
    );
  }

  private mergeNotes(current: string | null, next: string | null) {
    if (next == null || next.trim().length === 0) {
      return current;
    }
    if (current == null || current.trim().length === 0) {
      return next.trim();
    }
    return `${current}\n${next.trim()}`;
  }

  private toDto(cost: Cost) {
    return {
      id: cost.id,
      localUuid: cost.localUuid,
      description: cost.description,
      type: cost.type,
      category: cost.category,
      amountCents: cost.amountCents,
      referenceDate: cost.referenceDate.toISOString(),
      status: cost.status,
      isRecurring: cost.isRecurring,
      paidAt: cost.paidAt?.toISOString() ?? null,
      paymentMethod: cost.paymentMethod,
      notes: cost.notes,
      canceledAt: cost.canceledAt?.toISOString() ?? null,
      createdAt: cost.createdAt.toISOString(),
      updatedAt: cost.updatedAt.toISOString(),
    };
  }
}

