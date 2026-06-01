import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  assertSupportedTargetForAction,
  buildOperationalActionDryRun,
  buildPermissionRequiredResponse,
  sanitizeOperationalActionPayload,
} from "./support-actions.service";
import { mapSupportActionAuditToAdminAuditLog } from "./support-actions.audit";
import {
  decideSupportActionPermission,
  getSupportActionPermission,
} from "./support-actions.permissions";

const validRequest = {
  actionType: "revoke_session",
  companyId: "company-1",
  targetType: "session",
  targetId: "session-1",
  actorAdminId: "admin-1",
  reason: "Chamado de seguranca confirmado",
  dryRun: true,
  metadata: {
    authorization: "Bearer eyJabc.def.ghi",
    note: "avaliacao inicial",
  },
};

describe("support actions foundation", () => {
  it("prepara dry-run sem executar efeito real", () => {
    const response = buildOperationalActionDryRun(
      validRequest,
      new Date("2026-05-31T12:00:00.000Z"),
      {
        actorAdminId: "admin-1",
        permissionKeys: ["support.session.revoke"],
        isPlatformAdmin: true,
      },
    );

    assert.equal(response.ok, true);
    assert.equal(response.code, "OPERATIONAL_ACTION_DRY_RUN_READY");
    assert.equal(response.action?.permissionKey, "support.session.revoke");
    assert.equal(response.action?.dryRun, true);
    assert.equal(response.action?.auditRequired, true);
    assert.equal(response.action?.auditPrepared, true);
    assert.equal(response.action?.auditEventId, null);
    assert.equal(response.action?.createdAt, "2026-05-31T12:00:00.000Z");
    assert.equal(response.action?.result.status, "dry_run_ready");
    assert.equal(response.action?.auditDraft.riskLevel, "high");
    assert.equal(
      response.action?.expectedImpact.affectedEntities[0]?.id,
      "session-1",
    );
    const safePayload = response.action?.auditDraft.safePayload as {
      metadata?: { authorization?: unknown };
    };
    assert.equal(
      safePayload.metadata?.authorization,
      "[redacted]",
    );
  });

  it("nega acao sem permissionKey granular", () => {
    const response = buildOperationalActionDryRun(validRequest);

    assert.equal(response.ok, false);
    assert.equal(response.code, "OPERATIONAL_ACTION_MISSING_PERMISSION");
    assert.match(response.message, /isPlatformAdmin sozinho nao libera/);
    assert.match(JSON.stringify(response.details), /support.session.revoke/);
  });

  it("permite acao com permissionKey correta", () => {
    const response = buildOperationalActionDryRun(validRequest, new Date(), {
      actorAdminId: "admin-1",
      permissionKeys: ["support.session.revoke"],
    });

    assert.equal(response.ok, true);
    assert.equal(response.action?.permissionDecision.allowed, true);
    assert.equal(
      response.action?.permissionDecision.requiredPermission.permissionKey,
      "support.session.revoke",
    );
  });

  it("mapeia actionType para permissionKey correta", () => {
    assert.equal(
      getSupportActionPermission("resolve_conflict").permissionKey,
      "support.sync.conflict.resolve",
    );
    assert.equal(
      getSupportActionPermission("update_android_version_policy")
        .permissionKey,
      "support.androidVersionPolicy.update",
    );
  });

  it("isPlatformAdmin sozinho nao libera acao sensivel", () => {
    const response = buildOperationalActionDryRun(validRequest, new Date(), {
      actorAdminId: "admin-1",
      isPlatformAdmin: true,
      permissionKeys: [],
    });

    assert.equal(response.ok, false);
    assert.equal(response.code, "OPERATIONAL_ACTION_MISSING_PERMISSION");
  });

  it("fallback platform admin so funciona quando habilitado explicitamente", () => {
    const decision = decideSupportActionPermission({
      actionType: "revoke_session",
      context: {
        actorAdminId: "admin-1",
        isPlatformAdmin: true,
        allowPlatformAdminFallback: true,
      },
    });

    assert.equal(decision.allowed, true);
    assert.match(decision.reason, /Fallback temporario/);
  });

  it("exige actionType, companyId, target, actorAdminId e reason", () => {
    const response = buildOperationalActionDryRun({});

    assert.equal(response.ok, false);
    assert.equal(response.code, "OPERATIONAL_ACTION_VALIDATION_ERROR");
    assert.match(JSON.stringify(response.details), /actionType/);
    assert.match(JSON.stringify(response.details), /companyId/);
    assert.match(JSON.stringify(response.details), /targetType/);
    assert.match(JSON.stringify(response.details), /targetId/);
    assert.match(JSON.stringify(response.details), /actorAdminId/);
    assert.match(JSON.stringify(response.details), /reason/);
  });

  it("retorna actor_required quando actionType existe mas actorAdminId falta", () => {
    const { actorAdminId: _actorAdminId, ...input } = validRequest;
    const response = buildOperationalActionDryRun(input);

    assert.equal(response.ok, false);
    assert.equal(response.code, "OPERATIONAL_ACTION_ACTOR_REQUIRED");
    assert.match(response.message, /Ator administrativo/);
  });

  it("exige motivo minimo e claro para acoes sensiveis", () => {
    const response = buildOperationalActionDryRun({
      ...validRequest,
      reason: "curto",
    });

    assert.equal(response.ok, false);
    assert.equal(response.code, "OPERATIONAL_ACTION_VALIDATION_ERROR");
    assert.match(
      JSON.stringify(response.details),
      /pelo menos 12 caracteres/,
    );
  });

  it("bloqueia dryRun false nesta primeira etapa", () => {
    const response = buildOperationalActionDryRun({
      ...validRequest,
      dryRun: false,
    });

    assert.equal(response.ok, false);
    assert.equal(response.code, "OPERATIONAL_ACTION_VALIDATION_ERROR");
  });

  it("retorna erro padronizado para acao nao suportada", () => {
    const response = buildOperationalActionDryRun({
      ...validRequest,
      actionType: "drop_database",
    });

    assert.equal(response.ok, false);
    assert.equal(response.code, "OPERATIONAL_ACTION_UNSUPPORTED");
    assert.match(response.message, /nao suportada/);
  });

  it("retorna conflito de estado para alvo incompativel", () => {
    const response = buildOperationalActionDryRun({
      ...validRequest,
      actionType: "resolve_conflict",
      targetType: "session",
    });

    assert.equal(response.ok, false);
    assert.equal(response.code, "OPERATIONAL_ACTION_STATE_CONFLICT");
  });

  it("sanitiza payload seguro para auditoria futura", () => {
    const payload = sanitizeOperationalActionPayload({
      token: "secret-token",
      nested: {
        password: "123456",
        message: "texto operacional",
      },
      bearer: "Bearer eyJabc.def.ghi",
    });

    assert.equal(payload.token, "[redacted]");
    assert.deepEqual(payload.nested, {
      password: "[redacted]",
      message: "texto operacional",
    });
    assert.equal(payload.bearer, "[redacted]");
  });

  it("prepara auditoria segura e mapeavel para AdminAuditLog existente", () => {
    const response = buildOperationalActionDryRun(validRequest, new Date(), {
      actorAdminId: "admin-1",
      permissionKeys: ["support.session.revoke"],
    });

    assert.equal(response.ok, true);
    const draft = response.action?.auditDraft;
    assert.ok(draft);
    assert.equal(draft.permissionKey, "support.session.revoke");
    assert.equal(draft.confirmationRequired, true);
    const safePayload = draft.safePayload as {
      metadata?: { authorization?: unknown };
    };
    assert.equal(safePayload.metadata?.authorization, "[redacted]");

    const mapped = mapSupportActionAuditToAdminAuditLog(draft);
    assert.equal(mapped.actorType, "USER");
    assert.equal(mapped.actorUserId, "admin-1");
    assert.equal(mapped.actorLabel, null);
    assert.equal(mapped.targetCompanyId, "company-1");
    assert.equal(mapped.action, "support.revoke_session.dry_run");
    assert.equal(mapped.details.permissionKey, "support.session.revoke");
  });

  it("fornece resposta de ausencia de permissao futura", () => {
    const response = buildPermissionRequiredResponse({ permission: "support.run" });

    assert.equal(response.ok, false);
    assert.equal(response.code, "OPERATIONAL_ACTION_PERMISSION_REQUIRED");
    assert.match(response.message, /Permissao especifica/);
  });

  it("mapeia actionType e targetType permitidos", () => {
    assert.equal(assertSupportedTargetForAction("force_sync", "device"), true);
    assert.equal(assertSupportedTargetForAction("force_sync", "license"), false);
    assert.equal(assertSupportedTargetForAction("unknown", "device"), false);
  });
});
