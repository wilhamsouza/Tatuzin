import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { Prisma } from "@prisma/client";

import { normalizeAdminAuditActor } from "../admin/admin-audit-actor";
import { SupportActionRbacService } from "../support-actions/support-actions.rbac";
import {
  buildOperationalActionDryRun,
  sanitizeOperationalActionPayload,
} from "../support-actions/support-actions.service";
import {
  resolveIntegrationTestDatabaseConfig,
  withIsolatedIntegrationPrisma,
} from "../../shared/testing/integration-prisma";
import { AdminPermissionBootstrapService } from "./admin-permissions.bootstrap";
import { AdminPermissionsService } from "./admin-permissions.service";

const integrationConfig = resolveIntegrationTestDatabaseConfig();
const skipReason =
  integrationConfig.enabled ? false : integrationConfig.skipReason;

describe("admin permissions Prisma integration", { skip: skipReason }, () => {
  it("persiste AdminAuditLog BOOTSTRAP, USER e default legado USER com payload sanitizado", async () => {
    await withIntegration(async ({ prisma, testRunId, trackUser, trackAdminAuditLog }) => {
      const admin = await createAdminUser(prisma, testRunId, "audit-user");
      trackUser(admin.id);

      const bootstrapLog = await prisma.adminAuditLog.create({
        data: {
          actorType: "BOOTSTRAP",
          actorUserId: null,
          actorLabel: "SYSTEM_BOOTSTRAP",
          action: "admin_permissions.bootstrap.granted",
          details: sanitizeOperationalActionPayload({
            reason: "Bootstrap com token Bearer eyJabc.def.ghi",
            token: "secret-token",
            password: "senha-super-secreta",
          }) as Prisma.InputJsonValue,
        },
      });
      trackAdminAuditLog(bootstrapLog.id);

      assert.equal(bootstrapLog.actorType, "BOOTSTRAP");
      assert.equal(bootstrapLog.actorUserId, null);
      assert.equal(bootstrapLog.actorLabel, "SYSTEM_BOOTSTRAP");

      const userLog = await prisma.adminAuditLog.create({
        data: {
          actorType: "USER",
          actorUserId: admin.id,
          actorLabel: null,
          action: "admin_permissions.grant",
          details: sanitizeOperationalActionPayload({
            reason: "Concessao aprovada em chamado",
            authorization: "Bearer eyJabc.def.ghi",
          }) as Prisma.InputJsonValue,
        },
      });
      trackAdminAuditLog(userLog.id);

      assert.equal(userLog.actorType, "USER");
      assert.equal(userLog.actorUserId, admin.id);
      assert.equal(userLog.actorLabel, null);

      const legacyDefaultLog = await prisma.adminAuditLog.create({
        data: {
          actorUserId: admin.id,
          action: "legacy.admin.audit",
          details: { source: "legacy-default" },
        },
      });
      trackAdminAuditLog(legacyDefaultLog.id);

      assert.equal(legacyDefaultLog.actorType, "USER");
      assert.deepEqual(
        normalizeAdminAuditActor({
          actorUserId: legacyDefaultLog.actorUserId,
        }),
        {
          actorType: "USER",
          actorUserId: admin.id,
          actorLabel: null,
        },
      );

      const reloaded = await prisma.adminAuditLog.findMany({
        where: { id: { in: [bootstrapLog.id, userLog.id] } },
      });
      const serialized = JSON.stringify(reloaded);
      assert.match(serialized, /\[redacted\]/);
      assert.doesNotMatch(
        serialized,
        /Bearer eyJabc|secret-token|senha-super-secreta/,
      );
    });
  });

  it("persiste, lista, revoga e bloqueia duplicidade de AdminUserPermission", async () => {
    await withIntegration(async ({
      prisma,
      testRunId,
      trackUser,
      trackAdminAuditLog,
      trackAdminUserPermission,
    }) => {
      const manager = await createAdminUser(prisma, testRunId, "manager");
      const target = await createAdminUser(prisma, testRunId, "target");
      trackUser(manager.id);
      trackUser(target.id);

      const managePermission = await prisma.adminUserPermission.create({
        data: {
          actorUserId: manager.id,
          permissionKey: "admin-permissions.manage",
          scope: "platform",
          scopeId: "*",
          isActive: true,
        },
      });
      trackAdminUserPermission(managePermission.id);

      const service = new AdminPermissionsService(prisma);
      const listedManager = await service.listAdminPermissions({
        actorAdminId: manager.id,
        targetAdminId: manager.id,
      });
      assert.equal(listedManager.ok, true);
      assert.ok(
        listedManager.permissions?.some(
          (permission) =>
            permission.permissionKey === "admin-permissions.manage",
        ),
      );
      if (listedManager.auditEventId != null) {
        trackAdminAuditLog(listedManager.auditEventId);
      }

      const grantResult = await service.grantPermission({
        actorAdminId: manager.id,
        targetAdminId: target.id,
        permissionKey: "support.session.revoke",
        reason: "Concessao aprovada em chamado",
      });
      assert.equal(grantResult.ok, true);
      assert.equal(grantResult.permission?.permissionKey, "support.session.revoke");
      if (grantResult.permission?.id != null) {
        trackAdminUserPermission(grantResult.permission.id);
      }
      if (grantResult.auditEventId != null) {
        trackAdminAuditLog(grantResult.auditEventId);
      }

      const rbac = new SupportActionRbacService(prisma);
      assert.equal(
        await rbac.hasSupportActionPermission(
          target.id,
          "support.session.revoke",
        ),
        true,
      );
      const permissionContext =
        await rbac.getSupportActionPermissionContext(target.id);
      const dryRun = buildOperationalActionDryRun(
        {
          actionType: "revoke_session",
          companyId: "company-1",
          targetType: "session",
          targetId: "session-1",
          actorAdminId: target.id,
          reason: "Chamado de seguranca confirmado",
          dryRun: true,
          permissionKeys: ["support.session.revoke"],
        },
        new Date("2026-05-31T18:00:00.000Z"),
        permissionContext,
      );
      assert.equal(dryRun.ok, true);

      const revokeResult = await service.revokePermission({
        actorAdminId: manager.id,
        targetAdminId: target.id,
        permissionKey: "support.session.revoke",
        reason: "Revogacao aprovada em revisao",
      });
      assert.equal(revokeResult.ok, true);
      if (revokeResult.auditEventId != null) {
        trackAdminAuditLog(revokeResult.auditEventId);
      }
      assert.equal(
        await rbac.hasSupportActionPermission(
          target.id,
          "support.session.revoke",
        ),
        false,
      );
      const deniedDryRun = buildOperationalActionDryRun(
        {
          actionType: "revoke_session",
          companyId: "company-1",
          targetType: "session",
          targetId: "session-1",
          actorAdminId: target.id,
          reason: "Chamado de seguranca confirmado",
          dryRun: true,
          permissionKeys: ["support.session.revoke"],
        },
        new Date("2026-05-31T18:00:00.000Z"),
        await rbac.getSupportActionPermissionContext(target.id),
      );
      assert.equal(deniedDryRun.ok, false);
      assert.equal(deniedDryRun.code, "OPERATIONAL_ACTION_MISSING_PERMISSION");

      await assert.rejects(
        () =>
          prisma.adminUserPermission.create({
            data: {
              actorUserId: manager.id,
              permissionKey: "admin-permissions.manage",
              scope: "platform",
              scopeId: "*",
              isActive: true,
            },
          }),
        (error) =>
          error instanceof Prisma.PrismaClientKnownRequestError &&
          error.code === "P2002",
      );
    });
  });

  it("executa bootstrap em banco limpo de managers e nega segunda tentativa", async () => {
    await withIntegration(async ({
      prisma,
      testRunId,
      trackUser,
      trackAdminAuditLog,
      trackAdminUserPermission,
    }) => {
      const bootstrapTarget = await createAdminUser(
        prisma,
        testRunId,
        "bootstrap-target",
      );
      const secondTarget = await createAdminUser(
        prisma,
        testRunId,
        "bootstrap-second",
      );
      trackUser(bootstrapTarget.id);
      trackUser(secondTarget.id);

      const service = new AdminPermissionBootstrapService(prisma);
      const first = await service.bootstrapManagePermission({
        targetAdminId: bootstrapTarget.id,
        reason: "Bootstrap inicial aprovado",
        env: { ADMIN_PERMISSION_BOOTSTRAP_ENABLED: "true" },
      });

      assert.equal(first.ok, true);
      assert.equal(first.code, "ADMIN_PERMISSION_BOOTSTRAP_GRANTED");
      assert.equal(first.permission?.permissionKey, "admin-permissions.manage");
      if (first.permission?.id != null) {
        trackAdminUserPermission(first.permission.id);
      }
      for (const auditId of first.auditEventIds) {
        trackAdminAuditLog(auditId);
      }

      const persistedAudits = await prisma.adminAuditLog.findMany({
        where: { id: { in: first.auditEventIds } },
        orderBy: { createdAt: "asc" },
      });
      assert.equal(persistedAudits.length, 2);
      assert.ok(
        persistedAudits.every(
          (audit) =>
            audit.actorType === "BOOTSTRAP" &&
            audit.actorUserId == null &&
            audit.actorLabel === "SYSTEM_BOOTSTRAP",
        ),
      );

      const second = await service.bootstrapManagePermission({
        targetAdminId: secondTarget.id,
        reason: "Bootstrap duplicado negado",
        env: { ADMIN_PERMISSION_BOOTSTRAP_ENABLED: "true" },
      });

      assert.equal(second.ok, false);
      assert.equal(second.code, "ADMIN_PERMISSION_BOOTSTRAP_ALREADY_CONFIGURED");
      for (const auditId of second.auditEventIds) {
        trackAdminAuditLog(auditId);
      }
    });
  });
});

function withIntegration<T>(fn: Parameters<typeof withIsolatedIntegrationPrisma<T>>[1]) {
  if (!integrationConfig.enabled) {
    throw new Error(integrationConfig.skipReason);
  }
  return withIsolatedIntegrationPrisma(integrationConfig.databaseUrl, fn);
}

async function createAdminUser(
  prisma: import("@prisma/client").PrismaClient,
  testRunId: string,
  label: string,
) {
  return prisma.user.create({
    data: {
      email: `${testRunId}-${label}@integration.test`,
      passwordHash: "integration-test-password-hash",
      name: `Integration ${label}`,
      isActive: true,
      isPlatformAdmin: true,
    },
  });
}
