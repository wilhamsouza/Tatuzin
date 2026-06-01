import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { SupportActionRbacService } from "./support-actions.rbac";

describe("support actions persistent rbac service", () => {
  it("busca permissionKeys persistidas e ignora chaves desconhecidas", async () => {
    const service = new SupportActionRbacService({
      adminUserPermission: {
        async findMany() {
          return [
            {
              permissionKey: "support.session.revoke",
              scope: "platform",
              scopeId: "*",
              isActive: true,
            },
            {
              permissionKey: "support.unknown",
              scope: "platform",
              scopeId: "*",
              isActive: true,
            },
          ];
        },
      },
    });

    assert.deepEqual(await service.getAdminPermissionKeys("admin-1"), [
      "support.session.revoke",
    ]);
  });

  it("monta contexto de permissao sem fallback platform admin", async () => {
    const service = new SupportActionRbacService({
      adminUserPermission: {
        async findMany() {
          return [
            {
              permissionKey: "support.sync.force",
              scope: "platform",
              scopeId: "*",
              isActive: true,
            },
          ];
        },
      },
    });

    const context = await service.getSupportActionPermissionContext("admin-1");

    assert.equal(context.actorAdminId, "admin-1");
    assert.deepEqual(context.permissionKeys, ["support.sync.force"]);
    assert.equal(context.allowPlatformAdminFallback, false);
  });

  it("hasSupportActionPermission usa permissoes persistidas", async () => {
    const service = new SupportActionRbacService({
      adminUserPermission: {
        async findMany() {
          return [
            {
              permissionKey: "support.push.send",
              scope: "platform",
              scopeId: "*",
              isActive: true,
            },
          ];
        },
      },
    });

    assert.equal(
      await service.hasSupportActionPermission("admin-1", "support.push.send"),
      true,
    );
    assert.equal(
      await service.hasSupportActionPermission(
        "admin-1",
        "support.session.revoke",
      ),
      false,
    );
  });
});
