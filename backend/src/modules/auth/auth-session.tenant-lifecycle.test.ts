import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { AppError } from "../../shared/http/app-error";
import { AuthSessionService } from "./auth-session.service";

const baseInput = {
  userId: "user-1",
  userEmail: "user@tatuzin.test",
  userIsPlatformAdmin: false,
  companyId: "company-1",
  membershipId: "membership-1",
  membershipRole: "OWNER",
  licensePlan: "PRO",
  clientInput: {
    clientType: "mobile_app",
    clientInstanceId: "device-1",
  },
};

describe("auth session tenant lifecycle gate", () => {
  it("bloqueia login operacional antes de registrar dispositivo ou sessao", async () => {
    let deviceCalls = 0;
    const service = new AuthSessionService(
      {
        async registerOrResolve() {
          deviceCalls++;
          throw new Error("device should not be reached");
        },
      } as never,
      {
        async assertTenantOperational() {
          throw new AppError(
            "Tenant em quarentena.",
            423,
            "TENANT_PENDING_DELETION",
          );
        },
      } as never,
    );

    await assert.rejects(
      service.createSession(baseInput),
      (error: unknown) =>
        error instanceof AppError && error.code === "TENANT_PENDING_DELETION",
    );
    assert.equal(deviceCalls, 0);
  });

  it("preserva o caminho de suporte para platform admin no Admin Web", async () => {
    let lifecycleCalls = 0;
    let deviceCalls = 0;
    const service = new AuthSessionService(
      {
        async registerOrResolve() {
          deviceCalls++;
          throw new Error("support-path-reached");
        },
      } as never,
      {
        async assertTenantOperational() {
          lifecycleCalls++;
        },
      } as never,
    );

    await assert.rejects(
      service.createSession({
        ...baseInput,
        userIsPlatformAdmin: true,
        clientInput: {
          clientType: "admin_web",
          clientInstanceId: "admin-browser-1",
        },
      }),
      /support-path-reached/,
    );
    assert.equal(lifecycleCalls, 0);
    assert.equal(deviceCalls, 1);
  });
});
