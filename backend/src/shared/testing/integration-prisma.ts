import { PrismaClient } from "@prisma/client";

export type IntegrationTestDatabaseConfig =
  | {
      enabled: true;
      databaseUrl: string;
    }
  | {
      enabled: false;
      skipReason: string;
    };

type IntegrationTestCleanupState = {
  companyIds: string[];
  userIds: string[];
  adminAuditLogIds: string[];
  adminUserPermissionIds: string[];
  supportActionExecutionIds: string[];
};

export type IntegrationPrismaContext = {
  prisma: PrismaClient;
  testRunId: string;
  trackCompany(id: string): void;
  trackUser(id: string): void;
  trackAdminAuditLog(id: string): void;
  trackAdminUserPermission(id: string): void;
  trackSupportActionExecution(id: string): void;
};

const suspiciousUrlFragments = [
  "prod",
  "production",
  "staging",
  "homolog",
  "render.com",
  "railway.app",
  "supabase.co",
  "neon.tech",
  "amazonaws.com",
  "oraclecloud.com",
  "tatuzin.com",
  "tatuzin.com.br",
];

const blockedDatabaseNames = [
  "postgres",
  "simples_erp",
  "simples_erp_dev",
  "tatuzin",
  "tatuzin_prod",
  "simples_erp_prod",
];

export function resolveIntegrationTestDatabaseConfig(
  env: NodeJS.ProcessEnv = process.env,
): IntegrationTestDatabaseConfig {
  if (env.RUN_INTEGRATION_TESTS?.trim().toLowerCase() !== "true") {
    return {
      enabled: false,
      skipReason:
        "Integration tests skipped: set RUN_INTEGRATION_TESTS=true and INTEGRATION_TEST_DATABASE_URL for an isolated test database.",
    };
  }

  const databaseUrl = env.INTEGRATION_TEST_DATABASE_URL?.trim();
  if (databaseUrl == null || databaseUrl.length === 0) {
    throw new Error(
      "RUN_INTEGRATION_TESTS=true requires INTEGRATION_TEST_DATABASE_URL. Refusing to use DATABASE_URL for integration tests.",
    );
  }

  if (env.DATABASE_URL != null && databaseUrl === env.DATABASE_URL.trim()) {
    throw new Error(
      "INTEGRATION_TEST_DATABASE_URL must not be equal to DATABASE_URL.",
    );
  }

  assertSafeIntegrationTestDatabaseUrl(databaseUrl);
  return { enabled: true, databaseUrl };
}

export function assertSafeIntegrationTestDatabaseUrl(databaseUrl: string) {
  let parsed: URL;
  try {
    parsed = new URL(databaseUrl);
  } catch {
    throw new Error("INTEGRATION_TEST_DATABASE_URL is not a valid URL.");
  }

  if (!["postgres:", "postgresql:"].includes(parsed.protocol)) {
    throw new Error(
      "INTEGRATION_TEST_DATABASE_URL must use postgres:// or postgresql://.",
    );
  }

  const normalized = decodeURIComponent(databaseUrl).toLowerCase();
  const databaseName = parsed.pathname.replace(/^\//, "").toLowerCase();
  const schemaName = parsed.searchParams.get("schema")?.toLowerCase() ?? "";
  const hasTestMarker = /(test|integration|isolated|ci)/i.test(
    `${databaseName} ${schemaName} ${parsed.hostname} ${parsed.username}`,
  );

  if (!hasTestMarker) {
    throw new Error(
      "INTEGRATION_TEST_DATABASE_URL must clearly identify an isolated test database or schema. Include test, integration, isolated or ci in the database name, schema, host or username.",
    );
  }

  if (blockedDatabaseNames.includes(databaseName)) {
    throw new Error(
      `Refusing to run integration tests against blocked database name: ${databaseName}.`,
    );
  }

  const suspiciousFragment = suspiciousUrlFragments.find((fragment) =>
    normalized.includes(fragment),
  );
  if (suspiciousFragment != null) {
    throw new Error(
      `Refusing suspicious integration database URL containing '${suspiciousFragment}'.`,
    );
  }
}

export async function withIsolatedIntegrationPrisma<T>(
  databaseUrl: string,
  fn: (context: IntegrationPrismaContext) => Promise<T>,
) {
  assertSafeIntegrationTestDatabaseUrl(databaseUrl);
  const prisma = new PrismaClient({
    datasources: {
      db: {
        url: databaseUrl,
      },
    },
  });
  const cleanup: IntegrationTestCleanupState = {
    companyIds: [],
    userIds: [],
    adminAuditLogIds: [],
    adminUserPermissionIds: [],
    supportActionExecutionIds: [],
  };
  const testRunId = `it-${Date.now()}-${Math.random()
    .toString(36)
    .slice(2, 10)}`;

  try {
    return await fn({
      prisma,
      testRunId,
      trackCompany(id) {
        cleanup.companyIds.push(id);
      },
      trackUser(id) {
        cleanup.userIds.push(id);
      },
      trackAdminAuditLog(id) {
        cleanup.adminAuditLogIds.push(id);
      },
      trackAdminUserPermission(id) {
        cleanup.adminUserPermissionIds.push(id);
      },
      trackSupportActionExecution(id) {
        cleanup.supportActionExecutionIds.push(id);
      },
    });
  } finally {
    await cleanupIntegrationRows(prisma, cleanup);
    await prisma.$disconnect();
  }
}

async function cleanupIntegrationRows(
  prisma: PrismaClient,
  cleanup: IntegrationTestCleanupState,
) {
  if (cleanup.supportActionExecutionIds.length > 0) {
    await prisma.supportActionExecution.deleteMany({
      where: { id: { in: cleanup.supportActionExecutionIds } },
    });
  }

  if (cleanup.adminAuditLogIds.length > 0) {
    await prisma.adminAuditLog.deleteMany({
      where: { id: { in: cleanup.adminAuditLogIds } },
    });
  }

  if (cleanup.adminUserPermissionIds.length > 0) {
    await prisma.adminUserPermission.deleteMany({
      where: { id: { in: cleanup.adminUserPermissionIds } },
    });
  }

  if (cleanup.companyIds.length > 0) {
    await prisma.company.deleteMany({
      where: { id: { in: cleanup.companyIds } },
    });
  }

  if (cleanup.userIds.length > 0) {
    await prisma.user.deleteMany({
      where: { id: { in: cleanup.userIds } },
    });
  }
}
