import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  bootstrapAdminAuditActor,
  normalizeAdminAuditActor,
  userAdminAuditActor,
} from "./admin-audit-actor";

describe("admin audit actor helpers", () => {
  it("monta ator de usuario autenticado", () => {
    assert.deepEqual(userAdminAuditActor("admin-1"), {
      actorType: "USER",
      actorUserId: "admin-1",
      actorLabel: null,
    });
  });

  it("monta ator de bootstrap sem ancora tecnica de usuario", () => {
    assert.deepEqual(bootstrapAdminAuditActor(), {
      actorType: "BOOTSTRAP",
      actorUserId: null,
      actorLabel: "SYSTEM_BOOTSTRAP",
    });
  });

  it("interpreta log legado sem actorType como USER", () => {
    assert.deepEqual(
      normalizeAdminAuditActor({
        actorUserId: "legacy-admin",
      }),
      {
        actorType: "USER",
        actorUserId: "legacy-admin",
        actorLabel: null,
      },
    );
  });
});
