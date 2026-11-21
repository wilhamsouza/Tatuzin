import {
  supportActionPermissionMatrix,
} from "../support-actions/support-actions.permissions";
import {
  adminPermissionManagementKey,
  adminPlatformPermissionKeys,
  type AdminPermissionDefinition,
  type AdminPermissionKey,
  tenantDeletionPermissionKeys,
} from "./admin-permissions.types";

const supportActionPermissionDefinitions: AdminPermissionDefinition[] =
  Object.values(supportActionPermissionMatrix).map((permission) => ({
    permissionKey: permission.permissionKey,
    description: permission.description,
    riskLevel: permission.riskLevel,
    scopes: permission.scopes,
    category: "support-action",
    actionType: permission.actionType,
    requiresDryRun: permission.requiresDryRun,
    requiresReason: permission.requiresReason,
    requiresPersistentAudit: permission.requiresPersistentAudit,
    requiresExplicitConfirmation: permission.requiresExplicitConfirmation,
  }));

const tenantDeletionPermissionDefinitions: AdminPermissionDefinition[] = [
  {
    permissionKey: tenantDeletionPermissionKeys[0],
    description:
      "Permite consultar solicitacoes e inventarios read-only de exclusao de tenant.",
    riskLevel: "high",
    scopes: ["platform", "company"],
    category: "tenant-deletion",
    requiresDryRun: false,
    requiresReason: false,
    requiresPersistentAudit: true,
    requiresExplicitConfirmation: false,
  },
  {
    permissionKey: tenantDeletionPermissionKeys[1],
    description:
      "Permite registrar solicitacoes e iniciar a validacao de identidade sem executar exclusao real.",
    riskLevel: "critical",
    scopes: ["platform", "company"],
    category: "tenant-deletion",
    requiresDryRun: false,
    requiresReason: true,
    requiresPersistentAudit: true,
    requiresExplicitConfirmation: false,
  },
  {
    permissionKey: tenantDeletionPermissionKeys[2],
    description:
      "Permite registrar validacao de identidade e autoridade sobre a empresa.",
    riskLevel: "critical",
    scopes: ["platform", "company"],
    category: "tenant-deletion",
    requiresDryRun: false,
    requiresReason: true,
    requiresPersistentAudit: true,
    requiresExplicitConfirmation: false,
  },
  {
    permissionKey: tenantDeletionPermissionKeys[3],
    description:
      "Permite cancelar ou rejeitar solicitacao de exclusao de tenant sem alterar dados da empresa.",
    riskLevel: "critical",
    scopes: ["platform", "company"],
    category: "tenant-deletion",
    requiresDryRun: false,
    requiresReason: true,
    requiresPersistentAudit: true,
    requiresExplicitConfirmation: false,
  },
  {
    permissionKey: tenantDeletionPermissionKeys[4],
    description:
      "Permite colocar tenant em quarentena operacional reversivel, bloqueando acesso e sync sem excluir dados.",
    riskLevel: "critical",
    scopes: ["platform", "company"],
    category: "tenant-deletion",
    requiresDryRun: true,
    requiresReason: true,
    requiresPersistentAudit: true,
    requiresExplicitConfirmation: true,
  },
  {
    permissionKey: tenantDeletionPermissionKeys[5],
    description:
      "Permite executar anonimizacao e exclusao seletiva irreversivel de tenant em quarentena.",
    riskLevel: "critical",
    scopes: ["platform", "company"],
    category: "tenant-deletion",
    requiresDryRun: true,
    requiresReason: true,
    requiresPersistentAudit: true,
    requiresExplicitConfirmation: true,
  },
];

const platformLabels: Record<typeof adminPlatformPermissionKeys[number], string> = {
  "admin.overview.read": "Consultar visão geral da plataforma",
  "admin.companies.read": "Consultar empresas e pessoas no escopo autorizado",
  "admin.support.read": "Consultar suporte e chamados internos",
  "admin.support.manage": "Gerenciar chamados internos de suporte",
  "admin.sync.read": "Consultar eventos e conflitos de sincronização",
  "admin.billing.read": "Consultar assinaturas e cobranças",
  "admin.billing.manage": "Atualizar a situação de cobrança sem alterar o plano",
  "admin.devices.read": "Consultar dispositivos e sessões",
  "admin.usage.read": "Consultar eventos de uso da plataforma",
  "admin.audit.read": "Consultar auditoria administrativa",
};
const platformDefinitions: AdminPermissionDefinition[] = adminPlatformPermissionKeys.map(permissionKey => ({
  permissionKey, description: platformLabels[permissionKey],
  riskLevel: permissionKey.endsWith('.manage') ? 'critical' : 'high',
  scopes: ['platform', 'company'], category: 'platform',
  requiresDryRun: false, requiresReason: permissionKey.endsWith('.manage'),
  requiresPersistentAudit: true, requiresExplicitConfirmation: permissionKey.endsWith('.manage'),
}));

export const adminPermissionDefinitions: AdminPermissionDefinition[] = [
  ...platformDefinitions,
  {
    permissionKey: adminPermissionManagementKey,
    description:
      "Permite conceder, revogar e consultar permissoes administrativas persistidas.",
    riskLevel: "critical",
    scopes: ["platform"],
    category: "admin-permissions",
    requiresDryRun: false,
    requiresReason: true,
    requiresPersistentAudit: true,
    requiresExplicitConfirmation: true,
  },
  ...tenantDeletionPermissionDefinitions,
  ...supportActionPermissionDefinitions,
];

export function listKnownAdminPermissions() {
  return adminPermissionDefinitions;
}

export function getAdminPermissionDefinition(permissionKey: string) {
  return adminPermissionDefinitions.find(
    (permission) => permission.permissionKey === permissionKey,
  );
}

export function isKnownAdminPermissionKey(
  permissionKey: string,
): permissionKey is AdminPermissionKey {
  return getAdminPermissionDefinition(permissionKey) != null;
}

export function isCriticalAdminPermission(permissionKey: string) {
  const definition = getAdminPermissionDefinition(permissionKey);
  return (
    definition?.riskLevel === "critical" || definition?.riskLevel === "high"
  );
}
