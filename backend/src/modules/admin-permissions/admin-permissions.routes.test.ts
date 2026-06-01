import assert from "node:assert/strict";
import { after, before, beforeEach, describe, it } from "node:test";
import type { AddressInfo } from "node:net";
import type { Server } from "node:http";

import express from "express";

import { AdminPermissionsService } from "./admin-permissions.service";
import { createAdminPermissionsRouter } from "./admin-permissions.routes";

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

let server: Server;
let apiBaseUrl = "";
let fakeAuth: { userId: string; isPlatformAdmin: boolean } | null = {
  userId: "manager",
  isPlatformAdmin: true,
};
let client = createClient();

describe("admin permissions routes", () => {
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
      "/admin/permissions",
      createAdminPermissionsRouter({
        service: new AdminPermissionsService(client),
      }),
    );

    server = app.listen(0);
    const address = server.address() as AddressInfo;
    apiBaseUrl = `http://127.0.0.1:${address.port}`;
  });

  beforeEach(() => {
    fakeAuth = { userId: "manager", isPlatformAdmin: true };
    client.reset([permission("manager", "admin-permissions.manage")]);
  });

  after(async () => {
    await new Promise<void>((resolve, reject) => {
      server.close((error) => (error == null ? resolve() : reject(error)));
    });
  });

  it("exige ator autenticado", async () => {
    fakeAuth = null;

    const response = await requestJson("GET", "/admin/permissions/catalog");

    assert.equal(response.status, 401);
    assert.equal(response.data.code, "ADMIN_PERMISSION_ACTOR_REQUIRED");
  });

  it("lista catalogo read-only com permissoes de support-actions", async () => {
    const response = await requestJson("GET", "/admin/permissions/catalog");

    assert.equal(response.status, 200);
    assert.equal(response.data.ok, true);
    assert.ok(
      response.data.catalog.some(
        (permission: { permissionKey?: string; actionType?: string }) =>
          permission.permissionKey === "support.session.revoke" &&
          permission.actionType === "revoke_session",
      ),
    );
    assert.ok(
      response.data.catalog.some(
        (permission: { permissionKey?: string }) =>
          permission.permissionKey === "admin-permissions.manage",
      ),
    );
  });

  it("lista permissoes persistidas de um admin", async () => {
    client.rows.push(permission("target-admin", "support.session.revoke"));

    const response = await requestJson(
      "GET",
      "/admin/permissions/users/target-admin",
    );

    assert.equal(response.status, 200);
    assert.equal(response.data.permissions.length, 1);
    assert.equal(response.data.permissions[0].permissionKey, "support.session.revoke");
    assert.equal(client.audits[0]?.data.action, "admin.permission.list");
  });

  it("concede permissao com payload valido e audita", async () => {
    const response = await requestJson(
      "POST",
      "/admin/permissions/users/target-admin/grant",
      {
        permissionKey: "support.session.revoke",
        reason: "Concessao aprovada em chamado",
      },
    );

    assert.equal(response.status, 200);
    assert.equal(response.data.code, "ADMIN_PERMISSION_GRANTED");
    assert.equal(response.data.permission.permissionKey, "support.session.revoke");
    assert.equal(client.audits[0]?.data.action, "admin.permission.grant");
  });

  it("trata concessao duplicada de forma idempotente", async () => {
    client.rows.push(permission("target-admin", "support.session.revoke"));

    const response = await requestJson(
      "POST",
      "/admin/permissions/users/target-admin/grant",
      {
        permissionKey: "support.session.revoke",
        reason: "Concessao repetida em chamado",
      },
    );

    assert.equal(response.status, 200);
    assert.equal(response.data.code, "ADMIN_PERMISSION_GRANTED");
    assert.equal(
      client.rows.filter(
        (row) =>
          row.actorUserId === "target-admin" &&
          row.permissionKey === "support.session.revoke",
      ).length,
      1,
    );
  });

  it("revoga permissao com soft revoke e audita", async () => {
    client.rows.push(permission("target-admin", "support.session.revoke"));

    const response = await requestJson(
      "POST",
      "/admin/permissions/users/target-admin/revoke",
      {
        permissionKey: "support.session.revoke",
        reason: "Revogacao aprovada em revisao",
      },
    );

    assert.equal(response.status, 200);
    assert.equal(response.data.code, "ADMIN_PERMISSION_REVOKED");
    assert.equal(response.data.details.revokedCount, 1);
    assert.equal(
      client.rows.find((row) => row.actorUserId === "target-admin")?.isActive,
      false,
    );
    assert.equal(client.audits[0]?.data.action, "admin.permission.revoke");
  });

  it("trata revogacao inexistente de forma segura", async () => {
    const response = await requestJson(
      "POST",
      "/admin/permissions/users/target-admin/revoke",
      {
        permissionKey: "support.session.revoke",
        reason: "Revogacao aprovada em revisao",
      },
    );

    assert.equal(response.status, 200);
    assert.equal(response.data.code, "ADMIN_PERMISSION_REVOKED");
    assert.equal(response.data.details.revokedCount, 0);
  });

  it("rejeita motivo obrigatorio e audita payload invalido", async () => {
    const response = await requestJson(
      "POST",
      "/admin/permissions/users/target-admin/grant",
      {
        permissionKey: "support.session.revoke",
        reason: "curto",
        token: "secret-token",
      },
    );

    assert.equal(response.status, 422);
    assert.equal(response.data.code, "ADMIN_PERMISSION_VALIDATION_ERROR");
    assert.equal(client.audits[0]?.data.action, "admin.permission.grant.denied");
    const serialized = JSON.stringify(client.audits[0]?.data.details);
    assert.match(serialized, /\[redacted\]/);
    assert.doesNotMatch(serialized, /secret-token/);
  });

  it("rejeita permissionKey desconhecida e audita", async () => {
    const response = await requestJson(
      "POST",
      "/admin/permissions/users/target-admin/grant",
      {
        permissionKey: "support.unknown",
        reason: "Concessao aprovada em chamado",
      },
    );

    assert.equal(response.status, 422);
    assert.equal(response.data.code, "ADMIN_PERMISSION_UNSUPPORTED");
    assert.equal(client.audits[0]?.data.action, "admin.permission.grant.denied");
  });

  it("nega grant quando ator nao possui admin-permissions.manage", async () => {
    client.reset([permission("manager", "support.session.revoke")]);

    const response = await requestJson(
      "POST",
      "/admin/permissions/users/target-admin/grant",
      {
        permissionKey: "support.session.revoke",
        reason: "Concessao aprovada em chamado",
      },
    );

    assert.equal(response.status, 403);
    assert.equal(response.data.code, "ADMIN_PERMISSION_MANAGE_REQUIRED");
    assert.equal(client.audits[0]?.data.action, "admin.permission.grant.denied");
  });
});

async function requestJson(method: string, path: string, body?: unknown) {
  const response = await fetch(`${apiBaseUrl}${path}`, {
    method,
    headers:
      body == null ? undefined : { "content-type": "application/json" },
    body: body == null ? undefined : JSON.stringify(body),
  });

  return {
    status: response.status,
    data: await response.json(),
  };
}

function createClient(seed: PermissionRow[] = []) {
  let rows = [...seed];
  const audits: AuditRow[] = [];

  return {
    get rows() {
      return rows;
    },
    audits,
    reset(nextSeed: PermissionRow[] = []) {
      rows = [...nextSeed];
      audits.length = 0;
    },
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
