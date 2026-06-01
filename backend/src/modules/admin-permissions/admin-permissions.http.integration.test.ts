import assert from "node:assert/strict";
import type { Server } from "node:http";
import type { AddressInfo } from "node:net";
import { after, before, beforeEach, describe, it } from "node:test";

import type { PrismaClient } from "@prisma/client";
import bcrypt from "bcryptjs";

import {
  resolveIntegrationTestDatabaseConfig,
} from "../../shared/testing/integration-prisma";

const integrationConfig = resolveIntegrationTestDatabaseConfig();
const skipReason =
  integrationConfig.enabled ? false : integrationConfig.skipReason;
const runId = `admin-permissions-http-${Date.now()}`;
const testPassword = "IntegrationPassword1!";

let prisma: PrismaClient;
let server: Server | null = null;
let apiBaseUrl = "";

describe("admin permissions HTTP integration", { skip: skipReason }, () => {
  before(async () => {
    if (!integrationConfig.enabled) {
      throw new Error(integrationConfig.skipReason);
    }

    process.env.DATABASE_URL = integrationConfig.databaseUrl;
    process.env.JWT_SECRET ??= "integration-http-jwt-secret";
    process.env.APP_ENV ??= "integration-test";
    process.env.CORS_ORIGINS ??= "http://127.0.0.1";
    process.env.SUPPORT_ACTION_REVOKE_SESSION_EXECUTION_ENABLED = "true";

    const [{ createApp }, prismaModule] = await Promise.all([
      import("../../app"),
      import("../../database/prisma"),
    ]);
    prisma = prismaModule.prisma;
    await prisma.$connect();

    server = createApp().listen(0);
    const address = server.address() as AddressInfo;
    apiBaseUrl = `http://127.0.0.1:${address.port}/api`;
  });

  beforeEach(async () => {
    await cleanupFixtures();
  });

  after(async () => {
    await cleanupFixtures();
    if (server != null) {
      await new Promise<void>((resolve, reject) => {
        server?.close((error) => (error == null ? resolve() : reject(error)));
      });
    }
    await prisma?.$disconnect();
  });

  it("protege rotas administrativas com auth real e plataforma admin", async () => {
    const fixture = await createFixture();

    const unauthenticated = await requestJson(
      "GET",
      "/admin/permissions/catalog",
    );
    assert.equal(unauthenticated.status, 401);
    assert.equal(
      (unauthenticated.data as { code?: string }).code,
      "AUTH_REQUIRED",
    );

    const forbidden = await requestJson("GET", "/admin/permissions/catalog", {
      token: fixture.nonAdmin.token,
    });
    assert.equal(forbidden.status, 403);
    assert.equal(
      (forbidden.data as { code?: string }).code,
      "PLATFORM_ADMIN_REQUIRED",
    );

    const catalog = await requestJson("GET", "/admin/permissions/catalog", {
      token: fixture.noManage.token,
    });
    assert.equal(catalog.status, 200);
    assert.ok(
      (catalog.data as CatalogResponse).catalog.some(
        (permission) =>
          permission.permissionKey === "admin-permissions.manage",
      ),
    );

    const deniedList = await requestJson(
      "GET",
      `/admin/permissions/users/${fixture.target.id}`,
      { token: fixture.noManage.token },
    );
    assert.equal(deniedList.status, 403);
    assert.equal(
      (deniedList.data as { code?: string }).code,
      "ADMIN_PERMISSION_MANAGE_REQUIRED",
    );
  });

  it("valida list/grant/revoke, auditoria e support-actions dry-run por HTTP", async () => {
    const fixture = await createFixture();

    const initialList = await requestJson(
      "GET",
      `/admin/permissions/users/${fixture.target.id}`,
      { token: fixture.manager.token },
    );
    assert.equal(initialList.status, 200);
    assert.deepEqual((initialList.data as PermissionsResponse).permissions, []);

    const invalidGrant = await requestJson(
      "POST",
      `/admin/permissions/users/${fixture.target.id}/grant`,
      {
        token: fixture.manager.token,
        body: {
          permissionKey: "support.session.revoke",
          reason: "curto",
          authorization: "Bearer forged-token",
          secret: "secret-token",
          password: "senha-super-secreta",
        },
      },
    );
    assert.equal(invalidGrant.status, 422);
    assert.equal(
      (invalidGrant.data as { code?: string }).code,
      "ADMIN_PERMISSION_VALIDATION_ERROR",
    );
    await assertSanitizedAudit((invalidGrant.data as AuditResponse).auditEventId);

    const unknownPermission = await requestJson(
      "POST",
      `/admin/permissions/users/${fixture.target.id}/grant`,
      {
        token: fixture.manager.token,
        body: {
          permissionKey: "support.unknown.permission",
          reason: "Chamado aprovado pelo gestor",
        },
      },
    );
    assert.equal(unknownPermission.status, 422);
    assert.equal(
      (unknownPermission.data as { code?: string }).code,
      "ADMIN_PERMISSION_UNSUPPORTED",
    );
    await assertAuditExists(
      (unknownPermission.data as AuditResponse).auditEventId,
      "admin.permission.grant.denied",
    );

    const grant = await requestJson(
      "POST",
      `/admin/permissions/users/${fixture.target.id}/grant`,
      {
        token: fixture.manager.token,
        body: {
          permissionKey: "support.session.revoke",
          reason: "Chamado aprovado para analise segura",
        },
      },
    );
    assert.equal(grant.status, 200);
    assert.equal(
      (grant.data as { code?: string }).code,
      "ADMIN_PERMISSION_GRANTED",
    );
    await assertAuditExists(
      (grant.data as AuditResponse).auditEventId,
      "admin.permission.grant",
    );

    const listAfterGrant = await requestJson(
      "GET",
      `/admin/permissions/users/${fixture.target.id}`,
      { token: fixture.manager.token },
    );
    assert.equal(listAfterGrant.status, 200);
    assert.ok(
      (listAfterGrant.data as PermissionsResponse).permissions.some(
        (permission) => permission.permissionKey === "support.session.revoke",
      ),
    );

    const forgedPermissionDryRun = await requestJson(
      "POST",
      "/admin/support-actions/dry-run",
      {
        token: fixture.noManage.token,
        body: {
          actionType: "revoke_session",
          companyId: fixture.companyId,
          targetType: "session",
          targetId: "session-1",
          reason: "Chamado de seguranca confirmado",
          dryRun: true,
          permissionKeys: ["support.session.revoke"],
          metadata: {
            cookie: "session-cookie",
            jwt: "forged-jwt",
            credential: "raw-credential",
          },
        },
      },
    );
    assert.equal(forgedPermissionDryRun.status, 403);
    assert.equal(
      (forgedPermissionDryRun.data as { code?: string }).code,
      "OPERATIONAL_ACTION_MISSING_PERMISSION",
    );
    await assertSupportAuditSanitized(
      fixture.noManage.id,
      "support.revoke_session.dry_run.denied",
    );

    const allowedDryRun = await requestJson(
      "POST",
      "/admin/support-actions/dry-run",
      {
        token: fixture.target.token,
        body: {
          actionType: "revoke_session",
          companyId: fixture.companyId,
          targetType: "session",
          targetId: "session-2",
          actorAdminId: fixture.noManage.id,
          reason: "Chamado de seguranca confirmado",
          dryRun: true,
          metadata: {
            token: "secret-token",
            webhook: "webhook-secret",
          },
        },
      },
    );
    assert.equal(allowedDryRun.status, 200);
    const allowedDryRunPayload = allowedDryRun.data as DryRunResponse;
    assert.equal(allowedDryRunPayload.ok, true);
    assert.equal(allowedDryRunPayload.action.actorAdminId, fixture.target.id);
    assert.equal(allowedDryRunPayload.action.dryRun, true);
    assert.equal(
      allowedDryRunPayload.action.result.code,
      "OPERATIONAL_ACTION_DRY_RUN_READY",
    );
    await assertAuditExists(
      allowedDryRunPayload.action.auditEventId,
      "support.revoke_session.dry_run",
    );
    await assertSanitizedAudit(allowedDryRunPayload.action.auditEventId);

    const revocableSession = await prisma.deviceSession.findFirst({
      where: { userId: fixture.noManage.id },
      select: { id: true },
    });
    assert.ok(revocableSession);
    const executionDryRun = await requestJson(
      "POST",
      "/admin/support-actions/dry-run",
      {
        token: fixture.target.token,
        body: {
          actionType: "revoke_session",
          companyId: fixture.companyId,
          targetType: "session",
          targetId: revocableSession.id,
          reason: "Chamado aprovado para revogar sessao",
          dryRun: true,
        },
      },
    );
    assert.equal(executionDryRun.status, 200);
    const executionDryRunPayload = executionDryRun.data as DryRunResponse;
    const forgedExecution = await requestJson(
      "POST",
      "/admin/support-actions/revoke-session/execute",
      {
        token: fixture.noManage.token,
        body: {
          actionType: "revoke_session",
          companyId: fixture.companyId,
          targetType: "session",
          targetId: revocableSession.id,
          reason: "Chamado aprovado para revogar sessao",
          dryRunAuditEventId: executionDryRunPayload.action.auditEventId,
          idempotencyKey: `${runId}-forged-revoke-session`,
          explicitConfirmation: true,
          confirmationText: "REVOGAR_SESSAO",
          permissionKeys: ["support.session.revoke"],
        },
      },
    );
    assert.equal(forgedExecution.status, 403);
    assert.equal(
      (forgedExecution.data as { code?: string }).code,
      "SUPPORT_ACTION_EXECUTION_PERMISSION_DENIED",
    );
    const unsupportedExecution = await requestJson(
      "POST",
      "/admin/support-actions/revoke-session/execute",
      {
        token: fixture.target.token,
        body: {
          actionType: "block_user",
          companyId: fixture.companyId,
          targetType: "user",
          targetId: fixture.noManage.id,
          reason: "Tentativa bloqueada para acao nao liberada",
          dryRunAuditEventId: executionDryRunPayload.action.auditEventId,
          idempotencyKey: `${runId}-unsupported`,
          explicitConfirmation: true,
          confirmationText: "REVOGAR_SESSAO",
        },
      },
    );
    assert.equal(unsupportedExecution.status, 400);
    assert.equal(
      (unsupportedExecution.data as { code?: string }).code,
      "SUPPORT_ACTION_EXECUTION_UNSUPPORTED",
    );
    const execute = await requestJson(
      "POST",
      "/admin/support-actions/revoke-session/execute",
      {
        token: fixture.target.token,
        body: {
          actionType: "revoke_session",
          companyId: fixture.companyId,
          targetType: "session",
          targetId: revocableSession.id,
          actorAdminId: fixture.noManage.id,
          reason: "Chamado aprovado para revogar sessao",
          dryRunAuditEventId: executionDryRunPayload.action.auditEventId,
          idempotencyKey: `${runId}-revoke-session`,
          explicitConfirmation: true,
          confirmationText: "REVOGAR_SESSAO",
          metadata: {
            token: "secret-token",
          },
        },
      },
    );
    assert.equal(execute.status, 200);
    assert.equal(
      (execute.data as ExecutionResponse).code,
      "SUPPORT_ACTION_EXECUTED",
    );
    assert.equal(
      (execute.data as ExecutionResponse).execution.actorAdminId,
      fixture.target.id,
    );
    const persistedSession = await prisma.deviceSession.findUnique({
      where: { id: revocableSession.id },
    });
    assert.notEqual(persistedSession?.revokedAt, null);
    await assertAuditExists(
      (execute.data as ExecutionResponse).execution.beforeAuditEventId,
      "support.revoke_session.execute_requested",
    );
    await assertAuditExists(
      (execute.data as ExecutionResponse).execution.afterAuditEventId,
      "support.revoke_session.execute_succeeded",
    );
    const replay = await requestJson(
      "POST",
      "/admin/support-actions/revoke-session/execute",
      {
        token: fixture.target.token,
        body: {
          actionType: "revoke_session",
          companyId: fixture.companyId,
          targetType: "session",
          targetId: revocableSession.id,
          reason: "Chamado aprovado para revogar sessao",
          dryRunAuditEventId: executionDryRunPayload.action.auditEventId,
          idempotencyKey: `${runId}-revoke-session`,
          explicitConfirmation: true,
          confirmationText: "REVOGAR_SESSAO",
        },
      },
    );
    assert.equal(replay.status, 200);
    assert.equal(
      (replay.data as ExecutionResponse).code,
      "SUPPORT_ACTION_IDEMPOTENT_REPLAY",
    );

    const dryRunFalse = await requestJson(
      "POST",
      "/admin/support-actions/dry-run",
      {
        token: fixture.target.token,
        body: {
          actionType: "revoke_session",
          companyId: fixture.companyId,
          targetType: "session",
          targetId: "session-3",
          reason: "Chamado de seguranca confirmado",
          dryRun: false,
        },
      },
    );
    assert.equal(dryRunFalse.status, 422);

    const revoke = await requestJson(
      "POST",
      `/admin/permissions/users/${fixture.target.id}/revoke`,
      {
        token: fixture.manager.token,
        body: {
          permissionKey: "support.session.revoke",
          reason: "Revogacao aprovada em revisao",
        },
      },
    );
    assert.equal(revoke.status, 200);
    assert.equal(
      (revoke.data as { code?: string }).code,
      "ADMIN_PERMISSION_REVOKED",
    );
    await assertAuditExists(
      (revoke.data as AuditResponse).auditEventId,
      "admin.permission.revoke",
    );

    const revokeMissing = await requestJson(
      "POST",
      `/admin/permissions/users/${fixture.target.id}/revoke`,
      {
        token: fixture.manager.token,
        body: {
          permissionKey: "support.sync.force",
          reason: "Revogacao preventiva sem vinculo ativo",
        },
      },
    );
    assert.equal(revokeMissing.status, 200);
    assert.equal(
      (revokeMissing.data as RevokeResponse).details.revokedCount,
      0,
    );

    const deniedAfterRevoke = await requestJson(
      "POST",
      "/admin/support-actions/dry-run",
      {
        token: fixture.target.token,
        body: {
          actionType: "revoke_session",
          companyId: fixture.companyId,
          targetType: "session",
          targetId: "session-4",
          reason: "Chamado de seguranca confirmado",
          dryRun: true,
        },
      },
    );
    assert.equal(deniedAfterRevoke.status, 403);
    assert.equal(
      (deniedAfterRevoke.data as { code?: string }).code,
      "OPERATIONAL_ACTION_MISSING_PERMISSION",
    );
  });
});

type TestIdentity = {
  id: string;
  email: string;
  token: string;
};

type TestFixture = {
  companyId: string;
  manager: TestIdentity;
  target: TestIdentity;
  noManage: TestIdentity;
  nonAdmin: TestIdentity;
};

type CatalogResponse = {
  catalog: Array<{ permissionKey: string }>;
};

type PermissionsResponse = {
  permissions: Array<{ permissionKey: string }>;
};

type AuditResponse = {
  auditEventId: string | null;
};

type RevokeResponse = {
  details: { revokedCount: number };
};

type DryRunResponse = {
  ok: true;
  action: {
    actorAdminId: string;
    dryRun: boolean;
    auditEventId: string;
    result: { code: string };
  };
};

type ExecutionResponse = {
  code: string;
  execution: {
    actorAdminId: string;
    beforeAuditEventId: string;
    afterAuditEventId: string;
  };
};

async function createFixture(): Promise<TestFixture> {
  const suffix = `${Date.now()}-${Math.random().toString(16).slice(2)}`;
  const company = await prisma.company.create({
    data: {
      name: "Admin Permissions HTTP Integration",
      legalName: "Admin Permissions HTTP Integration LTDA",
      slug: `${runId}-${suffix}`,
    },
  });
  await prisma.license.create({
    data: {
      companyId: company.id,
      plan: "pro",
      status: "ACTIVE",
      startsAt: new Date(),
      maxDevices: 10,
      syncEnabled: true,
    },
  });

  const passwordHash = await bcrypt.hash(testPassword, 8);
  const [managerUser, targetUser, noManageUser, nonAdminUser] =
    await Promise.all([
      createUser("manager", passwordHash, true),
      createUser("target", passwordHash, true),
      createUser("no-manage", passwordHash, true),
      createUser("non-admin", passwordHash, false),
    ]);

  await Promise.all([
    createMembership(company.id, managerUser.id),
    createMembership(company.id, targetUser.id),
    createMembership(company.id, noManageUser.id),
    createMembership(company.id, nonAdminUser.id),
  ]);
  await prisma.adminUserPermission.create({
    data: {
      actorUserId: managerUser.id,
      permissionKey: "admin-permissions.manage",
      scope: "platform",
      scopeId: "*",
      isActive: true,
    },
  });

  const [managerToken, targetToken, noManageToken, nonAdminToken] =
    await Promise.all([
      login(managerUser.email, "manager"),
      login(targetUser.email, "target"),
      login(noManageUser.email, "no-manage"),
      login(nonAdminUser.email, "non-admin"),
    ]);

  return {
    companyId: company.id,
    manager: { id: managerUser.id, email: managerUser.email, token: managerToken },
    target: { id: targetUser.id, email: targetUser.email, token: targetToken },
    noManage: {
      id: noManageUser.id,
      email: noManageUser.email,
      token: noManageToken,
    },
    nonAdmin: {
      id: nonAdminUser.id,
      email: nonAdminUser.email,
      token: nonAdminToken,
    },
  };
}

async function createUser(
  label: string,
  passwordHash: string,
  isPlatformAdmin: boolean,
) {
  return prisma.user.create({
    data: {
      email: `${runId}-${label}-${Date.now()}-${Math.random()
        .toString(16)
        .slice(2)}@integration.test`,
      passwordHash,
      name: `HTTP ${label}`,
      isActive: true,
      isPlatformAdmin,
    },
  });
}

async function createMembership(companyId: string, userId: string) {
  return prisma.membership.create({
    data: {
      companyId,
      userId,
      role: "OWNER",
      isDefault: true,
    },
  });
}

async function login(email: string, label: string) {
  const response = await requestJson("POST", "/auth/login", {
    body: {
      email,
      password: testPassword,
      clientType: "admin_web",
      clientInstanceId: `${runId}-${label}`,
      deviceLabel: `Integration ${label}`,
      platform: "admin_web",
      appVersion: "integration",
    },
  });

  assert.equal(response.status, 200);
  return (response.data as { accessToken: string }).accessToken;
}

async function requestJson(
  method: string,
  path: string,
  options?: {
    token?: string;
    body?: unknown;
  },
) {
  const headers: Record<string, string> = {};
  if (options?.token != null) {
    headers.Authorization = `Bearer ${options.token}`;
  }
  if (options?.body != null) {
    headers["Content-Type"] = "application/json";
  }

  const response = await fetch(`${apiBaseUrl}${path}`, {
    method,
    headers,
    body: options?.body == null ? undefined : JSON.stringify(options.body),
  });
  const rawBody = await response.text();
  return {
    status: response.status,
    data: rawBody.trim().length === 0 ? null : JSON.parse(rawBody),
  };
}

async function assertAuditExists(
  auditEventId: string | null,
  expectedAction: string,
) {
  if (typeof auditEventId !== "string") {
    assert.fail("auditEventId obrigatorio.");
  }
  const audit = await prisma.adminAuditLog.findUnique({
    where: { id: auditEventId },
  });
  assert.notEqual(audit, null);
  assert.equal(audit?.action, expectedAction);
  assert.equal(audit?.actorType, "USER");
}

async function assertSanitizedAudit(auditEventId: string | null) {
  if (typeof auditEventId !== "string") {
    assert.fail("auditEventId obrigatorio.");
  }
  const audit = await prisma.adminAuditLog.findUnique({
    where: { id: auditEventId },
  });
  assert.notEqual(audit, null);
  const serialized = JSON.stringify(audit?.details ?? {});
  assert.doesNotMatch(
    serialized,
    /Bearer forged-token|secret-token|senha-super-secreta|session-cookie|forged-jwt|raw-credential|webhook-secret/,
  );
  assert.doesNotMatch(
    serialized.toLowerCase(),
    /authorization"\s*:\s*"bearer|password"\s*:\s*"senha|secret"\s*:\s*"secret|token"\s*:\s*"secret|cookie"\s*:\s*"session|credential"\s*:\s*"raw|webhook"\s*:\s*"webhook/,
  );
}

async function assertSupportAuditSanitized(
  actorUserId: string,
  expectedAction: string,
) {
  const audit = await prisma.adminAuditLog.findFirst({
    where: {
      actorUserId,
      action: expectedAction,
    },
    orderBy: { createdAt: "desc" },
  });
  assert.notEqual(audit, null);
  await assertSanitizedAudit(audit?.id ?? null);
}

async function cleanupFixtures() {
  if (prisma == null) {
    return;
  }

  const users = await prisma.user.findMany({
    where: {
      email: {
        startsWith: `${runId}-`,
      },
    },
    select: { id: true },
  });
  const companies = await prisma.company.findMany({
    where: {
      slug: {
        startsWith: `${runId}-`,
      },
    },
    select: { id: true },
  });
  const userIds = users.map((user) => user.id);
  const companyIds = companies.map((company) => company.id);

  const adminAuditFilters = [
    ...(userIds.length === 0 ? [] : [{ actorUserId: { in: userIds } }]),
    ...(companyIds.length === 0
      ? []
      : [{ targetCompanyId: { in: companyIds } }]),
  ];
  const sessionAuditFilters = [
    ...(userIds.length === 0 ? [] : [{ actorUserId: { in: userIds } }]),
    ...(userIds.length === 0 ? [] : [{ subjectUserId: { in: userIds } }]),
    ...(companyIds.length === 0 ? [] : [{ companyId: { in: companyIds } }]),
  ];

  if (adminAuditFilters.length > 0) {
    await prisma.adminAuditLog.deleteMany({
      where: {
        OR: adminAuditFilters,
      },
    });
  }

  if (userIds.length > 0 || companyIds.length > 0) {
    await prisma.supportActionExecution.deleteMany({
      where: {
        OR: [
          ...(userIds.length === 0 ? [] : [{ actorUserId: { in: userIds } }]),
          ...(companyIds.length === 0
            ? []
            : [{ targetCompanyId: { in: companyIds } }]),
        ],
      },
    });
  }

  if (sessionAuditFilters.length > 0) {
    await prisma.sessionAuditLog.deleteMany({
      where: {
        OR: sessionAuditFilters,
      },
    });
  }

  if (companyIds.length > 0) {
    await prisma.company.deleteMany({
      where: { id: { in: companyIds } },
    });
  }
  if (userIds.length > 0) {
    await prisma.user.deleteMany({
      where: { id: { in: userIds } },
    });
  }
}
