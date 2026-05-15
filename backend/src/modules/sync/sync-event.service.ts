import { Prisma, SyncEventStatus } from "@prisma/client";
import { ZodError } from "zod";

import { prisma } from "../../database/prisma";
import { AppError } from "../../shared/http/app-error";
import type { AppContext } from "../app/app-context.types";
import {
  asRecord as asPayloadRecord,
  firstString,
  localSequenceFor,
  persistableLocalSequence,
  syncMetadataFor,
} from "./materializers/payload-utils";
import { SyncMaterializerService } from "./materializers/sync-materializer.service";
import { SyncCheckpointService } from "./sync-checkpoint.service";
import { SyncConflictService } from "./sync-conflict.service";
import {
  ALLOWED_LOCAL_FIRST_SYNC_ENTITIES,
  SyncPolicyService,
} from "./sync-policy.service";
import {
  syncPushBatchSchema,
  syncPushEventSchema,
  type SyncPullQueryInput,
  type SyncPushEventInput,
} from "./sync.schemas";
import { SyncVersionService } from "./sync-version.service";

const MAX_EVENTS_PER_PUSH = 100;

type PushItemResult = {
  eventId: string;
  entity: string;
  operation: string;
  serverVersion: string | null;
  entityServerId: string | null;
};

type RejectedItemResult = PushItemResult & {
  code: string;
  message: string;
  details?: Prisma.InputJsonValue;
};

type PullProjectionResult = {
  projection: Prisma.InputJsonValue | null;
  warning: string | null;
};

type PullSyncEvent = {
  id: string;
  eventId: string;
  feature: string;
  entity: string;
  operation: string;
  entityLocalId: string | null;
  entityServerId: string | null;
  occurredAt: Date;
  payload: Prisma.JsonValue;
  status: SyncEventStatus;
  serverVersion: bigint | null;
  materializedAt: Date | null;
  createdAt: Date;
};

export class SyncEventService {
  constructor(
    private readonly policy = new SyncPolicyService(),
    private readonly versionService = new SyncVersionService(),
    private readonly checkpointService = new SyncCheckpointService(),
    private readonly conflictService = new SyncConflictService(),
    private readonly materializer = new SyncMaterializerService(),
  ) {}

  async push(context: AppContext, rawBody: unknown) {
    const batch = syncPushBatchSchema.safeParse(rawBody);
    if (!batch.success) {
      await this.createIncident({
        context,
        code: "INVALID_SYNC_BATCH",
        message: "Batch de sincronizacao invalido.",
        severity: "warn",
        details: this.zodDetails(batch.error),
      });
      throw new AppError(
        "Batch de sincronizacao invalido.",
        422,
        "INVALID_SYNC_BATCH",
        this.zodDetails(batch.error),
      );
    }

    if (batch.data.events.length > MAX_EVENTS_PER_PUSH) {
      await this.createIncident({
        context,
        code: "SYNC_BATCH_TOO_LARGE",
        message: "O push aceita no maximo 100 eventos por requisicao.",
        severity: "warn",
        details: {
          count: batch.data.events.length,
          max: MAX_EVENTS_PER_PUSH,
        },
      });
      throw new AppError(
        "O push aceita no maximo 100 eventos por requisicao.",
        413,
        "SYNC_BATCH_TOO_LARGE",
        {
          count: batch.data.events.length,
          max: MAX_EVENTS_PER_PUSH,
        },
      );
    }

    const accepted: PushItemResult[] = [];
    const duplicates: PushItemResult[] = [];
    const rejected: RejectedItemResult[] = [];
    const conflicts: RejectedItemResult[] = [];

    for (const rawEvent of batch.data.events) {
      const parsedEvent = syncPushEventSchema.safeParse(rawEvent);
      if (!parsedEvent.success) {
        rejected.push(
          await this.rejectMalformedEvent(context, rawEvent, parsedEvent.error),
        );
        continue;
      }

      const normalizedEvent = this.normalizeEvent(parsedEvent.data);
      const result = await this.processEvent(context, normalizedEvent);
      if (result.bucket === "accepted") {
        accepted.push(result.item);
      } else if (result.bucket === "duplicates") {
        duplicates.push(result.item);
      } else if (result.bucket === "conflicts") {
        conflicts.push(result.item);
      } else {
        rejected.push(result.item);
      }
    }

    const currentServerVersion = await this.versionService.getCurrentVersion(
      context.company.id,
    );

    return {
      ok: true,
      currentServerVersion: this.versionService.toDto(currentServerVersion),
      accepted,
      duplicates,
      rejected,
      conflicts,
      summary: {
        accepted: accepted.length,
        duplicates: duplicates.length,
        rejected: rejected.length,
        conflicts: conflicts.length,
      },
    };
  }

  async pull(context: AppContext, query: SyncPullQueryInput) {
    const sinceVersion = BigInt(query.sinceVersion);
    const features = query.features;

    const events = await prisma.syncEvent.findMany({
      where: {
        companyId: context.company.id,
        entity: {
          in: [...ALLOWED_LOCAL_FIRST_SYNC_ENTITIES],
        },
        status: {
          in: [SyncEventStatus.ACCEPTED, SyncEventStatus.CONFLICT],
        },
        serverVersion: {
          gt: sinceVersion,
        },
        ...(features.length === 0
          ? {}
          : {
              feature: {
                in: features,
              },
            }),
        ...(query.includeOwnEvents
          ? {}
          : {
              deviceId: {
                not: context.device.id,
              },
            }),
      },
      orderBy: {
        serverVersion: "asc",
      },
      take: query.limit,
    });

    const latestVersion =
      events.length === 0
        ? sinceVersion
        : (events[events.length - 1]?.serverVersion ?? sinceVersion);

    await this.checkpointService.recordPull({
      companyId: context.company.id,
      deviceId: context.device.id,
      features:
        features.length === 0
          ? [...new Set(events.map((event) => event.feature))]
          : features,
      serverVersion: latestVersion,
    });

    const currentServerVersion = await this.versionService.getCurrentVersion(
      context.company.id,
    );

    const changes = await Promise.all(
      events.map((event) => this.toPullChangeDto(context, event)),
    );

    return {
      ok: true,
      sinceVersion: sinceVersion.toString(),
      currentServerVersion: currentServerVersion.toString(),
      nextSinceVersion: latestVersion.toString(),
      hasMore: events.length === query.limit,
      changes,
      events: changes,
    };
  }

  async getStatus(context: AppContext) {
    const [
      state,
      checkpoints,
      openConflictsCount,
      lastIncidents,
      eventCounts,
      lastMaterialized,
    ] = await Promise.all([
      this.versionService.getOrCreateState(context.company.id),
      this.checkpointService.listForDevice({
        companyId: context.company.id,
        deviceId: context.device.id,
      }),
      this.conflictService.countOpen(context.company.id),
      prisma.syncIncident.findMany({
        where: {
          companyId: context.company.id,
        },
        orderBy: {
          createdAt: "desc",
        },
        take: 5,
      }),
      prisma.syncEvent.groupBy({
        by: ["status"],
        where: {
          companyId: context.company.id,
        },
        _count: {
          _all: true,
        },
      }),
      prisma.syncEvent.findFirst({
        where: {
          companyId: context.company.id,
          materializedAt: {
            not: null,
          },
        },
        orderBy: {
          materializedAt: "desc",
        },
        select: {
          materializedAt: true,
        },
      }),
    ]);
    const countByStatus = (status: SyncEventStatus) =>
      eventCounts.find((item) => item.status === status)?._count._all ?? 0;
    const pendingCount = countByStatus(SyncEventStatus.PENDING);
    const acceptedCount = countByStatus(SyncEventStatus.ACCEPTED);
    const duplicateCount = countByStatus(SyncEventStatus.DUPLICATE);
    const conflictCount = countByStatus(SyncEventStatus.CONFLICT);
    const rejectedCount = countByStatus(SyncEventStatus.REJECTED);
    const failedCount = countByStatus(SyncEventStatus.FAILED);

    return {
      ok: true,
      companyId: context.company.id,
      deviceId: context.device.id,
      syncEnabled: context.license.syncEnabled,
      currentServerVersion: state.currentVersion.toString(),
      checkpoints,
      openConflictsCount,
      requiresReviewCount: openConflictsCount,
      pendingCount,
      acceptedCount,
      duplicateCount,
      conflictCount,
      rejectedCount,
      failedCount,
      errorCount: rejectedCount + failedCount,
      requiresReview: openConflictsCount > 0,
      hasError: failedCount > 0,
      lastMaterializedAt:
        lastMaterialized?.materializedAt?.toISOString() ?? null,
      lastIncidents: lastIncidents.map((incident) => ({
        id: incident.id,
        code: incident.code,
        message: incident.message,
        severity: incident.severity,
        createdAt: incident.createdAt.toISOString(),
      })),
      device: context.device,
      serverFirstSnapshotVersion: state.serverFirstSnapshotVersion.toString(),
    };
  }

  private async processEvent(context: AppContext, event: SyncPushEventInput) {
    const duplicate = await prisma.syncEvent.findUnique({
      where: {
        companyId_deviceId_eventId: {
          companyId: context.company.id,
          deviceId: context.device.id,
          eventId: event.eventId,
        },
      },
    });

    if (duplicate != null) {
      return {
        bucket: "duplicates" as const,
        item: {
          eventId: duplicate.eventId,
          entity: duplicate.entity,
          operation: duplicate.operation,
          serverVersion: duplicate.serverVersion?.toString() ?? null,
          entityServerId: duplicate.entityServerId,
        },
      };
    }

    if (!this.policy.isLocalFirstEntity(event.entity)) {
      const item = await this.rejectEvent(context, event, {
        code: "ENTITY_NOT_LOCAL_FIRST",
        message:
          "Esta entidade e server-first/cache e nao pode ser enviada por /sync/push.",
        createIncident: true,
      });
      return { bucket: "rejected" as const, item };
    }

    if (!this.policy.isAllowedOperation(event.operation)) {
      const item = await this.rejectEvent(context, event, {
        code: "INVALID_OPERATION",
        message:
          "Operacao invalida para sync. Use create, update, delete, upsert ou append.",
      });
      return { bucket: "rejected" as const, item };
    }

    try {
      return await prisma.$transaction(async (tx) => {
        const materialized =
          (await this.detectStaleLocalSequence(tx, context, event)) ??
          (await this.materializer.materialize({
            tx,
            context,
            event,
            payload: event.payload,
          }));

        if (materialized.outcome === "duplicate") {
          const syncEvent = await tx.syncEvent.create({
            data: {
              companyId: context.company.id,
              deviceId: context.device.id,
              userId: context.user.id,
              eventId: event.eventId,
              feature: event.feature,
              entity: event.entity,
              operation: event.operation,
              entityLocalId: event.entityLocalId,
              entityServerId:
                materialized.entityServerId ?? event.entityServerId,
              occurredAt: new Date(event.occurredAt),
              payload: event.payload as Prisma.InputJsonValue,
              status: SyncEventStatus.DUPLICATE,
              serverVersion: materialized.serverVersion,
            },
          });

          return {
            bucket: "duplicates" as const,
            item: {
              eventId: event.eventId,
              entity: event.entity,
              operation: event.operation,
              serverVersion: syncEvent.serverVersion?.toString() ?? null,
              entityServerId: syncEvent.entityServerId,
            },
          };
        }

        if (materialized.outcome === "rejected") {
          const syncEvent = await tx.syncEvent.create({
            data: {
              companyId: context.company.id,
              deviceId: context.device.id,
              userId: context.user.id,
              eventId: event.eventId,
              feature: event.feature,
              entity: event.entity,
              operation: event.operation,
              entityLocalId: event.entityLocalId,
              entityServerId: event.entityServerId,
              occurredAt: new Date(event.occurredAt),
              payload: event.payload as Prisma.InputJsonValue,
              status: SyncEventStatus.REJECTED,
              rejectionCode: materialized.code,
              rejectionMessage: materialized.message,
            },
          });

          return {
            bucket: "rejected" as const,
            item: {
              eventId: syncEvent.eventId,
              entity: syncEvent.entity,
              operation: syncEvent.operation,
              serverVersion: null,
              entityServerId: syncEvent.entityServerId,
              code: materialized.code,
              message: materialized.message,
              details: materialized.details,
            },
          };
        }

        if (materialized.outcome === "conflict") {
          const serverVersion = await this.versionService.nextCompanyVersion(
            tx,
            context.company.id,
          );
          const syncEvent = await tx.syncEvent.create({
            data: {
              companyId: context.company.id,
              deviceId: context.device.id,
              userId: context.user.id,
              eventId: event.eventId,
              feature: event.feature,
              entity: event.entity,
              operation: event.operation,
              entityLocalId: event.entityLocalId,
              entityServerId: event.entityServerId,
              occurredAt: new Date(event.occurredAt),
              payload: event.payload as Prisma.InputJsonValue,
              status: SyncEventStatus.CONFLICT,
              serverVersion,
            },
          });

          await this.conflictService.createConflict({
            tx,
            companyId: context.company.id,
            deviceId: context.device.id,
            userId: context.user.id,
            syncEventId: syncEvent.id,
            entity: event.entity,
            entityLocalId: event.entityLocalId,
            entityServerId: syncEvent.entityServerId,
            code: materialized.code,
            message: materialized.message,
            payload: materialized.payload ?? {},
          });

          await this.checkpointService.recordPush({
            tx,
            companyId: context.company.id,
            deviceId: context.device.id,
            feature: event.feature,
            serverVersion,
          });

          await tx.syncIncident.create({
            data: {
              companyId: context.company.id,
              deviceId: context.device.id,
              userId: context.user.id,
              syncEventId: syncEvent.id,
              code: materialized.code,
              message: materialized.message,
              severity: "warn",
              details: materialized.payload ?? {},
            },
          });

          return {
            bucket: "conflicts" as const,
            item: {
              eventId: event.eventId,
              entity: event.entity,
              operation: event.operation,
              serverVersion: serverVersion.toString(),
              entityServerId: syncEvent.entityServerId,
              code: materialized.code,
              message: materialized.message,
              details: materialized.payload ?? {},
            },
          };
        }

        const serverVersion = await this.versionService.nextCompanyVersion(
          tx,
          context.company.id,
        );
        const syncEvent = await tx.syncEvent.create({
          data: {
            companyId: context.company.id,
            deviceId: context.device.id,
            userId: context.user.id,
            eventId: event.eventId,
            feature: event.feature,
            entity: event.entity,
            operation: event.operation,
            entityLocalId: event.entityLocalId,
            entityServerId: materialized.entityServerId ?? event.entityServerId,
            occurredAt: new Date(event.occurredAt),
            payload: event.payload as Prisma.InputJsonValue,
            status: SyncEventStatus.ACCEPTED,
            serverVersion,
            materializedAt:
              materialized.materializedAt === undefined
                ? new Date()
                : materialized.materializedAt,
          },
        });

        await this.checkpointService.recordPush({
          tx,
          companyId: context.company.id,
          deviceId: context.device.id,
          feature: event.feature,
          serverVersion,
        });

        return {
          bucket: "accepted" as const,
          item: {
            eventId: event.eventId,
            entity: event.entity,
            operation: event.operation,
            serverVersion: serverVersion.toString(),
            entityServerId: syncEvent.entityServerId,
          },
        };
      });
    } catch (error) {
      const item = await this.failEvent(context, event, error);
      return { bucket: "rejected" as const, item };
    }
  }

  private async rejectMalformedEvent(
    context: AppContext,
    rawEvent: unknown,
    error: ZodError,
  ): Promise<RejectedItemResult> {
    const raw = this.asRecord(rawEvent);
    const eventId = this.stringField(raw, "eventId") ?? "unknown";
    const feature = this.stringField(raw, "feature") ?? "unknown";
    const entity = this.stringField(raw, "entity") ?? "unknown";
    const operation = this.stringField(raw, "operation") ?? "unknown";
    const message = "Evento de sincronizacao invalido.";

    if (eventId !== "unknown") {
      await this.createRejectedSyncEvent(
        context,
        {
          eventId,
          feature,
          entity,
          operation,
          entityLocalId: this.stringField(raw, "entityLocalId") ?? undefined,
          entityServerId: this.stringField(raw, "entityServerId") ?? undefined,
          occurredAt: this.validIsoDate(this.stringField(raw, "occurredAt")),
          payload: this.asRecord(raw.payload),
        },
        {
          code: "INVALID_SYNC_EVENT",
          message,
        },
      );
    }

    await this.createIncident({
      context,
      code: "INVALID_SYNC_EVENT",
      message,
      severity: "warn",
      details: this.zodDetails(error),
    });

    return {
      eventId,
      entity,
      operation,
      serverVersion: null,
      entityServerId: null,
      code: "INVALID_SYNC_EVENT",
      message,
    };
  }

  private async rejectEvent(
    context: AppContext,
    event: SyncPushEventInput,
    rejection: {
      code: string;
      message: string;
      createIncident?: boolean;
    },
  ): Promise<RejectedItemResult> {
    const syncEvent = await this.createRejectedSyncEvent(
      context,
      event,
      rejection,
    );

    if (rejection.createIncident === true) {
      await this.createIncident({
        context,
        syncEventId: syncEvent.id,
        code: rejection.code,
        message: rejection.message,
        severity: "warn",
        details: {
          entity: event.entity,
          operation: event.operation,
        },
      });
    }

    return {
      eventId: event.eventId,
      entity: event.entity,
      operation: event.operation,
      serverVersion: null,
      entityServerId: event.entityServerId ?? null,
      code: rejection.code,
      message: rejection.message,
    };
  }

  private async failEvent(
    context: AppContext,
    event: SyncPushEventInput,
    error: unknown,
  ): Promise<RejectedItemResult> {
    const details = this.errorDetails(error);
    const message = "Falha inesperada ao materializar evento operacional.";
    const syncEvent = await prisma.syncEvent.create({
      data: {
        companyId: context.company.id,
        deviceId: context.device.id,
        userId: context.user.id,
        eventId: event.eventId,
        feature: event.feature,
        entity: event.entity,
        operation: event.operation,
        entityLocalId: event.entityLocalId,
        entityServerId: event.entityServerId,
        occurredAt: new Date(event.occurredAt),
        payload: event.payload as Prisma.InputJsonValue,
        status: SyncEventStatus.FAILED,
        rejectionCode: "SYNC_MATERIALIZATION_FAILED",
        rejectionMessage: message,
      },
    });

    await this.createIncident({
      context,
      syncEventId: syncEvent.id,
      code: "SYNC_MATERIALIZATION_FAILED",
      message,
      severity: "error",
      details,
    });

    return {
      eventId: event.eventId,
      entity: event.entity,
      operation: event.operation,
      serverVersion: null,
      entityServerId: event.entityServerId ?? null,
      code: "SYNC_MATERIALIZATION_FAILED",
      message,
    };
  }

  private async createRejectedSyncEvent(
    context: AppContext,
    event: SyncPushEventInput,
    rejection: { code: string; message: string },
  ) {
    return prisma.syncEvent.create({
      data: {
        companyId: context.company.id,
        deviceId: context.device.id,
        userId: context.user.id,
        eventId: event.eventId,
        feature: event.feature,
        entity: event.entity,
        operation: event.operation,
        entityLocalId: event.entityLocalId,
        entityServerId: event.entityServerId,
        occurredAt: new Date(this.validIsoDate(event.occurredAt)),
        payload: event.payload as Prisma.InputJsonValue,
        status: SyncEventStatus.REJECTED,
        rejectionCode: rejection.code,
        rejectionMessage: rejection.message,
      },
    });
  }

  private async createIncident(input: {
    context: AppContext;
    syncEventId?: string;
    code: string;
    message: string;
    severity: string;
    details?: Prisma.InputJsonValue;
  }) {
    await prisma.syncIncident.create({
      data: {
        companyId: input.context.company.id,
        deviceId: input.context.device.id,
        userId: input.context.user.id,
        syncEventId: input.syncEventId,
        code: input.code,
        message: input.message,
        severity: input.severity,
        details: input.details,
      },
    });
  }

  private normalizeEvent(event: SyncPushEventInput): SyncPushEventInput {
    const metadata = syncMetadataFor(event, event.payload);
    return {
      ...event,
      operation: event.operation.trim().toLowerCase(),
      entity: event.entity.trim(),
      feature: event.feature.trim(),
      eventId: event.eventId.trim(),
      entityLocalId: metadata.entityLocalId ?? event.entityLocalId,
      entityServerId: metadata.entityServerId ?? event.entityServerId,
    };
  }

  private async detectStaleLocalSequence(
    tx: Prisma.TransactionClient,
    context: AppContext,
    event: SyncPushEventInput,
  ): Promise<{
    outcome: "conflict";
    code: string;
    message: string;
    payload: Prisma.InputJsonValue;
  } | null> {
    if (!["update", "upsert"].includes(event.operation)) {
      return null;
    }

    const metadata = syncMetadataFor(event, event.payload);
    const localSequence = metadata.localSequence;
    const storedLocalSequence = persistableLocalSequence(localSequence);
    const entityLocalId = metadata.entityLocalId;
    if (localSequence == null || entityLocalId == null) {
      return null;
    }

    const domainLastLocalSequence = await this.findDomainLastLocalSequence(
      tx,
      context,
      event.entity,
      entityLocalId,
    );
    if (domainLastLocalSequence != null && storedLocalSequence != null) {
      return null;
    }

    // Fallback for entities without lastLocalSequence, or legacy rows that
    // still have it null.
    const previousEvents = await tx.syncEvent.findMany({
      where: {
        companyId: context.company.id,
        entity: event.entity,
        entityLocalId,
        status: SyncEventStatus.ACCEPTED,
        serverVersion: {
          not: null,
        },
      },
      orderBy: [{ serverVersion: "desc" }, { createdAt: "desc" }],
      take: 20,
      select: {
        eventId: true,
        serverVersion: true,
        payload: true,
      },
    });

    for (const previous of previousEvents) {
      const previousPayload = asPayloadRecord(previous.payload);
      const previousSequence = localSequenceFor(
        {
          eventId: previous.eventId,
          feature: event.feature,
          entity: event.entity,
          operation: event.operation,
          entityLocalId,
          occurredAt: event.occurredAt,
          payload: previousPayload,
        },
        previousPayload,
      );

      if (previousSequence == null) {
        continue;
      }

      if (previousSequence > localSequence) {
        return {
          outcome: "conflict",
          code: "STALE_LOCAL_SEQUENCE",
          message:
            "Evento operacional possui localSequence anterior ao ultimo evento materializado para a entidade.",
          payload: {
            entity: event.entity,
            entityLocalId,
            eventId: event.eventId,
            localSequence,
            latestLocalSequence: previousSequence,
            latestEventId: previous.eventId,
            latestServerVersion: previous.serverVersion?.toString() ?? null,
          },
        };
      }

      return null;
    }

    return null;
  }

  private async findDomainLastLocalSequence(
    tx: Prisma.TransactionClient,
    context: AppContext,
    entity: string,
    entityLocalId: string,
  ) {
    if (entity === "operationalOrder") {
      const order = await tx.operationalOrder.findUnique({
        where: {
          companyId_localUuid: {
            companyId: context.company.id,
            localUuid: entityLocalId,
          },
        },
        select: {
          lastLocalSequence: true,
        },
      });
      return order?.lastLocalSequence ?? null;
    }

    if (entity === "cashSession") {
      const cashSession = await tx.cashSession.findUnique({
        where: {
          companyId_localUuid: {
            companyId: context.company.id,
            localUuid: entityLocalId,
          },
        },
        select: {
          lastLocalSequence: true,
        },
      });
      return cashSession?.lastLocalSequence ?? null;
    }

    return null;
  }

  private async toPullChangeDto(context: AppContext, event: PullSyncEvent) {
    const projection = await this.projectionForEvent(context, event);
    if (
      projection.projection == null &&
      projection.warning === "PROJECTION_NOT_FOUND"
    ) {
      await this.createProjectionIncident(context, event);
    }

    return {
      ...this.toEventDto(event),
      projection: projection.projection,
      projectionWarning: projection.warning,
    };
  }

  private async projectionForEvent(
    context: AppContext,
    event: PullSyncEvent,
  ): Promise<PullProjectionResult> {
    if (event.status !== SyncEventStatus.ACCEPTED) {
      return {
        projection: null,
        warning: "SYNC_EVENT_NOT_ACCEPTED",
      };
    }

    if (event.operation === "delete") {
      return {
        projection: null,
        warning: "DELETE_PROJECTION_NOT_AVAILABLE",
      };
    }

    if (event.entityServerId == null) {
      return {
        projection: null,
        warning: "PROJECTION_NOT_AVAILABLE_FOR_ENTITY",
      };
    }

    const projection = await this.findProjection(context, event);
    if (projection == null) {
      return {
        projection: null,
        warning: this.supportsProjection(event.entity)
          ? "PROJECTION_NOT_FOUND"
          : "PROJECTION_NOT_AVAILABLE_FOR_ENTITY",
      };
    }

    return {
      projection,
      warning: null,
    };
  }

  private async findProjection(
    context: AppContext,
    event: PullSyncEvent,
  ): Promise<Prisma.InputJsonValue | null> {
    switch (event.entity) {
      case "cashSession":
        return this.cashSessionProjection(context.company.id, event);
      case "cashMovement":
        return this.cashMovementProjection(context.company.id, event);
      case "operationalOrder":
        return this.operationalOrderProjection(context.company.id, event);
      case "operationalOrderItem":
        return this.operationalOrderItemProjection(context.company.id, event);
      case "sale":
        return this.saleProjection(context.company.id, event);
      case "saleItem":
        return this.saleItemProjection(context.company.id, event);
      case "payment":
        return this.paymentProjection(context.company.id, event);
      case "receipt":
        return this.receiptProjection(context.company.id, event);
      case "stockReservation":
        return this.stockReservationProjection(context.company.id, event);
      case "stockDeduction":
        return this.stockDeductionProjection(context.company.id, event);
      default:
        return null;
    }
  }

  private supportsProjection(entity: string) {
    return [
      "cashSession",
      "cashMovement",
      "operationalOrder",
      "operationalOrderItem",
      "sale",
      "saleItem",
      "payment",
      "receipt",
      "stockReservation",
      "stockDeduction",
    ].includes(entity);
  }

  private async cashSessionProjection(companyId: string, event: PullSyncEvent) {
    const cashSession = await prisma.cashSession.findFirst({
      where: { id: event.entityServerId!, companyId },
      select: {
        id: true,
        localUuid: true,
        payload: true,
        status: true,
        openedAt: true,
        closedAt: true,
        openingBalanceCents: true,
        closingBalanceCents: true,
        expectedBalanceCents: true,
        createdAt: true,
        updatedAt: true,
        user: {
          select: {
            name: true,
          },
        },
      },
    });
    if (cashSession == null) {
      return null;
    }

    const operatorName =
      firstString(asPayloadRecord(cashSession.payload), ["operatorName"]) ??
      cashSession.user?.name ??
      null;

    return {
      entityServerId: cashSession.id,
      id: cashSession.id,
      localUuid: cashSession.localUuid,
      operatorName,
      status: cashSession.status,
      openedAt: cashSession.openedAt?.toISOString() ?? null,
      closedAt: cashSession.closedAt?.toISOString() ?? null,
      totals: {
        openingBalanceCents: cashSession.openingBalanceCents,
        closingBalanceCents: cashSession.closingBalanceCents,
        expectedBalanceCents: cashSession.expectedBalanceCents,
      },
      createdAt: cashSession.createdAt.toISOString(),
      updatedAt: cashSession.updatedAt.toISOString(),
    };
  }

  private async cashMovementProjection(
    companyId: string,
    event: PullSyncEvent,
  ) {
    const movement = await prisma.cashEvent.findFirst({
      where: { id: event.entityServerId!, companyId },
      select: {
        id: true,
        cashSessionId: true,
        eventType: true,
        amountCents: true,
        notes: true,
        createdAt: true,
      },
    });
    if (movement == null) {
      return null;
    }

    return {
      entityServerId: movement.id,
      id: movement.id,
      cashSessionId: movement.cashSessionId,
      type: movement.eventType,
      amountCents: movement.amountCents,
      reason: movement.notes,
      createdAt: movement.createdAt.toISOString(),
    };
  }

  private async operationalOrderProjection(
    companyId: string,
    event: PullSyncEvent,
  ) {
    const order = await prisma.operationalOrder.findFirst({
      where: { id: event.entityServerId!, companyId },
      select: {
        id: true,
        localUuid: true,
        status: true,
        subtotalCents: true,
        discountCents: true,
        totalCents: true,
        convertedSaleId: true,
        createdAt: true,
        updatedAt: true,
        closedAt: true,
        cancelledAt: true,
        _count: {
          select: {
            items: true,
          },
        },
      },
    });
    if (order == null) {
      return null;
    }

    return {
      entityServerId: order.id,
      id: order.id,
      localUuid: order.localUuid,
      status: order.status,
      totals: {
        subtotalCents: order.subtotalCents,
        discountCents: order.discountCents,
        totalCents: order.totalCents,
      },
      convertedSaleId: order.convertedSaleId,
      itemsCount: order._count.items,
      timestamps: {
        createdAt: order.createdAt.toISOString(),
        updatedAt: order.updatedAt.toISOString(),
        closedAt: order.closedAt?.toISOString() ?? null,
        cancelledAt: order.cancelledAt?.toISOString() ?? null,
      },
    };
  }

  private async operationalOrderItemProjection(
    companyId: string,
    event: PullSyncEvent,
  ) {
    const item = await prisma.operationalOrderItem.findFirst({
      where: { id: event.entityServerId!, companyId },
      select: {
        id: true,
        operationalOrderId: true,
        productId: true,
        productVariantId: true,
        description: true,
        quantityMil: true,
        unitPriceCents: true,
        totalCents: true,
      },
    });
    if (item == null) {
      return null;
    }

    return {
      entityServerId: item.id,
      id: item.id,
      operationalOrderId: item.operationalOrderId,
      productId: item.productId,
      productVariantId: item.productVariantId,
      description: item.description,
      quantityMil: item.quantityMil,
      totals: {
        unitPriceCents: item.unitPriceCents,
        totalCents: item.totalCents,
      },
    };
  }

  private async saleProjection(companyId: string, event: PullSyncEvent) {
    const sale = await prisma.sale.findFirst({
      where: { id: event.entityServerId!, companyId },
      select: {
        id: true,
        localUuid: true,
        status: true,
        totalAmountCents: true,
        totalCostCents: true,
        receiptNumber: true,
        cashSessionId: true,
        soldAt: true,
        createdAt: true,
      },
    });
    if (sale == null) {
      return null;
    }

    return {
      entityServerId: sale.id,
      id: sale.id,
      localUuid: sale.localUuid,
      status: sale.status,
      total: {
        totalAmountCents: sale.totalAmountCents,
        totalCostCents: sale.totalCostCents,
      },
      receiptNumber: sale.receiptNumber,
      cashSessionId: sale.cashSessionId,
      soldAt: sale.soldAt.toISOString(),
      createdAt: sale.createdAt.toISOString(),
    };
  }

  private async saleItemProjection(companyId: string, event: PullSyncEvent) {
    const item = await prisma.saleItem.findFirst({
      where: {
        id: event.entityServerId!,
        sale: {
          companyId,
        },
      },
      select: {
        id: true,
        saleId: true,
        productId: true,
        productNameSnapshot: true,
        quantityMil: true,
        unitPriceCents: true,
        totalPriceCents: true,
        totalCostCents: true,
      },
    });
    if (item == null) {
      return null;
    }

    return {
      entityServerId: item.id,
      id: item.id,
      saleId: item.saleId,
      productId: item.productId,
      productVariantId: null,
      description: item.productNameSnapshot,
      quantityMil: item.quantityMil,
      totals: {
        unitPriceCents: item.unitPriceCents,
        totalPriceCents: item.totalPriceCents,
        totalCostCents: item.totalCostCents,
      },
    };
  }

  private async paymentProjection(companyId: string, event: PullSyncEvent) {
    const payment = await prisma.financialEvent.findFirst({
      where: { id: event.entityServerId!, companyId },
      select: {
        id: true,
        saleId: true,
        amountCents: true,
        paymentType: true,
        createdAt: true,
      },
    });
    if (payment == null) {
      return null;
    }

    return {
      entityServerId: payment.id,
      id: payment.id,
      saleId: payment.saleId,
      financialEventId: payment.id,
      amountCents: payment.amountCents,
      method: payment.paymentType,
      createdAt: payment.createdAt.toISOString(),
    };
  }

  private async receiptProjection(companyId: string, event: PullSyncEvent) {
    const sale = await prisma.sale.findFirst({
      where: { id: event.entityServerId!, companyId },
      select: {
        id: true,
        receiptNumber: true,
        updatedAt: true,
      },
    });
    if (sale == null) {
      return null;
    }

    return {
      entityServerId: sale.id,
      saleId: sale.id,
      receiptNumber: sale.receiptNumber,
      emittedAt:
        event.materializedAt?.toISOString() ?? sale.updatedAt.toISOString(),
    };
  }

  private async stockReservationProjection(
    companyId: string,
    event: PullSyncEvent,
  ) {
    const reservation = await prisma.stockReservation.findFirst({
      where: { id: event.entityServerId!, companyId },
      select: {
        id: true,
        productId: true,
        productVariantId: true,
        quantityMil: true,
        status: true,
      },
    });
    if (reservation == null) {
      return null;
    }

    return {
      entityServerId: reservation.id,
      id: reservation.id,
      productId: reservation.productId,
      productVariantId: reservation.productVariantId,
      quantityMil: reservation.quantityMil,
      status: reservation.status,
    };
  }

  private async stockDeductionProjection(
    companyId: string,
    event: PullSyncEvent,
  ) {
    const deduction = await prisma.stockDeduction.findFirst({
      where: { id: event.entityServerId!, companyId },
      select: {
        id: true,
        saleId: true,
        productId: true,
        productVariantId: true,
        quantityMil: true,
      },
    });
    if (deduction == null) {
      return null;
    }

    return {
      entityServerId: deduction.id,
      id: deduction.id,
      saleId: deduction.saleId,
      productId: deduction.productId,
      productVariantId: deduction.productVariantId,
      quantityMil: deduction.quantityMil,
    };
  }

  private async createProjectionIncident(
    context: AppContext,
    event: PullSyncEvent,
  ) {
    const existing = await prisma.syncIncident.findFirst({
      where: {
        syncEventId: event.id,
        code: "PULL_PROJECTION_MISSING",
      },
      select: {
        id: true,
      },
    });
    if (existing != null) {
      return;
    }

    await this.createIncident({
      context,
      syncEventId: event.id,
      code: "PULL_PROJECTION_MISSING",
      message:
        "Evento operacional materializado nao possui projection reconstruivel no pull.",
      severity: "warn",
      details: {
        entity: event.entity,
        operation: event.operation,
        entityLocalId: event.entityLocalId,
        entityServerId: event.entityServerId,
        serverVersion: event.serverVersion?.toString() ?? null,
      },
    });
  }

  private toEventDto(event: PullSyncEvent) {
    return {
      id: event.id,
      eventId: event.eventId,
      feature: event.feature,
      entity: event.entity,
      operation: event.operation,
      entityLocalId: event.entityLocalId,
      entityServerId: event.entityServerId,
      occurredAt: event.occurredAt.toISOString(),
      payload: event.payload,
      status: event.status,
      serverVersion: event.serverVersion?.toString() ?? null,
      materializedAt: event.materializedAt?.toISOString() ?? null,
      createdAt: event.createdAt.toISOString(),
    };
  }

  private zodDetails(error: ZodError): Prisma.InputJsonValue {
    return error.flatten() as Prisma.InputJsonValue;
  }

  private errorDetails(error: unknown): Prisma.InputJsonValue {
    if (error instanceof Error) {
      return {
        name: error.name,
        message: error.message,
      };
    }

    return {
      message: String(error),
    };
  }

  private asRecord(value: unknown): Record<string, unknown> {
    if (value == null || typeof value !== "object" || Array.isArray(value)) {
      return {};
    }

    return value as Record<string, unknown>;
  }

  private stringField(payload: Record<string, unknown>, key: string) {
    const value = payload[key];
    return typeof value === "string" && value.trim().length > 0
      ? value.trim()
      : null;
  }

  private validIsoDate(value: string | null | undefined) {
    if (value == null) {
      return new Date().toISOString();
    }

    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? new Date().toISOString() : value;
  }
}
