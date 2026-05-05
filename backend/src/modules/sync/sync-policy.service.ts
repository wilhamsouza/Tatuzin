import type { Prisma } from '@prisma/client';

export const ALLOWED_LOCAL_FIRST_SYNC_ENTITIES = [
  'cashSession',
  'cashMovement',
  'operationalOrder',
  'operationalOrderItem',
  'sale',
  'saleItem',
  'payment',
  'receipt',
  'stockReservation',
  'stockDeduction',
  'offlineOperationLog',
] as const;

export const SERVER_FIRST_SYNC_ENTITIES = [
  'product',
  'products',
  'category',
  'categories',
  'supplier',
  'suppliers',
  'purchase',
  'purchases',
  'supply',
  'supplies',
  'cost',
  'costs',
  'report',
  'reports',
  'customer',
  'customers',
  'fiado',
] as const;

export const ALLOWED_SYNC_OPERATIONS = [
  'create',
  'update',
  'delete',
  'upsert',
  'append',
] as const;

export type LocalFirstSyncEntity =
  (typeof ALLOWED_LOCAL_FIRST_SYNC_ENTITIES)[number];

export type SyncPolicyEvent = {
  eventId: string;
  feature: string;
  entity: string;
  operation: string;
  entityLocalId?: string | null;
  entityServerId?: string | null;
  payload: Record<string, unknown>;
};

export type SyncConflictDecision = {
  code: string;
  message: string;
  payload: Prisma.InputJsonValue;
};

export class SyncPolicyService {
  isLocalFirstEntity(entity: string) {
    return ALLOWED_LOCAL_FIRST_SYNC_ENTITIES.includes(
      entity as LocalFirstSyncEntity,
    );
  }

  isAllowedOperation(operation: string) {
    return ALLOWED_SYNC_OPERATIONS.includes(
      operation as (typeof ALLOWED_SYNC_OPERATIONS)[number],
    );
  }

  async detectConflict(input: {
    tx: Prisma.TransactionClient;
    companyId: string;
    event: SyncPolicyEvent;
  }): Promise<SyncConflictDecision | null> {
    const { event } = input;

    if (event.entity === 'cashSession') {
      return this.detectCashSessionConflict(input);
    }

    if (event.entity === 'sale') {
      return this.detectSaleConflict(input);
    }

    if (event.entity === 'stockReservation') {
      return this.detectStockReservationConflict(event);
    }

    if (event.entity === 'receipt') {
      return this.detectReceiptConflict(input);
    }

    return null;
  }

  private async detectCashSessionConflict(input: {
    tx: Prisma.TransactionClient;
    companyId: string;
    event: SyncPolicyEvent;
  }) {
    if (
      !['update', 'upsert'].includes(input.event.operation) ||
      !this.isOpeningStatus(input.event.payload)
    ) {
      return null;
    }

    const previous = await this.findPreviousEvent(input, 'cashSession');
    if (previous == null || !this.isClosedStatus(previous.payload)) {
      return null;
    }

    return {
      code: 'CASH_SESSION_CLOSED',
      message: 'Sessao de caixa fechada nao pode ser reaberta por evento offline.',
      payload: {
        previousEventId: previous.eventId,
        previousServerVersion: previous.serverVersion?.toString() ?? null,
      },
    };
  }

  private async detectSaleConflict(input: {
    tx: Prisma.TransactionClient;
    companyId: string;
    event: SyncPolicyEvent;
  }) {
    if (!['update', 'delete'].includes(input.event.operation)) {
      return null;
    }

    if (input.event.entityServerId != null) {
      const existingSale = await input.tx.sale.findFirst({
        where: {
          companyId: input.companyId,
          id: input.event.entityServerId,
          status: {
            not: 'canceled',
          },
        },
        select: {
          id: true,
          status: true,
        },
      });

      if (existingSale != null) {
        return {
          code: 'SALE_IMMUTABLE',
          message: 'Venda finalizada nao pode ser alterada por evento offline.',
          payload: {
            saleId: existingSale.id,
            status: existingSale.status,
          },
        };
      }
    }

    const previous = await this.findPreviousEvent(input, 'sale');
    if (previous == null || !this.isFinalizedSale(previous.payload)) {
      return null;
    }

    return {
      code: 'SALE_IMMUTABLE',
      message: 'Venda finalizada nao pode ser alterada por evento offline.',
      payload: {
        previousEventId: previous.eventId,
        previousServerVersion: previous.serverVersion?.toString() ?? null,
      },
    };
  }

  private detectStockReservationConflict(event: SyncPolicyEvent) {
    const availability = this.firstNumber(event.payload, [
      'availableAfter',
      'availableAfterMil',
      'resultingAvailable',
      'resultingAvailableMil',
      'stockAfter',
      'stockAfterMil',
    ]);

    if (availability == null || availability >= 0) {
      return null;
    }

    return {
      code: 'STOCK_UNAVAILABLE',
      message:
        'Reserva de estoque nao pode resultar em disponibilidade negativa.',
      payload: {
        availability,
      },
    };
  }

  private async detectReceiptConflict(input: {
    tx: Prisma.TransactionClient;
    companyId: string;
    event: SyncPolicyEvent;
  }) {
    const receiptNumber = this.firstString(input.event.payload, [
      'receiptNumber',
      'number',
    ]);

    if (receiptNumber == null) {
      return null;
    }

    const previousReceipts = await input.tx.syncEvent.findMany({
      where: {
        companyId: input.companyId,
        entity: 'receipt',
        status: 'ACCEPTED',
      },
      orderBy: {
        createdAt: 'desc',
      },
      take: 200,
    });

    const duplicate = previousReceipts.find((event) => {
      if (event.eventId === input.event.eventId) {
        return false;
      }
      return (
        this.firstString(this.asRecord(event.payload), [
          'receiptNumber',
          'number',
        ]) === receiptNumber
      );
    });

    if (duplicate != null) {
      return {
        code: 'DUPLICATE_RECEIPT',
        message:
          'Numero de comprovante duplicado para a mesma empresa.',
        payload: {
          duplicateEventId: duplicate.eventId,
          receiptNumber,
        },
      };
    }

    const saleReceipt = await input.tx.sale.findFirst({
      where: {
        companyId: input.companyId,
        receiptNumber,
      },
      select: {
        id: true,
        receiptNumber: true,
      },
    });

    if (saleReceipt == null) {
      return null;
    }

    return {
      code: 'DUPLICATE_RECEIPT',
      message:
        'Numero de comprovante duplicado para a mesma empresa.',
      payload: {
        saleId: saleReceipt.id,
        receiptNumber,
      },
    };
  }

  private async findPreviousEvent(
    input: {
      tx: Prisma.TransactionClient;
      companyId: string;
      event: SyncPolicyEvent;
    },
    entity: string,
  ) {
    const identityFilters = [
      ...(input.event.entityLocalId == null
        ? []
        : [{ entityLocalId: input.event.entityLocalId }]),
      ...(input.event.entityServerId == null
        ? []
        : [{ entityServerId: input.event.entityServerId }]),
    ];

    if (identityFilters.length === 0) {
      return null;
    }

    return input.tx.syncEvent.findFirst({
      where: {
        companyId: input.companyId,
        entity,
        status: {
          in: ['ACCEPTED', 'CONFLICT'],
        },
        OR: identityFilters,
      },
      orderBy: [
        {
          serverVersion: 'desc',
        },
        {
          createdAt: 'desc',
        },
      ],
    });
  }

  private isOpeningStatus(payload: unknown) {
    const status = this.firstString(this.asRecord(payload), ['status', 'state']);
    return status != null && ['open', 'opened', 'active'].includes(status);
  }

  private isClosedStatus(payload: unknown) {
    const status = this.firstString(this.asRecord(payload), ['status', 'state']);
    return (
      status != null &&
      ['closed', 'finished', 'fechada', 'fechado'].includes(status)
    );
  }

  private isFinalizedSale(payload: unknown) {
    const status = this.firstString(this.asRecord(payload), ['status', 'state']);
    if (status == null) {
      return true;
    }

    return !['draft', 'open', 'pending', 'canceled', 'cancelada'].includes(
      status,
    );
  }

  private firstString(
    payload: Record<string, unknown>,
    keys: string[],
  ): string | null {
    for (const key of keys) {
      const value = payload[key];
      if (typeof value === 'string' && value.trim().length > 0) {
        return value.trim();
      }
    }

    return null;
  }

  private firstNumber(
    payload: Record<string, unknown>,
    keys: string[],
  ): number | null {
    for (const key of keys) {
      const value = payload[key];
      if (typeof value === 'number' && Number.isFinite(value)) {
        return value;
      }
    }

    return null;
  }

  private asRecord(value: unknown): Record<string, unknown> {
    if (value == null || typeof value !== 'object' || Array.isArray(value)) {
      return {};
    }

    return value as Record<string, unknown>;
  }
}
