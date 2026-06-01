import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { AppError } from "../../shared/http/app-error";
import {
  legacySessionRevokeLogContext,
  revokeLegacyAdminSession,
} from "./legacy-session-revoke-audit";

describe("legacy admin session revoke audit", () => {
  it("persiste requested e succeeded sem alterar a revogacao legada", async () => {
    const fixture = createFixture();

    await revokeLegacyAdminSession(validInput(), fixture.dependencies);

    assert.deepEqual(fixture.revocations, [validInput()]);
    assert.equal(fixture.audits.length, 2);
    assert.equal(fixture.audits[0]?.data.action, "admin.sessions.legacy_revoke.used");
    assert.equal(fixture.audits[1]?.data.action, "admin.sessions.legacy_revoke.used");
    assert.equal(fixture.audits[0]?.data.actorType, "USER");
    assert.equal(fixture.audits[0]?.data.actorUserId, "admin-1");
    assert.equal(fixture.audits[0]?.data.actorLabel, null);
    assert.equal(fixture.audits[0]?.data.targetCompanyId, "company-1");
    assert.match(JSON.stringify(fixture.audits[0]), /"result":"requested"/);
    assert.match(JSON.stringify(fixture.audits[1]), /"result":"succeeded"/);
    assert.match(JSON.stringify(fixture.audits), /"targetType":"session"/);
    assert.match(JSON.stringify(fixture.audits), /"targetId":"session-1"/);
    assert.match(JSON.stringify(fixture.audits), /"origin":"legacy_route"/);
    assert.match(
      JSON.stringify(fixture.audits),
      /migrate_to_support_actions_revoke_session/,
    );
  });

  it("persiste falha segura e preserva o erro funcional legado", async () => {
    const expectedError = new AppError(
      "secret-token Bearer eyJabc.def.ghi",
      404,
      "SESSION_NOT_FOUND",
    );
    const fixture = createFixture({ revocationError: expectedError });

    await assert.rejects(
      revokeLegacyAdminSession(validInput(), fixture.dependencies),
      (error) => error === expectedError,
    );

    assert.equal(fixture.audits.length, 2);
    assert.match(JSON.stringify(fixture.audits[0]), /"result":"requested"/);
    assert.match(JSON.stringify(fixture.audits[1]), /"result":"failed"/);
    assert.match(JSON.stringify(fixture.audits[1]), /SESSION_NOT_FOUND/);
    assert.doesNotMatch(JSON.stringify(fixture.audits), /secret-token|Bearer/);
  });

  it("sanitiza sessionId suspeito antes de persistir ou registrar falha", async () => {
    const fixture = createFixture({
      sessionId: "Bearer eyJabc.def.ghi",
      auditPersistenceError: new Error("secret-token"),
    });

    await revokeLegacyAdminSession(
      { actorUserId: "admin-1", sessionId: "Bearer eyJabc.def.ghi" },
      fixture.dependencies,
    );

    assert.equal(fixture.audits.length, 0);
    assert.deepEqual(
      legacySessionRevokeLogContext({
        actorUserId: "admin-1",
        sessionId: "Bearer eyJabc.def.ghi",
      }),
      {
        actorUserId: "admin-1",
        sessionId: "[redacted]",
      },
    );
    const serializedLogs = JSON.stringify(fixture.logs);
    assert.match(serializedLogs, /\[redacted\]/);
    assert.doesNotMatch(serializedLogs, /Bearer|secret-token/);
  });

  it("mantem compatibilidade quando a persistencia de auditoria falha", async () => {
    const fixture = createFixture({
      auditPersistenceError: new Error("audit unavailable"),
    });

    await revokeLegacyAdminSession(validInput(), fixture.dependencies);

    assert.deepEqual(fixture.revocations, [validInput()]);
    assert.equal(fixture.audits.length, 0);
    assert.match(JSON.stringify(fixture.logs), /audit_persistence_failed/);
  });
});

function validInput() {
  return {
    sessionId: "session-1",
    actorUserId: "admin-1",
  };
}

function createFixture(
  options: {
    sessionId?: string;
    revocationError?: Error;
    auditPersistenceError?: Error;
  } = {},
) {
  const audits: Array<{ data: Record<string, unknown> }> = [];
  const logs: Array<{ message: string; context?: Record<string, unknown> }> = [];
  const revocations: Array<{ sessionId: string; actorUserId: string }> = [];
  const sessionId = options.sessionId ?? "session-1";

  return {
    audits,
    logs,
    revocations,
    dependencies: {
      client: {
        deviceSession: {
          async findUnique(input: { where: { id: string } }) {
            return input.where.id === sessionId ? { companyId: "company-1" } : null;
          },
        },
        adminAuditLog: {
          async create(input: { data: Record<string, unknown> }) {
            if (options.auditPersistenceError != null) {
              throw options.auditPersistenceError;
            }
            audits.push(input);
            return { id: `audit-${audits.length}` };
          },
        },
      },
      operationalLogger: {
        warn(message: string, context?: Record<string, unknown>) {
          logs.push({ message, context });
        },
        error(message: string, context?: Record<string, unknown>) {
          logs.push({ message, context });
        },
      },
      now: () => new Date("2026-05-31T20:00:00.000Z"),
      async revokeSession(input: { sessionId: string; actorUserId: string }) {
        revocations.push(input);
        if (options.revocationError != null) {
          throw options.revocationError;
        }
      },
    },
  };
}
