import { ZodError } from "zod";

import {
  isOperationalActionTargetType,
  isOperationalActionType,
  operationalActionDryRunRequestSchema,
  unsupportedOperationalActionProbeSchema,
  type OperationalActionDryRunRequest,
} from "./support-actions.schemas";
import { buildSupportActionAuditDraft } from "./support-actions.audit";
import {
  decideSupportActionPermission,
  getSupportActionPermission,
} from "./support-actions.permissions";
import {
  type OperationalActionApiResponse,
  type OperationalActionContract,
  type OperationalActionExpectedImpact,
  type OperationalActionResult,
  type OperationalActionResultCode,
  type OperationalActionResultStatus,
  type OperationalActionTargetType,
  type OperationalActionType,
  type SupportActionPermissionContext,
} from "./support-actions.types";

type ActionDefinition = {
  targetTypes: readonly OperationalActionTargetType[];
  confirmationRequired: boolean;
  impactSummary: string;
  risks: readonly string[];
};

const actionDefinitions: Record<OperationalActionType, ActionDefinition> = {
  revoke_session: {
    targetTypes: ["session"],
    confirmationRequired: true,
    impactSummary:
      "Revogaria a sessao alvo e exigiria novo login no proximo uso.",
    risks: [
      "Pode interromper um operador em atendimento.",
      "Exige auditoria completa antes de execucao real.",
    ],
  },
  block_user: {
    targetTypes: ["user"],
    confirmationRequired: true,
    impactSummary:
      "Bloquearia o acesso do usuario alvo sem remover dados historicos.",
    risks: [
      "Pode impedir acesso legitimo se o alvo estiver incorreto.",
      "Deve preservar OWNER e regras de permissao granular.",
    ],
  },
  unblock_user: {
    targetTypes: ["user"],
    confirmationRequired: true,
    impactSummary:
      "Reativaria acesso previamente bloqueado, sem alterar senha ou papel.",
    risks: [
      "Pode restaurar acesso indevido se o motivo nao for validado.",
      "Deve respeitar licenca, membership e status efetivo.",
    ],
  },
  force_sync: {
    targetTypes: ["device", "sync"],
    confirmationRequired: true,
    impactSummary:
      "Solicitaria uma sincronizacao operacional controlada para o alvo.",
    risks: [
      "Pode aumentar carga de sync se usado em massa.",
      "Nao deve sobrescrever fila local nem materializadores sem dry-run.",
    ],
  },
  resolve_conflict: {
    targetTypes: ["conflict"],
    confirmationRequired: true,
    impactSummary:
      "Prepararia resolucao auditada de um conflito de sync especifico.",
    risks: [
      "Resolucao errada pode alterar a leitura operacional de vendas ou caixa.",
      "Exige payload seguro e politica de conciliacao por entidade.",
    ],
  },
  update_license: {
    targetTypes: ["license", "company"],
    confirmationRequired: true,
    impactSummary:
      "Prepararia alteracao administrativa de licenca ou politica de acesso.",
    risks: [
      "Pode liberar ou restringir features se executada incorretamente.",
      "Nao deve ignorar billing, entitlement e auditoria financeira.",
    ],
  },
  update_android_version_policy: {
    targetTypes: ["android_version_policy", "company"],
    confirmationRequired: true,
    impactSummary:
      "Prepararia ajuste de politica de versao Android minima ou recomendada.",
    risks: [
      "Pode bloquear dispositivos antigos se a politica for executada.",
      "Depende de suporte Android para enforcement e mensagens ao usuario.",
    ],
  },
  send_push_notification: {
    targetTypes: ["push_notification", "device", "user", "company"],
    confirmationRequired: true,
    impactSummary:
      "Prepararia envio futuro de push notification sem chamar Firebase.",
    risks: [
      "Pode expor mensagem sensivel se payload nao for revisado.",
      "Depende de token FCM, preferencias e auditoria de envio.",
    ],
  },
};

const sensitiveKeyFragments = [
  "authorization",
  "password",
  "secret",
  "token",
  "jwt",
  "cookie",
  "provider",
  "webhook",
  "credential",
  "refresh",
  "access",
  "card",
];

export function buildOperationalActionDryRun(
  rawInput: unknown,
  now = new Date(),
  permissionContext?: SupportActionPermissionContext,
): OperationalActionApiResponse {
  const unsupportedProbe =
    unsupportedOperationalActionProbeSchema.safeParse(rawInput);

  if (
    unsupportedProbe.success &&
    !isOperationalActionType(unsupportedProbe.data.actionType)
  ) {
    return errorResponse(
      "OPERATIONAL_ACTION_UNSUPPORTED",
      "unsupported_action",
      "Acao operacional nao suportada nesta fundacao.",
      { actionType: unsupportedProbe.data.actionType },
    );
  }

  if (
    unsupportedProbe.success &&
    isOperationalActionType(unsupportedProbe.data.actionType) &&
    (unsupportedProbe.data.actorAdminId == null ||
      unsupportedProbe.data.actorAdminId.trim() === "")
  ) {
    return actorRequiredResponse({
      actionType: unsupportedProbe.data.actionType,
    });
  }

  const parsed = operationalActionDryRunRequestSchema.safeParse(rawInput);

  if (!parsed.success) {
    return validationErrorResponse(parsed.error);
  }

  const input = parsed.data;
  const definition = actionDefinitions[input.actionType];
  const requiredPermission = getSupportActionPermission(input.actionType);

  if (!definition.targetTypes.includes(input.targetType)) {
    return errorResponse(
      "OPERATIONAL_ACTION_STATE_CONFLICT",
      "state_conflict",
      "Tipo de alvo incompativel com a acao operacional solicitada.",
      {
        actionType: input.actionType,
        targetType: input.targetType,
        expectedTargetTypes: definition.targetTypes,
      },
    );
  }

  const permissionDecision = decideSupportActionPermission({
    actionType: input.actionType,
    context: permissionContext ?? {
      actorAdminId: input.actorAdminId,
      permissionKeys: [],
    },
  });

  if (!permissionDecision.allowed) {
    return permissionDeniedResponse(permissionDecision);
  }

  const createdAt = now.toISOString();
  const result = resultPayload(
    "OPERATIONAL_ACTION_DRY_RUN_READY",
    "dry_run_ready",
    "Dry-run preparado. Nenhum dado real foi alterado.",
  );
  const expectedImpact = buildExpectedImpact(input, definition);
  const safePayload = sanitizeOperationalActionPayload({
    metadata: input.metadata,
    expectedImpact,
    permission: {
      permissionKey: requiredPermission.permissionKey,
      scopes: requiredPermission.scopes,
      riskLevel: requiredPermission.riskLevel,
    },
  });
  const auditDraft = buildSupportActionAuditDraft({
    actorAdminId: input.actorAdminId,
    companyId: input.companyId,
    actionType: input.actionType,
    targetType: input.targetType,
    targetId: input.targetId,
    dryRun: true,
    confirmationRequired: definition.confirmationRequired,
    reason: input.reason,
    result,
    safePayload,
    affectedEntities: expectedImpact.affectedEntities,
    permissionDecision,
    createdAt,
  });

  const action: OperationalActionContract = {
    actionType: input.actionType,
    permissionKey: requiredPermission.permissionKey,
    companyId: input.companyId,
    targetType: input.targetType,
    targetId: input.targetId,
    actorAdminId: input.actorAdminId,
    reason: input.reason,
    dryRun: true,
    confirmationRequired: definition.confirmationRequired,
    expectedImpact,
    result,
    permissionDecision,
    auditRequired: requiredPermission.requiresPersistentAudit,
    auditPrepared: true,
    auditEventId: null,
    auditDraft,
    createdAt,
  };

  return {
    ok: true,
    code: result.code,
    message: result.message,
    action,
  };
}

export function buildPermissionRequiredResponse(
  details?: unknown,
): OperationalActionApiResponse {
  return errorResponse(
    "OPERATIONAL_ACTION_PERMISSION_REQUIRED",
    "permission_required",
    "Permissao especifica sera exigida antes da execucao real.",
    details,
  );
}

export function buildAuditRequiredResponse(
  details?: unknown,
): OperationalActionApiResponse {
  return errorResponse(
    "OPERATIONAL_ACTION_AUDIT_REQUIRED",
    "audit_required",
    "Auditoria persistida sera obrigatoria antes da execucao real.",
    details,
  );
}

export function buildTargetNotFoundResponse(
  details?: unknown,
): OperationalActionApiResponse {
  return errorResponse(
    "OPERATIONAL_ACTION_TARGET_NOT_FOUND",
    "target_not_found",
    "Alvo operacional nao encontrado.",
    details,
  );
}

export function buildInternalErrorResponse(): OperationalActionApiResponse {
  return errorResponse(
    "OPERATIONAL_ACTION_INTERNAL_ERROR",
    "internal_error",
    "Erro interno ao preparar acao operacional.",
  );
}

export function sanitizeOperationalActionPayload(
  value: unknown,
): Record<string, unknown> {
  const sanitized = sanitizeValue(value);
  if (sanitized != null && typeof sanitized === "object" && !Array.isArray(sanitized)) {
    return sanitized as Record<string, unknown>;
  }

  return { value: sanitized };
}

function buildExpectedImpact(
  input: OperationalActionDryRunRequest,
  definition: ActionDefinition,
): OperationalActionExpectedImpact {
  return {
    summary: definition.impactSummary,
    risks: [...definition.risks],
    affectedEntities: [
      {
        type: input.targetType,
        id: input.targetId,
      },
      {
        type: "audit",
        id: "pending",
        label: "Evento de auditoria futuro",
      },
      {
        type: "permission",
        id: input.actorAdminId,
        label: "Permissao granular futura do administrador",
      },
    ],
    confirmationRequired: definition.confirmationRequired,
  };
}

function validationErrorResponse(error: ZodError): OperationalActionApiResponse {
  return errorResponse(
    "OPERATIONAL_ACTION_VALIDATION_ERROR",
    "validation_error",
    "Payload de acao operacional invalido.",
    error.flatten(),
  );
}

function permissionDeniedResponse(
  decision: ReturnType<typeof decideSupportActionPermission>,
): OperationalActionApiResponse {
  const code =
    decision.missingPermission == null
      ? "OPERATIONAL_ACTION_PERMISSION_DENIED"
      : "OPERATIONAL_ACTION_MISSING_PERMISSION";
  const status =
    decision.missingPermission == null
      ? "permission_denied"
      : "missing_permission";
  return errorResponse(code, status, decision.reason, {
    actionType: decision.actionType,
    requiredPermission: decision.requiredPermission.permissionKey,
    missingPermission: decision.missingPermission ?? null,
    riskLevel: decision.requiredPermission.riskLevel,
    scopes: decision.requiredPermission.scopes,
  });
}

function actorRequiredResponse(details?: unknown): OperationalActionApiResponse {
  return errorResponse(
    "OPERATIONAL_ACTION_ACTOR_REQUIRED",
    "actor_required",
    "Ator administrativo obrigatorio para acao operacional.",
    details,
  );
}

function errorResponse(
  code: OperationalActionResultCode,
  status: OperationalActionResultStatus,
  message: string,
  details?: unknown,
): OperationalActionApiResponse {
  const result = resultPayload(code, status, message);
  return {
    ok: false,
    code: result.code,
    message: result.message,
    details: details == null ? undefined : sanitizeValue(details),
    error: {
      code: result.code,
      message: result.message,
      details: details == null ? undefined : sanitizeValue(details),
    },
  };
}

function resultPayload(
  code: OperationalActionResultCode,
  status: OperationalActionResultStatus,
  message: string,
): OperationalActionResult {
  return { code, status, message };
}

function sanitizeValue(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.slice(0, 30).map(sanitizeValue);
  }

  if (value instanceof Date) {
    return value.toISOString();
  }

  if (typeof value === "string") {
    return sanitizeString(value);
  }

  if (value == null || typeof value !== "object") {
    return value;
  }

  const output: Record<string, unknown> = {};
  for (const [key, nested] of Object.entries(value)) {
    if (isSensitiveKey(key)) {
      output[key] = "[redacted]";
      continue;
    }

    output[key] = sanitizeValue(nested);
  }
  return output;
}

function isSensitiveKey(key: string) {
  const normalized = key.toLowerCase();
  return sensitiveKeyFragments.some((fragment) => normalized.includes(fragment));
}

function sanitizeString(value: string) {
  const normalized = value.trim();
  if (normalized.length > 500) {
    return `${normalized.slice(0, 500)}...`;
  }

  if (looksLikeSecret(normalized)) {
    return "[redacted]";
  }

  return normalized;
}

function looksLikeSecret(value: string) {
  if (/bearer\s+[a-z0-9._-]{16,}/i.test(value)) {
    return true;
  }

  if (/eyJ[a-z0-9_-]+\.[a-z0-9_-]+\.[a-z0-9_-]+/i.test(value)) {
    return true;
  }

  if (/sk_(live|test)_[a-z0-9]+/i.test(value)) {
    return true;
  }

  if (/(secret|token|password|authorization|cookie|credential)/i.test(value)) {
    return true;
  }

  return false;
}

export function assertSupportedTargetForAction(
  actionType: string,
  targetType: string,
) {
  return (
    isOperationalActionType(actionType) &&
    isOperationalActionTargetType(targetType) &&
    actionDefinitions[actionType].targetTypes.includes(targetType)
  );
}
