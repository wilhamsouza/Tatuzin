import { SyncConflictStatus, type Prisma } from '@prisma/client';

import { prisma } from '../../database/prisma';
import { AppError } from '../../shared/http/app-error';
import type { AppContext } from '../app/app-context.types';
import type { SyncConflictQueryInput, SyncResolveConflictInput } from './sync.schemas';

export class SyncConflictService {
  async createConflict(input: {
    tx: Prisma.TransactionClient;
    companyId: string;
    deviceId: string;
    userId: string;
    syncEventId: string;
    entity: string;
    entityLocalId?: string | null;
    entityServerId?: string | null;
    code: string;
    message: string;
    payload: Prisma.InputJsonValue;
  }) {
    return input.tx.syncConflict.create({
      data: {
        companyId: input.companyId,
        deviceId: input.deviceId,
        userId: input.userId,
        syncEventId: input.syncEventId,
        entity: input.entity,
        entityLocalId: input.entityLocalId,
        entityServerId: input.entityServerId,
        code: input.code,
        message: input.message,
        payload: input.payload,
      },
    });
  }

  async list(context: AppContext, query: SyncConflictQueryInput) {
    const conflicts = await prisma.syncConflict.findMany({
      where: {
        companyId: context.company.id,
        status: query.status,
      },
      orderBy: {
        createdAt: 'desc',
      },
      take: query.limit,
      include: {
        syncEvent: {
          select: {
            eventId: true,
            feature: true,
            operation: true,
            serverVersion: true,
          },
        },
      },
    });

    return {
      items: conflicts.map((conflict) => ({
        id: conflict.id,
        entity: conflict.entity,
        entityLocalId: conflict.entityLocalId,
        entityServerId: conflict.entityServerId,
        code: conflict.code,
        message: conflict.message,
        status: conflict.status,
        payload: conflict.payload,
        resolution: conflict.resolution,
        createdAt: conflict.createdAt.toISOString(),
        resolvedAt: conflict.resolvedAt?.toISOString() ?? null,
        event: {
          eventId: conflict.syncEvent.eventId,
          feature: conflict.syncEvent.feature,
          operation: conflict.syncEvent.operation,
          serverVersion:
            conflict.syncEvent.serverVersion?.toString() ?? null,
        },
      })),
      count: conflicts.length,
    };
  }

  async resolve(
    context: AppContext,
    conflictId: string,
    input: SyncResolveConflictInput,
  ) {
    const conflict = await prisma.syncConflict.findFirst({
      where: {
        id: conflictId,
        companyId: context.company.id,
      },
    });

    if (conflict == null) {
      throw new AppError(
        'Conflito de sincronizacao nao encontrado.',
        404,
        'SYNC_CONFLICT_NOT_FOUND',
      );
    }

    if (conflict.status !== SyncConflictStatus.OPEN) {
      return {
        conflict: this.toDto(conflict),
      };
    }

    const resolved = await prisma.syncConflict.update({
      where: { id: conflict.id },
      data: {
        status: SyncConflictStatus.RESOLVED,
        resolution: input.resolution as Prisma.InputJsonValue,
        resolvedAt: new Date(),
        resolvedByUserId: context.user.id,
      },
    });

    return {
      conflict: this.toDto(resolved),
    };
  }

  async countOpen(companyId: string) {
    return prisma.syncConflict.count({
      where: {
        companyId,
        status: SyncConflictStatus.OPEN,
      },
    });
  }

  private toDto(conflict: {
    id: string;
    entity: string;
    entityLocalId: string | null;
    entityServerId: string | null;
    code: string;
    message: string;
    status: SyncConflictStatus;
    payload: Prisma.JsonValue | null;
    resolution: Prisma.JsonValue | null;
    createdAt: Date;
    resolvedAt: Date | null;
  }) {
    return {
      id: conflict.id,
      entity: conflict.entity,
      entityLocalId: conflict.entityLocalId,
      entityServerId: conflict.entityServerId,
      code: conflict.code,
      message: conflict.message,
      status: conflict.status,
      payload: conflict.payload,
      resolution: conflict.resolution,
      createdAt: conflict.createdAt.toISOString(),
      resolvedAt: conflict.resolvedAt?.toISOString() ?? null,
    };
  }
}
