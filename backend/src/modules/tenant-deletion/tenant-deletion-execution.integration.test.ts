import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, before, describe, it } from "node:test";

import { Prisma } from "@prisma/client";

import { prisma } from "../../database/prisma";
import { TenantDeletionExecutionService } from "./tenant-deletion-execution.service";

const suffix = randomUUID();
let adminUserId: string;
let unprivilegedPlatformAdminUserId: string;
let ordinaryUserId: string;
let companyId: string;
let requestId: string;

before(async () => {
  await prisma.$connect();
  const admin = await prisma.user.create({
    data: {
      email: `phase4-admin-${suffix}@tatuzin.test`,
      passwordHash: "integration-test-hash",
      name: "Phase 4 Admin",
      isPlatformAdmin: true,
    },
  });
  const unprivilegedPlatformAdmin = await prisma.user.create({
    data: {
      email: `phase4-unprivileged-admin-${suffix}@tatuzin.test`,
      passwordHash: "integration-test-hash",
      name: "Platform Admin Without Execution RBAC",
      isPlatformAdmin: true,
    },
  });
  const ordinary = await prisma.user.create({
    data: {
      email: `phase4-user-${suffix}@tatuzin.test`,
      passwordHash: "integration-test-hash",
      name: "Tenant User Must Remain Global",
    },
  });
  adminUserId = admin.id;
  unprivilegedPlatformAdminUserId = unprivilegedPlatformAdmin.id;
  ordinaryUserId = ordinary.id;

  const company = await prisma.company.create({
    data: {
      name: "Empresa Phase 4",
      legalName: "Empresa Phase 4 LTDA",
      documentNumber: "12345678900",
      slug: `phase4-${suffix}`,
      license: {
        create: {
          plan: "BASIC",
          status: "ACTIVE",
          startsAt: new Date("2026-01-01T00:00:00.000Z"),
          syncEnabled: true,
        },
      },
    },
  });
  companyId = company.id;

  const membership = await prisma.membership.create({
    data: { companyId, userId: ordinaryUserId, role: "OWNER", isDefault: true },
  });
  const device = await prisma.companyDevice.create({
    data: {
      companyId,
      userId: ordinaryUserId,
      clientInstanceId: `phase4-device-${suffix}`,
      deviceLabel: "Telefone pessoal",
      platform: "android",
      appVersion: "1.0.0",
      status: "ACTIVE",
    },
  });
  await prisma.deviceSession.create({
    data: {
      companyId,
      userId: ordinaryUserId,
      membershipId: membership.id,
      clientInstanceId: `phase4-session-${suffix}`,
      refreshTokenHash: `phase4-refresh-${suffix}`,
      refreshTokenExpiresAt: new Date("2027-01-01T00:00:00.000Z"),
    },
  });
  const supportMembership = await prisma.membership.create({
    data: { companyId, userId: adminUserId, role: "OWNER", isDefault: false },
  });
  await prisma.deviceSession.create({
    data: {
      companyId,
      userId: adminUserId,
      membershipId: supportMembership.id,
      clientType: "ADMIN_WEB",
      clientInstanceId: `phase4-support-session-${suffix}`,
      refreshTokenHash: `phase4-support-refresh-${suffix}`,
      refreshTokenExpiresAt: new Date("2027-01-01T00:00:00.000Z"),
    },
  });
  await prisma.employeeProfile.create({
    data: {
      companyId,
      userId: ordinaryUserId,
      membershipId: membership.id,
      name: "Pessoa Funcionaria",
      email: `employee-${suffix}@tatuzin.test`,
      emailNormalized: `employee-${suffix}@tatuzin.test`,
      phone: "11999999999",
      role: "OWNER",
    },
  });
  const customer = await prisma.customer.create({
    data: {
      companyId,
      localUuid: `customer-${suffix}`,
      name: "Cliente Identificavel",
      phone: "11888888888",
      address: "Rua Teste",
      notes: "Preferencias pessoais",
    },
  });
  await prisma.customerNote.create({
    data: { companyId, customerId: customer.id, body: "Conteudo pessoal", authorUserId: ordinaryUserId },
  });
  await prisma.supplier.create({
    data: {
      companyId,
      localUuid: `supplier-${suffix}`,
      name: "Fornecedor Identificavel",
      email: `supplier-${suffix}@tatuzin.test`,
      document: "99887766000100",
    },
  });
  await prisma.syncEvent.create({
    data: {
      companyId,
      deviceId: device.id,
      userId: ordinaryUserId,
      eventId: `event-${suffix}`,
      feature: "customers",
      entity: "customer",
      operation: "upsert",
      occurredAt: new Date("2026-06-10T12:00:00.000Z"),
      payload: { name: "Cliente Identificavel" },
      status: "ACCEPTED",
    },
  });
  await prisma.analyticsCustomerDailySnapshot.create({
    data: {
      companyId,
      snapshotDate: new Date("2026-06-10T00:00:00.000Z"),
      customerKey: `customer-${suffix}`,
      customerId: customer.id,
      customerNameSnapshot: "Cliente Identificavel",
    },
  });
  await prisma.sale.create({
    data: {
      companyId,
      localUuid: `sale-${suffix}`,
      customerId: customer.id,
      paymentType: "cash",
      paymentMethod: "cash",
      totalAmountCents: 10000,
      totalCostCents: 4000,
      soldAt: new Date("2026-06-10T12:30:00.000Z"),
      notes: "Observacao pessoal removivel",
    },
  });
  await prisma.billingInvoice.create({
    data: { companyId, provider: "test-provider", status: "paid", amountCents: 3500 },
  });
  await prisma.billingCheckoutSession.create({
    data: { companyId, userId: adminUserId, plan: "BASIC", billingCycle: "monthly", status: "COMPLETED", provider: "test-provider" },
  });
  await prisma.billingProviderEvent.create({
    data: { companyId, provider: "test-provider", eventType: "invoice.paid", dedupeKey: `phase4-${suffix}`, payload: { retained: true }, status: "PROCESSED" },
  });
  await prisma.billingAdminAuditLog.create({
    data: { actorUserId: adminUserId, companyId, action: "billing.test", reason: "Registro financeiro preservado" },
  });

  const deletionRequest = await prisma.tenantDeletionRequest.create({
    data: {
      companyId,
      activeCompanyGuard: companyId,
      status: "FUTURE_PENDING_DELETION",
      requestedByAdminUserId: adminUserId,
      requestedByEmail: admin.email,
      requestedCompanyNameSnapshot: company.name,
      source: "ADMIN_WEB",
      reason: "Solicitacao validada para teste de integracao",
      identityStatus: "VERIFIED",
      identityVerifiedByAdminUserId: adminUserId,
      identityVerifiedAt: new Date("2026-06-10T10:00:00.000Z"),
      dryRunGeneratedAt: new Date("2026-06-10T10:30:00.000Z"),
      dryRunSnapshotJson: {
        categories: [],
        blockers: [
          { key: "company_physical_delete_forbidden", severity: "blocking" },
          { key: "billing_provider_not_cancelled", severity: "warning" },
        ],
      },
    },
  });
  requestId = deletionRequest.id;
  await prisma.adminUserPermission.create({
    data: {
      actorUserId: adminUserId,
      permissionKey: "tenant.deletion.execute",
      scope: "platform",
      scopeId: "*",
    },
  });
});

after(async () => {
  if (companyId) {
    await prisma.tenantDeletionAuditEvent.deleteMany({ where: { companyId } });
    await prisma.billingAdminAuditLog.deleteMany({ where: { companyId } });
    await prisma.billingProviderEvent.deleteMany({ where: { companyId } });
    await prisma.billingInvoice.deleteMany({ where: { companyId } });
    await prisma.billingCheckoutSession.deleteMany({ where: { companyId } });
    await prisma.tenantDeletionRequest.deleteMany({ where: { companyId } });
    await prisma.adminAuditLog.deleteMany({ where: { targetCompanyId: companyId } });
    await prisma.company.deleteMany({ where: { id: companyId } });
  }
  if (adminUserId || unprivilegedPlatformAdminUserId || ordinaryUserId) {
    const userIds = [adminUserId, unprivilegedPlatformAdminUserId, ordinaryUserId].filter(Boolean);
    await prisma.adminUserPermission.deleteMany({ where: { actorUserId: { in: userIds } } });
    await prisma.user.deleteMany({ where: { id: { in: userIds } } });
  }
  await prisma.$disconnect();
});

describe("tenant deletion selective execution", () => {
  it("mantem a execucao indisponivel quando a feature flag esta desligada", async () => {
    const service = new TenantDeletionExecutionService(prisma, undefined, { enabled: false });
    const result = await execute(service);
    assert.equal(result.code, "TENANT_DELETION_EXECUTION_DISABLED");
    assert.equal((await prisma.company.findUniqueOrThrow({ where: { id: companyId } })).name, "Empresa Phase 4");
  });

  it("nao aceita platform admin sem permissao granular", async () => {
    const service = new TenantDeletionExecutionService(prisma, undefined, { enabled: true });
    const result = await service.execute({
      actorAdminId: unprivilegedPlatformAdminUserId,
      requestId,
      companyId,
      reason: "Tentativa sem permissao granular persistida",
      confirmation: "ANONIMIZAR TENANT",
    });
    assert.equal(result.code, "TENANT_DELETION_PERMISSION_REQUIRED");
  });

  it("exige identidade, dry-run e quarentena ativa", async () => {
    const service = new TenantDeletionExecutionService(prisma, undefined, { enabled: true });

    await prisma.tenantDeletionRequest.update({ where: { id: requestId }, data: { identityStatus: "NOT_STARTED", identityVerifiedAt: null } });
    assert.equal((await execute(service)).code, "TENANT_DELETION_STATE_CONFLICT");

    await prisma.tenantDeletionRequest.update({ where: { id: requestId }, data: { identityStatus: "VERIFIED", identityVerifiedAt: new Date("2026-06-10T10:00:00.000Z"), dryRunSnapshotJson: Prisma.JsonNull, dryRunGeneratedAt: null } });
    assert.equal((await execute(service)).code, "TENANT_DELETION_STATE_CONFLICT");

    await prisma.tenantDeletionRequest.update({ where: { id: requestId }, data: { dryRunSnapshotJson: { categories: [], blockers: [{ key: "company_physical_delete_forbidden", severity: "blocking" }] }, dryRunGeneratedAt: new Date("2026-06-10T10:30:00.000Z"), status: "DRY_RUN_READY" } });
    assert.equal((await execute(service)).code, "TENANT_DELETION_STATE_CONFLICT");
    assert.equal((await prisma.company.findUniqueOrThrow({ where: { id: companyId } })).name, "Empresa Phase 4");

    for (const status of ["CANCELLED", "REJECTED"] as const) {
      await prisma.tenantDeletionRequest.update({ where: { id: requestId }, data: { status } });
      assert.equal((await execute(service)).code, "TENANT_DELETION_STATE_CONFLICT");
    }

    await prisma.tenantDeletionRequest.update({ where: { id: requestId }, data: { status: "FUTURE_PENDING_DELETION" } });
  });

  it("recalcula blockers criticos imediatamente antes da execucao", async () => {
    const blocker = await prisma.billingCheckoutSession.create({
      data: {
        companyId,
        userId: adminUserId,
        plan: "BASIC",
        billingCycle: "monthly",
        status: "PENDING",
        provider: "test-provider",
      },
    });
    const service = new TenantDeletionExecutionService(prisma, undefined, { enabled: true });
    const result = await execute(service);

    assert.equal(result.code, "TENANT_DELETION_STATE_CONFLICT");
    const request = await prisma.tenantDeletionRequest.findUniqueOrThrow({
      where: { id: requestId },
    });
    assert.equal(request.status, "FUTURE_PENDING_DELETION");
    const snapshot = request.dryRunSnapshotJson as {
      executionRevalidation?: { criticalBlockers?: Array<{ key?: string }> };
    };
    assert.ok(
      snapshot.executionRevalidation?.criticalBlockers?.some(
        (item) => item.key === "pending_checkout_sessions",
      ),
    );
    assert.equal(
      await prisma.tenantDeletionAuditEvent.count({
        where: { requestId, eventType: "EXECUTION_CATEGORY_COMPLETED" },
      }),
      0,
    );
    await prisma.billingCheckoutSession.delete({ where: { id: blocker.id } });
  });

  it("serializa retries concorrentes e retoma sem duplicar categorias", async () => {
    let releaseLock!: () => void;
    let announceLock!: () => void;
    const lockReleased = new Promise<void>((resolve) => {
      releaseLock = resolve;
    });
    const lockAcquired = new Promise<void>((resolve) => {
      announceLock = resolve;
    });
    const service = new TenantDeletionExecutionService(prisma, undefined, {
      enabled: true,
      now: () => new Date("2026-06-10T14:00:00.000Z"),
      onLockAcquired: async () => {
        announceLock();
        await lockReleased;
      },
    });
    const conflictingCompany = await prisma.company.create({
      data: {
        name: "Conflito temporario",
        legalName: "Conflito temporario",
        slug: "deleted-" + companyId,
      },
    });

    const firstExecution = execute(service);
    await lockAcquired;
    const concurrent = await execute(
      new TenantDeletionExecutionService(prisma, undefined, {
        enabled: true,
        now: () => new Date("2026-06-10T14:00:00.000Z"),
      }),
    );
    assert.equal(concurrent.code, "TENANT_DELETION_STATE_CONFLICT");
    releaseLock();

    const failed = await firstExecution;
    assert.equal(failed.ok, false);
    assert.equal(
      (await prisma.tenantDeletionRequest.findUniqueOrThrow({ where: { id: requestId } })).status,
      "EXECUTION_IN_PROGRESS",
    );
    const completedBeforeRetry = await prisma.tenantDeletionAuditEvent.findMany({
      where: { requestId, eventType: "EXECUTION_CATEGORY_COMPLETED" },
      select: { metadataJson: true },
    });
    assert.ok(completedBeforeRetry.length > 0);
    assert.equal(
      new Set(
        completedBeforeRetry.map((event) =>
          String((event.metadataJson as { category?: unknown }).category),
        ),
      ).size,
      completedBeforeRetry.length,
    );
    await prisma.company.delete({ where: { id: conflictingCompany.id } });

    const resumed = await execute(
      new TenantDeletionExecutionService(prisma, undefined, { enabled: true }),
    );
    assert.equal(resumed.ok, true);
    const categoryEvents = await prisma.tenantDeletionAuditEvent.findMany({
      where: { requestId, eventType: "EXECUTION_CATEGORY_COMPLETED" },
      select: { metadataJson: true },
    });
    assert.equal(categoryEvents.length, 9);
    assert.equal(
      new Set(
        categoryEvents.map((event) =>
          String((event.metadataJson as { category?: unknown }).category),
        ),
      ).size,
      9,
    );
  });

  it("anonimiza seletivamente, preserva registros justificados e permite retry idempotente", async () => {
    const service = new TenantDeletionExecutionService(prisma, undefined, {
      enabled: true,
      now: () => new Date("2026-06-10T15:00:00.000Z"),
    });
    const result = await execute(service);
    assert.equal(result.ok, true);
    assert.equal(result.code, "TENANT_DELETION_EXECUTED");

    const request = await prisma.tenantDeletionRequest.findUniqueOrThrow({ where: { id: requestId } });
    const company = await prisma.company.findUniqueOrThrow({ where: { id: companyId }, include: { license: true } });
    const customer = await prisma.customer.findFirstOrThrow({ where: { companyId } });
    const supplier = await prisma.supplier.findFirstOrThrow({ where: { companyId } });
    const employee = await prisma.employeeProfile.findFirstOrThrow({ where: { companyId } });
    const globalUser = await prisma.user.findUniqueOrThrow({ where: { id: ordinaryUserId } });
    const supportSession = await prisma.deviceSession.findFirstOrThrow({
      where: { companyId, userId: adminUserId, clientType: "ADMIN_WEB" },
    });

    assert.equal(request.status, "DELETION_EXECUTED");
    const executionAudits = await prisma.tenantDeletionAuditEvent.findMany({
      where: { requestId },
      select: { eventType: true, reason: true, beforeJson: true, afterJson: true },
    });
    assert.ok(executionAudits.every((event) => event.reason === "[redacted]"));
    assert.ok(executionAudits.every((event) => event.beforeJson != null && event.afterJson != null));
    const categoryAudit = executionAudits.find(
      (event) => event.eventType === "EXECUTION_CATEGORY_COMPLETED",
    );
    const categoryBefore = categoryAudit?.beforeJson as {
      status?: unknown;
      counts?: Record<string, unknown>;
    };
    const categoryAfter = categoryAudit?.afterJson as {
      status?: unknown;
      counts?: Record<string, unknown>;
    };
    assert.equal(categoryBefore.status, "pending");
    assert.equal(categoryAfter.status, "completed");
    assert.ok(Object.keys(categoryBefore.counts ?? {}).length > 0);
    assert.ok(Object.keys(categoryAfter.counts ?? {}).length > 0);
    assert.equal(company.name, "Empresa excluida");
    assert.equal(company.documentNumber, null);
    assert.equal(company.isActive, false);
    assert.equal(company.license?.status, "ACTIVE");
    assert.equal(customer.name, "Cliente anonimizado");
    assert.equal(customer.phone, null);
    assert.equal(supplier.name, "Fornecedor anonimizado");
    assert.equal(employee.name, "Funcionario anonimizado");
    assert.equal(employee.userId, null);
    assert.equal(globalUser.email, `phase4-user-${suffix}@tatuzin.test`);
    assert.equal(supportSession.revokedAt, null);
    assert.equal(
      await prisma.membership.count({ where: { companyId, userId: adminUserId } }),
      1,
    );
    assert.equal(await prisma.customerNote.count({ where: { companyId } }), 0);
    assert.equal(await prisma.syncEvent.count({ where: { companyId } }), 0);
    assert.equal(await prisma.analyticsCustomerDailySnapshot.count({ where: { companyId } }), 0);
    assert.equal(await prisma.membership.count({ where: { companyId, userId: ordinaryUserId } }), 0);
    assert.equal(await prisma.billingInvoice.count({ where: { companyId } }), 1);
    assert.equal(await prisma.billingCheckoutSession.count({ where: { companyId } }), 1);
    assert.equal(await prisma.billingProviderEvent.count({ where: { companyId } }), 1);
    assert.equal(await prisma.billingAdminAuditLog.count({ where: { companyId } }), 1);
    assert.equal(await prisma.sale.count({ where: { companyId } }), 1);
    assert.equal((await prisma.sale.findFirstOrThrow({ where: { companyId } })).notes, null);

    const completionEvents = await prisma.tenantDeletionAuditEvent.count({
      where: { requestId, eventType: "EXECUTION_COMPLETED" },
    });
    const retry = await execute(service);
    assert.equal(retry.ok, true);
    assert.equal(retry.message, "Exclusao seletiva ja concluida; retorno idempotente.");
    assert.equal(await prisma.tenantDeletionAuditEvent.count({ where: { requestId, eventType: "EXECUTION_COMPLETED" } }), completionEvents);
  });
});

function execute(service: TenantDeletionExecutionService) {
  return service.execute({
    actorAdminId: adminUserId,
    requestId,
    companyId,
    reason: "Bearer abcdefghijklmnopqrstuvwxyz",
    confirmation: "ANONIMIZAR TENANT",
  });
}
