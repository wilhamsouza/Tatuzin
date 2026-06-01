import { createHash } from "node:crypto";

import { Prisma } from "@prisma/client";

import { env } from "../../config/env";
import { prisma } from "../../database/prisma";
import { AppError } from "../../shared/http/app-error";
import { logger } from "../../shared/observability/logger";
import { userAdminAuditActor } from "../admin/admin-audit-actor";
import { AuthSessionService } from "../auth/auth-session.service";
import { decideSupportActionPermission } from "./support-actions.permissions";
import {
  revokeSessionExecutionRequestSchema,
  supportActionExecutionProbeSchema,
  type RevokeSessionExecutionRequest,
} from "./support-actions.execution.schemas";
import {
  revokeSessionExecutionActionType,
  type RevokeSessionExecutionContract,
  type SupportActionExecutionCode,
  type SupportActionExecutionResponse,
} from "./support-actions.execution.types";
import { sanitizeOperationalActionPayload } from "./support-actions.service";
import type { SupportActionPermissionContext } from "./support-actions.types";

const dryRunValidityMs = 15 * 60 * 1000;

type AdminAuditRow = {
  id: string;
  actorUserId: string | null;
  targetCompanyId: string | null;
  action: string;
  details: unknown;
  createdAt: Date;
};

type SessionRow = {
  id: string;
  companyId: string;
  userId: string;
  revokedAt: Date | null;
};

type ExecutionReceiptRow = {
  id: string;
  idempotencyKey: string;
  requestFingerprint: string;
  dryRunAuditEventId: string;
  actionType: string;
  targetCompanyId: string;
  targetType: string;
  targetId: string;
  actorUserId: string;
  reason: string;
  status: "PENDING" | "SUCCEEDED" | "FAILED";
  beforeAuditEventId: string | null;
  afterAuditEventId: string | null;
  result: unknown;
  createdAt: Date;
  updatedAt: Date;
  executedAt: Date | null;
};

type SupportActionExecutionClient = {
  adminAuditLog: {
    findUnique(input: {
      where: { id: string };
      select: {
        id: true;
        actorUserId: true;
        targetCompanyId: true;
        action: true;
        details: true;
        createdAt: true;
      };
    }): Promise<AdminAuditRow | null>;
    create(input: {
      data: {
        actorType: "USER";
        actorUserId: string;
        actorLabel: null;
        targetCompanyId: string;
        action: string;
        details: Prisma.InputJsonValue;
      };
      select: { id: true };
    }): Promise<{ id: string }>;
  };
  deviceSession: {
    findUnique(input: {
      where: { id: string };
      select: { id: true; companyId: true; userId: true; revokedAt: true };
    }): Promise<SessionRow | null>;
  };
  supportActionExecution: {
    findUnique(input: {
      where: { idempotencyKey: string };
    }): Promise<ExecutionReceiptRow | null>;
    create(input: {
      data: {
        idempotencyKey: string;
        requestFingerprint: string;
        dryRunAuditEventId: string;
        actionType: string;
        targetCompanyId: string;
        targetType: string;
        targetId: string;
        actorUserId: string;
        reason: string;
        status: "PENDING";
        beforeAuditEventId: string;
      };
    }): Promise<ExecutionReceiptRow>;
    update(input: {
      where: { id: string };
      data: {
        status: "SUCCEEDED" | "FAILED";
        afterAuditEventId: string;
        result: Prisma.InputJsonValue;
        executedAt: Date;
      };
    }): Promise<ExecutionReceiptRow>;
  };
};

type SessionRevoker = {
  revokeCompanySession(input: {
    companyId: string;
    sessionId: string;
    actorUserId: string;
  }): Promise<void>;
};

type OperationalLogger = Pick<typeof logger, "info" | "warn" | "error">;

type SupportActionExecutionOptions = {
  revokeSessionExecutionEnabled?: boolean;
  logger?: OperationalLogger;
};

export class SupportActionExecutionService {
  private readonly revokeSessionExecutionEnabled: boolean;
  private readonly operationalLogger: OperationalLogger;

  constructor(
    private readonly client: SupportActionExecutionClient =
      prisma as unknown as SupportActionExecutionClient,
    private readonly sessionRevoker: SessionRevoker = new AuthSessionService(),
    private readonly now: () => Date = () => new Date(),
    options: SupportActionExecutionOptions = {},
  ) {
    this.revokeSessionExecutionEnabled =
      options.revokeSessionExecutionEnabled ??
      env.SUPPORT_ACTION_REVOKE_SESSION_EXECUTION_ENABLED;
    this.operationalLogger = options.logger ?? logger;
  }

  async executeRevokeSession(
    rawInput: unknown,
    permissionContext?: SupportActionPermissionContext,
  ): Promise<SupportActionExecutionResponse> {
    const rawObject = readObject(rawInput);
    if (
      typeof rawObject.actorAdminId !== "string" ||
      rawObject.actorAdminId.trim().length === 0
    ) {
      this.log("warn", "support.revoke_session.execution.actor_required", rawInput);
      return errorResponse(
        "SUPPORT_ACTION_EXECUTION_ACTOR_REQUIRED",
        "Ator administrativo autenticado obrigatorio para executar revoke_session.",
      );
    }

    const probe = supportActionExecutionProbeSchema.safeParse(rawInput);
    if (
      probe.success &&
      probe.data.actionType !== revokeSessionExecutionActionType
    ) {
      this.log("warn", "support.revoke_session.execution.unsupported", rawInput);
      return errorResponse(
        "SUPPORT_ACTION_EXECUTION_UNSUPPORTED",
        "Execucao real ainda nao habilitada para esta acao.",
        { actionType: probe.data.actionType },
      );
    }

    const parsed = revokeSessionExecutionRequestSchema.safeParse(rawInput);
    if (!parsed.success) {
      this.log("warn", "support.revoke_session.execution.payload_invalid", rawInput);
      return errorResponse(
        "SUPPORT_ACTION_EXECUTION_VALIDATION_ERROR",
        "Payload de execucao de revoke_session invalido.",
        parsed.error.flatten(),
      );
    }

    const input = parsed.data;
    if (!this.revokeSessionExecutionEnabled) {
      await this.recordDenied(input, "feature_flag_disabled");
      this.log("warn", "support.revoke_session.execution.disabled", input);
      return errorResponse(
        "SUPPORT_ACTION_EXECUTION_DISABLED",
        "Execucao real de revoke_session desabilitada por configuracao operacional.",
      );
    }

    const permissionDecision = decideSupportActionPermission({
      actionType: revokeSessionExecutionActionType,
      context: permissionContext ?? {
        actorAdminId: input.actorAdminId,
        permissionKeys: [],
      },
    });
    if (!permissionDecision.allowed) {
      await this.recordDenied(input, "permission_denied", {
        missingPermission: permissionDecision.missingPermission ?? null,
      });
      this.log("warn", "support.revoke_session.execution.permission_denied", input, {
        missingPermission: permissionDecision.missingPermission ?? null,
      });
      return errorResponse(
        "SUPPORT_ACTION_EXECUTION_PERMISSION_DENIED",
        permissionDecision.reason,
        {
          requiredPermission:
            permissionDecision.requiredPermission.permissionKey,
          missingPermission: permissionDecision.missingPermission ?? null,
        },
      );
    }

    const fingerprint = buildRequestFingerprint(input);
    const existing = await this.client.supportActionExecution.findUnique({
      where: { idempotencyKey: input.idempotencyKey },
    });
    if (existing != null) {
      return this.replayExisting(existing, fingerprint);
    }

    const dryRun = await this.client.adminAuditLog.findUnique({
      where: { id: input.dryRunAuditEventId },
      select: {
        id: true,
        actorUserId: true,
        targetCompanyId: true,
        action: true,
        details: true,
        createdAt: true,
      },
    });
    const dryRunValidation = validateDryRunEvidence(dryRun, input, this.now());
    if (!dryRunValidation.ok) {
      await this.recordDenied(input, "dry_run_rejected", {
        code: dryRunValidation.code,
      });
      this.log("warn", "support.revoke_session.execution.dry_run_rejected", input, {
        code: dryRunValidation.code,
      });
      return errorResponse(dryRunValidation.code, dryRunValidation.message);
    }

    const session = await this.client.deviceSession.findUnique({
      where: { id: input.targetId },
      select: { id: true, companyId: true, userId: true, revokedAt: true },
    });
    if (session == null || session.companyId !== input.companyId) {
      await this.recordDenied(input, "target_not_found");
      this.log("warn", "support.revoke_session.execution.target_not_found", input);
      return errorResponse(
        "SUPPORT_ACTION_EXECUTION_TARGET_NOT_FOUND",
        "Sessao nao encontrada para esta empresa.",
      );
    }
    if (session.revokedAt != null) {
      await this.recordDenied(input, "target_already_revoked");
      this.log("warn", "support.revoke_session.execution.state_conflict", input, {
        result: "target_already_revoked",
      });
      return errorResponse(
        "SUPPORT_ACTION_EXECUTION_STATE_CONFLICT",
        "Sessao ja estava revogada. Gere um novo dry-run para revisar o estado.",
      );
    }

    const attemptedAuditId = await this.recordAudit(input, "attempted", {
      dryRunAuditEventId: input.dryRunAuditEventId,
      targetUserId: session.userId,
    });
    this.log("info", "support.revoke_session.execution.requested", input, {
      auditBeforeId: attemptedAuditId,
    });

    let receipt: ExecutionReceiptRow;
    try {
      receipt = await this.client.supportActionExecution.create({
        data: {
          idempotencyKey: input.idempotencyKey,
          requestFingerprint: fingerprint,
          dryRunAuditEventId: input.dryRunAuditEventId,
          actionType: input.actionType,
          targetCompanyId: input.companyId,
          targetType: input.targetType,
          targetId: input.targetId,
          actorUserId: input.actorAdminId,
          reason: safeReason(input.reason),
          status: "PENDING",
          beforeAuditEventId: attemptedAuditId,
        },
      });
    } catch (error) {
      if (isUniqueConstraintError(error)) {
        const raced = await this.client.supportActionExecution.findUnique({
          where: { idempotencyKey: input.idempotencyKey },
        });
        if (raced != null) {
          return this.replayExisting(raced, fingerprint);
        }
      }
      throw error;
    }

    try {
      await this.sessionRevoker.revokeCompanySession({
        companyId: input.companyId,
        sessionId: input.targetId,
        actorUserId: input.actorAdminId,
      });
      const executedAt = this.now();
      const safeResult = sanitizeOperationalActionPayload({
        effectApplied: true,
        targetId: input.targetId,
        dryRunAuditEventId: input.dryRunAuditEventId,
      });
      const succeededAuditId = await this.recordAudit(input, "succeeded", {
        executionId: receipt.id,
        ...safeResult,
      });
      receipt = await this.client.supportActionExecution.update({
        where: { id: receipt.id },
        data: {
          status: "SUCCEEDED",
          afterAuditEventId: succeededAuditId,
          result: safeResult as Prisma.InputJsonValue,
          executedAt,
        },
      });
      this.log("info", "support.revoke_session.execution.succeeded", input, {
        executionId: receipt.id,
        auditBeforeId: attemptedAuditId,
        auditAfterId: succeededAuditId,
      });

      return {
        ok: true,
        code: "SUPPORT_ACTION_EXECUTED",
        message: "Sessao revogada com auditoria persistida.",
        execution: serializeReceipt(receipt, "succeeded"),
      };
    } catch (error) {
      const executedAt = this.now();
      const safeFailure = sanitizeOperationalActionPayload({
        effectApplied: false,
        errorCode: error instanceof AppError ? error.code : "INTERNAL_ERROR",
        errorMessage:
          error instanceof AppError
            ? error.message
            : "Falha interna ao revogar sessao.",
      });
      const failedAuditId = await this.recordAudit(input, "failed", {
        executionId: receipt.id,
        ...safeFailure,
      });
      await this.client.supportActionExecution.update({
        where: { id: receipt.id },
        data: {
          status: "FAILED",
          afterAuditEventId: failedAuditId,
          result: safeFailure as Prisma.InputJsonValue,
          executedAt,
        },
      });
      this.log("error", "support.revoke_session.execution.failed", input, {
        executionId: receipt.id,
        auditBeforeId: attemptedAuditId,
        auditAfterId: failedAuditId,
        errorCode: safeFailure.errorCode,
      });

      if (error instanceof AppError && error.code === "SESSION_NOT_FOUND") {
        return errorResponse(
          "SUPPORT_ACTION_EXECUTION_TARGET_NOT_FOUND",
          "Sessao nao encontrada para esta empresa.",
        );
      }
      return errorResponse(
        "SUPPORT_ACTION_EXECUTION_INTERNAL_ERROR",
        "Falha segura ao executar revoke_session. Revise a auditoria antes de tentar novamente.",
      );
    }
  }

  private replayExisting(
    receipt: ExecutionReceiptRow,
    fingerprint: string,
  ): SupportActionExecutionResponse {
    if (receipt.requestFingerprint !== fingerprint) {
      this.logReceipt(
        "warn",
        "support.revoke_session.execution.idempotency_conflict",
        receipt,
      );
      return errorResponse(
        "SUPPORT_ACTION_EXECUTION_STATE_CONFLICT",
        "Idempotency key ja utilizada com payload diferente.",
      );
    }
    if (receipt.status !== "SUCCEEDED") {
      this.logReceipt(
        "warn",
        "support.revoke_session.execution.idempotency_pending",
        receipt,
      );
      return errorResponse(
        "SUPPORT_ACTION_EXECUTION_STATE_CONFLICT",
        "Execucao anterior ainda nao concluiu com sucesso. Revise a auditoria.",
      );
    }

    this.logReceipt(
      "info",
      "support.revoke_session.execution.idempotent_replay",
      receipt,
    );
    return {
      ok: true,
      code: "SUPPORT_ACTION_IDEMPOTENT_REPLAY",
      message: "Sessao ja havia sido revogada por esta solicitacao.",
      execution: serializeReceipt(receipt, "idempotent_replay"),
    };
  }

  private recordDenied(
    input: RevokeSessionExecutionRequest,
    result: string,
    details?: Record<string, unknown>,
  ) {
    return this.recordAudit(input, "denied", { result, ...details });
  }

  private async recordAudit(
    input: RevokeSessionExecutionRequest,
    event: "attempted" | "succeeded" | "failed" | "denied",
    details: Record<string, unknown>,
  ) {
    const audit = await this.client.adminAuditLog.create({
      data: {
        ...userAdminAuditActor(input.actorAdminId),
        targetCompanyId: input.companyId,
        action: supportActionExecutionAuditName(event),
        details: sanitizeOperationalActionPayload({
          actionType: input.actionType,
          permissionKey: "support.session.revoke",
          targetType: input.targetType,
          targetId: input.targetId,
          dryRunAuditEventId: input.dryRunAuditEventId,
          reason: input.reason,
          idempotencyKey: input.idempotencyKey,
          idempotencyKeyHash: hashValue(input.idempotencyKey),
          safePayload: sanitizeOperationalActionPayload({
            metadata: input.metadata,
          }),
          timestamp: this.now().toISOString(),
          ...details,
        }) as Prisma.InputJsonValue,
      },
      select: { id: true },
    });
    return audit.id;
  }

  private log(
    level: "info" | "warn" | "error",
    message: string,
    rawInput: unknown,
    details?: Record<string, unknown>,
  ) {
    const input = readObject(rawInput);
    const idempotencyKey =
      typeof input.idempotencyKey === "string" ? input.idempotencyKey : null;
    this.operationalLogger[level](
      message,
      sanitizeOperationalActionPayload({
        actionType: input.actionType,
        actorAdminId: input.actorAdminId,
        companyId: input.companyId,
        targetType: input.targetType,
        targetId: input.targetId,
        dryRunAuditEventId: input.dryRunAuditEventId,
        idempotencyKeyHash:
          idempotencyKey == null ? null : hashValue(idempotencyKey),
        ...details,
      }),
    );
  }

  private logReceipt(
    level: "info" | "warn" | "error",
    message: string,
    receipt: ExecutionReceiptRow,
  ) {
    this.operationalLogger[level](message, {
      actionType: receipt.actionType,
      actorAdminId: receipt.actorUserId,
      companyId: receipt.targetCompanyId,
      targetType: receipt.targetType,
      targetId: receipt.targetId,
      dryRunAuditEventId: receipt.dryRunAuditEventId,
      idempotencyKeyHash: hashValue(receipt.idempotencyKey),
      executionId: receipt.id,
      status: receipt.status,
    });
  }
}

function validateDryRunEvidence(
  dryRun: AdminAuditRow | null,
  input: RevokeSessionExecutionRequest,
  now: Date,
):
  | { ok: true }
  | {
      ok: false;
      code:
        | "SUPPORT_ACTION_EXECUTION_DRY_RUN_REQUIRED"
        | "SUPPORT_ACTION_EXECUTION_DRY_RUN_EXPIRED"
        | "SUPPORT_ACTION_EXECUTION_DRY_RUN_MISMATCH";
      message: string;
    } {
  if (dryRun == null) {
    return {
      ok: false,
      code: "SUPPORT_ACTION_EXECUTION_DRY_RUN_REQUIRED",
      message: "Dry-run persistido obrigatorio antes da execucao.",
    };
  }
  if (now.getTime() - dryRun.createdAt.getTime() > dryRunValidityMs) {
    return {
      ok: false,
      code: "SUPPORT_ACTION_EXECUTION_DRY_RUN_EXPIRED",
      message: "Dry-run expirado. Gere uma nova simulacao antes da execucao.",
    };
  }

  const details = readObject(dryRun.details);
  const result = readObject(details.result);
  const matches =
    dryRun.action === "support.revoke_session.dry_run" &&
    dryRun.actorUserId === input.actorAdminId &&
    dryRun.targetCompanyId === input.companyId &&
    details.actionType === input.actionType &&
    details.targetType === input.targetType &&
    details.targetId === input.targetId &&
    details.dryRun === true &&
    details.confirmationRequired === true &&
    details.reason === safeReason(input.reason) &&
    result.code === "OPERATIONAL_ACTION_DRY_RUN_READY";
  if (!matches) {
    return {
      ok: false,
      code: "SUPPORT_ACTION_EXECUTION_DRY_RUN_MISMATCH",
      message: "Dry-run nao corresponde ao ator, empresa, alvo e motivo informados.",
    };
  }

  return { ok: true };
}

function buildRequestFingerprint(input: RevokeSessionExecutionRequest) {
  return hashValue(
    JSON.stringify({
      actionType: input.actionType,
      companyId: input.companyId,
      targetType: input.targetType,
      targetId: input.targetId,
      actorAdminId: input.actorAdminId,
      reason: safeReason(input.reason),
      dryRunAuditEventId: input.dryRunAuditEventId,
    }),
  );
}

function hashValue(value: string) {
  return createHash("sha256").update(value).digest("hex");
}

function safeReason(reason: string) {
  const sanitized = sanitizeOperationalActionPayload({ reason });
  return typeof sanitized.reason === "string" ? sanitized.reason : "[redacted]";
}

function serializeReceipt(
  receipt: ExecutionReceiptRow,
  status: RevokeSessionExecutionContract["status"],
): RevokeSessionExecutionContract {
  return {
    id: receipt.id,
    actionType: revokeSessionExecutionActionType,
    companyId: receipt.targetCompanyId,
    targetType: "session",
    targetId: receipt.targetId,
    target: {
      type: "session",
      id: receipt.targetId,
      companyId: receipt.targetCompanyId,
    },
    actorAdminId: receipt.actorUserId,
    dryRunAuditEventId: receipt.dryRunAuditEventId,
    correlationId: receipt.dryRunAuditEventId,
    idempotencyKey: receipt.idempotencyKey,
    status,
    result: {
      status,
      effectApplied: true,
    },
    auditBeforeId: receipt.beforeAuditEventId,
    auditAfterId: receipt.afterAuditEventId,
    beforeAuditEventId: receipt.beforeAuditEventId,
    afterAuditEventId: receipt.afterAuditEventId,
    executedAt: receipt.executedAt?.toISOString() ?? null,
  };
}

function supportActionExecutionAuditName(
  event: "attempted" | "succeeded" | "failed" | "denied",
) {
  switch (event) {
    case "attempted":
      return "support.revoke_session.execute_requested";
    case "succeeded":
      return "support.revoke_session.execute_succeeded";
    case "failed":
      return "support.revoke_session.execute_failed";
    case "denied":
      return "support.revoke_session.execute_denied";
  }
}

function errorResponse(
  code: SupportActionExecutionCode,
  message: string,
  details?: unknown,
): SupportActionExecutionResponse {
  const safeDetails =
    details == null ? undefined : sanitizeOperationalActionPayload(details);
  return {
    ok: false,
    code,
    message,
    details: safeDetails,
    error: {
      code,
      message,
      details: safeDetails,
    },
  };
}

function readObject(value: unknown): Record<string, unknown> {
  if (value != null && typeof value === "object" && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return {};
}

function isUniqueConstraintError(error: unknown) {
  return (
    error instanceof Prisma.PrismaClientKnownRequestError &&
    error.code === "P2002"
  );
}
