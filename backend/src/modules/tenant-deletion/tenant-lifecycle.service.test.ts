import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { AppError } from "../../shared/http/app-error";
import { TenantLifecycleService } from "./tenant-lifecycle.service";

describe("tenant lifecycle operational guard", () => {
  it("permite tenant sem quarentena ativa", async () => {
    const service = new TenantLifecycleService({
      tenantDeletionRequest: {
        async findFirst() {
          return null;
        },
      },
    } as never);

    await service.assertTenantOperational("company-1");
  });

  it("bloqueia tenant em FUTURE_PENDING_DELETION com codigo claro", async () => {
    const service = new TenantLifecycleService({
      tenantDeletionRequest: {
        async findFirst() {
          return {
            id: "request-1",
            companyId: "company-1",
            status: "FUTURE_PENDING_DELETION",
            updatedAt: new Date("2026-06-10T12:00:00.000Z"),
          };
        },
      },
    } as never);

    await assert.rejects(
      service.assertTenantOperational("company-1"),
      (error: unknown) =>
        error instanceof AppError &&
        error.statusCode === 423 &&
        error.code === "TENANT_PENDING_DELETION",
    );
  });
});
