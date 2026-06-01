import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { Prisma } from "@prisma/client";

import {
  resolveIntegrationTestDatabaseConfig,
  withIsolatedIntegrationPrisma,
} from "../../shared/testing/integration-prisma";
import { buildOperationalActionDryRun } from "./support-actions.service";
import { SupportActionAuditPersistenceService } from "./support-actions.audit-persistence";
import { SupportActionExecutionService } from "./support-actions.execution.service";
import { SupportActionRbacService } from "./support-actions.rbac";

const integrationConfig = resolveIntegrationTestDatabaseConfig();
const skipReason =
  integrationConfig.enabled ? false : integrationConfig.skipReason;

describe("support action revoke_session Prisma integration", { skip: skipReason }, () => {
  it("persiste dry-run, recibo idempotente e auditoria before/after em banco isolado", async () => {
    await withIntegration(async ({
      prisma,
      testRunId,
      trackCompany,
      trackUser,
      trackAdminAuditLog,
      trackAdminUserPermission,
      trackSupportActionExecution,
    }) => {
      const company = await prisma.company.create({
        data: {
          name: "Support Action Integration",
          legalName: "Support Action Integration LTDA",
          slug: `${testRunId}-support-action`,
        },
      });
      trackCompany(company.id);
      const actor = await prisma.user.create({
        data: {
          email: `${testRunId}-actor@integration.test`,
          passwordHash: "integration-test-password-hash",
          name: "Integration Actor",
          isActive: true,
          isPlatformAdmin: true,
        },
      });
      const subject = await prisma.user.create({
        data: {
          email: `${testRunId}-subject@integration.test`,
          passwordHash: "integration-test-password-hash",
          name: "Integration Subject",
          isActive: true,
        },
      });
      trackUser(actor.id);
      trackUser(subject.id);
      const membership = await prisma.membership.create({
        data: {
          companyId: company.id,
          userId: subject.id,
          role: "OPERATOR",
        },
      });
      const session = await prisma.deviceSession.create({
        data: {
          userId: subject.id,
          companyId: company.id,
          membershipId: membership.id,
          clientInstanceId: `${testRunId}-device`,
          refreshTokenHash: `${testRunId}-refresh`,
          refreshTokenExpiresAt: new Date(Date.now() + 60 * 60 * 1000),
        },
      });
      const permission = await prisma.adminUserPermission.create({
        data: {
          actorUserId: actor.id,
          permissionKey: "support.session.revoke",
        },
      });
      trackAdminUserPermission(permission.id);

      const rbac = new SupportActionRbacService(prisma);
      const dryRun = buildOperationalActionDryRun(
        {
          actionType: "revoke_session",
          companyId: company.id,
          targetType: "session",
          targetId: session.id,
          actorAdminId: actor.id,
          reason: "Chamado de seguranca confirmado",
          dryRun: true,
          metadata: { token: "secret-token" },
        },
        new Date(),
        await rbac.getSupportActionPermissionContext(actor.id),
      );
      assert.equal(dryRun.ok, true);
      assert.ok(dryRun.action);
      const dryRunAuditId = await new SupportActionAuditPersistenceService(
        prisma,
      ).recordDryRun(dryRun.action);
      trackAdminAuditLog(dryRunAuditId);

      const executionService = new SupportActionExecutionService(
        prisma as never,
        {
          async revokeCompanySession(input) {
            const target = await prisma.deviceSession.findUnique({
              where: { id: input.sessionId },
            });
            assert.equal(target?.companyId, input.companyId);
            await prisma.deviceSession.update({
              where: { id: input.sessionId },
              data: {
                revokedAt: new Date(),
                revokedReason: "support_action_revoke_session",
              },
            });
          },
        },
        () => new Date(),
        {
          revokeSessionExecutionEnabled: true,
        },
      );
      const request = {
        actionType: "revoke_session",
        companyId: company.id,
        targetType: "session",
        targetId: session.id,
        actorAdminId: actor.id,
        reason: "Chamado de seguranca confirmado",
        dryRunAuditEventId: dryRunAuditId,
        idempotencyKey: `${testRunId}-idempotency`,
        explicitConfirmation: true,
        confirmationText: "REVOGAR_SESSAO",
        metadata: {
          authorization: "Bearer eyJabc.def.ghi",
          secret: "raw-secret",
        },
      };
      const first = await executionService.executeRevokeSession(
        request,
        await rbac.getSupportActionPermissionContext(actor.id),
      );
      assert.equal(first.code, "SUPPORT_ACTION_EXECUTED");
      assert.ok(first.execution);
      trackSupportActionExecution(first.execution.id);
      if (first.execution.beforeAuditEventId != null) {
        trackAdminAuditLog(first.execution.beforeAuditEventId);
      }
      if (first.execution.afterAuditEventId != null) {
        trackAdminAuditLog(first.execution.afterAuditEventId);
      }
      const replay = await executionService.executeRevokeSession(
        request,
        await rbac.getSupportActionPermissionContext(actor.id),
      );
      assert.equal(replay.code, "SUPPORT_ACTION_IDEMPOTENT_REPLAY");

      const persistedSession = await prisma.deviceSession.findUnique({
        where: { id: session.id },
      });
      assert.notEqual(persistedSession?.revokedAt, null);
      const receipt = await prisma.supportActionExecution.findUnique({
        where: { id: first.execution.id },
      });
      assert.equal(receipt?.status, "SUCCEEDED");
      const audits = await prisma.adminAuditLog.findMany({
        where: {
          id: {
            in: [
              first.execution.beforeAuditEventId!,
              first.execution.afterAuditEventId!,
            ],
          },
        },
      });
      assert.deepEqual(
        new Set(audits.map((audit) => audit.action)),
        new Set([
          "support.revoke_session.execute_requested",
          "support.revoke_session.execute_succeeded",
        ]),
      );
      const serialized = JSON.stringify(audits);
      assert.match(serialized, /\[redacted\]/);
      assert.doesNotMatch(serialized, /Bearer eyJabc|raw-secret/);
    });
  });
});

function withIntegration<T>(
  fn: Parameters<typeof withIsolatedIntegrationPrisma<T>>[1],
) {
  if (!integrationConfig.enabled) {
    throw new Error(integrationConfig.skipReason);
  }
  return withIsolatedIntegrationPrisma(integrationConfig.databaseUrl, fn);
}
