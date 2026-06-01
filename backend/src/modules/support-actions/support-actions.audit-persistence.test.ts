import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { SupportActionAuditPersistenceService } from "./support-actions.audit-persistence";
import { buildOperationalActionDryRun } from "./support-actions.service";

describe("support actions audit persistence", () => {
  it("persiste dry-run em formato AdminAuditLog seguro", async () => {
    const created: Array<{ data: Record<string, unknown> }> = [];
    const service = new SupportActionAuditPersistenceService({
      adminAuditLog: {
        async create(input) {
          created.push(input);
          return { id: "audit-1" };
        },
      },
    });
    const response = buildOperationalActionDryRun(
      {
        actionType: "revoke_session",
        companyId: "company-1",
        targetType: "session",
        targetId: "session-1",
        actorAdminId: "admin-1",
        reason: "Chamado de seguranca confirmado",
        dryRun: true,
        metadata: {
          authorization: "Bearer eyJabc.def.ghi",
          note: "triagem",
        },
      },
      new Date("2026-05-31T17:00:00.000Z"),
      {
        actorAdminId: "admin-1",
        permissionKeys: ["support.session.revoke"],
      },
    );

    assert.equal(response.ok, true);
    assert.ok(response.action);

    const auditId = await service.recordDryRun(response.action);

    assert.equal(auditId, "audit-1");
    assert.equal(created[0]?.data.actorType, "USER");
    assert.equal(created[0]?.data.actorUserId, "admin-1");
    assert.equal(created[0]?.data.actorLabel, null);
    assert.equal(created[0]?.data.targetCompanyId, "company-1");
    assert.equal(created[0]?.data.action, "support.revoke_session.dry_run");
    assert.match(JSON.stringify(created[0]?.data.details), /\[redacted\]/);
    assert.doesNotMatch(
      JSON.stringify(created[0]?.data.details),
      /Bearer eyJabc/,
    );
  });

  it("audita tentativa negada sem vazar payload sensivel", async () => {
    const created: Array<{ data: Record<string, unknown> }> = [];
    const service = new SupportActionAuditPersistenceService({
      adminAuditLog: {
        async create(input) {
          created.push(input);
          return { id: "audit-denied-1" };
        },
      },
    });

    const auditId = await service.recordDeniedAttempt({
      actorAdminId: "admin-1",
      companyId: "company-1",
      actionType: "drop_database",
      targetType: "company",
      targetId: "company-1",
      response: {
        ok: false,
        code: "OPERATIONAL_ACTION_UNSUPPORTED",
        message: "Acao operacional nao suportada nesta fundacao.",
      },
      rawPayload: {
        actionType: "drop_database",
        authorization: "Bearer eyJabc.def.ghi",
        token: "secret-token",
      },
    });

    assert.equal(auditId, "audit-denied-1");
    assert.equal(created[0]?.data.actorType, "USER");
    assert.equal(created[0]?.data.actorUserId, "admin-1");
    assert.equal(created[0]?.data.actorLabel, null);
    assert.equal(created[0]?.data.action, "support.drop_database.dry_run.denied");
    assert.match(JSON.stringify(created[0]?.data.details), /\[redacted\]/);
    assert.doesNotMatch(
      JSON.stringify(created[0]?.data.details),
      /secret-token|Bearer eyJabc/,
    );
  });
});
