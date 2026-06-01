import {
  type OperationalActionType,
  type SupportActionPermission,
  type SupportActionPermissionContext,
  type SupportActionPermissionDecision,
} from "./support-actions.types";

export const supportActionPermissionMatrix: Record<
  OperationalActionType,
  SupportActionPermission
> = {
  revoke_session: {
    actionType: "revoke_session",
    permissionKey: "support.session.revoke",
    description: "Permite preparar revogacao auditada de sessao.",
    riskLevel: "high",
    scopes: ["platform", "company", "user", "device"],
    requiresDryRun: true,
    requiresExplicitConfirmation: true,
    requiresReason: true,
    requiresPersistentAudit: true,
  },
  block_user: {
    actionType: "block_user",
    permissionKey: "support.user.block",
    description: "Permite preparar bloqueio auditado de usuario.",
    riskLevel: "critical",
    scopes: ["platform", "company", "user"],
    requiresDryRun: true,
    requiresExplicitConfirmation: true,
    requiresReason: true,
    requiresPersistentAudit: true,
  },
  unblock_user: {
    actionType: "unblock_user",
    permissionKey: "support.user.unblock",
    description: "Permite preparar reativacao auditada de usuario.",
    riskLevel: "critical",
    scopes: ["platform", "company", "user"],
    requiresDryRun: true,
    requiresExplicitConfirmation: true,
    requiresReason: true,
    requiresPersistentAudit: true,
  },
  force_sync: {
    actionType: "force_sync",
    permissionKey: "support.sync.force",
    description: "Permite preparar solicitacao auditada de sync.",
    riskLevel: "high",
    scopes: ["platform", "company", "device", "sync"],
    requiresDryRun: true,
    requiresExplicitConfirmation: true,
    requiresReason: true,
    requiresPersistentAudit: true,
  },
  resolve_conflict: {
    actionType: "resolve_conflict",
    permissionKey: "support.sync.conflict.resolve",
    description: "Permite preparar resolucao auditada de conflito de sync.",
    riskLevel: "critical",
    scopes: ["platform", "company", "sync"],
    requiresDryRun: true,
    requiresExplicitConfirmation: true,
    requiresReason: true,
    requiresPersistentAudit: true,
  },
  update_license: {
    actionType: "update_license",
    permissionKey: "support.license.update",
    description: "Permite preparar alteracao auditada de licenca.",
    riskLevel: "critical",
    scopes: ["platform", "company", "billing"],
    requiresDryRun: true,
    requiresExplicitConfirmation: true,
    requiresReason: true,
    requiresPersistentAudit: true,
  },
  update_android_version_policy: {
    actionType: "update_android_version_policy",
    permissionKey: "support.androidVersionPolicy.update",
    description: "Permite preparar politica auditada de versao Android.",
    riskLevel: "high",
    scopes: ["platform", "company", "android_version"],
    requiresDryRun: true,
    requiresExplicitConfirmation: true,
    requiresReason: true,
    requiresPersistentAudit: true,
  },
  send_push_notification: {
    actionType: "send_push_notification",
    permissionKey: "support.push.send",
    description: "Permite preparar envio auditado de push futuro.",
    riskLevel: "high",
    scopes: ["platform", "company", "user", "device", "fcm"],
    requiresDryRun: true,
    requiresExplicitConfirmation: true,
    requiresReason: true,
    requiresPersistentAudit: true,
  },
};

export function getSupportActionPermission(actionType: OperationalActionType) {
  return supportActionPermissionMatrix[actionType];
}

export function decideSupportActionPermission(input: {
  actionType: OperationalActionType;
  context: SupportActionPermissionContext;
}): SupportActionPermissionDecision {
  const requiredPermission = getSupportActionPermission(input.actionType);

  if (input.context.actorAdminId == null || input.context.actorAdminId.trim() === "") {
    return {
      allowed: false,
      denied: true,
      reason: "Ator administrativo obrigatorio para acao operacional.",
      missingPermission: requiredPermission.permissionKey,
      requiredPermission,
      actionType: input.actionType,
    };
  }

  const hasPermission = input.context.permissionKeys?.includes(
    requiredPermission.permissionKey,
  );

  if (hasPermission) {
    return {
      allowed: true,
      denied: false,
      reason: "Permissao granular concedida.",
      requiredPermission,
      actionType: input.actionType,
    };
  }

  if (
    input.context.allowPlatformAdminFallback === true &&
    input.context.isPlatformAdmin === true
  ) {
    return {
      allowed: true,
      denied: false,
      reason:
        "Fallback temporario por isPlatformAdmin habilitado explicitamente.",
      requiredPermission,
      actionType: input.actionType,
    };
  }

  return {
    allowed: false,
    denied: true,
    reason:
      "Permissao granular ausente. isPlatformAdmin sozinho nao libera acao sensivel.",
    missingPermission: requiredPermission.permissionKey,
    requiredPermission,
    actionType: input.actionType,
  };
}
