import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { SupportActionExecutionService } from "./support-actions.execution.service";

describe("support action revoke_session execution pilot", () => {
  it("revoga sessao uma unica vez com auditoria before/after sanitizada", async () => {
    const fixture = createFixture();
    const response = await fixture.service.executeRevokeSession(
      validInput(),
      allowedPermissionContext(),
    );

    assert.equal(response.ok, true);
    assert.equal(response.code, "SUPPORT_ACTION_EXECUTED");
    assert.equal(response.execution?.status, "succeeded");
    assert.equal(fixture.revocations.length, 1);
    assert.equal(fixture.audits.length, 2);
    assert.equal(
      fixture.audits[0]?.data.action,
      "support.revoke_session.execute_requested",
    );
    assert.equal(
      fixture.audits[1]?.data.action,
      "support.revoke_session.execute_succeeded",
    );
    const serializedAudits = JSON.stringify(fixture.audits);
    assert.match(serializedAudits, /\[redacted\]/);
    assert.doesNotMatch(serializedAudits, /secret-token|Bearer eyJabc/);
    assert.match(serializedAudits, /support\.session\.revoke/);
    assert.match(serializedAudits, /revoke-session-ticket-123/);
    assert.match(serializedAudits, /timestamp/);
    const serializedLogs = JSON.stringify(fixture.logs);
    assert.match(serializedLogs, /execution\.requested/);
    assert.match(serializedLogs, /execution\.succeeded/);
    assert.doesNotMatch(serializedLogs, /secret-token|Bearer eyJabc/);
  });

  it("nega por padrao quando feature flag esta desligada e audita denied", async () => {
    const fixture = createFixture({ executionEnabled: false });
    const response = await fixture.service.executeRevokeSession(
      validInput(),
      allowedPermissionContext(),
    );

    assert.equal(response.ok, false);
    assert.equal(response.code, "SUPPORT_ACTION_EXECUTION_DISABLED");
    assert.equal(fixture.revocations.length, 0);
    assert.equal(
      fixture.audits[0]?.data.action,
      "support.revoke_session.execute_denied",
    );
    assert.match(JSON.stringify(fixture.audits[0]), /feature_flag_disabled/);
    assert.match(JSON.stringify(fixture.logs), /execution\.disabled/);
    assert.doesNotMatch(
      JSON.stringify(fixture.logs),
      /secret-token|Bearer eyJabc/,
    );
  });

  it("retorna replay idempotente sem revogar novamente", async () => {
    const fixture = createFixture();
    const first = await fixture.service.executeRevokeSession(
      validInput(),
      allowedPermissionContext(),
    );
    const second = await fixture.service.executeRevokeSession(
      validInput(),
      allowedPermissionContext(),
    );

    assert.equal(first.code, "SUPPORT_ACTION_EXECUTED");
    assert.equal(second.ok, true);
    assert.equal(second.code, "SUPPORT_ACTION_IDEMPOTENT_REPLAY");
    assert.equal(second.execution?.status, "idempotent_replay");
    assert.equal(fixture.revocations.length, 1);
    assert.match(JSON.stringify(fixture.logs), /execution\.idempotent_replay/);
  });

  it("audita e registra log seguro quando o revogador falha", async () => {
    const fixture = createFixture({
      revocationError: new Error("secret-token Bearer eyJabc.def.ghi"),
    });
    const response = await fixture.service.executeRevokeSession(
      validInput(),
      allowedPermissionContext(),
    );

    assert.equal(response.ok, false);
    assert.equal(response.code, "SUPPORT_ACTION_EXECUTION_INTERNAL_ERROR");
    assert.equal(
      fixture.audits[1]?.data.action,
      "support.revoke_session.execute_failed",
    );
    assert.match(JSON.stringify(fixture.logs), /execution\.failed/);
    assert.doesNotMatch(
      JSON.stringify(fixture.logs),
      /secret-token|Bearer eyJabc/,
    );
  });

  it("nega execucao sem permissao persistida mesmo para platform admin", async () => {
    const fixture = createFixture();
    const response = await fixture.service.executeRevokeSession(validInput(), {
      actorAdminId: "admin-1",
      permissionKeys: [],
      isPlatformAdmin: true,
      allowPlatformAdminFallback: false,
    });

    assert.equal(response.ok, false);
    assert.equal(response.code, "SUPPORT_ACTION_EXECUTION_PERMISSION_DENIED");
    assert.equal(fixture.revocations.length, 0);
    assert.equal(
      fixture.audits[0]?.data.action,
      "support.revoke_session.execute_denied",
    );
  });

  it("nega execucao sem dry-run persistido ou com dry-run expirado", async () => {
    const missing = createFixture({ dryRun: null });
    const missingResponse = await missing.service.executeRevokeSession(
      validInput(),
      allowedPermissionContext(),
    );
    assert.equal(
      missingResponse.code,
      "SUPPORT_ACTION_EXECUTION_DRY_RUN_REQUIRED",
    );

    const expired = createFixture({
      dryRunCreatedAt: new Date("2026-05-31T16:40:00.000Z"),
    });
    const expiredResponse = await expired.service.executeRevokeSession(
      validInput(),
      allowedPermissionContext(),
    );
    assert.equal(
      expiredResponse.code,
      "SUPPORT_ACTION_EXECUTION_DRY_RUN_EXPIRED",
    );
  });

  it("nega dry-run divergente, confirmacao ausente e idempotency key reutilizada", async () => {
    const mismatch = createFixture({
      dryRunDetails: { targetId: "outra-sessao" },
    });
    const mismatchResponse = await mismatch.service.executeRevokeSession(
      validInput(),
      allowedPermissionContext(),
    );
    assert.equal(
      mismatchResponse.code,
      "SUPPORT_ACTION_EXECUTION_DRY_RUN_MISMATCH",
    );

    const missingConfirmation = createFixture();
    const confirmationResponse =
      await missingConfirmation.service.executeRevokeSession(
        { ...validInput(), explicitConfirmation: false },
        allowedPermissionContext(),
      );
    assert.equal(
      confirmationResponse.code,
      "SUPPORT_ACTION_EXECUTION_VALIDATION_ERROR",
    );
    assert.match(
      JSON.stringify(missingConfirmation.logs),
      /execution\.payload_invalid/,
    );
    assert.doesNotMatch(
      JSON.stringify(missingConfirmation.logs),
      /secret-token|Bearer eyJabc/,
    );

    const keyReuse = createFixture();
    await keyReuse.service.executeRevokeSession(
      validInput(),
      allowedPermissionContext(),
    );
    const keyReuseResponse = await keyReuse.service.executeRevokeSession(
      { ...validInput(), targetId: "session-2" },
      allowedPermissionContext(),
    );
    assert.equal(
      keyReuseResponse.code,
      "SUPPORT_ACTION_EXECUTION_STATE_CONFLICT",
    );
  });

  it("nega motivo ausente e idempotency key ausente", async () => {
    const fixture = createFixture();
    const missingReason = await fixture.service.executeRevokeSession(
      { ...validInput(), reason: undefined },
      allowedPermissionContext(),
    );
    assert.equal(
      missingReason.code,
      "SUPPORT_ACTION_EXECUTION_VALIDATION_ERROR",
    );
    const missingIdempotencyKey = await fixture.service.executeRevokeSession(
      { ...validInput(), idempotencyKey: undefined },
      allowedPermissionContext(),
    );
    assert.equal(
      missingIdempotencyKey.code,
      "SUPPORT_ACTION_EXECUTION_VALIDATION_ERROR",
    );
  });

  it("nega alvo inexistente, fora da empresa ou sessao ja revogada", async () => {
    const missing = createFixture({ session: null });
    const missingResponse = await missing.service.executeRevokeSession(
      validInput(),
      allowedPermissionContext(),
    );
    assert.equal(
      missingResponse.code,
      "SUPPORT_ACTION_EXECUTION_TARGET_NOT_FOUND",
    );

    const wrongCompany = createFixture({
      session: {
        id: "session-1",
        companyId: "outra-empresa",
        userId: "user-1",
        revokedAt: null,
      },
    });
    const wrongCompanyResponse =
      await wrongCompany.service.executeRevokeSession(
        validInput(),
        allowedPermissionContext(),
      );
    assert.equal(
      wrongCompanyResponse.code,
      "SUPPORT_ACTION_EXECUTION_TARGET_NOT_FOUND",
    );

    const revoked = createFixture({
      session: {
        id: "session-1",
        companyId: "company-1",
        userId: "user-1",
        revokedAt: new Date("2026-05-31T16:30:00.000Z"),
      },
    });
    const revokedResponse = await revoked.service.executeRevokeSession(
      validInput(),
      allowedPermissionContext(),
    );
    assert.equal(
      revokedResponse.code,
      "SUPPORT_ACTION_EXECUTION_STATE_CONFLICT",
    );
  });

  it("nega qualquer actionType diferente de revoke_session", async () => {
    const fixture = createFixture();
    const response = await fixture.service.executeRevokeSession(
      { ...validInput(), actionType: "block_user", targetType: "user" },
      allowedPermissionContext(),
    );

    assert.equal(response.code, "SUPPORT_ACTION_EXECUTION_UNSUPPORTED");
    assert.equal(fixture.revocations.length, 0);
  });
});

function validInput() {
  return {
    actionType: "revoke_session",
    companyId: "company-1",
    targetType: "session",
    targetId: "session-1",
    actorAdminId: "admin-1",
    reason: "Chamado de seguranca confirmado",
    dryRunAuditEventId: "dry-run-audit-1",
    idempotencyKey: "revoke-session-ticket-123",
    explicitConfirmation: true,
    confirmationText: "REVOGAR_SESSAO",
    metadata: {
      token: "secret-token",
      authorization: "Bearer eyJabc.def.ghi",
      note: "execucao controlada",
    },
  };
}

function allowedPermissionContext() {
  return {
    actorAdminId: "admin-1",
    permissionKeys: ["support.session.revoke"] as const,
    allowPlatformAdminFallback: false,
  };
}

function createFixture(options?: {
  dryRun?: ReturnType<typeof createDryRun> | null;
  dryRunCreatedAt?: Date;
  dryRunDetails?: Record<string, unknown>;
  executionEnabled?: boolean;
  revocationError?: Error;
  session?: SessionRow | null;
}) {
  const audits: Array<{ data: Record<string, unknown> }> = [];
  const receipts = new Map<string, ReceiptRow>();
  const revocations: Array<Record<string, unknown>> = [];
  const logs: Array<{
    level: "info" | "warn" | "error";
    message: string;
    context?: Record<string, unknown>;
  }> = [];
  const dryRun =
    options?.dryRun === null
      ? null
      : options?.dryRun ??
        createDryRun(options?.dryRunCreatedAt, options?.dryRunDetails);
  const session =
    options != null && "session" in options
      ? options.session
      : {
          id: "session-1",
          companyId: "company-1",
          userId: "user-1",
          revokedAt: null,
        };

  const client = {
    adminAuditLog: {
      async findUnique() {
        return dryRun;
      },
      async create(input: { data: Record<string, unknown> }) {
        audits.push(input);
        return { id: `audit-${audits.length}` };
      },
    },
    deviceSession: {
      async findUnique() {
        return session;
      },
    },
    supportActionExecution: {
      async findUnique(input: { where: { idempotencyKey: string } }) {
        return receipts.get(input.where.idempotencyKey) ?? null;
      },
      async create(input: { data: Omit<ReceiptRow, "id" | "result" | "createdAt" | "updatedAt" | "executedAt" | "afterAuditEventId"> }) {
        const now = new Date("2026-05-31T17:00:00.000Z");
        const receipt: ReceiptRow = {
          id: `execution-${receipts.size + 1}`,
          ...input.data,
          afterAuditEventId: null,
          result: null,
          createdAt: now,
          updatedAt: now,
          executedAt: null,
        };
        receipts.set(receipt.idempotencyKey, receipt);
        return receipt;
      },
      async update(input: {
        where: { id: string };
        data: Pick<
          ReceiptRow,
          "status" | "afterAuditEventId" | "result" | "executedAt"
        >;
      }) {
        const receipt = [...receipts.values()].find(
          (candidate) => candidate.id === input.where.id,
        );
        assert.ok(receipt);
        Object.assign(receipt, input.data);
        return receipt;
      },
    },
  };
  const service = new SupportActionExecutionService(
    client as never,
    {
      async revokeCompanySession(input) {
        revocations.push(input);
        if (options?.revocationError != null) {
          throw options.revocationError;
        }
      },
    },
    () => new Date("2026-05-31T17:00:00.000Z"),
    {
      revokeSessionExecutionEnabled: options?.executionEnabled ?? true,
      logger: {
        info(message, context) {
          logs.push({ level: "info", message, context });
        },
        warn(message, context) {
          logs.push({ level: "warn", message, context });
        },
        error(message, context) {
          logs.push({ level: "error", message, context });
        },
      },
    },
  );

  return { service, audits, receipts, revocations, logs };
}

function createDryRun(
  createdAt = new Date("2026-05-31T16:55:00.000Z"),
  detailsOverride?: Record<string, unknown>,
) {
  return {
    id: "dry-run-audit-1",
    actorUserId: "admin-1",
    targetCompanyId: "company-1",
    action: "support.revoke_session.dry_run",
    details: {
      actionType: "revoke_session",
      targetType: "session",
      targetId: "session-1",
      dryRun: true,
      confirmationRequired: true,
      reason: "Chamado de seguranca confirmado",
      result: {
        code: "OPERATIONAL_ACTION_DRY_RUN_READY",
      },
      ...detailsOverride,
    },
    createdAt,
  };
}

type SessionRow = {
  id: string;
  companyId: string;
  userId: string;
  revokedAt: Date | null;
};

type ReceiptRow = {
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
