import assert from "node:assert/strict";
import type { Server } from "node:http";
import type { AddressInfo } from "node:net";
import { after, before, describe, it } from "node:test";

import express, {
  type NextFunction,
  type Request,
  type Response,
} from "express";

import { createPublicTenantDeletionRouter } from "./tenant-deletion-public.routes";

let server: Server;
let apiBaseUrl = "";
let receivedInput: Record<string, unknown> | null = null;

describe("public tenant deletion acknowledgement route", () => {
  before(() => {
    const app = express();
    app.use(express.json());
    app.use(
      "/tenant-deletion",
      createPublicTenantDeletionRouter({
        rateLimit: (_request, _response, next) => next(),
        acknowledgementService: {
          async acknowledge(input: Record<string, unknown>) {
            receivedInput = input;
            return {
              ok: true,
              acknowledged: true,
              idempotent: false,
              acknowledgementId: "ack-1",
              acknowledgedAt: "2026-06-12T12:00:00.000Z",
              createdAt: "2026-06-12T12:00:00.000Z",
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
        response.status(422).json({ ok: false, code: "VALIDATION_ERROR" });
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

  it("aceita payload minimo sem autenticacao operacional", async () => {
    const response = await fetch(
      `${apiBaseUrl}/tenant-deletion/acknowledge-pending-deletion`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          acknowledgementToken: "x".repeat(64),
          companyId: "11111111-1111-4111-8111-111111111111",
          clientInstanceId: "device-instance-1",
          platform: "android",
          appVersion: "1.0.0",
        }),
      },
    );

    assert.equal(response.status, 200);
    assert.equal(receivedInput?.platform, "android");
    const serialized = JSON.stringify(await response.json());
    assert.equal(serialized.includes("access_token"), false);
    assert.equal(serialized.includes("refresh_token"), false);
  });

  it("rejeita payload excessivo antes do servico", async () => {
    receivedInput = null;
    const response = await fetch(
      `${apiBaseUrl}/tenant-deletion/acknowledge-pending-deletion`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          acknowledgementToken: "x".repeat(64),
          companyId: "not-a-uuid",
          clientInstanceId: "short",
          deviceLabel: "x".repeat(500),
        }),
      },
    );

    assert.equal(response.status, 422);
    assert.equal(receivedInput, null);
  });
});
