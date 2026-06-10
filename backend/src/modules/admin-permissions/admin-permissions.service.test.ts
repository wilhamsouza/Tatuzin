import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { AdminPermissionsService } from "./admin-permissions.service";

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
    actorType: "USER";
    actorUserId: string;
    actorLabel?: string | null;
    targetCompanyId?: string | null;
    action: string;
    details?: unknown;
  };
};

describe("admin permissions service", () => {
  it("lista permissoes administrativas conhecidas", () => {
    const service = new AdminPermissionsService(createClient());

    const result = service.listKnownPermissions();

    assert.equal(result.ok, true);
    assert.equal(result.code, "ADMIN_PERMISSION_LISTED");
    assert.ok(
      result.knownPermissions?.some(
        (permission) => permission.permissionKey === "admin-permissions.manage",
      ),
    );
    assert.ok(
      result.knownPermissions?.some(
        (permission) => permission.permissionKey === "support.session.revoke",
      ),
    );
  });

  it("lista apenas as permissoes proprias sem exigir manage", async () => {
    const client = createClient([
      permission("operator", "tenant.deletion.quarantine"),
      permission("other-admin", "admin-permissions.manage"),
    ]);
    const service = new AdminPermissionsService(client);

    const result = await service.listOwnPermissions({
      actorAdminId: "operator",
    });

    assert.equal(result.ok, true);
    assert.deepEqual(
      result.permissions?.map((item) => item.permissionKey),
      ["tenant.deletion.quarantine"],
    );
    assert.equal(client.audits[0]?.data.action, "admin.permission.list_self");
  });

  it("concede permissao quando ator possui admin-permissions.manage", async () => {
    const client = createClient([
      permission("manager", "admin-permissions.manage"),
    ]);
    const service = new AdminPermissionsService(client);

    const result = await service.grantPermission({
      actorAdminId: "manager",
      targetAdminId: "target-admin",
      permissionKey: "support.session.revoke",
      reason: "Concessao aprovada em chamado",
    });

    assert.equal(result.ok, true);
    assert.equal(result.code, "ADMIN_PERMISSION_GRANTED");
    assert.equal(result.permission?.actorUserId, "target-admin");
    assert.equal(result.permission?.permissionKey, "support.session.revoke");
    assert.equal(client.audits[0]?.data.actorType, "USER");
    assert.equal(client.audits[0]?.data.actorUserId, "manager");
    assert.equal(client.audits[0]?.data.actorLabel, null);
    assert.equal(client.audits[0]?.data.action, "admin.permission.grant");
  });

  it("nega concessao sem permissao de gestao", async () => {
    const client = createClient([
      permission("manager", "support.session.revoke"),
    ]);
    const service = new AdminPermissionsService(client);

    const result = await service.grantPermission({
      actorAdminId: "manager",
      targetAdminId: "target-admin",
      permissionKey: "support.session.revoke",
      reason: "Concessao aprovada em chamado",
    });

    assert.equal(result.ok, false);
    assert.equal(result.code, "ADMIN_PERMISSION_MANAGE_REQUIRED");
    assert.equal(
      client.rows.some((row) => row.actorUserId === "target-admin"),
      false,
    );
    assert.equal(
      client.audits[0]?.data.action,
      "admin.permission.grant.denied",
    );
  });

  it("bloqueia autoelevacao critica por padrao", async () => {
    const client = createClient([
      permission("manager", "admin-permissions.manage"),
    ]);
    const service = new AdminPermissionsService(client);

    const result = await service.grantPermission({
      actorAdminId: "manager",
      targetAdminId: "manager",
      permissionKey: "support.license.update",
      reason: "Tentativa de ajuste proprio",
    });

    assert.equal(result.ok, false);
    assert.equal(result.code, "ADMIN_PERMISSION_SELF_GRANT_BLOCKED");
    assert.equal(
      client.rows.some(
        (row) =>
          row.actorUserId === "manager" &&
          row.permissionKey === "support.license.update",
      ),
      false,
    );
    assert.equal(
      client.audits[0]?.data.action,
      "admin.permission.grant.denied",
    );
  });

  it("revoga permissao quando ator possui admin-permissions.manage", async () => {
    const client = createClient([
      permission("manager", "admin-permissions.manage"),
      permission("target-admin", "support.session.revoke"),
    ]);
    const service = new AdminPermissionsService(client);

    const result = await service.revokePermission({
      actorAdminId: "manager",
      targetAdminId: "target-admin",
      permissionKey: "support.session.revoke",
      reason: "Revogacao aprovada em revisao",
    });

    assert.equal(result.ok, true);
    assert.equal(result.code, "ADMIN_PERMISSION_REVOKED");
    assert.equal(
      client.rows.find(
        (row) =>
          row.actorUserId === "target-admin" &&
          row.permissionKey === "support.session.revoke",
      )?.isActive,
      false,
    );
    assert.equal(client.audits[0]?.data.actorType, "USER");
    assert.equal(client.audits[0]?.data.actorUserId, "manager");
    assert.equal(client.audits[0]?.data.action, "admin.permission.revoke");
  });

  it("nega revogacao sem permissao de gestao", async () => {
    const client = createClient([
      permission("target-admin", "support.session.revoke"),
    ]);
    const service = new AdminPermissionsService(client);

    const result = await service.revokePermission({
      actorAdminId: "manager",
      targetAdminId: "target-admin",
      permissionKey: "support.session.revoke",
      reason: "Revogacao aprovada em revisao",
    });

    assert.equal(result.ok, false);
    assert.equal(result.code, "ADMIN_PERMISSION_MANAGE_REQUIRED");
    assert.equal(
      client.rows.find(
        (row) =>
          row.actorUserId === "target-admin" &&
          row.permissionKey === "support.session.revoke",
      )?.isActive,
      true,
    );
    assert.equal(
      client.audits[0]?.data.action,
      "admin.permission.revoke.denied",
    );
  });

  it("lista permissoes persistidas de um admin e audita listagem sensivel", async () => {
    const client = createClient([
      permission("manager", "admin-permissions.manage"),
      permission("target-admin", "support.session.revoke"),
      permission("target-admin", "support.sync.force"),
    ]);
    const service = new AdminPermissionsService(client);

    const result = await service.listAdminPermissions({
      actorAdminId: "manager",
      targetAdminId: "target-admin",
    });

    assert.equal(result.ok, true);
    assert.equal(result.code, "ADMIN_PERMISSION_LISTED");
    assert.equal(result.permissions?.length, 2);
    assert.equal(client.audits[0]?.data.action, "admin.permission.list");
  });

  it("auditoria de grant/revoke nao grava secrets", async () => {
    const client = createClient([
      permission("manager", "admin-permissions.manage"),
      permission("target-admin", "support.session.revoke"),
    ]);
    const service = new AdminPermissionsService(client);

    await service.grantPermission({
      actorAdminId: "manager",
      targetAdminId: "target-admin",
      permissionKey: "support.sync.force",
      reason: "Concessao com token secreto Bearer eyJabc.def.ghi",
    });
    await service.revokePermission({
      actorAdminId: "manager",
      targetAdminId: "target-admin",
      permissionKey: "support.session.revoke",
      reason: "Revogacao com secret-token interno",
    });

    const serialized = JSON.stringify(client.audits);
    assert.match(serialized, /\[redacted\]/);
    assert.doesNotMatch(serialized, /Bearer eyJabc|secret-token/);
  });
});

function createClient(seed: PermissionRow[] = []) {
  const rows = [...seed];
  const audits: AuditRow[] = [];

  return {
    rows,
    audits,
    adminUserPermission: {
      async findMany(input: {
        where: Partial<{ actorUserId: string; isActive: boolean }>;
      }) {
        return rows.filter((row) => {
          if (
            input.where.actorUserId != null &&
            row.actorUserId !== input.where.actorUserId
          ) {
            return false;
          }
          if (
            input.where.isActive != null &&
            row.isActive !== input.where.isActive
          ) {
            return false;
          }
          return true;
        });
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
        const existing = rows.find(
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
        rows.push(created);
        return created;
      },
      async updateMany(input: {
        where: {
          actorUserId: string;
          permissionKey: string;
          scope: string;
          scopeId: string;
          isActive: boolean;
        };
        data: { isActive: boolean };
      }) {
        let count = 0;
        for (const row of rows) {
          if (
            row.actorUserId === input.where.actorUserId &&
            row.permissionKey === input.where.permissionKey &&
            row.scope === input.where.scope &&
            row.scopeId === input.where.scopeId &&
            row.isActive === input.where.isActive
          ) {
            row.isActive = input.data.isActive;
            row.updatedAt = new Date();
            count++;
          }
        }
        return { count };
      },
    },
    adminAuditLog: {
      async create(input: {
        data: {
          actorType: "USER";
          actorUserId: string;
          actorLabel?: string | null;
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
