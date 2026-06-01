import { spawnSync } from "node:child_process";

import { resolveIntegrationTestDatabaseConfig } from "../src/shared/testing/integration-prisma";

const config = resolveIntegrationTestDatabaseConfig();

if (!config.enabled) {
  console.error(config.skipReason);
  process.exit(1);
}

const result = spawnSync("npx", ["prisma", "migrate", "deploy"], {
  cwd: process.cwd(),
  env: {
    ...process.env,
    DATABASE_URL: config.databaseUrl,
  },
  shell: process.platform === "win32",
  stdio: "inherit",
});

if (result.error != null) {
  console.error(result.error);
  process.exit(1);
}

process.exit(result.status ?? 1);
