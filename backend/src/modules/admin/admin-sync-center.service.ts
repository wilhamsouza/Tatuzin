import {
  Prisma,
  SyncConflictStatus,
  SyncEventStatus,
  type SyncEvent,
} from "@prisma/client";

import { prisma } from "../../database/prisma";
import { buildAdminListResponse } from "../../shared/http/api-response";
import { AppError } from "../../shared/http/app-error";
import { toPaginationParams } from "../../shared/http/pagination";
import type { AppContext } from "../app/app-context.types";
import { SyncCheckpointService } from "../sync/sync-checkpoint.service";
import {
  SyncDiagnosticsService,
  type SyncDiagnosticResult,
} from "../sync/sync-diagnostics.service";
import { SyncMaterializerService } from "../sync/materializers/sync-materializer.service";
import { asRecord } from "../sync/materializers/payload-utils";
import type { SyncPushEventInput } from "../sync/sync.schemas";
import { SyncVersionService } from "../sync/sync-version.service";
import type {
  AdminSyncCenterArchiveBodyInput,
  AdminSyncCenterCompaniesQueryInput,
  AdminSyncCenterConflictsQueryInput,
  AdminSyncCenterDryRunBodyInput,
  AdminSyncCenterEventsQueryInput,
  AdminSyncCenterManualStockAdjustmentBodyInput,
  AdminSyncCenterReprocessBodyInput,
} from "./admin.schemas";

type AdminActionContext = {
  actorUserId: string;
  ipAddress: string | null;
  userAgent: string | null;
};

type EventWithRelations = Prisma.SyncEventGetPayload<{
  include: {
    conflict: true;
    incidents: {
      orderBy: { createdAt: "desc" };
      take: 5;
    };
    device: {
      select: {
        id: true;
        deviceLabel: true;
        clientInstanceId: true;
        status: true;
        platform: true;
        appVersion: true;
      };
    };
    user: {
      select: {
        id: true;
        name: true;
        email: true;
      };
    };
  };
}>;

type ConflictWithRelations = Prisma.SyncConflictGetPayload<{
  include: {
    syncEvent: {
      include: {
        incidents: {
          orderBy: { createdAt: "desc" };
          take: 5;
        };
      };
    };
    device: {
      select: {
        id: true;
        deviceLabel: true;
        clientInstanceId: true;
        status: true;
      };
    };
    user: {
      select: {
        id: true;
        name: true;
        email: true;
      };
    };
    resolvedBy: {
      select: {
        id: true;
        name: true;
        email: true;
      };
    };
  };
}>;

export class AdminSyncCenterService {
  constructor(
    private readonly diagnostics = new SyncDiagnosticsService(),
    private readonly materializer = new SyncMaterializerService(),
    private readonly versionService = new SyncVersionService(),
    private readonly checkpointService = new SyncCheckpointService(),
  ) {}

  async listCompanies(query: AdminSyncCenterCompaniesQueryInput) {
    const companies = await prisma.company.findMany({
      where: this.companySearchWhere(query.search),
      include: {
        license: true,
        syncState: true,
      },
      orderBy: { name: "asc" },
    });
    const companyIds = companies.map((company) => company.id);
    const [
      eventStatusRows,
      conflictRows,
      incidentRows,
      latestEventRows,
      latestIncidentRows,
    ] = await Promise.all([
      prisma.syncEvent.groupBy({
        by: ["companyId", "status"],
        where: { companyId: { in: companyIds } },
        _count: { _all: true },
      }),
      prisma.syncConflict.groupBy({
        by: ["companyId", "status"],
        where: { companyId: { in: companyIds } },
        _count: { _all: true },
      }),
      prisma.syncIncident.groupBy({
        by: ["companyId"],
        where: { companyId: { in: companyIds } },
        _count: { _all: true },
      }),
      prisma.syncEvent.groupBy({
        by: ["companyId"],
        where: { companyId: { in: companyIds } },
        _max: { createdAt: true },
      }),
      prisma.syncIncident.groupBy({
        by: ["companyId"],
        where: { companyId: { in: companyIds } },
        _max: { createdAt: true },
      }),
    ]);

    const eventCounts = eventCountsByCompany(eventStatusRows);
    const openConflicts = openConflictsByCompany(conflictRows);
    const incidentCounts = countByCompany(incidentRows);
    const latestEventAt = maxDateByCompany(latestEventRows);
    const latestIncidentAt = maxDateByCompany(latestIncidentRows);

    const summaries = companies.map((company) => {
      const counts = eventCounts.get(company.id) ?? emptyEventCounts();
      const openConflictCount = openConflicts.get(company.id) ?? 0;
      const incidentCount = incidentCounts.get(company.id) ?? 0;
      const syncStatus = classifyCompanySyncStatus({
        counts,
        openConflictCount,
        incidentCount,
      });
      return {
        companyId: company.id,
        companyName: company.name,
        plan: company.license?.plan ?? null,
        syncStatus,
        currentVersion: company.syncState?.currentVersion.toString() ?? "0",
        serverFirstSnapshotVersion:
          company.syncState?.serverFirstSnapshotVersion.toString() ?? "0",
        acceptedCount: counts.ACCEPTED,
        duplicateCount: counts.DUPLICATE,
        pendingCount: counts.PENDING,
        conflictCount: counts.CONFLICT,
        failedCount: counts.FAILED,
        openConflictCount,
        incidentCount,
        lastEventAt: latestEventAt.get(company.id)?.toISOString() ?? null,
        lastIncidentAt: latestIncidentAt.get(company.id)?.toISOString() ?? null,
        requiresReview: syncStatus !== "healthy",
      };
    });

    const filtered = summaries.filter((item) => {
      if (query.status === "all") {
        return true;
      }
      if (query.status === "requires_review") {
        return item.requiresReview;
      }
      return item.syncStatus === query.status;
    });
    const { skip, take } = toPaginationParams(query);

    return buildAdminListResponse({
      items: filtered.slice(skip, skip + take),
      page: query.page,
      pageSize: query.pageSize,
      total: filtered.length,
      filters: {
        search: query.search ?? null,
        status: query.status,
      },
      sort: { by: "companyName", direction: "asc" },
    });
  }

  async getCompanySummary(companyId: string) {
    const company = await this.requireCompany(companyId);
    const [
      eventStatusRows,
      entityStatusRows,
      conflictRows,
      incidentRows,
      latestEvents,
      latestConflicts,
      latestIncidents,
    ] = await Promise.all([
      prisma.syncEvent.groupBy({
        by: ["status"],
        where: { companyId },
        _count: { _all: true },
      }),
      prisma.syncEvent.groupBy({
        by: ["entity", "operation", "status"],
        where: { companyId },
        _count: { _all: true },
      }),
      prisma.syncConflict.groupBy({
        by: ["code", "entity", "status"],
        where: { companyId },
        _count: { _all: true },
      }),
      prisma.syncIncident.groupBy({
        by: ["severity", "code"],
        where: { companyId },
        _count: { _all: true },
      }),
      prisma.syncEvent.findMany({
        where: { companyId },
        orderBy: { createdAt: "desc" },
        take: 10,
      }),
      prisma.syncConflict.findMany({
        where: { companyId },
        orderBy: { createdAt: "desc" },
        take: 10,
        include: { syncEvent: true },
      }),
      prisma.syncIncident.findMany({
        where: { companyId },
        orderBy: { createdAt: "desc" },
        take: 10,
      }),
    ]);

    const eventCounts = emptyEventCounts();
    for (const row of eventStatusRows) {
      eventCounts[row.status] = row._count._all;
    }
    const openConflictCount = conflictRows
      .filter((row) => row.status === "OPEN")
      .reduce((total, row) => total + row._count._all, 0);
    const syncStatus = classifyCompanySyncStatus({
      counts: eventCounts,
      openConflictCount,
      incidentCount: incidentRows.reduce(
        (total, row) => total + row._count._all,
        0,
      ),
    });

    return {
      company: {
        companyId: company.id,
        companyName: company.name,
        plan: company.license?.plan ?? null,
      },
      syncState: {
        currentVersion: company.syncState?.currentVersion.toString() ?? "0",
        serverFirstSnapshotVersion:
          company.syncState?.serverFirstSnapshotVersion.toString() ?? "0",
        updatedAt: company.syncState?.updatedAt.toISOString() ?? null,
      },
      eventStatusCounts: eventCountsToDto(eventCounts),
      entityOperationStatusCounts: entityStatusRows.map((row) => ({
        entity: row.entity,
        operation: row.operation,
        status: row.status.toLowerCase(),
        count: row._count._all,
      })),
      conflictCounts: conflictRows.map((row) => ({
        code: row.code,
        entity: row.entity,
        status: row.status.toLowerCase(),
        count: row._count._all,
      })),
      incidentCounts: incidentRows.map((row) => ({
        severity: row.severity,
        code: row.code,
        count: row._count._all,
      })),
      latestEvents: await Promise.all(
        latestEvents.map((event) => this.toEventListItem(event)),
      ),
      latestConflicts: await Promise.all(
        latestConflicts.map((conflict) => this.toConflictListItem(conflict)),
      ),
      latestIncidents: latestIncidents.map((incident) => ({
        id: incident.id,
        code: incident.code,
        message: incident.message,
        severity: incident.severity,
        createdAt: incident.createdAt.toISOString(),
      })),
      recommendation: this.recommendCompanyAction(syncStatus),
      requiresReview: syncStatus !== "healthy",
    };
  }

  async listEvents(companyId: string, query: AdminSyncCenterEventsQueryInput) {
    await this.requireCompany(companyId);
    const where: Prisma.SyncEventWhereInput = {
      companyId,
      ...(query.status == null
        ? {}
        : { status: query.status as SyncEventStatus }),
      ...(query.entity == null ? {} : { entity: query.entity }),
      ...(query.operation == null ? {} : { operation: query.operation }),
      ...(query.feature == null ? {} : { feature: query.feature }),
      ...createdAtRange(query.startDate, query.endDate),
    };
    const { skip, take } = toPaginationParams(query);
    const [total, events] = await prisma.$transaction([
      prisma.syncEvent.count({ where }),
      prisma.syncEvent.findMany({
        where,
        skip,
        take,
        orderBy: { createdAt: "desc" },
        include: {
          conflict: {
            select: {
              id: true,
            },
          },
        },
      }),
    ]);

    return buildAdminListResponse({
      items: await Promise.all(
        events.map((event) => this.toEventListItem(event)),
      ),
      page: query.page,
      pageSize: query.pageSize,
      total,
      filters: {
        status: query.status?.toLowerCase() ?? null,
        entity: query.entity ?? null,
        operation: query.operation ?? null,
        feature: query.feature ?? null,
        startDate: query.startDate?.toISOString() ?? null,
        endDate: query.endDate?.toISOString() ?? null,
      },
      sort: { by: "createdAt", direction: "desc" },
    });
  }

  async getEvent(eventId: string, companyId: string) {
    const event = await this.findEvent(eventId, companyId);
    if (event == null) {
      throw new AppError(
        "Evento de sync nao encontrado.",
        404,
        "SYNC_EVENT_NOT_FOUND",
      );
    }

    const diagnostic = await this.classifyEvent(event);
    return {
      event: {
        ...this.eventBaseDto(event),
        relatedConflictId: event.conflict?.id ?? null,
        payload: this.diagnostics.sanitizePayload(event.payload),
        safePayloadPreview: this.diagnostics.safePayloadPreview(
          event.entity,
          event.payload,
        ),
      },
      conflict:
        event.conflict == null
          ? null
          : this.conflictBaseDto(event.conflict, diagnostic),
      incidents: event.incidents.map((incident) => ({
        id: incident.id,
        code: incident.code,
        message: incident.message,
        severity: incident.severity,
        details: this.diagnostics.sanitizePayload(incident.details),
        createdAt: incident.createdAt.toISOString(),
      })),
      classification: diagnostic.classification,
      recommendedAction: diagnostic.recommendedAction,
      canReprocess: diagnostic.canReprocess,
      canArchive: diagnostic.canArchive,
      risks: diagnostic.risks,
      blockers: diagnostic.blockers,
      message: diagnostic.message,
    };
  }

  async listConflicts(
    companyId: string,
    query: AdminSyncCenterConflictsQueryInput,
  ) {
    await this.requireCompany(companyId);
    const where: Prisma.SyncConflictWhereInput = {
      companyId,
      ...(query.status == null
        ? {}
        : { status: query.status as SyncConflictStatus }),
      ...(query.code == null ? {} : { code: query.code }),
      ...(query.entity == null ? {} : { entity: query.entity }),
    };
    const { skip, take } = toPaginationParams(query);
    const [total, conflicts] = await prisma.$transaction([
      prisma.syncConflict.count({ where }),
      prisma.syncConflict.findMany({
        where,
        skip,
        take,
        orderBy: { createdAt: "desc" },
        include: { syncEvent: true },
      }),
    ]);

    return buildAdminListResponse({
      items: await Promise.all(
        conflicts.map((conflict) => this.toConflictListItem(conflict)),
      ),
      page: query.page,
      pageSize: query.pageSize,
      total,
      filters: {
        status: query.status?.toLowerCase() ?? null,
        code: query.code ?? null,
        entity: query.entity ?? null,
      },
      sort: { by: "createdAt", direction: "desc" },
    });
  }

  async getConflict(conflictId: string, companyId: string) {
    const conflict = await this.findConflict(conflictId, companyId);
    if (conflict == null) {
      throw new AppError(
        "Conflito de sync nao encontrado.",
        404,
        "SYNC_CONFLICT_NOT_FOUND",
      );
    }

    const diagnostic = await this.classifyConflict(conflict);
    return {
      conflict: {
        ...this.conflictBaseDto(conflict, diagnostic),
        payload: this.diagnostics.sanitizePayload(conflict.payload),
        resolution: this.diagnostics.sanitizePayload(conflict.resolution),
      },
      event: {
        ...this.eventBaseDto(conflict.syncEvent),
        payload: this.diagnostics.sanitizePayload(conflict.syncEvent.payload),
        safePayloadPreview: this.diagnostics.safePayloadPreview(
          conflict.entity,
          conflict.syncEvent.payload,
        ),
      },
      incidents: conflict.syncEvent.incidents.map((incident) => ({
        id: incident.id,
        code: incident.code,
        message: incident.message,
        severity: incident.severity,
        details: this.diagnostics.sanitizePayload(incident.details),
        createdAt: incident.createdAt.toISOString(),
      })),
      classification: diagnostic.classification,
      recommendedAction: diagnostic.recommendedAction,
      canReprocess: diagnostic.canReprocess,
      canArchive: diagnostic.canArchive,
      canCreateManualStockAdjustment: diagnostic.canCreateManualStockAdjustment,
      risks: diagnostic.risks,
      blockers: diagnostic.blockers,
      message: diagnostic.message,
    };
  }

  async reprocessDryRun(
    eventId: string,
    input: AdminSyncCenterDryRunBodyInput,
  ) {
    const event = await this.requireEvent(eventId, input.companyId);
    const diagnostic = await this.classifyEvent(event);
    return {
      wouldReprocess: diagnostic.canReprocess,
      classification: diagnostic.classification,
      blockers: diagnostic.blockers,
      expectedAction: diagnostic.recommendedAction,
      risks: diagnostic.risks,
      message: diagnostic.message,
    };
  }

  async reprocessEvent(
    eventId: string,
    input: AdminSyncCenterReprocessBodyInput,
    action: AdminActionContext,
  ) {
    const event = await this.requireEvent(eventId, input.companyId);
    const before = this.eventAuditSnapshot(event);
    const diagnostic = await this.classifyEvent(event);
    this.assertReprocessable(diagnostic);

    const result = await prisma.$transaction(async (tx) => {
      const context = await this.buildMaterializerContext(tx, event);
      const materialized = await this.materializer.materialize({
        tx,
        context,
        event: this.toPushEventInput(event),
        payload: asRecord(event.payload),
      });

      if (materialized.outcome === "accepted") {
        const serverVersion = await this.versionService.nextCompanyVersion(
          tx,
          event.companyId,
        );
        await this.checkpointService.recordPush({
          tx,
          companyId: event.companyId,
          deviceId: event.deviceId,
          feature: event.feature,
          serverVersion,
        });
        return tx.syncEvent.update({
          where: { id: event.id },
          data: {
            status: SyncEventStatus.ACCEPTED,
            entityServerId: materialized.entityServerId ?? event.entityServerId,
            serverVersion,
            rejectionCode: null,
            rejectionMessage: null,
            materializedAt:
              materialized.materializedAt === undefined
                ? new Date()
                : materialized.materializedAt,
          },
        });
      }

      if (materialized.outcome === "duplicate") {
        return tx.syncEvent.update({
          where: { id: event.id },
          data: {
            status: SyncEventStatus.DUPLICATE,
            entityServerId: materialized.entityServerId ?? event.entityServerId,
            rejectionCode: null,
            rejectionMessage: null,
          },
        });
      }

      if (materialized.outcome === "conflict") {
        const serverVersion = await this.versionService.nextCompanyVersion(
          tx,
          event.companyId,
        );
        await this.checkpointService.recordPush({
          tx,
          companyId: event.companyId,
          deviceId: event.deviceId,
          feature: event.feature,
          serverVersion,
        });
        const updated = await tx.syncEvent.update({
          where: { id: event.id },
          data: {
            status: SyncEventStatus.CONFLICT,
            serverVersion,
            rejectionCode: null,
            rejectionMessage: null,
          },
        });
        await tx.syncConflict.upsert({
          where: { syncEventId: event.id },
          create: {
            companyId: event.companyId,
            deviceId: event.deviceId,
            userId: event.userId,
            syncEventId: event.id,
            entity: event.entity,
            entityLocalId: event.entityLocalId,
            entityServerId: event.entityServerId,
            code: materialized.code,
            message: materialized.message,
            payload: materialized.payload ?? {},
          },
          update: {
            status: SyncConflictStatus.OPEN,
            code: materialized.code,
            message: materialized.message,
            payload: materialized.payload ?? {},
            resolvedAt: null,
            resolvedByUserId: null,
          },
        });
        return updated;
      }

      return tx.syncEvent.update({
        where: { id: event.id },
        data: {
          status: SyncEventStatus.REJECTED,
          rejectionCode: materialized.code,
          rejectionMessage: materialized.message,
        },
      });
    });

    await this.recordAudit({
      actorUserId: action.actorUserId,
      companyId: input.companyId,
      action: "sync.event.reprocess",
      targetType: "SyncEvent",
      targetId: event.id,
      before,
      after: this.eventAuditSnapshot(result),
      reason: input.reason,
      metadata: {
        source: "admin_sync_center",
        classification: diagnostic.classification,
        confirmationText: input.confirmationText,
      },
      ipAddress: action.ipAddress,
      userAgent: action.userAgent,
    });

    return {
      ok: true,
      event: this.eventBaseDto(result),
      classification: diagnostic.classification,
      message: "Evento reprocessado com auditoria.",
    };
  }

  async archiveDryRun(
    conflictId: string,
    input: AdminSyncCenterDryRunBodyInput,
  ) {
    const conflict = await this.requireConflict(conflictId, input.companyId);
    if (conflict.status !== SyncConflictStatus.OPEN) {
      return {
        wouldArchive: false,
        classification: "ALREADY_HANDLED",
        expectedConfirmationText: "ARQUIVAR",
        blockers: ["Este conflito ja foi tratado."],
        risks: [],
        message: "Este conflito ja foi tratado.",
      };
    }
    const diagnostic = await this.classifyConflict(conflict);
    return {
      wouldArchive: diagnostic.canArchive,
      classification: diagnostic.classification,
      expectedConfirmationText: "ARQUIVAR",
      blockers: diagnostic.canArchive ? [] : diagnostic.blockers,
      risks: diagnostic.risks,
      message: diagnostic.canArchive
        ? "Conflito pode ser arquivado com auditoria. Nenhum dado operacional sera alterado."
        : diagnostic.message,
    };
  }

  async archiveConflict(
    conflictId: string,
    input: AdminSyncCenterArchiveBodyInput,
    action: AdminActionContext,
  ) {
    const conflict = await this.requireConflict(conflictId, input.companyId);
    if (input.confirmationText !== "ARQUIVAR") {
      throw new AppError(
        "Digite ARQUIVAR para confirmar.",
        422,
        "SYNC_CONFLICT_CONFIRMATION_REQUIRED",
        { expectedConfirmationText: "ARQUIVAR" },
      );
    }
    if (conflict.status !== SyncConflictStatus.OPEN) {
      throw new AppError(
        "Este conflito ja foi tratado.",
        409,
        "SYNC_CONFLICT_ALREADY_HANDLED",
        { status: conflict.status },
      );
    }
    const diagnostic = await this.classifyConflict(conflict);
    if (!diagnostic.canArchive) {
      throw new AppError(
        "Conflito bloqueado para arquivamento automatico.",
        409,
        "SYNC_CONFLICT_ARCHIVE_BLOCKED",
        {
          classification: diagnostic.classification,
          blockers: diagnostic.blockers,
        },
      );
    }

    const before = this.conflictAuditSnapshot(conflict);
    const resolution = {
      action: "archive",
      strategy: "archived_legacy_event",
      reason: input.reason,
      reviewedBy: action.actorUserId,
      reviewedAt: new Date().toISOString(),
      note: input.note ?? null,
      source: "admin_web",
    };
    const archived = await prisma.syncConflict.update({
      where: { id: conflict.id },
      data: {
        status: SyncConflictStatus.RESOLVED,
        resolution,
        resolvedAt: new Date(),
        resolvedByUserId: action.actorUserId,
      },
    });

    await this.recordAudit({
      actorUserId: action.actorUserId,
      companyId: input.companyId,
      action: "sync.conflict.archive",
      targetType: "SyncConflict",
      targetId: conflict.id,
      before,
      after: this.conflictAuditSnapshot(archived),
      reason: input.reason,
      metadata: {
        source: "admin_sync_center",
        classification: diagnostic.classification,
        confirmationText: input.confirmationText,
      },
      ipAddress: action.ipAddress,
      userAgent: action.userAgent,
    });

    return {
      ok: true,
      conflict: {
        id: archived.id,
        status: archived.status.toLowerCase(),
        resolution: archived.resolution,
        resolvedAt: archived.resolvedAt?.toISOString() ?? null,
      },
      message:
        "Conflito arquivado com auditoria. Nenhum dado operacional foi alterado.",
    };
  }

  async manualStockAdjustmentDryRun(
    conflictId: string,
    input: AdminSyncCenterDryRunBodyInput,
  ) {
    const conflict = await this.requireConflict(conflictId, input.companyId);
    const diagnostic = await this.classifyConflict(conflict);
    return {
      canCreateManualStockAdjustment: false,
      classification: diagnostic.classification,
      blockers: [
        "Ajuste manual auditado de estoque ainda nao esta disponivel no Centro de Sincronizacao.",
      ],
      risks: diagnostic.risks,
      message:
        "Ajuste manual auditado ainda nao esta disponivel. Use revisao operacional fora desta fase.",
    };
  }

  async manualStockAdjustment(
    _conflictId: string,
    _input: AdminSyncCenterManualStockAdjustmentBodyInput,
  ) {
    throw new AppError(
      "Ajuste manual auditado de estoque ainda nao esta disponivel.",
      501,
      "MANUAL_STOCK_ADJUSTMENT_NOT_IMPLEMENTED",
    );
  }

  private async toEventListItem(
    event: SyncEvent & { conflict?: { id: string } | null },
  ) {
    const diagnostic = await this.classifyEvent(event);
    return {
      ...this.eventBaseDto(event),
      relatedConflictId: event.conflict?.id ?? null,
      classification: diagnostic.classification,
      recommendedAction: diagnostic.recommendedAction,
      canReprocess: diagnostic.canReprocess,
      canArchive: diagnostic.canArchive,
      safePayloadPreview: this.diagnostics.safePayloadPreview(
        event.entity,
        event.payload,
      ),
    };
  }

  private async toConflictListItem(
    conflict: Prisma.SyncConflictGetPayload<{ include: { syncEvent: true } }>,
  ) {
    const diagnostic = await this.classifyConflict(conflict);
    return this.conflictBaseDto(conflict, diagnostic);
  }

  private eventBaseDto(event: {
    id: string;
    eventId: string;
    feature: string;
    entity: string;
    operation: string;
    entityLocalId: string | null;
    entityServerId: string | null;
    status: SyncEventStatus;
    serverVersion: bigint | null;
    rejectionCode: string | null;
    rejectionMessage: string | null;
    occurredAt: Date;
    createdAt: Date;
    updatedAt: Date;
    materializedAt: Date | null;
  }) {
    return {
      id: event.id,
      eventId: event.eventId,
      feature: event.feature,
      entity: event.entity,
      operation: event.operation,
      entityLocalId: event.entityLocalId,
      entityServerId: event.entityServerId,
      status: event.status.toLowerCase(),
      serverVersion: event.serverVersion?.toString() ?? null,
      rejectionCode: event.rejectionCode,
      rejectionMessage: event.rejectionMessage,
      occurredAt: event.occurredAt.toISOString(),
      createdAt: event.createdAt.toISOString(),
      updatedAt: event.updatedAt.toISOString(),
      materializedAt: event.materializedAt?.toISOString() ?? null,
    };
  }

  private conflictBaseDto(
    conflict: {
      id: string;
      syncEventId: string;
      entity: string;
      entityLocalId: string | null;
      entityServerId: string | null;
      code: string;
      message: string;
      status: SyncConflictStatus;
      createdAt: Date;
      updatedAt: Date;
      resolvedAt: Date | null;
      payload: Prisma.JsonValue | null;
    },
    diagnostic: SyncDiagnosticResult,
  ) {
    return {
      conflictId: conflict.id,
      syncEventId: conflict.syncEventId,
      entity: conflict.entity,
      entityLocalId: conflict.entityLocalId,
      entityServerId: conflict.entityServerId,
      code: conflict.code,
      message: conflict.message,
      status: conflict.status.toLowerCase(),
      createdAt: conflict.createdAt.toISOString(),
      updatedAt: conflict.updatedAt.toISOString(),
      resolvedAt: conflict.resolvedAt?.toISOString() ?? null,
      classification: diagnostic.classification,
      recommendedAction: diagnostic.recommendedAction,
      canReprocess: diagnostic.canReprocess,
      canArchive: diagnostic.canArchive,
      canCreateManualStockAdjustment: diagnostic.canCreateManualStockAdjustment,
      safePayloadPreview: this.diagnostics.safePayloadPreview(
        conflict.entity,
        conflict.payload,
      ),
    };
  }

  private async classifyEvent(event: {
    companyId: string;
    entity: string;
    operation: string;
    status: SyncEventStatus;
    rejectionCode: string | null;
    payload: Prisma.JsonValue;
  }) {
    return this.diagnostics.classify({
      companyId: event.companyId,
      entity: event.entity,
      operation: event.operation,
      status: event.status,
      rejectionCode: event.rejectionCode,
      payload: event.payload,
    });
  }

  private async classifyConflict(conflict: {
    companyId: string;
    entity: string;
    code: string;
    payload: Prisma.JsonValue | null;
    syncEvent?: {
      operation: string;
      status: SyncEventStatus;
      rejectionCode: string | null;
      payload: Prisma.JsonValue;
    };
  }) {
    return this.diagnostics.classify({
      companyId: conflict.companyId,
      entity: conflict.entity,
      operation: conflict.syncEvent?.operation ?? "create",
      status: conflict.syncEvent?.status ?? null,
      rejectionCode: conflict.syncEvent?.rejectionCode ?? null,
      code: conflict.code,
      payload: conflict.syncEvent?.payload ?? conflict.payload,
    });
  }

  private async requireCompany(companyId: string) {
    const company = await prisma.company.findUnique({
      where: { id: companyId },
      include: {
        license: true,
        syncState: true,
      },
    });
    if (company == null) {
      throw new AppError(
        "Empresa nao encontrada.",
        404,
        "ADMIN_COMPANY_NOT_FOUND",
      );
    }
    return company;
  }

  private async findEvent(eventId: string, companyId: string) {
    return prisma.syncEvent.findFirst({
      where: {
        companyId,
        OR: [{ id: eventId }, { eventId }],
      },
      include: {
        conflict: true,
        incidents: {
          orderBy: { createdAt: "desc" },
          take: 5,
        },
        device: {
          select: {
            id: true,
            deviceLabel: true,
            clientInstanceId: true,
            status: true,
            platform: true,
            appVersion: true,
          },
        },
        user: {
          select: {
            id: true,
            name: true,
            email: true,
          },
        },
      },
    });
  }

  private async requireEvent(eventId: string, companyId: string) {
    const event = await this.findEvent(eventId, companyId);
    if (event == null) {
      throw new AppError(
        "Evento de sync nao encontrado.",
        404,
        "SYNC_EVENT_NOT_FOUND",
      );
    }
    return event;
  }

  private async findConflict(conflictId: string, companyId: string) {
    return prisma.syncConflict.findFirst({
      where: {
        id: conflictId,
        companyId,
      },
      include: {
        syncEvent: {
          include: {
            incidents: {
              orderBy: { createdAt: "desc" },
              take: 5,
            },
          },
        },
        device: {
          select: {
            id: true,
            deviceLabel: true,
            clientInstanceId: true,
            status: true,
          },
        },
        user: {
          select: {
            id: true,
            name: true,
            email: true,
          },
        },
        resolvedBy: {
          select: {
            id: true,
            name: true,
            email: true,
          },
        },
      },
    });
  }

  private async requireConflict(conflictId: string, companyId: string) {
    const conflict = await this.findConflict(conflictId, companyId);
    if (conflict == null) {
      throw new AppError(
        "Conflito de sync nao encontrado.",
        404,
        "SYNC_CONFLICT_NOT_FOUND",
      );
    }
    return conflict;
  }

  private assertReprocessable(diagnostic: SyncDiagnosticResult) {
    if (diagnostic.classification !== "REPROCESSABLE") {
      throw new AppError(
        "Evento bloqueado para reprocessamento automatico.",
        409,
        "SYNC_REPROCESS_BLOCKED",
        {
          classification: diagnostic.classification,
          blockers: diagnostic.blockers,
        },
      );
    }
  }

  private toPushEventInput(event: EventWithRelations): SyncPushEventInput {
    return {
      eventId: event.eventId,
      feature: event.feature,
      entity: event.entity,
      operation: event.operation,
      entityLocalId: event.entityLocalId ?? undefined,
      entityServerId: event.entityServerId ?? undefined,
      occurredAt: event.occurredAt.toISOString(),
      payload: asRecord(event.payload),
    };
  }

  private async buildMaterializerContext(
    tx: Prisma.TransactionClient,
    event: EventWithRelations,
  ): Promise<AppContext> {
    const [company, license] = await Promise.all([
      tx.company.findUniqueOrThrow({
        where: { id: event.companyId },
        select: {
          id: true,
          name: true,
          legalName: true,
          documentNumber: true,
          receiptDisplayName: true,
          receiptDocument: true,
          receiptPhone: true,
          receiptAddress: true,
          receiptFooterMessage: true,
          showDocumentOnReceipt: true,
          showPhoneOnReceipt: true,
          showAddressOnReceipt: true,
          showFooterMessageOnReceipt: true,
        },
      }),
      tx.license.findUnique({
        where: { companyId: event.companyId },
      }),
    ]);

    return {
      user: event.user,
      company: {
        id: company.id,
        name: company.name,
        legalName: company.legalName,
        documentNumber: company.documentNumber,
        receiptDisplayName: company.receiptDisplayName,
        receiptDocument: company.receiptDocument,
        receiptPhone: company.receiptPhone,
        receiptAddress: company.receiptAddress,
        receiptFooterMessage: company.receiptFooterMessage,
        showDocumentOnReceipt: company.showDocumentOnReceipt,
        showPhoneOnReceipt: company.showPhoneOnReceipt,
        showAddressOnReceipt: company.showAddressOnReceipt,
        showFooterMessageOnReceipt: company.showFooterMessageOnReceipt,
        setupCompleted: true,
      },
      membership: {
        id: "admin-sync-center",
        role: "PLATFORM_ADMIN",
        permissions: [],
      },
      license: {
        id: license?.id ?? "admin-sync-center-license",
        plan: license?.plan ?? "unknown",
        status: license?.status.toString().toLowerCase() ?? "unknown",
        syncEnabled: license?.syncEnabled ?? true,
        maxDevices: license?.maxDevices ?? null,
        expiresAt: license?.expiresAt?.toISOString() ?? null,
        pendingPlan: license?.pendingPlan ?? null,
        pendingPlanRequestedAt:
          license?.pendingPlanRequestedAt?.toISOString() ?? null,
      },
      device: {
        id: event.device.id,
        clientInstanceId: event.device.clientInstanceId,
        status: event.device.status,
        deviceLabel: event.device.deviceLabel,
        platform: event.device.platform,
        appVersion: event.device.appVersion,
        lastSeenAt: null,
      },
      plan: "PRO",
      features: {} as AppContext["features"],
      limits: {} as AppContext["limits"],
      clientInstanceId: event.device.clientInstanceId,
      tenantReady: true,
    };
  }

  private async recordAudit(input: {
    actorUserId: string;
    companyId: string;
    action: string;
    targetType: string;
    targetId: string;
    before: Prisma.InputJsonValue;
    after: Prisma.InputJsonValue;
    reason: string;
    metadata: Prisma.InputJsonValue;
    ipAddress: string | null;
    userAgent: string | null;
  }) {
    const details = this.diagnostics.sanitizePayload({
      targetType: input.targetType,
      targetId: input.targetId,
      before: input.before,
      after: input.after,
      reason: input.reason,
      metadata: input.metadata,
      ipAddress: input.ipAddress,
      userAgent: input.userAgent,
      createdAt: new Date().toISOString(),
    });
    await prisma.adminAuditLog.create({
      data: {
        actorUserId: input.actorUserId,
        targetCompanyId: input.companyId,
        action: input.action,
        details,
      },
    });
  }

  private eventAuditSnapshot(event: {
    id: string;
    eventId: string;
    status: SyncEventStatus;
    rejectionCode: string | null;
    rejectionMessage: string | null;
    serverVersion: bigint | null;
    entityServerId: string | null;
    materializedAt: Date | null;
  }): Prisma.InputJsonValue {
    return {
      id: event.id,
      eventId: event.eventId,
      status: event.status,
      rejectionCode: event.rejectionCode,
      rejectionMessage: event.rejectionMessage,
      serverVersion: event.serverVersion?.toString() ?? null,
      entityServerId: event.entityServerId,
      materializedAt: event.materializedAt?.toISOString() ?? null,
    };
  }

  private conflictAuditSnapshot(conflict: {
    id: string;
    status: SyncConflictStatus;
    resolution: Prisma.JsonValue | null;
    resolvedAt: Date | null;
    resolvedByUserId: string | null;
  }): Prisma.InputJsonValue {
    return {
      id: conflict.id,
      status: conflict.status,
      resolution: this.diagnostics.sanitizePayload(conflict.resolution),
      resolvedAt: conflict.resolvedAt?.toISOString() ?? null,
      resolvedByUserId: conflict.resolvedByUserId,
    };
  }

  private companySearchWhere(
    search: string | undefined,
  ): Prisma.CompanyWhereInput {
    if (search == null) {
      return {};
    }
    return {
      OR: [
        { name: { contains: search, mode: "insensitive" } },
        { legalName: { contains: search, mode: "insensitive" } },
        { slug: { contains: search, mode: "insensitive" } },
      ],
    };
  }

  private recommendCompanyAction(syncStatus: string) {
    if (syncStatus === "failed") {
      return "Existem falhas de materializacao. Abra os eventos com erro antes de qualquer acao.";
    }
    if (syncStatus === "conflict") {
      return "Existem conflitos abertos. Classifique e use dry-run antes de arquivar ou reprocessar.";
    }
    if (syncStatus === "requires_review") {
      return "Existem eventos pendentes ou incidentes. Revise a fila operacional.";
    }
    return "Nenhuma acao urgente encontrada para sync operacional.";
  }
}

function emptyEventCounts(): Record<SyncEventStatus, number> {
  return {
    PENDING: 0,
    ACCEPTED: 0,
    DUPLICATE: 0,
    REJECTED: 0,
    CONFLICT: 0,
    FAILED: 0,
  };
}

function eventCountsToDto(counts: Record<SyncEventStatus, number>) {
  return {
    pending: counts.PENDING,
    accepted: counts.ACCEPTED,
    duplicate: counts.DUPLICATE,
    rejected: counts.REJECTED,
    conflict: counts.CONFLICT,
    failed: counts.FAILED,
  };
}

function eventCountsByCompany(
  rows: Array<{
    companyId: string;
    status: SyncEventStatus;
    _count: { _all: number };
  }>,
) {
  const map = new Map<string, Record<SyncEventStatus, number>>();
  for (const row of rows) {
    const counts = map.get(row.companyId) ?? emptyEventCounts();
    counts[row.status] = row._count._all;
    map.set(row.companyId, counts);
  }
  return map;
}

function openConflictsByCompany(
  rows: Array<{
    companyId: string;
    status: SyncConflictStatus;
    _count: { _all: number };
  }>,
) {
  const map = new Map<string, number>();
  for (const row of rows) {
    if (row.status === "OPEN") {
      map.set(row.companyId, row._count._all);
    }
  }
  return map;
}

function countByCompany(
  rows: Array<{
    companyId: string | null;
    _count: { _all: number };
  }>,
) {
  const map = new Map<string, number>();
  for (const row of rows) {
    if (row.companyId != null) {
      map.set(row.companyId, row._count._all);
    }
  }
  return map;
}

function maxDateByCompany(
  rows: Array<{
    companyId: string | null;
    _max: { createdAt: Date | null };
  }>,
) {
  const map = new Map<string, Date>();
  for (const row of rows) {
    if (row.companyId != null && row._max.createdAt != null) {
      map.set(row.companyId, row._max.createdAt);
    }
  }
  return map;
}

function classifyCompanySyncStatus(input: {
  counts: Record<SyncEventStatus, number>;
  openConflictCount: number;
  incidentCount: number;
}) {
  if (input.counts.FAILED > 0) {
    return "failed";
  }
  if (input.openConflictCount > 0 || input.counts.CONFLICT > 0) {
    return "conflict";
  }
  if (input.counts.PENDING > 0 || input.incidentCount > 0) {
    return "requires_review";
  }
  return "healthy";
}

function createdAtRange(from: Date | undefined, to: Date | undefined) {
  if (from == null && to == null) {
    return {};
  }
  return {
    createdAt: {
      ...(from == null ? {} : { gte: from }),
      ...(to == null ? {} : { lte: to }),
    },
  };
}
