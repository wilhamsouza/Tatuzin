import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import type { Server } from "node:http";
import type { AddressInfo } from "node:net";

import express, {
  type NextFunction,
  type Request,
  type Response,
} from "express";

import { createTenantDeletionRouter } from "./tenant-deletion.routes";

const requestId = "11111111-1111-4111-8111-111111111111";
let server: Server;
let apiBaseUrl = "";
let quarantineInput: Record<string, unknown> | null = null;

describe("tenant deletion quarantine routes", () => {
  before(() => {
    const app = express();
    app.use(express.json());
    app.use((request, _response, next) => {
      request.auth = {
        userId: "admin-1",
        companyId: "platform-company",
        membershipId: "membership-1",
        membershipRole: "OWNER",
        email: "admin@tatuzin.test",
        isPlatformAdmin: true,
        accessToken: "test-token",
      };
      next();
    });
    app.use(
      "/admin/tenant-deletion",
      createTenantDeletionRouter({
        service: {
          async quarantineRequest(input: Record<string, unknown>) {
            quarantineInput = input;
            return {
              ok: true,
              code: "TENANT_DELETION_QUARANTINED",
              message: "Tenant colocado em quarentena.",
              auditEventId: "audit-1",
            };
          },
        } as never,
      }),
    );
    app.use(
      (
        _error: unknown,
        _request: Request,
        response: Response,
        _next: NextFunction,
      ) => {
        response.status(422).json({
          ok: false,
          code: "TENANT_DELETION_VALIDATION_ERROR",
        });
      },
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

  it("valida confirmacao e encaminha ator autenticado", async () => {
    const response = await requestJson({
      companyId: "company-1",
      reason: "Quarentena aprovada apos analise operacional",
      confirmation: "QUARENTENA",
    });

    assert.equal(response.status, 200);
    assert.equal(response.data.code, "TENANT_DELETION_QUARANTINED");
    assert.equal(quarantineInput?.requestId, requestId);
    assert.equal(quarantineInput?.actorAdminId, "admin-1");
    assert.equal(quarantineInput?.companyId, "company-1");
  });

  it("rejeita confirmacao diferente sem chamar o servico", async () => {
    quarantineInput = null;

    const response = await requestJson({
      companyId: "company-1",
      reason: "Quarentena aprovada apos analise operacional",
      confirmation: "CONFIRMO",
    });

    assert.equal(response.status, 422);
    assert.equal(quarantineInput, null);
  });
});

async function requestJson(body: unknown) {
  const response = await fetch(
    `${apiBaseUrl}/admin/tenant-deletion/requests/${requestId}/quarantine`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    },
  );
  return {
    status: response.status,
    data: await response.json(),
  };
}
