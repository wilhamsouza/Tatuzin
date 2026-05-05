import {
  type CompanyDeviceStatus,
  type Prisma,
  type SyncConflictStatus,
  type SyncEventStatus,
} from '@prisma/client';

import { prisma } from '../../database/prisma';
import { buildAdminListResponse } from '../../shared/http/api-response';
import { AppError } from '../../shared/http/app-error';
import type {
  AdminCompanySyncConflictsQueryInput,
  AdminCompanySyncEventsQueryInput,
  AdminCompanySyncIncidentsQueryInput,
} from './admin.schemas';

type DeviceSyncState = {
  deviceId: string;
  deviceLabel: string | null;
  clientInstanceId: string;
  status: string;
  lastSyncAt: string | null;
  lastSeenAt: string | null;
};

export class AdminSyncHealthService {
  async getHealth(companyId: string) {
    const company = await this.getCompanyForSyncHealth(companyId);

    const [
      deviceStatusCounts,
      eventStatusCounts,
      openConflictsCount,
      lastMaterialized,
      lastIncident,
      devices,
      checkpoints,
      latestEventsByDevice,
    ] = await Promise.all([
      prisma.companyDevice.groupBy({
        by: ['status'],
        where: { companyId },
        _count: { _all: true },
      }),
      prisma.syncEvent.groupBy({
        by: ['status'],
        where: { companyId },
        _count: { _all: true },
      }),
      prisma.syncConflict.count({
        where: { companyId, status: 'OPEN' },
      }),
      prisma.syncEvent.findFirst({
        where: { companyId, materializedAt: { not: null } },
        orderBy: { materializedAt: 'desc' },
        select: { materializedAt: true },
      }),
      prisma.syncIncident.findFirst({
        where: { companyId },
        orderBy: { createdAt: 'desc' },
      }),
      prisma.companyDevice.findMany({
        where: { companyId },
        orderBy: [{ status: 'asc' }, { lastSeenAt: 'desc' }],
        select: {
          id: true,
          clientInstanceId: true,
          deviceLabel: true,
          status: true,
          lastSeenAt: true,
        },
      }),
      prisma.syncCheckpoint.findMany({
        where: { companyId },
        select: {
          deviceId: true,
          lastPushedAt: true,
          lastPulledAt: true,
          updatedAt: true,
        },
      }),
      prisma.syncEvent.groupBy({
        by: ['deviceId'],
        where: { companyId },
        _max: { createdAt: true },
      }),
    ]);

    const devicesSummary = this.deviceCounts(deviceStatusCounts);
    const eventsSummary = this.eventCounts(eventStatusCounts);
    const lastSyncByDevice = this.lastSyncByDevice({
      checkpoints,
      latestEventsByDevice,
    });
    const deviceSyncStates = devices.map((device) => {
      const lastSyncAt = lastSyncByDevice.get(device.id) ?? null;
      return {
        deviceId: device.id,
        deviceLabel: device.deviceLabel,
        clientInstanceId: device.clientInstanceId,
        status: device.status.toLowerCase(),
        lastSyncAt: lastSyncAt?.toISOString() ?? null,
        lastSeenAt: device.lastSeenAt?.toISOString() ?? null,
      };
    });
    const latestDeviceSyncAt = this.latestDate(
      deviceSyncStates.map((device) =>
        device.lastSyncAt == null ? null : new Date(device.lastSyncAt),
      ),
    );
    const lastSyncAt =
      latestDeviceSyncAt?.toISOString() ??
      lastMaterialized?.materializedAt?.toISOString() ??
      null;

    return {
      companyId: company.id,
      companyName: company.name,
      companySlug: company.slug,
      currentServerVersion: company.syncState?.currentVersion.toString() ?? '0',
      serverFirstSnapshotVersion:
        company.syncState?.serverFirstSnapshotVersion.toString() ?? '0',
      status: this.classifyHealth({
        syncEnabled: company.license?.syncEnabled ?? false,
        openConflictsCount,
        failedCount: eventsSummary.failed,
        lastIncidentSeverity: lastIncident?.severity ?? null,
        lastSyncAt,
        activeDevicesCount: devicesSummary.active,
      }),
      syncEnabled: company.license?.syncEnabled ?? false,
      license: company.license == null ? null : this.toLicenseDto(company),
      devices: devicesSummary,
      events: eventsSummary,
      openConflictsCount,
      lastMaterializedAt:
        lastMaterialized?.materializedAt?.toISOString() ?? null,
      lastSyncAt,
      deviceSyncStates,
      lastIncident:
        lastIncident == null
          ? null
          : {
              id: lastIncident.id,
              code: lastIncident.code,
              message: lastIncident.message,
              severity: lastIncident.severity.toLowerCase(),
              createdAt: lastIncident.createdAt.toISOString(),
            },
    };
  }

  async listEvents(
    companyId: string,
    query: AdminCompanySyncEventsQueryInput,
  ) {
    await this.getCompanyForSyncHealth(companyId);
    const where: Prisma.SyncEventWhereInput = {
      companyId,
      ...(query.deviceId == null ? {} : { deviceId: query.deviceId }),
      ...(query.status == null
        ? {}
        : { status: query.status as SyncEventStatus }),
      ...(query.entity == null ? {} : { entity: query.entity }),
      ...(query.feature == null ? {} : { feature: query.feature }),
      ...this.createdAtRange(query.from, query.to),
    };

    const [total, events] = await prisma.$transaction([
      prisma.syncEvent.count({ where }),
      prisma.syncEvent.findMany({
        where,
        skip: this.skip(query),
        take: query.limit,
        orderBy: { createdAt: 'desc' },
        include: {
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
        },
      }),
    ]);

    return buildAdminListResponse({
      items: events.map((event) => ({
        id: event.id,
        eventId: event.eventId,
        feature: event.feature,
        entity: event.entity,
        operation: event.operation,
        entityLocalId: event.entityLocalId,
        entityServerId: event.entityServerId,
        status: event.status.toLowerCase(),
        occurredAt: event.occurredAt.toISOString(),
        createdAt: event.createdAt.toISOString(),
        materializedAt: event.materializedAt?.toISOString() ?? null,
        serverVersion: event.serverVersion?.toString() ?? null,
        errorCode: event.rejectionCode,
        errorMessage: event.rejectionMessage,
        payloadSummary: this.summarizeJson(event.payload),
        device: this.toDeviceRef(event.device),
        user: this.toUserRef(event.user),
      })),
      page: query.page,
      pageSize: query.limit,
      total,
      filters: {
        deviceId: query.deviceId ?? null,
        status: query.status?.toLowerCase() ?? null,
        entity: query.entity ?? null,
        feature: query.feature ?? null,
        from: query.from?.toISOString() ?? null,
        to: query.to?.toISOString() ?? null,
      },
      sort: { by: 'createdAt', direction: 'desc' },
    });
  }

  async listConflicts(
    companyId: string,
    query: AdminCompanySyncConflictsQueryInput,
  ) {
    await this.getCompanyForSyncHealth(companyId);
    const where: Prisma.SyncConflictWhereInput = {
      companyId,
      ...(query.status == null
        ? {}
        : { status: query.status as SyncConflictStatus }),
    };

    const [total, conflicts] = await prisma.$transaction([
      prisma.syncConflict.count({ where }),
      prisma.syncConflict.findMany({
        where,
        skip: this.skip(query),
        take: query.limit,
        orderBy: { createdAt: 'desc' },
        include: {
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
          syncEvent: {
            select: {
              id: true,
              eventId: true,
              feature: true,
              entity: true,
              operation: true,
              status: true,
              serverVersion: true,
            },
          },
        },
      }),
    ]);

    return buildAdminListResponse({
      items: conflicts.map((conflict) => ({
        id: conflict.id,
        entity: conflict.entity,
        entityLocalId: conflict.entityLocalId,
        entityServerId: conflict.entityServerId,
        code: conflict.code,
        message: conflict.message,
        status: conflict.status.toLowerCase(),
        createdAt: conflict.createdAt.toISOString(),
        resolvedAt: conflict.resolvedAt?.toISOString() ?? null,
        payloadSummary: this.summarizeJson(conflict.payload),
        resolutionSummary: this.summarizeJson(conflict.resolution),
        device: this.toDeviceRef(conflict.device),
        user: this.toUserRef(conflict.user),
        resolvedBy:
          conflict.resolvedBy == null ? null : this.toUserRef(conflict.resolvedBy),
        event: {
          id: conflict.syncEvent.id,
          eventId: conflict.syncEvent.eventId,
          feature: conflict.syncEvent.feature,
          entity: conflict.syncEvent.entity,
          operation: conflict.syncEvent.operation,
          status: conflict.syncEvent.status.toLowerCase(),
          serverVersion: conflict.syncEvent.serverVersion?.toString() ?? null,
        },
      })),
      page: query.page,
      pageSize: query.limit,
      total,
      filters: {
        status: query.status?.toLowerCase() ?? null,
      },
      sort: { by: 'createdAt', direction: 'desc' },
    });
  }

  async listIncidents(
    companyId: string,
    query: AdminCompanySyncIncidentsQueryInput,
  ) {
    await this.getCompanyForSyncHealth(companyId);
    const where: Prisma.SyncIncidentWhereInput = {
      companyId,
      ...(query.severity == null ? {} : { severity: query.severity }),
      ...this.createdAtRange(query.from, query.to),
    };

    const [total, incidents] = await prisma.$transaction([
      prisma.syncIncident.count({ where }),
      prisma.syncIncident.findMany({
        where,
        skip: this.skip(query),
        take: query.limit,
        orderBy: { createdAt: 'desc' },
        include: {
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
          syncEvent: {
            select: {
              id: true,
              eventId: true,
              feature: true,
              entity: true,
              operation: true,
              status: true,
              serverVersion: true,
            },
          },
        },
      }),
    ]);

    return buildAdminListResponse({
      items: incidents.map((incident) => ({
        id: incident.id,
        code: incident.code,
        message: incident.message,
        severity: incident.severity.toLowerCase(),
        createdAt: incident.createdAt.toISOString(),
        detailsSummary: this.summarizeJson(incident.details),
        device: incident.device == null ? null : this.toDeviceRef(incident.device),
        user: incident.user == null ? null : this.toUserRef(incident.user),
        event:
          incident.syncEvent == null
            ? null
            : {
                id: incident.syncEvent.id,
                eventId: incident.syncEvent.eventId,
                feature: incident.syncEvent.feature,
                entity: incident.syncEvent.entity,
                operation: incident.syncEvent.operation,
                status: incident.syncEvent.status.toLowerCase(),
                serverVersion:
                  incident.syncEvent.serverVersion?.toString() ?? null,
              },
      })),
      page: query.page,
      pageSize: query.limit,
      total,
      filters: {
        severity: query.severity ?? null,
        from: query.from?.toISOString() ?? null,
        to: query.to?.toISOString() ?? null,
      },
      sort: { by: 'createdAt', direction: 'desc' },
    });
  }

  async listDevices(companyId: string) {
    await this.getCompanyForSyncHealth(companyId);
    const devices = await prisma.companyDevice.findMany({
      where: { companyId },
      orderBy: [{ status: 'asc' }, { lastSeenAt: 'desc' }],
      include: {
        user: {
          select: {
            id: true,
            name: true,
            email: true,
          },
        },
      },
    });

    return {
      items: devices.map((device) => ({
        id: device.id,
        deviceLabel: device.deviceLabel,
        platform: device.platform,
        appVersion: device.appVersion,
        status: device.status.toLowerCase(),
        lastSeenAt: device.lastSeenAt?.toISOString() ?? null,
        userId: device.userId,
        userName: device.user.name,
        userEmail: device.user.email,
        clientInstanceId: device.clientInstanceId,
        createdAt: device.createdAt.toISOString(),
        approvedAt: device.approvedAt?.toISOString() ?? null,
        revokedAt: device.revokedAt?.toISOString() ?? null,
        revokedReason: device.revokedReason,
      })),
      count: devices.length,
    };
  }

  private async getCompanyForSyncHealth(companyId: string) {
    const company = await this.findCompanyForSyncHealth(companyId);
    if (company == null) {
      throw new AppError(
        'Empresa nao encontrada.',
        404,
        'ADMIN_COMPANY_NOT_FOUND',
      );
    }

    return company;
  }

  private async findCompanyForSyncHealth(companyId: string) {
    return prisma.company.findUnique({
      where: { id: companyId },
      select: {
        id: true,
        name: true,
        slug: true,
        license: {
          select: {
            id: true,
            plan: true,
            status: true,
            startsAt: true,
            expiresAt: true,
            maxDevices: true,
            syncEnabled: true,
            createdAt: true,
            updatedAt: true,
          },
        },
        syncState: {
          select: {
            currentVersion: true,
            serverFirstSnapshotVersion: true,
            updatedAt: true,
          },
        },
      },
    });
  }

  private deviceCounts(
    rows: Array<{
      status: CompanyDeviceStatus;
      _count: { _all: number };
    }>,
  ) {
    const counts = {
      active: 0,
      blocked: 0,
      revoked: 0,
      pending: 0,
      total: 0,
    };

    for (const row of rows) {
      const key = row.status.toLowerCase() as keyof typeof counts;
      counts[key] = row._count._all;
      counts.total += row._count._all;
    }

    return counts;
  }

  private eventCounts(
    rows: Array<{
      status: SyncEventStatus;
      _count: { _all: number };
    }>,
  ) {
    const counts = {
      accepted: 0,
      rejected: 0,
      conflict: 0,
      failed: 0,
      duplicate: 0,
      pending: 0,
      total: 0,
    };

    for (const row of rows) {
      const key = row.status.toLowerCase() as keyof typeof counts;
      counts[key] = row._count._all;
      counts.total += row._count._all;
    }

    return counts;
  }

  private lastSyncByDevice(input: {
    checkpoints: Array<{
      deviceId: string;
      lastPushedAt: Date | null;
      lastPulledAt: Date | null;
      updatedAt: Date;
    }>;
    latestEventsByDevice: Array<{
      deviceId: string;
      _max: { createdAt: Date | null };
    }>;
  }) {
    const map = new Map<string, Date>();

    for (const checkpoint of input.checkpoints) {
      this.registerLatestDate(map, checkpoint.deviceId, checkpoint.lastPushedAt);
      this.registerLatestDate(map, checkpoint.deviceId, checkpoint.lastPulledAt);
    }

    for (const eventAggregate of input.latestEventsByDevice) {
      this.registerLatestDate(
        map,
        eventAggregate.deviceId,
        eventAggregate._max.createdAt,
      );
    }

    return map;
  }

  private registerLatestDate(
    map: Map<string, Date>,
    key: string,
    value: Date | null,
  ) {
    if (value == null) {
      return;
    }

    const current = map.get(key);
    if (current == null || value > current) {
      map.set(key, value);
    }
  }

  private latestDate(values: Array<Date | null>) {
    return values.reduce<Date | null>((latest, value) => {
      if (value == null || Number.isNaN(value.getTime())) {
        return latest;
      }
      if (latest == null || value > latest) {
        return value;
      }
      return latest;
    }, null);
  }

  private classifyHealth(input: {
    syncEnabled: boolean;
    openConflictsCount: number;
    failedCount: number;
    lastIncidentSeverity: string | null;
    lastSyncAt: string | null;
    activeDevicesCount: number;
  }) {
    if (!input.syncEnabled) {
      return 'pending';
    }

    if (
      input.failedCount > 0 ||
      input.lastIncidentSeverity === 'error' ||
      input.lastIncidentSeverity === 'critical'
    ) {
      return 'error';
    }

    if (input.openConflictsCount > 0) {
      return 'conflict';
    }

    if (input.lastSyncAt != null && input.activeDevicesCount > 0) {
      return 'synced';
    }

    return 'pending';
  }

  private toLicenseDto(company: {
    id: string;
    license: {
      id: string;
      plan: string;
      status: string;
      startsAt: Date;
      expiresAt: Date | null;
      maxDevices: number | null;
      syncEnabled: boolean;
      createdAt: Date;
      updatedAt: Date;
    } | null;
  }) {
    const license = company.license!;
    return {
      id: license.id,
      companyId: company.id,
      plan: license.plan,
      status: license.status.toLowerCase(),
      startsAt: license.startsAt.toISOString(),
      expiresAt: license.expiresAt?.toISOString() ?? null,
      maxDevices: license.maxDevices,
      syncEnabled: license.syncEnabled,
      createdAt: license.createdAt.toISOString(),
      updatedAt: license.updatedAt.toISOString(),
    };
  }

  private toDeviceRef(device: {
    id: string;
    deviceLabel: string | null;
    clientInstanceId: string;
    status: CompanyDeviceStatus;
  }) {
    return {
      id: device.id,
      deviceLabel: device.deviceLabel,
      clientInstanceId: device.clientInstanceId,
      status: device.status.toLowerCase(),
    };
  }

  private toUserRef(user: { id: string; name: string; email: string }) {
    return {
      id: user.id,
      name: user.name,
      email: user.email,
    };
  }

  private skip(query: { page: number; limit: number }) {
    return (query.page - 1) * query.limit;
  }

  private createdAtRange(from: Date | undefined, to: Date | undefined) {
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

  private summarizeJson(value: Prisma.JsonValue | null) {
    if (value == null) {
      return null;
    }

    try {
      const serialized = JSON.stringify(value);
      if (serialized.length <= 600) {
        return serialized;
      }
      return `${serialized.slice(0, 600)}...`;
    } catch (_error) {
      return '[payload indisponivel para resumo]';
    }
  }
}
