import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  assertSafeIntegrationTestDatabaseUrl,
  resolveIntegrationTestDatabaseConfig,
} from "./integration-prisma";

describe("integration Prisma safety guard", () => {
  it("pula sem opt-in explicito", () => {
    const config = resolveIntegrationTestDatabaseConfig({});

    assert.equal(config.enabled, false);
    if (!config.enabled) {
      assert.match(config.skipReason, /RUN_INTEGRATION_TESTS=true/);
    }
  });

  it("recusa usar DATABASE_URL como banco de integracao", () => {
    assert.throws(
      () =>
        resolveIntegrationTestDatabaseConfig({
          RUN_INTEGRATION_TESTS: "true",
          DATABASE_URL:
            "postgresql://postgres:postgres@localhost:5432/simples_erp_integration_test",
          INTEGRATION_TEST_DATABASE_URL:
            "postgresql://postgres:postgres@localhost:5432/simples_erp_integration_test",
        }),
      /must not be equal/,
    );
  });

  it("recusa URL sem marcador claro de teste", () => {
    assert.throws(
      () =>
        assertSafeIntegrationTestDatabaseUrl(
          "postgresql://postgres:postgres@localhost:5432/simples_erp_dev?schema=public",
        ),
      /must clearly identify/,
    );
  });

  it("recusa URL suspeita de producao", () => {
    assert.throws(
      () =>
        assertSafeIntegrationTestDatabaseUrl(
          "postgresql://postgres:postgres@prod-db.example.com:5432/simples_erp_integration_test",
        ),
      /suspicious/,
    );
  });

  it("aceita URL claramente isolada de integracao", () => {
    assert.doesNotThrow(() =>
      assertSafeIntegrationTestDatabaseUrl(
        "postgresql://postgres:postgres@localhost:5432/simples_erp_integration_test?schema=integration_test",
      ),
    );
  });
});
