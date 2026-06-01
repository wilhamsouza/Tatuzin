import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  AdminPermissionBootstrapService,
  adminPermissionBootstrapEnvKey,
} from "./admin-permissions.bootstrap";

type UserRow = {
  id: string;
  email: string;
  name: string;
  isActive: boolean;
  isPlatformAdmin: boolean;
};

type PermissionRow = {
  id: string;
  actorUserId: string;
  permissionKey: string;
  scope: string;
  scopeId: string;
  isActive: boolean;
  createdAt: Date;
  updatedAt: Date;
};

type AuditRow = {
  data: {
    actorType: "BOOTSTRAP";
    actorUserId: string | null;
    actorLabel: string;
    targetCompanyId?: string | null;
    action: string;
    details?: unknown;
  };
};

describe("admin permissions bootstrap service", () => {
  it("concede admin-permissions.manage quando env esta habilitada e ainda nao existe manager", async () => {
    const client = createClient({ users: [adminUser("admin-1")] });
    const service = new AdminPermissionBootstrapService(client);

    const result = await service.bootstrapManagePermission({
      targetAdminId: "admin-1",
      reason: "Bootstrap inicial aprovado",
      env: enabledEnv(),
    });

    assert.equal(result.ok, true);
    assert.equal(result.code, "ADMIN_PERMISSION_BOOTSTRAP_GRANTED");
    assert.equal(result.permission?.actorUserId, "admin-1");
    assert.equal(result.permission?.permissionKey, "admin-permissions.manage");
    assert.equal(client.audits[0]?.data.actorType, "BOOTSTRAP");
    assert.equal(client.audits[0]?.data.actorUserId, null);
    assert.equal(client.audits[0]?.data.actorLabel, "SYSTEM_BOOTSTRAP");
    assert.deepEqual(
      client.audits.map((audit) => audit.data.action),
      [
        "admin_permissions.bootstrap.attempted",
        "admin_permissions.bootstrap.granted",
      ],
    );
  });

  it("nega bootstrap quando env esta desabilitada", async () => {
    const client = createClient({ users: [adminUser("admin-1")] });
    const service = new AdminPermissionBootstrapService(client);

    const result = await service.bootstrapManagePermission({
      targetAdminId: "admin-1",
      reason: "Bootstrap inicial aprovado",
      env: {},
    });

    assert.equal(result.ok, false);
    assert.equal(result.code, "ADMIN_PERMISSION_BOOTSTRAP_DISABLED");
    assert.equal(client.permissions.length, 0);
    assert.equal(
      client.audits.at(-1)?.data.action,
      "admin_permissions.bootstrap.denied",
    );
  });

  it("nega bootstrap sem motivo obrigatorio", async () => {
    const client = createClient({ users: [adminUser("admin-1")] });
    const service = new AdminPermissionBootstrapService(client);

    const result = await service.bootstrapManagePermission({
      targetEmail: "admin@example.com",
      reason: "curto",
      env: enabledEnv(),
    });

    assert.equal(result.ok, false);
    assert.equal(result.code, "ADMIN_PERMISSION_BOOTSTRAP_REASON_REQUIRED");
    assert.equal(client.permissions.length, 0);
  });

  it("nega bootstrap para permissao fora da allowlist", async () => {
    const client = createClient({ users: [adminUser("admin-1")] });
    const service = new AdminPermissionBootstrapService(client);

    const result = await service.bootstrapManagePermission({
      targetAdminId: "admin-1",
      permissionKey: "support.session.revoke",
      reason: "Bootstrap inicial aprovado",
      env: enabledEnv(),
    });

    assert.equal(result.ok, false);
    assert.equal(result.code, "ADMIN_PERMISSION_BOOTSTRAP_PERMISSION_UNSUPPORTED");
    assert.equal(client.permissions.length, 0);
  });

  it("nega bootstrap quando ja existe admin-permissions.manage ativo", async () => {
    const client = createClient({
      users: [adminUser("admin-1"), adminUser("admin-2", "other@example.com")],
      permissions: [permission("admin-2", "admin-permissions.manage")],
    });
    const service = new AdminPermissionBootstrapService(client);

    const result = await service.bootstrapManagePermission({
      targetAdminId: "admin-1",
      reason: "Bootstrap inicial aprovado",
      env: enabledEnv(),
    });

    assert.equal(result.ok, false);
    assert.equal(result.code, "ADMIN_PERMISSION_BOOTSTRAP_ALREADY_CONFIGURED");
    assert.equal(
      client.permissions.some(
        (row) =>
          row.actorUserId === "admin-1" &&
          row.permissionKey === "admin-permissions.manage",
      ),
      false,
    );
  });

  it("nega bootstrap quando alvo nao existe", async () => {
    const client = createClient({ users: [] });
    const service = new AdminPermissionBootstrapService(client);

    const result = await service.bootstrapManagePermission({
      targetAdminId: "missing-admin",
      reason: "Bootstrap inicial aprovado",
      env: enabledEnv(),
    });

    assert.equal(result.ok, false);
    assert.equal(result.code, "ADMIN_PERMISSION_BOOTSTRAP_TARGET_NOT_FOUND");
    assert.equal(result.auditEventIds.length, 2);
    assert.equal(client.audits.length, 2);
    assert.equal(client.audits[0]?.data.actorType, "BOOTSTRAP");
    assert.equal(client.audits[0]?.data.actorUserId, null);
    assert.equal(client.audits.at(-1)?.data.action, "admin_permissions.bootstrap.denied");
  });

  it("registra auditoria segura de sucesso", async () => {
    const client = createClient({ users: [adminUser("admin-1")] });
    const service = new AdminPermissionBootstrapService(client);

    const result = await service.bootstrapManagePermission({
      targetAdminId: "admin-1",
      reason: "Bootstrap inicial aprovado",
      env: enabledEnv(),
    });

    assert.equal(result.ok, true);
    assert.equal(result.auditEventIds.length, 2);
    const details = client.audits[1]?.data.details as Record<string, unknown>;
    assert.equal(client.audits[1]?.data.actorType, "BOOTSTRAP");
    assert.equal(client.audits[1]?.data.actorUserId, null);
    assert.equal(client.audits[1]?.data.actorLabel, "SYSTEM_BOOTSTRAP");
    assert.equal(details.systemActor, "SYSTEM_BOOTSTRAP");
    assert.equal(details.permissionKey, "admin-permissions.manage");
  });

  it("registra auditoria segura de negacao", async () => {
    const client = createClient({ users: [adminUser("admin-1")] });
    const service = new AdminPermissionBootstrapService(client);

    const result = await service.bootstrapManagePermission({
      targetAdminId: "admin-1",
      reason: "Bootstrap inicial aprovado",
      env: {},
    });

    assert.equal(result.ok, false);
    assert.equal(result.auditEventIds.length, 2);
    const details = client.audits[1]?.data.details as Record<string, unknown>;
    assert.equal(details.systemActor, "SYSTEM_BOOTSTRAP");
    assert.equal(
      (details.result as Record<string, unknown>).code,
      "ADMIN_PERMISSION_BOOTSTRAP_DISABLED",
    );
  });

  it("sanitiza payload de auditoria", async () => {
    const client = createClient({ users: [adminUser("admin-1")] });
    const service = new AdminPermissionBootstrapService(client);

    await service.bootstrapManagePermission({
      targetAdminId: "admin-1",
      reason: "Bootstrap com token Bearer eyJabc.def.ghi",
      env: enabledEnv(),
    });

    const serialized = JSON.stringify(client.audits);
    assert.match(serialized, /\[redacted\]/);
    assert.doesNotMatch(serialized, /Bearer eyJabc|eyJabc\.def\.ghi/);
  });
});

function enabledEnv() {
  return { [adminPermissionBootstrapEnvKey]: "true" };
}

function createClient(seed: {
  users?: UserRow[];
  permissions?: PermissionRow[];
} = {}) {
  const users = [...(seed.users ?? [])];
  const permissions = [...(seed.permissions ?? [])];
  const audits: AuditRow[] = [];

  return {
    users,
    permissions,
    audits,
    user: {
      async findFirst(input: {
        where: {
          OR: Array<{ id: string } | { email: string }>;
        };
      }) {
        return (
          users.find((user) =>
            input.where.OR.some((condition) => {
              if ("id" in condition) {
                return condition.id === user.id;
              }
              return condition.email === user.email;
            }),
          ) ?? null
        );
      },
    },
    adminUserPermission: {
      async findMany(input: {
        where: { permissionKey: string; isActive: boolean };
      }) {
        return permissions.filter(
          (row) =>
            row.permissionKey === input.where.permissionKey &&
            row.isActive === input.where.isActive,
        );
      },
      async upsert(input: {
        where: {
          actorUserId_permissionKey_scope_scopeId: {
            actorUserId: string;
            permissionKey: string;
            scope: string;
            scopeId: string;
          };
        };
        create: {
          actorUserId: string;
          permissionKey: string;
          scope: string;
          scopeId: string;
          isActive: boolean;
        };
        update: { isActive: boolean };
      }) {
        const where = input.where.actorUserId_permissionKey_scope_scopeId;
        const existing = permissions.find(
          (row) =>
            row.actorUserId === where.actorUserId &&
            row.permissionKey === where.permissionKey &&
            row.scope === where.scope &&
            row.scopeId === where.scopeId,
        );
        if (existing != null) {
          existing.isActive = input.update.isActive;
          existing.updatedAt = new Date();
          return existing;
        }

        const created = permission(
          input.create.actorUserId,
          input.create.permissionKey,
          input.create.scope,
          input.create.scopeId,
          input.create.isActive,
        );
        permissions.push(created);
        return created;
      },
    },
    adminAuditLog: {
      async create(input: {
        data: {
          actorType: "BOOTSTRAP";
          actorUserId: string | null;
          actorLabel: string;
          targetCompanyId?: string | null;
          action: string;
          details?: unknown;
        };
        select: { id: true };
      }) {
        audits.push({ data: input.data });
        return { id: `audit-${audits.length}` };
      },
    },
  };
}

function adminUser(
  id: string,
  email = "admin@example.com",
  isPlatformAdmin = true,
  isActive = true,
): UserRow {
  return {
    id,
    email,
    name: "Admin User",
    isActive,
    isPlatformAdmin,
  };
}

function permission(
  actorUserId: string,
  permissionKey: string,
  scope = "platform",
  scopeId = "*",
  isActive = true,
): PermissionRow {
  return {
    id: `${actorUserId}-${permissionKey}-${scope}-${scopeId}`,
    actorUserId,
    permissionKey,
    scope,
    scopeId,
    isActive,
    createdAt: new Date("2026-05-31T18:00:00.000Z"),
    updatedAt: new Date("2026-05-31T18:00:00.000Z"),
  };
}
