import {
  Prisma,
  SyncConflictStatus,
  SyncSupportCommandStatus,
  SyncSupportCommandType,
} from "@prisma/client";

import { prisma } from "../../database/prisma";
import { AppError } from "../../shared/http/app-error";
import type { AppContext } from "../app/app-context.types";
import type {
  SyncSupportCommandCompleteInput,
  SyncSupportCommandFailInput,
  SyncSupportDiagnosticInput,
} from "./sync.schemas";
import type {
  AdminSyncSupportActionInput,
  AdminSyncSupportDryRunInput,
} from "../admin/admin.schemas";

type AdminActionContext = {
  actorUserId: string;
  ipAddress: string | null;
  userAgent: string | null;
};

const confirmationByCommand: Record<SyncSupportCommandType, string> = {
  RETRY_FAILED_SYNC_EVENTS: "REPROCESSAR",
  REPAIR_OPERATIONAL_ORDER_ITEM_TOTAL_CENTS: "REPARAR",
  CLEAR_RESOLVED_CONFLICT_CACHE: "LIMPAR",
  FORCE_SYNC_PULL: "ATUALIZAR",
  REFRESH_SYNC_STATUS: "RECALCULAR",
};

const commandLabels: Record<SyncSupportCommandType, string> = {
  RETRY_FAILED_SYNC_EVENTS: "Reprocessar falhas locais",
  REPAIR_OPERATIONAL_ORDER_ITEM_TOTAL_CENTS: "Reparar totalCents de itens",
  CLEAR_RESOLVED_CONFLICT_CACHE: "Limpar conflitos resolvidos",
  FORCE_SYNC_PULL: "Forcar atualizacao da nuvem",
  REFRESH_SYNC_STATUS: "Recalcular status de sync",
};

export class SyncSupportService {
  async reportDiagnostic(
    context: AppContext,
    input: SyncSupportDiagnosticInput,
  ) {
    const safeDetails = sanitizeJson(input.safeDetails ?? {});
    const diagnostic = await prisma.deviceSyncDiagnostic.upsert({
      where: {
        companyId_deviceId: {
          companyId: context.company.id,
          deviceId: context.device.id,
        },
      },
      create: {
        companyId: context.company.id,
        deviceId: context.device.id,
        userId: context.user.id,
        clientInstanceId: context.clientInstanceId,
        appVersion: input.appVersion ?? context.device.appVersion,
        localSchemaVersion: input.localSchemaVersion,
        pendingCount: input.pendingCount,
        failedCount: input.failedCount,
        openConflictCount: input.openConflictCount,
        resolvedConflictCount: input.resolvedConflictCount,
        ignoredConflictCount: input.ignoredConflictCount,
        lastLocalError: truncate(input.lastLocalError, 400),
        lastLocalErrorCode: truncate(input.lastLocalErrorCode, 120),
        lastLocalErrorEntity: truncate(input.lastLocalErrorEntity, 120),
        lastPushAt: input.lastPushAt,
        lastPullAt: input.lastPullAt,
        lastSuccessfulSyncAt: input.lastSuccessfulSyncAt,
        safeDetails,
        reportedAt: new Date(),
      },
      update: {
        userId: context.user.id,
        clientInstanceId: context.clientInstanceId,
        appVersion: input.appVersion ?? context.device.appVersion,
        localSchemaVersion: input.localSchemaVersion,
        pendingCount: input.pendingCount,
        failedCount: input.failedCount,
        openConflictCount: input.openConflictCount,
        resolvedConflictCount: input.resolvedConflictCount,
        ignoredConflictCount: input.ignoredConflictCount,
        lastLocalError: truncate(input.lastLocalError, 400),
        lastLocalErrorCode: truncate(input.lastLocalErrorCode, 120),
        lastLocalErrorEntity: truncate(input.lastLocalErrorEntity, 120),
        lastPushAt: input.lastPushAt,
        lastPullAt: input.lastPullAt,
        lastSuccessfulSyncAt: input.lastSuccessfulSyncAt,
        safeDetails,
        reportedAt: new Date(),
      },
    });

    return { ok: true, diagnostic: this.diagnosticDto(diagnostic) };
  }

  async pullCommands(context: AppContext) {
    await this.expireCommands(context.company.id, context.device.id);
    const now = new Date();
    const pending = await prisma.syncSupportCommand.findMany({
      where: {
        companyId: context.company.id,
        deviceId: context.device.id,
        status: SyncSupportCommandStatus.PENDING,
        expiresAt: { gt: now },
      },
      orderBy: { requestedAt: "asc" },
      take: 10,
    });
    if (pending.length === 0) {
      return { ok: true, items: [] };
    }
    const ids = pending.map((command) => command.id);
    await prisma.syncSupportCommand.updateMany({
      where: {
        id: { in: ids },
        companyId: context.company.id,
        deviceId: context.device.id,
        status: SyncSupportCommandStatus.PENDING,
      },
      data: {
        status: SyncSupportCommandStatus.RUNNING,
        pickedUpAt: now,
      },
    });
    const running = await prisma.syncSupportCommand.findMany({
      where: { id: { in: ids } },
      orderBy: { requestedAt: "asc" },
    });
    return {
      ok: true,
      items: running.map((command) => this.commandDto(command)),
    };
  }

  async startCommand(context: AppContext, commandId: string) {
    const command = await this.requireDeviceCommand(context, commandId);
    if (this.isExecutableExpired(command)) {
      const expired = await this.markExpired(command.id);
      return { ok: false, command: this.commandDto(expired) };
    }
    if (command.status === SyncSupportCommandStatus.RUNNING) {
      return { ok: true, command: this.commandDto(command) };
    }
    if (command.status !== SyncSupportCommandStatus.PENDING) {
      throw new AppError(
        "Comando nao esta pendente.",
        409,
        "SYNC_SUPPORT_COMMAND_NOT_PENDING",
      );
    }
    const running = await prisma.syncSupportCommand.update({
      where: { id: command.id },
      data: {
        status: SyncSupportCommandStatus.RUNNING,
        pickedUpAt: new Date(),
      },
    });
    return { ok: true, command: this.commandDto(running) };
  }

  async completeCommand(
    context: AppContext,
    commandId: string,
    input: SyncSupportCommandCompleteInput,
  ) {
    const command = await this.requireDeviceCommand(context, commandId);
    if (command.status === SyncSupportCommandStatus.SUCCEEDED) {
      return { ok: true, command: this.commandDto(command) };
    }
    if (this.isExecutableExpired(command)) {
      await this.markExpired(command.id);
      throw new AppError(
        "Comando expirado.",
        409,
        "SYNC_SUPPORT_COMMAND_EXPIRED",
      );
    }
    if (command.status !== SyncSupportCommandStatus.RUNNING) {
      throw new AppError(
        "Comando nao esta em execucao.",
        409,
        "SYNC_SUPPORT_COMMAND_NOT_RUNNING",
      );
    }
    const completed = await prisma.syncSupportCommand.update({
      where: { id: command.id },
      data: {
        status: SyncSupportCommandStatus.SUCCEEDED,
        completedAt: new Date(),
        result: sanitizeJson(input.result ?? {}),
        errorMessage: null,
      },
    });
    return { ok: true, command: this.commandDto(completed) };
  }

  async failCommand(
    context: AppContext,
    commandId: string,
    input: SyncSupportCommandFailInput,
  ) {
    const command = await this.requireDeviceCommand(context, commandId);
    if (command.status === SyncSupportCommandStatus.FAILED) {
      return { ok: true, command: this.commandDto(command) };
    }
    if (this.isExecutableExpired(command)) {
      await this.markExpired(command.id);
      throw new AppError(
        "Comando expirado.",
        409,
        "SYNC_SUPPORT_COMMAND_EXPIRED",
      );
    }
    if (command.status !== SyncSupportCommandStatus.RUNNING) {
      throw new AppError(
        "Comando nao esta em execucao.",
        409,
        "SYNC_SUPPORT_COMMAND_NOT_RUNNING",
      );
    }
    const failed = await prisma.syncSupportCommand.update({
      where: { id: command.id },
      data: {
        status: SyncSupportCommandStatus.FAILED,
        completedAt: new Date(),
        errorMessage: truncate(input.errorMessage, 400),
        result: sanitizeJson(input.result ?? {}),
      },
    });
    return { ok: true, command: this.commandDto(failed) };
  }

  async listAdminDevices(companyId: string) {
    await this.requireCompany(companyId);
    const devices = await prisma.companyDevice.findMany({
      where: { companyId },
      orderBy: [{ lastSeenAt: "desc" }, { createdAt: "desc" }],
      include: {
        user: { select: { id: true, name: true, email: true } },
        syncDiagnostic: true,
        syncCheckpoints: true,
      },
    });
    const openRows = await prisma.syncConflict.groupBy({
      by: ["deviceId", "status"],
      where: { companyId },
      _count: { _all: true },
    });
    const conflictsByDevice = new Map<string, Record<string, number>>();
    for (const row of openRows) {
      const current = conflictsByDevice.get(row.deviceId) ?? {};
      current[row.status] = row._count._all;
      conflictsByDevice.set(row.deviceId, current);
    }
    return {
      ok: true,
      items: devices.map((device) => {
        const conflicts = conflictsByDevice.get(device.id) ?? {};
        return this.deviceDto(device, {
          openConflictCount: conflicts.OPEN ?? 0,
          resolvedConflictCount: conflicts.RESOLVED ?? 0,
          ignoredConflictCount: conflicts.IGNORED ?? 0,
        });
      }),
    };
  }

  async getAdminDeviceDiagnostics(companyId: string, deviceId: string) {
    const device = await this.requireDevice(companyId, deviceId);
    const [commands, openConflicts, resolvedConflicts, failedEvents] =
      await Promise.all([
        prisma.syncSupportCommand.findMany({
          where: { companyId, deviceId },
          orderBy: { requestedAt: "desc" },
          take: 20,
        }),
        prisma.syncConflict.findMany({
          where: { companyId, deviceId, status: SyncConflictStatus.OPEN },
          orderBy: { createdAt: "desc" },
          take: 20,
        }),
        prisma.syncConflict.findMany({
          where: {
            companyId,
            deviceId,
            status: {
              in: [SyncConflictStatus.RESOLVED, SyncConflictStatus.IGNORED],
            },
          },
          orderBy: { updatedAt: "desc" },
          take: 20,
        }),
        prisma.syncEvent.findMany({
          where: { companyId, deviceId, status: "FAILED" },
          orderBy: { updatedAt: "desc" },
          take: 20,
        }),
      ]);

    return {
      ok: true,
      device: this.deviceDto(device, {
        openConflictCount: openConflicts.length,
        resolvedConflictCount: resolvedConflicts.filter(
          (conflict) => conflict.status === SyncConflictStatus.RESOLVED,
        ).length,
        ignoredConflictCount: resolvedConflicts.filter(
          (conflict) => conflict.status === SyncConflictStatus.IGNORED,
        ).length,
      }),
      diagnostic:
        device.syncDiagnostic == null
          ? null
          : this.diagnosticDto(device.syncDiagnostic),
      failedEvents: failedEvents.map((event) => ({
        id: event.id,
        eventId: event.eventId,
        entity: event.entity,
        operation: event.operation,
        errorCode: event.rejectionCode,
        errorMessage: truncate(event.rejectionMessage, 400),
        updatedAt: event.updatedAt.toISOString(),
        payloadSummary: summarizeJson(event.payload),
      })),
      openConflicts: openConflicts.map((conflict) =>
        this.conflictDto(conflict),
      ),
      resolvedConflicts: resolvedConflicts.map((conflict) =>
        this.conflictDto(conflict),
      ),
      commands: commands.map((command) => this.commandDto(command)),
    };
  }

  async listAdminCommands(companyId: string, deviceId: string) {
    await this.requireDevice(companyId, deviceId);
    const commands = await prisma.syncSupportCommand.findMany({
      where: { companyId, deviceId },
      orderBy: { requestedAt: "desc" },
      take: 50,
    });
    return {
      ok: true,
      items: commands.map((command) => this.commandDto(command)),
    };
  }

  async adminDryRun(
    companyId: string,
    deviceId: string,
    input: AdminSyncSupportDryRunInput,
  ) {
    const device = await this.requireDevice(companyId, deviceId);
    return this.buildDryRun(device, input.command as SyncSupportCommandType);
  }

  async createAdminCommand(
    companyId: string,
    deviceId: string,
    input: AdminSyncSupportActionInput,
    action: AdminActionContext,
  ) {
    const device = await this.requireDevice(companyId, deviceId);
    const commandType = input.command as SyncSupportCommandType;
    const dryRun = await this.buildDryRun(device, commandType);
    if (!dryRun.allowed) {
      throw new AppError(
        "Comando bloqueado pelo dry-run.",
        409,
        "SYNC_SUPPORT_COMMAND_BLOCKED",
        dryRun,
      );
    }
    if (input.confirmationText !== dryRun.expectedConfirmationText) {
      throw new AppError(
        `Digite ${dryRun.expectedConfirmationText} para confirmar.`,
        422,
        "SYNC_SUPPORT_CONFIRMATION_REQUIRED",
        { expectedConfirmationText: dryRun.expectedConfirmationText },
      );
    }
    await this.expireCommands(companyId, deviceId);
    const existingPending = await prisma.syncSupportCommand.findFirst({
      where: {
        companyId,
        deviceId,
        command: commandType,
        status: SyncSupportCommandStatus.PENDING,
        expiresAt: { gt: new Date() },
      },
      orderBy: { requestedAt: "desc" },
    });
    if (existingPending != null) {
      return {
        ok: true,
        command: this.commandDto(existingPending),
        message: "Ja existe um comando pendente igual para este dispositivo.",
      };
    }

    const command = await prisma.syncSupportCommand.create({
      data: {
        companyId,
        deviceId,
        actorUserId: action.actorUserId,
        command: commandType,
        reason: input.reason,
        confirmationText: input.confirmationText,
        dryRunResult: dryRun as Prisma.InputJsonValue,
        payload: sanitizeJson(input.payload ?? {}),
        expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000),
      },
    });
    await this.recordAudit({
      actorUserId: action.actorUserId,
      companyId,
      action: "sync.support_command.create",
      details: {
        targetType: "CompanyDevice",
        targetId: deviceId,
        commandId: command.id,
        command: command.command,
        reason: input.reason,
        dryRun,
        ipAddress: action.ipAddress,
        userAgent: action.userAgent,
      },
    });

    return {
      ok: true,
      command: this.commandDto(command),
      message: "Comando enviado ao dispositivo.",
    };
  }

  private async buildDryRun(
    device: { id: string; companyId: string; syncDiagnostic?: unknown },
    command: SyncSupportCommandType,
  ) {
    const diagnostic = await prisma.deviceSyncDiagnostic.findUnique({
      where: {
        companyId_deviceId: {
          companyId: device.companyId,
          deviceId: device.id,
        },
      },
    });
    const blockers: string[] = [];
    const risks = [
      "O comando sera executado pelo app no proprio dispositivo.",
      "Nenhuma venda, pedido ou estoque sera apagado pelo backend.",
    ];
    const requiresReportedFailure =
      command ===
        SyncSupportCommandType.REPAIR_OPERATIONAL_ORDER_ITEM_TOTAL_CENTS ||
      command === SyncSupportCommandType.RETRY_FAILED_SYNC_EVENTS;
    if (diagnostic == null && requiresReportedFailure) {
      blockers.push("Este dispositivo ainda nao reportou diagnostico local.");
    }
    if (
      command ===
        SyncSupportCommandType.REPAIR_OPERATIONAL_ORDER_ITEM_TOTAL_CENTS &&
      (diagnostic?.failedCount ?? 0) === 0
    ) {
      blockers.push("Nao ha falhas locais reportadas para reparar.");
    }
    if (
      command === SyncSupportCommandType.RETRY_FAILED_SYNC_EVENTS &&
      (diagnostic?.failedCount ?? 0) === 0
    ) {
      blockers.push("Nao ha eventos locais com falha reportados.");
    }
    if (command === SyncSupportCommandType.CLEAR_RESOLVED_CONFLICT_CACHE) {
      risks.push(
        "Mesmo com diagnostico zerado, o app vai conferir o cache local e limpar apenas conflitos resolvidos ou ignorados.",
      );
    }
    if (
      command === SyncSupportCommandType.FORCE_SYNC_PULL ||
      command === SyncSupportCommandType.REFRESH_SYNC_STATUS
    ) {
      risks.push(
        "Acao segura para realinhar o status visual do app com a nuvem.",
      );
    }
    return {
      allowed: blockers.length === 0,
      command,
      label: commandLabels[command],
      expectedConfirmationText: confirmationByCommand[command],
      blockers,
      risks,
      summary:
        blockers.length === 0
          ? "Comando pode ser enviado com seguranca para execucao local."
          : "Comando bloqueado ate o diagnostico indicar um caso aplicavel.",
    };
  }

  private async requireCompany(companyId: string) {
    const company = await prisma.company.findUnique({
      where: { id: companyId },
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

  private async requireDevice(companyId: string, deviceId: string) {
    const device = await prisma.companyDevice.findFirst({
      where: { id: deviceId, companyId },
      include: {
        user: { select: { id: true, name: true, email: true } },
        syncDiagnostic: true,
        syncCheckpoints: true,
      },
    });
    if (device == null) {
      throw new AppError(
        "Dispositivo nao encontrado nesta empresa.",
        404,
        "SYNC_SUPPORT_DEVICE_NOT_FOUND",
      );
    }
    return device;
  }

  private async requireDeviceCommand(context: AppContext, commandId: string) {
    const command = await prisma.syncSupportCommand.findFirst({
      where: {
        id: commandId,
        companyId: context.company.id,
        deviceId: context.device.id,
      },
    });
    if (command == null) {
      throw new AppError(
        "Comando de suporte nao encontrado.",
        404,
        "SYNC_SUPPORT_COMMAND_NOT_FOUND",
      );
    }
    return command;
  }

  private async expireCommands(companyId: string, deviceId?: string) {
    await prisma.syncSupportCommand.updateMany({
      where: {
        companyId,
        ...(deviceId == null ? {} : { deviceId }),
        status: {
          in: [
            SyncSupportCommandStatus.PENDING,
            SyncSupportCommandStatus.RUNNING,
          ],
        },
        expiresAt: { lte: new Date() },
      },
      data: { status: SyncSupportCommandStatus.EXPIRED },
    });
  }

  private isExecutableExpired(command: {
    status: SyncSupportCommandStatus;
    expiresAt: Date;
  }) {
    return (
      command.expiresAt <= new Date() &&
      (command.status === SyncSupportCommandStatus.PENDING ||
        command.status === SyncSupportCommandStatus.RUNNING)
    );
  }

  private markExpired(commandId: string) {
    return prisma.syncSupportCommand.update({
      where: { id: commandId },
      data: { status: SyncSupportCommandStatus.EXPIRED },
    });
  }

  private async recordAudit(input: {
    actorUserId: string;
    companyId: string;
    action: string;
    details: Prisma.InputJsonValue;
  }) {
    await prisma.adminAuditLog.create({
      data: {
        actorUserId: input.actorUserId,
        targetCompanyId: input.companyId,
        action: input.action,
        details: input.details,
      },
    });
  }

  private deviceDto(
    device: {
      id: string;
      companyId: string;
      clientInstanceId: string;
      deviceLabel: string | null;
      platform: string | null;
      appVersion: string | null;
      status: string;
      lastSeenAt: Date | null;
      createdAt: Date;
      user?: { id: string; name: string; email: string } | null;
      syncDiagnostic?: {
        pendingCount: number;
        failedCount: number;
        openConflictCount: number;
        resolvedConflictCount: number;
        ignoredConflictCount: number;
        lastLocalError: string | null;
        reportedAt: Date;
      } | null;
      syncCheckpoints?: Array<{
        lastPushedAt: Date | null;
        lastPulledAt: Date | null;
      }>;
    },
    conflictCounts: {
      openConflictCount: number;
      resolvedConflictCount: number;
      ignoredConflictCount: number;
    },
  ) {
    const lastPushAt = latestDate(
      device.syncCheckpoints?.map((checkpoint) => checkpoint.lastPushedAt) ??
        [],
    );
    const lastPullAt = latestDate(
      device.syncCheckpoints?.map((checkpoint) => checkpoint.lastPulledAt) ??
        [],
    );
    const diagnostic = device.syncDiagnostic;
    const failedCount = diagnostic?.failedCount ?? 0;
    const openConflictCount =
      diagnostic?.openConflictCount ?? conflictCounts.openConflictCount;
    return {
      id: device.id,
      maskedDeviceId: maskId(device.id),
      clientInstanceId: maskId(device.clientInstanceId),
      deviceLabel: device.deviceLabel,
      platform: device.platform,
      appVersion: diagnostic?.reportedAt
        ? device.appVersion
        : device.appVersion,
      status: classifyDeviceStatus({ failedCount, openConflictCount }),
      deviceStatus: device.status.toLowerCase(),
      lastSeenAt: device.lastSeenAt?.toISOString() ?? null,
      lastPushAt: lastPushAt?.toISOString() ?? null,
      lastPullAt: lastPullAt?.toISOString() ?? null,
      user: device.user == null ? null : this.userDto(device.user),
      diagnostic:
        diagnostic == null
          ? null
          : {
              pendingCount: diagnostic.pendingCount,
              failedCount: diagnostic.failedCount,
              openConflictCount: diagnostic.openConflictCount,
              resolvedConflictCount: diagnostic.resolvedConflictCount,
              ignoredConflictCount: diagnostic.ignoredConflictCount,
              lastLocalError: diagnostic.lastLocalError,
              reportedAt: diagnostic.reportedAt.toISOString(),
            },
      remoteConflictCounts: conflictCounts,
    };
  }

  private diagnosticDto(diagnostic: {
    id: string;
    companyId: string;
    deviceId: string;
    userId: string | null;
    clientInstanceId: string | null;
    appVersion: string | null;
    localSchemaVersion: string | null;
    pendingCount: number;
    failedCount: number;
    openConflictCount: number;
    resolvedConflictCount: number;
    ignoredConflictCount: number;
    lastLocalError: string | null;
    lastLocalErrorCode: string | null;
    lastLocalErrorEntity: string | null;
    lastPushAt: Date | null;
    lastPullAt: Date | null;
    lastSuccessfulSyncAt: Date | null;
    safeDetails: Prisma.JsonValue | null;
    reportedAt: Date;
  }) {
    return {
      id: diagnostic.id,
      companyId: diagnostic.companyId,
      deviceId: diagnostic.deviceId,
      userId: diagnostic.userId,
      clientInstanceId: diagnostic.clientInstanceId,
      appVersion: diagnostic.appVersion,
      localSchemaVersion: diagnostic.localSchemaVersion,
      pendingCount: diagnostic.pendingCount,
      failedCount: diagnostic.failedCount,
      openConflictCount: diagnostic.openConflictCount,
      resolvedConflictCount: diagnostic.resolvedConflictCount,
      ignoredConflictCount: diagnostic.ignoredConflictCount,
      lastLocalError: diagnostic.lastLocalError,
      lastLocalErrorCode: diagnostic.lastLocalErrorCode,
      lastLocalErrorEntity: diagnostic.lastLocalErrorEntity,
      lastPushAt: diagnostic.lastPushAt?.toISOString() ?? null,
      lastPullAt: diagnostic.lastPullAt?.toISOString() ?? null,
      lastSuccessfulSyncAt:
        diagnostic.lastSuccessfulSyncAt?.toISOString() ?? null,
      safeDetails: sanitizeJson(diagnostic.safeDetails ?? {}),
      reportedAt: diagnostic.reportedAt.toISOString(),
    };
  }

  private commandDto(command: {
    id: string;
    command: SyncSupportCommandType;
    status: SyncSupportCommandStatus;
    reason: string;
    payload: Prisma.JsonValue | null;
    result: Prisma.JsonValue | null;
    errorMessage: string | null;
    requestedAt: Date;
    pickedUpAt: Date | null;
    completedAt: Date | null;
    expiresAt: Date;
  }) {
    return {
      id: command.id,
      command: command.command,
      label: commandLabels[command.command],
      status: command.status,
      reason: command.reason,
      payload: sanitizeJson(command.payload ?? {}),
      result: sanitizeJson(command.result ?? {}),
      errorMessage: command.errorMessage,
      requestedAt: command.requestedAt.toISOString(),
      pickedUpAt: command.pickedUpAt?.toISOString() ?? null,
      completedAt: command.completedAt?.toISOString() ?? null,
      expiresAt: command.expiresAt.toISOString(),
    };
  }

  private conflictDto(conflict: {
    id: string;
    entity: string;
    code: string;
    message: string;
    status: SyncConflictStatus;
    createdAt: Date;
    resolvedAt: Date | null;
  }) {
    return {
      id: conflict.id,
      entity: conflict.entity,
      code: conflict.code,
      message: conflict.message,
      status: conflict.status.toLowerCase(),
      createdAt: conflict.createdAt.toISOString(),
      resolvedAt: conflict.resolvedAt?.toISOString() ?? null,
    };
  }

  private userDto(user: { id: string; name: string; email: string }) {
    return { id: user.id, name: user.name, email: user.email };
  }
}

function classifyDeviceStatus(input: {
  failedCount: number;
  openConflictCount: number;
}) {
  if (input.failedCount > 0) {
    return "local_failure";
  }
  if (input.openConflictCount > 0) {
    return "remote_conflict";
  }
  return "cloud_ok";
}

function latestDate(values: Array<Date | null>) {
  return values.reduce<Date | null>((latest, value) => {
    if (value == null) {
      return latest;
    }
    if (latest == null || value > latest) {
      return value;
    }
    return latest;
  }, null);
}

function maskId(value: string) {
  if (value.length <= 10) {
    return value;
  }
  return `${value.slice(0, 6)}...${value.slice(-4)}`;
}

function truncate(value: string | null | undefined, maxLength: number) {
  if (value == null) {
    return null;
  }
  const normalized = value.trim();
  if (normalized.length <= maxLength) {
    return normalized;
  }
  return `${normalized.slice(0, maxLength)}...`;
}

function summarizeJson(value: Prisma.JsonValue) {
  return truncate(JSON.stringify(sanitizeJson(value)), 500);
}

function sanitizeJson(value: unknown): Prisma.InputJsonValue {
  if (Array.isArray(value)) {
    return value.slice(0, 20).map((item) => sanitizeJson(item));
  }
  if (value != null && typeof value === "object") {
    const output: Record<string, Prisma.InputJsonValue> = {};
    for (const [key, raw] of Object.entries(value)) {
      const normalizedKey = key.toLowerCase();
      if (
        normalizedKey.includes("token") ||
        normalizedKey.includes("authorization") ||
        normalizedKey.includes("password") ||
        normalizedKey.includes("card") ||
        normalizedKey.includes("headers") ||
        normalizedKey.includes("apikey") ||
        normalizedKey.includes("api_key") ||
        normalizedKey.includes("secret") ||
        normalizedKey.includes("cvv")
      ) {
        output[key] = "[redacted]";
        continue;
      }
      output[key] = sanitizeJson(raw);
    }
    return output;
  }
  if (
    typeof value === "string" ||
    typeof value === "number" ||
    typeof value === "boolean"
  ) {
    return typeof value === "string" ? sanitizeString(value) : value;
  }
  return {};
}

function sanitizeString(value: string) {
  const normalized = truncate(value, 1000) ?? "";
  if (
    /\bbearer\s+/i.test(normalized) ||
    /[?&](token|authorization|api[_-]?key|secret)=/i.test(normalized)
  ) {
    return "[redacted]";
  }
  return normalized;
}
