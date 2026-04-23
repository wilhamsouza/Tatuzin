import {
  CustomerTaskStatus,
  CustomerTimelineEventType,
  type Prisma,
} from '@prisma/client';

import { prisma } from '../../database/prisma';
import { buildAdminListResponse } from '../../shared/http/api-response';
import { AppError } from '../../shared/http/app-error';
import { toPaginationParams } from '../../shared/http/pagination';
import type {
  CrmCustomerContextQueryInput,
  CrmCustomerNoteCreateInput,
  CrmCustomerTagsApplyInput,
  CrmCustomerTaskCreateInput,
  CrmCustomerTimelineQueryInput,
  CrmCustomersListQueryInput,
} from './crm.schemas';

export class CrmService {
  async listCustomersWithCommercialContext(query: CrmCustomersListQueryInput) {
    const where = this.buildCustomerWhere(query);
    const { skip, take } = toPaginationParams(query);

    const [total, customers] = await prisma.$transaction([
      prisma.customer.count({ where }),
      prisma.customer.findMany({
        where,
        skip,
        take,
        orderBy: this.resolveCustomerOrderBy(query),
        include: {
          crmTagAssignments: {
            include: {
              tag: true,
            },
            orderBy: { createdAt: 'desc' },
          },
        },
      }),
    ]);

    const customerIds = customers.map((customer) => customer.id);
    const contextMap = await this.buildCommercialContextMap(
      query.companyId,
      customerIds,
    );

    const items = customers.map((customer) =>
      this.toCustomerSummaryDto(customer, contextMap.get(customer.id)),
    );

    return buildAdminListResponse({
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      filters: {
        companyId: query.companyId,
        search: query.search ?? null,
        tag: query.tag ?? null,
      },
      sort: {
        by: query.sortBy,
        direction: query.sortDirection,
      },
    });
  }

  async getCustomerDetail(
    customerId: string,
    query: CrmCustomerContextQueryInput,
  ) {
    const customer = await prisma.customer.findFirst({
      where: {
        id: customerId,
        companyId: query.companyId,
        deletedAt: null,
      },
      include: {
        crmTagAssignments: {
          include: {
            tag: true,
          },
          orderBy: { createdAt: 'desc' },
        },
        crmNotes: {
          include: {
            authorUser: {
              select: {
                id: true,
                name: true,
                email: true,
              },
            },
          },
          orderBy: { createdAt: 'desc' },
          take: 40,
        },
        crmTasks: {
          include: {
            createdByUser: {
              select: {
                id: true,
                name: true,
                email: true,
              },
            },
            assignedToUser: {
              select: {
                id: true,
                name: true,
                email: true,
              },
            },
          },
          orderBy: [{ status: 'asc' }, { dueAt: 'asc' }, { createdAt: 'desc' }],
          take: 60,
        },
      },
    });

    if (!customer) {
      throw new AppError('Cliente CRM nao encontrado.', 404, 'CRM_CUSTOMER_NOT_FOUND');
    }

    const contextMap = await this.buildCommercialContextMap(query.companyId, [
      customer.id,
    ]);

    return {
      customer: this.toCustomerSummaryDto(customer, contextMap.get(customer.id)),
      notes: customer.crmNotes.map((note) => this.toCustomerNoteDto(note)),
      tasks: customer.crmTasks.map((task) => this.toCustomerTaskDto(task)),
    };
  }

  async getCustomerTimeline(
    customerId: string,
    query: CrmCustomerTimelineQueryInput,
  ) {
    await this.ensureCustomerForCompany(query.companyId, customerId);

    const [crmEvents, sales, fiadoPayments] = await Promise.all([
      prisma.customerTimelineEvent.findMany({
        where: {
          companyId: query.companyId,
          customerId,
        },
        include: {
          actorUser: {
            select: {
              id: true,
              name: true,
              email: true,
            },
          },
        },
        orderBy: { createdAt: 'desc' },
      }),
      prisma.sale.findMany({
        where: {
          companyId: query.companyId,
          customerId,
          status: 'active',
        },
        orderBy: { soldAt: 'desc' },
        select: {
          id: true,
          receiptNumber: true,
          paymentType: true,
          paymentMethod: true,
          totalAmountCents: true,
          totalCostCents: true,
          soldAt: true,
        },
      }),
      prisma.fiadoPayment.findMany({
        where: {
          companyId: query.companyId,
          sale: {
            customerId,
          },
        },
        orderBy: { createdAt: 'desc' },
        select: {
          id: true,
          amountCents: true,
          paymentMethod: true,
          createdAt: true,
          saleId: true,
        },
      }),
    ]);

    const mergedEvents = [
      ...crmEvents.map((event) => this.toCrmTimelineEventDto(event)),
      ...sales.map((sale) => ({
        id: `sale:${sale.id}`,
        source: 'sales',
        eventType: 'sale_recorded',
        occurredAt: sale.soldAt.toISOString(),
        headline: 'Venda sincronizada',
        body: (() => {
          const parts = [
            sale.paymentType,
            sale.paymentMethod,
            sale.receiptNumber == null ? null : `cupom ${sale.receiptNumber}`,
          ].filter((item): item is string => item != null && item.trim().length > 0);

          return parts.length === 0 ? null : parts.join(' | ');
        })(),
        actor: null,
        amountCents: sale.totalAmountCents,
        metadata: {
          saleId: sale.id,
          totalCostCents: sale.totalCostCents,
        },
      })),
      ...fiadoPayments.map((payment) => ({
        id: `fiado_payment:${payment.id}`,
        source: 'sales',
        eventType: 'fiado_payment_received',
        occurredAt: payment.createdAt.toISOString(),
        headline: 'Recebimento de fiado sincronizado',
        body: payment.paymentMethod,
        actor: null,
        amountCents: payment.amountCents,
        metadata: {
          saleId: payment.saleId,
        },
      })),
    ].sort(
      (left, right) =>
        new Date(right.occurredAt).getTime() - new Date(left.occurredAt).getTime(),
    );

    const { skip, take } = toPaginationParams(query);
    const items = mergedEvents.slice(skip, skip + take);

    return buildAdminListResponse({
      items,
      page: query.page,
      pageSize: query.pageSize,
      total: mergedEvents.length,
      filters: {
        companyId: query.companyId,
        customerId,
      },
      sort: {
        by: 'occurredAt',
        direction: 'desc',
      },
    });
  }

  async createCustomerNote(
    customerId: string,
    input: CrmCustomerNoteCreateInput,
    actorUserId: string,
  ) {
    await this.ensureCustomerForCompany(input.companyId, customerId);

    const note = await prisma.$transaction(async (tx) => {
      const created = await tx.customerNote.create({
        data: {
          companyId: input.companyId,
          customerId,
          authorUserId: actorUserId,
          body: input.body,
        },
        include: {
          authorUser: {
            select: {
              id: true,
              name: true,
              email: true,
            },
          },
        },
      });

      await tx.customerTimelineEvent.create({
        data: {
          companyId: input.companyId,
          customerId,
          actorUserId,
          eventType: CustomerTimelineEventType.NOTE_ADDED,
          headline: 'Nota CRM adicionada',
          body: input.body,
          metadata: {
            noteId: created.id,
          },
        },
      });

      return created;
    });

    return { note: this.toCustomerNoteDto(note) };
  }

  async createCustomerTask(
    customerId: string,
    input: CrmCustomerTaskCreateInput,
    actorUserId: string,
  ) {
    await this.ensureCustomerForCompany(input.companyId, customerId);
    await this.ensureAssignableUser(input.assignedToUserId);

    const task = await prisma.$transaction(async (tx) => {
      const created = await tx.customerTask.create({
        data: {
          companyId: input.companyId,
          customerId,
          createdByUserId: actorUserId,
          assignedToUserId: input.assignedToUserId,
          title: input.title,
          description: input.description,
          status: CustomerTaskStatus.OPEN,
          dueAt: input.dueAt,
        },
        include: {
          createdByUser: {
            select: {
              id: true,
              name: true,
              email: true,
            },
          },
          assignedToUser: {
            select: {
              id: true,
              name: true,
              email: true,
            },
          },
        },
      });

      await tx.customerTimelineEvent.create({
        data: {
          companyId: input.companyId,
          customerId,
          actorUserId,
          eventType: CustomerTimelineEventType.TASK_CREATED,
          headline: input.title,
          body: input.description,
          metadata: {
            taskId: created.id,
            dueAt: created.dueAt?.toISOString() ?? null,
            assignedToUserId: created.assignedToUserId,
          },
        },
      });

      return created;
    });

    return { task: this.toCustomerTaskDto(task) };
  }

  async applyCustomerTags(
    customerId: string,
    input: CrmCustomerTagsApplyInput,
    actorUserId: string,
  ) {
    await this.ensureCustomerForCompany(input.companyId, customerId);

    const normalizedInputs = deduplicateTagInputs(input.tags);

    const result = await prisma.$transaction(async (tx) => {
      const tags = [];
      for (const tagInput of normalizedInputs) {
        const tag = await tx.customerTag.upsert({
          where: {
            companyId_normalizedLabel: {
              companyId: input.companyId,
              normalizedLabel: tagInput.normalizedLabel,
            },
          },
          update: {
            label: tagInput.label,
            color: tagInput.color,
          },
          create: {
            companyId: input.companyId,
            label: tagInput.label,
            normalizedLabel: tagInput.normalizedLabel,
            color: tagInput.color,
          },
        });
        tags.push(tag);
      }

      if (input.mode === 'replace') {
        await tx.customerTagAssignment.deleteMany({
          where: {
            companyId: input.companyId,
            customerId,
            ...(tags.length === 0
                ? {}
                : {
                    tagId: {
                      notIn: tags.map((tag) => tag.id),
                    },
                  }),
          },
        });
      }

      if (tags.length > 0) {
        await tx.customerTagAssignment.createMany({
          data: tags.map((tag) => ({
            companyId: input.companyId,
            customerId,
            tagId: tag.id,
            assignedByUserId: actorUserId,
          })),
          skipDuplicates: true,
        });
      }

      const assignments = await tx.customerTagAssignment.findMany({
        where: {
          companyId: input.companyId,
          customerId,
        },
        include: {
          tag: true,
        },
        orderBy: { createdAt: 'desc' },
      });

      await tx.customerTimelineEvent.create({
        data: {
          companyId: input.companyId,
          customerId,
          actorUserId,
          eventType: CustomerTimelineEventType.TAGS_UPDATED,
          headline: 'Tags CRM atualizadas',
          body:
            assignments.length == 0
              ? 'Cliente sem tags ativas.'
              : assignments.map((assignment) => assignment.tag.label).join(', '),
          metadata: {
            mode: input.mode,
            tags: assignments.map((assignment) => ({
              id: assignment.tag.id,
              label: assignment.tag.label,
              color: assignment.tag.color,
            })),
          },
        },
      });

      return assignments;
    });

    return {
      tags: result.map((assignment) => this.toCustomerTagDto(assignment)),
    };
  }

  private buildCustomerWhere(query: CrmCustomersListQueryInput) {
    const filters: Prisma.CustomerWhereInput[] = [
      {
        companyId: query.companyId,
        deletedAt: null,
      },
    ];

    if (query.search != null) {
      filters.push({
        OR: [
          { name: { contains: query.search, mode: 'insensitive' } },
          { phone: { contains: query.search, mode: 'insensitive' } },
          { address: { contains: query.search, mode: 'insensitive' } },
          { notes: { contains: query.search, mode: 'insensitive' } },
        ],
      });
    }

    if (query.tag != null) {
      filters.push({
        crmTagAssignments: {
          some: {
            tag: {
              normalizedLabel: normalizeTagLabel(query.tag),
            },
          },
        },
      });
    }

    return {
      AND: filters,
    } satisfies Prisma.CustomerWhereInput;
  }

  private resolveCustomerOrderBy(
    query: Pick<CrmCustomersListQueryInput, 'sortBy' | 'sortDirection'>,
  ): Prisma.CustomerOrderByWithRelationInput[] {
    switch (query.sortBy) {
      case 'name':
        return [{ name: query.sortDirection }, { updatedAt: 'desc' }];
      case 'createdAt':
        return [{ createdAt: query.sortDirection }, { name: 'asc' }];
      default:
        return [{ updatedAt: query.sortDirection }, { name: 'asc' }];
    }
  }

  private async buildCommercialContextMap(companyId: string, customerIds: string[]) {
    if (customerIds.length === 0) {
      return new Map<string, CommercialContext>();
    }

    const [sales, fiadoPayments, tasks, timelineEvents] = await prisma.$transaction([
      prisma.sale.groupBy({
        by: ['customerId'],
        orderBy: {
          customerId: 'asc',
        },
        where: {
          companyId,
          status: 'active',
          customerId: {
            in: customerIds,
          },
        },
        _count: {
          id: true,
        },
        _sum: {
          totalAmountCents: true,
          totalCostCents: true,
        },
        _max: {
          soldAt: true,
        },
      }),
      prisma.fiadoPayment.findMany({
        where: {
          companyId,
          sale: {
            customerId: {
              in: customerIds,
            },
          },
        },
        select: {
          amountCents: true,
          createdAt: true,
          sale: {
            select: {
              customerId: true,
            },
          },
        },
      }),
      prisma.customerTask.findMany({
        where: {
          companyId,
          customerId: {
            in: customerIds,
          },
        },
        select: {
          customerId: true,
          status: true,
          dueAt: true,
        },
      }),
      prisma.customerTimelineEvent.findMany({
        where: {
          companyId,
          customerId: {
            in: customerIds,
          },
        },
        select: {
          customerId: true,
          createdAt: true,
        },
        orderBy: { createdAt: 'desc' },
      }),
    ]);

    const map = new Map<string, CommercialContext>();
    const now = Date.now();

    for (const sale of sales) {
      if (sale.customerId == null) {
        continue;
      }

      const totalSalesCount =
        typeof sale._count === 'object' &&
        sale._count != null &&
        'id' in sale._count &&
        typeof sale._count.id === 'number'
          ? sale._count.id
          : 0;

      map.set(sale.customerId, {
        ...(map.get(sale.customerId) ?? createEmptyCommercialContext()),
        totalSalesCount,
        totalRevenueCents: sale._sum?.totalAmountCents ?? 0,
        totalProfitCents:
          (sale._sum?.totalAmountCents ?? 0) - (sale._sum?.totalCostCents ?? 0),
        lastSaleAt: sale._max?.soldAt?.toISOString() ?? null,
      });
    }

    for (const payment of fiadoPayments) {
      const customerId = payment.sale.customerId;
      if (customerId == null) {
        continue;
      }

      const current = map.get(customerId) ?? createEmptyCommercialContext();
      current.totalFiadoPaymentsCents += payment.amountCents;
      if (
        current.lastFiadoPaymentAt == null ||
        payment.createdAt.getTime() > new Date(current.lastFiadoPaymentAt).getTime()
      ) {
        current.lastFiadoPaymentAt = payment.createdAt.toISOString();
      }
      map.set(customerId, current);
    }

    for (const task of tasks) {
      const current = map.get(task.customerId) ?? createEmptyCommercialContext();
      if (task.status === CustomerTaskStatus.OPEN) {
        current.openTasksCount += 1;
        if (task.dueAt != null && task.dueAt.getTime() < now) {
          current.overdueTasksCount += 1;
        }
      }
      map.set(task.customerId, current);
    }

    for (const event of timelineEvents) {
      const current = map.get(event.customerId) ?? createEmptyCommercialContext();
      if (current.lastCrmEventAt == null) {
        current.lastCrmEventAt = event.createdAt.toISOString();
      }
      map.set(event.customerId, current);
    }

    return map;
  }

  private async ensureCustomerForCompany(companyId: string, customerId: string) {
    const customer = await prisma.customer.findFirst({
      where: {
        id: customerId,
        companyId,
        deletedAt: null,
      },
      select: {
        id: true,
      },
    });

    if (!customer) {
      throw new AppError('Cliente CRM nao encontrado.', 404, 'CRM_CUSTOMER_NOT_FOUND');
    }
  }

  private async ensureAssignableUser(userId: string | null) {
    if (userId == null) {
      return;
    }

    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        isActive: true,
      },
    });

    if (!user?.isActive) {
      throw new AppError(
        'Usuario informado para a tarefa nao esta disponivel.',
        400,
        'CRM_TASK_ASSIGNEE_INVALID',
      );
    }
  }

  private toCustomerSummaryDto(
    customer: {
      id: string;
      companyId: string;
      localUuid: string;
      name: string;
      phone: string | null;
      address: string | null;
      notes: string | null;
      isActive: boolean;
      createdAt: Date;
      updatedAt: Date;
      crmTagAssignments: Array<{
        id: string;
        createdAt: Date;
        tag: {
          id: string;
          label: string;
          color: string | null;
        };
      }>;
    },
    context: CommercialContext | undefined,
  ) {
    const commercial = context ?? createEmptyCommercialContext();
    return {
      id: customer.id,
      companyId: customer.companyId,
      localUuid: customer.localUuid,
      name: customer.name,
      phone: customer.phone,
      address: customer.address,
      operationalNotes: customer.notes,
      isActive: customer.isActive,
      createdAt: customer.createdAt.toISOString(),
      updatedAt: customer.updatedAt.toISOString(),
      tags: customer.crmTagAssignments.map((assignment) =>
        this.toCustomerTagDto(assignment),
      ),
      commercialSummary: {
        totalSalesCount: commercial.totalSalesCount,
        totalRevenueCents: commercial.totalRevenueCents,
        totalProfitCents: commercial.totalProfitCents,
        totalFiadoPaymentsCents: commercial.totalFiadoPaymentsCents,
        openTasksCount: commercial.openTasksCount,
        overdueTasksCount: commercial.overdueTasksCount,
        lastSaleAt: commercial.lastSaleAt,
        lastFiadoPaymentAt: commercial.lastFiadoPaymentAt,
        lastCrmEventAt: commercial.lastCrmEventAt,
      },
    };
  }

  private toCustomerTagDto(assignment: {
    id: string;
    createdAt: Date;
    tag: {
      id: string;
      label: string;
      color: string | null;
    };
  }) {
    return {
      id: assignment.tag.id,
      assignmentId: assignment.id,
      label: assignment.tag.label,
      color: assignment.tag.color,
      assignedAt: assignment.createdAt.toISOString(),
    };
  }

  private toCustomerNoteDto(note: {
    id: string;
    body: string;
    createdAt: Date;
    updatedAt: Date;
    authorUser: {
      id: string;
      name: string;
      email: string;
    } | null;
  }) {
    return {
      id: note.id,
      body: note.body,
      createdAt: note.createdAt.toISOString(),
      updatedAt: note.updatedAt.toISOString(),
      author: note.authorUser == null
          ? null
          : {
              id: note.authorUser.id,
              name: note.authorUser.name,
              email: note.authorUser.email,
            },
    };
  }

  private toCustomerTaskDto(task: {
    id: string;
    title: string;
    description: string | null;
    status: CustomerTaskStatus;
    dueAt: Date | null;
    completedAt: Date | null;
    createdAt: Date;
    updatedAt: Date;
    createdByUser: {
      id: string;
      name: string;
      email: string;
    } | null;
    assignedToUser: {
      id: string;
      name: string;
      email: string;
    } | null;
  }) {
    return {
      id: task.id,
      title: task.title,
      description: task.description,
      status: task.status.toLowerCase(),
      dueAt: task.dueAt?.toISOString() ?? null,
      completedAt: task.completedAt?.toISOString() ?? null,
      createdAt: task.createdAt.toISOString(),
      updatedAt: task.updatedAt.toISOString(),
      createdBy: task.createdByUser == null
          ? null
          : {
              id: task.createdByUser.id,
              name: task.createdByUser.name,
              email: task.createdByUser.email,
            },
      assignedTo: task.assignedToUser == null
          ? null
          : {
              id: task.assignedToUser.id,
              name: task.assignedToUser.name,
              email: task.assignedToUser.email,
            },
    };
  }

  private toCrmTimelineEventDto(event: {
    id: string;
    eventType: CustomerTimelineEventType;
    headline: string;
    body: string | null;
    metadata: Prisma.JsonValue | null;
    createdAt: Date;
    actorUser: {
      id: string;
      name: string;
      email: string;
    } | null;
  }) {
    return {
      id: `crm:${event.id}`,
      source: 'crm',
      eventType: event.eventType.toLowerCase(),
      occurredAt: event.createdAt.toISOString(),
      headline: event.headline,
      body: event.body,
      actor: event.actorUser == null
          ? null
          : {
              id: event.actorUser.id,
              name: event.actorUser.name,
              email: event.actorUser.email,
            },
      amountCents: null,
      metadata: event.metadata,
    };
  }
}

type CommercialContext = {
  totalSalesCount: number;
  totalRevenueCents: number;
  totalProfitCents: number;
  totalFiadoPaymentsCents: number;
  openTasksCount: number;
  overdueTasksCount: number;
  lastSaleAt: string | null;
  lastFiadoPaymentAt: string | null;
  lastCrmEventAt: string | null;
};

function createEmptyCommercialContext(): CommercialContext {
  return {
    totalSalesCount: 0,
    totalRevenueCents: 0,
    totalProfitCents: 0,
    totalFiadoPaymentsCents: 0,
    openTasksCount: 0,
    overdueTasksCount: 0,
    lastSaleAt: null,
    lastFiadoPaymentAt: null,
    lastCrmEventAt: null,
  };
}

function normalizeTagLabel(label: string) {
  return label.trim().toLowerCase().replace(/\s+/g, ' ');
}

function deduplicateTagInputs(
  tags: Array<{
    label: string;
    color: string | null;
  }>,
) {
  const deduplicated = new Map<
    string,
    {
      label: string;
      normalizedLabel: string;
      color: string | null;
    }
  >();

  for (const tag of tags) {
    const normalizedLabel = normalizeTagLabel(tag.label);
    if (normalizedLabel.length === 0) {
      continue;
    }

    deduplicated.set(normalizedLabel, {
      label: tag.label.trim(),
      normalizedLabel,
      color: tag.color,
    });
  }

  return [...deduplicated.values()];
}
