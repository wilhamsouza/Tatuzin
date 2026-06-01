import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import type { AddressInfo } from "node:net";
import type { Server } from "node:http";

import express from "express";

import { createSupportActionsRouter } from "./support-actions.routes";
import type {
  OperationalActionApiResponse,
  OperationalActionContract,
  SupportActionPermissionContext,
  SupportActionPermissionKey,
} from "./support-actions.types";
import type { SupportActionExecutionResponse } from "./support-actions.execution.types";

let server: Server;
let apiBaseUrl = "";
let fakeAuth:
  | {
      userId: string;
      isPlatformAdmin: boolean;
    }
  | null = {
  userId: "admin-1",
  isPlatformAdmin: true,
};
let persistedPermissionKeys: SupportActionPermissionKey[] = [
  "support.session.revoke",
];
const dryRunAudits: OperationalActionContract[] = [];
const deniedAudits: Array<{
  actorAdminId: string | null | undefined;
  response: OperationalActionApiResponse;
  rawPayload: unknown;
}> = [];
const executionRequests: Array<{
  rawInput: unknown;
  permissionContext?: SupportActionPermissionContext;
}> = [];

describe("support actions dry-run route", () => {
  before(() => {
    const app = express();
    app.use(express.json());
    app.use((request, _response, next) => {
      if (fakeAuth != null) {
        request.auth = {
          userId: fakeAuth.userId,
          companyId: "platform-company",
          membershipId: "membership-1",
          membershipRole: "OWNER",
          email: "admin@tatuzin.test",
          isPlatformAdmin: fakeAuth.isPlatformAdmin,
          accessToken: "test-token",
        };
      }
      next();
    });
    app.use(
      "/admin/support-actions",
      createSupportActionsRouter({
        rbacService: {
          async getSupportActionPermissionContext(
            actorAdminId: string,
          ): Promise<SupportActionPermissionContext> {
            return {
              actorAdminId,
              permissionKeys: persistedPermissionKeys,
              allowPlatformAdminFallback: false,
            };
          },
        },
        auditService: {
          async recordDryRun(action: OperationalActionContract) {
            dryRunAudits.push(action);
            return `audit-${dryRunAudits.length}`;
          },
          async recordDeniedAttempt(input) {
            deniedAudits.push(input);
            return input.actorAdminId == null
              ? null
              : `denied-audit-${deniedAudits.length}`;
          },
        },
        executionService: {
          async executeRevokeSession(
            rawInput,
            permissionContext,
          ): Promise<SupportActionExecutionResponse> {
            executionRequests.push({ rawInput, permissionContext });
            return {
              ok: true,
              code: "SUPPORT_ACTION_EXECUTED",
              message: "Sessao revogada com auditoria persistida.",
              execution: {
                id: "execution-1",
                actionType: "revoke_session",
                companyId: "company-1",
                targetType: "session",
                targetId: "session-1",
                target: {
                  type: "session",
                  id: "session-1",
                  companyId: "company-1",
                },
                actorAdminId: "admin-1",
                dryRunAuditEventId: "audit-1",
                correlationId: "audit-1",
                idempotencyKey: "ticket-123",
                status: "succeeded",
                result: {
                  status: "succeeded",
                  effectApplied: true,
                },
                auditBeforeId: "audit-before",
                auditAfterId: "audit-after",
                beforeAuditEventId: "audit-before",
                afterAuditEventId: "audit-after",
                executedAt: "2026-05-31T17:00:00.000Z",
              },
            };
          },
        },
        now: () => new Date("2026-05-31T17:00:00.000Z"),
      }),
    );

    server = app.listen(0);
    const address = server.address() as AddressInfo;
    apiBaseUrl = `http://127.0.0.1:${address.port}`;
  });

  after(async () => {
    await new Promise<void>((resolve, reject) => {
      server.close((error) => (error == null ? resolve() : reject(error)));
    });
  });

  it("retorna dry-run com payload valido e permissao granular", async () => {
    fakeAuth = { userId: "admin-1", isPlatformAdmin: true };
    persistedPermissionKeys = ["support.session.revoke"];
    dryRunAudits.length = 0;

    const response = await requestJson("/admin/support-actions/dry-run", {
      body: validBody(),
    });

    assert.equal(response.status, 200);
    assert.equal(response.data.ok, true);
    assert.equal(response.data.action.permissionKey, "support.session.revoke");
    assert.equal(response.data.action.dryRun, true);
    assert.equal(response.data.action.confirmationRequired, true);
    assert.equal(response.data.action.auditDraft.safePayload.metadata.token, "[redacted]");
    assert.equal(response.data.action.auditEventId, "audit-1");
    assert.equal(dryRunAudits.length, 1);
    const safePayload = dryRunAudits[0]?.auditDraft.safePayload as {
      metadata?: { token?: unknown };
    };
    assert.equal(safePayload.metadata?.token, "[redacted]");
  });

  it("rejeita dryRun false", async () => {
    const response = await requestJson("/admin/support-actions/dry-run", {
      body: { ...validBody(), dryRun: false },
    });

    assert.equal(response.status, 422);
    assert.equal(response.data.code, "OPERATIONAL_ACTION_VALIDATION_ERROR");
  });

  it("rejeita reason ausente ou curto", async () => {
    const missing = await requestJson("/admin/support-actions/dry-run", {
      body: { ...validBody(), reason: undefined },
    });
    assert.equal(missing.status, 422);
    assert.equal(missing.data.code, "OPERATIONAL_ACTION_VALIDATION_ERROR");

    const short = await requestJson("/admin/support-actions/dry-run", {
      body: { ...validBody(), reason: "curto" },
    });
    assert.equal(short.status, 422);
    assert.match(JSON.stringify(short.data.details), /pelo menos 12/);
  });

  it("retorna actor_required quando nao ha ator autenticado", async () => {
    fakeAuth = null;
    deniedAudits.length = 0;

    const response = await requestJson("/admin/support-actions/dry-run", {
      body: validBody(),
    });

    assert.equal(response.status, 401);
    assert.equal(response.data.code, "OPERATIONAL_ACTION_ACTOR_REQUIRED");
    assert.equal(deniedAudits.length, 1);
    assert.equal(deniedAudits[0]?.actorAdminId, undefined);
    fakeAuth = { userId: "admin-1", isPlatformAdmin: true };
  });

  it("ignora permissionKeys do cliente e exige permissao persistida", async () => {
    persistedPermissionKeys = [];
    deniedAudits.length = 0;

    const response = await requestJson("/admin/support-actions/dry-run", {
      body: {
        ...validBody(),
        permissionKeys: ["support.session.revoke"],
      },
    });

    assert.equal(response.status, 403);
    assert.equal(response.data.code, "OPERATIONAL_ACTION_MISSING_PERMISSION");
    assert.equal(deniedAudits.length, 1);
    assert.equal(deniedAudits[0]?.response.code, "OPERATIONAL_ACTION_MISSING_PERMISSION");
  });

  it("isPlatformAdmin sozinho nao libera acao sensivel", async () => {
    fakeAuth = { userId: "admin-1", isPlatformAdmin: true };
    persistedPermissionKeys = [];

    const response = await requestJson("/admin/support-actions/dry-run", {
      body: validBody(),
    });

    assert.equal(response.status, 403);
    assert.match(response.data.message, /isPlatformAdmin sozinho nao libera/);
  });

  it("fallback por platform admin nao funciona sem contexto backend explicito", async () => {
    fakeAuth = { userId: "admin-1", isPlatformAdmin: true };
    persistedPermissionKeys = [];

    const response = await requestJson("/admin/support-actions/dry-run", {
      body: {
        ...validBody(),
        allowPlatformAdminFallback: true,
      },
    });

    assert.equal(response.status, 403);
    assert.equal(response.data.code, "OPERATIONAL_ACTION_MISSING_PERMISSION");
  });

  it("retorna unsupported action sem preparar execucao", async () => {
    persistedPermissionKeys = ["support.session.revoke"];
    const response = await requestJson("/admin/support-actions/dry-run", {
      body: { ...validBody(), actionType: "drop_database" },
    });

    assert.equal(response.status, 400);
    assert.equal(response.data.code, "OPERATIONAL_ACTION_UNSUPPORTED");
    assert.equal(response.data.action, undefined);
  });

  it("nao chama execucao real e persiste apenas auditoria de dry-run", async () => {
    persistedPermissionKeys = ["support.session.revoke"];
    dryRunAudits.length = 0;
    const response = await requestJson("/admin/support-actions/dry-run", {
      body: validBody(),
    });

    assert.equal(response.status, 200);
    assert.equal(response.data.action.auditPrepared, true);
    assert.equal(response.data.action.auditEventId, "audit-1");
    assert.equal(response.data.action.result.status, "dry_run_ready");
    assert.equal(dryRunAudits.length, 1);
  });

  it("expoe somente rota explicita de revoke_session e usa ator do token", async () => {
    fakeAuth = { userId: "admin-1", isPlatformAdmin: true };
    persistedPermissionKeys = ["support.session.revoke"];
    executionRequests.length = 0;

    const response = await requestJson(
      "/admin/support-actions/revoke-session/execute",
      {
        body: {
          ...validBody(),
          actorAdminId: "forged-admin",
          dryRunAuditEventId: "audit-1",
          idempotencyKey: "ticket-123",
          explicitConfirmation: true,
          confirmationText: "REVOGAR_SESSAO",
        },
      },
    );

    assert.equal(response.status, 200);
    assert.equal(response.data.code, "SUPPORT_ACTION_EXECUTED");
    assert.equal(executionRequests.length, 1);
    assert.equal(
      (executionRequests[0]?.rawInput as { actorAdminId?: string }).actorAdminId,
      "admin-1",
    );
    assert.deepEqual(executionRequests[0]?.permissionContext?.permissionKeys, [
      "support.session.revoke",
    ]);
  });
});

function validBody() {
  return {
    actionType: "revoke_session",
    companyId: "company-1",
    targetType: "session",
    targetId: "session-1",
    reason: "Chamado de seguranca confirmado",
    metadata: {
      token: "secret-token",
      authorization: "Bearer eyJabc.def.ghi",
      note: "triagem segura",
    },
    permissionKeys: ["support.session.revoke"],
  };
}

async function requestJson(path: string, options: { body: unknown }) {
  const response = await fetch(`${apiBaseUrl}${path}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(options.body),
  });

  return {
    status: response.status,
    data: await response.json(),
  };
}
