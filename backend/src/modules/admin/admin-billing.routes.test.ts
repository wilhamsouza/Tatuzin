import assert from "node:assert/strict";
import { after, before, beforeEach, describe, it } from "node:test";
import type { AddressInfo } from "node:net";

import type { Server } from "http";
import jwt from "jsonwebtoken";

import { createApp } from "../../app";
import { env } from "../../config/env";
import { prisma } from "../../database/prisma";

const runId = `admin-billing-${Date.now()}`;

let server: Server;
let apiBaseUrl = "";
let originalFetch: typeof globalThis.fetch;
const originalAccessToken = env.MERCADO_PAGO_ACCESS_TOKEN;

describe("admin billing routes", () => {
  before(async () => {
    await prisma.$connect();
    originalFetch = globalThis.fetch;
    env.MERCADO_PAGO_ACCESS_TOKEN = "test-mercado-token";
    server = createApp().listen(0);
    const address = server.address() as AddressInfo;
    apiBaseUrl = `http://127.0.0.1:${address.port}/api`;
  });

  beforeEach(async () => {
    await cleanupFixtures();
    env.MERCADO_PAGO_ACCESS_TOKEN = "test-mercado-token";
    globalThis.fetch = originalFetch;
  });

  after(async () => {
    await cleanupFixtures();
    env.MERCADO_PAGO_ACCESS_TOKEN = originalAccessToken;
    globalThis.fetch = originalFetch;
    await new Promise<void>((resolve, reject) => {
      server.close((error) => (error == null ? resolve() : reject(error)));
    });
    await prisma.$disconnect();
  });

  it("keeps admin billing routes protected by platform admin auth", async () => {
    const fixture = await createFixture();

    const forbidden = await requestJson("GET", `/admin/billing/companies`, {
      token: fixture.operatorToken,
    });
    assert.equal(forbidden.status, 403);
    assert.equal(
      (forbidden.data as { code?: string }).code,
      "PLATFORM_ADMIN_REQUIRED",
    );

    const allowed = await requestJson("GET", "/admin/billing/companies", {
      token: fixture.adminToken,
    });
    assert.equal(allowed.status, 200);

    const forbiddenExtension = await requestJson(
      "POST",
      `/admin/companies/${fixture.companyId}/license/extension/dry-run`,
      {
        token: fixture.operatorToken,
        body: { days: 3, reason: "Atendimento emergencial" },
      },
    );
    assert.equal(forbiddenExtension.status, 403);

    const forbiddenSuspend = await requestJson(
      "POST",
      `/admin/companies/${fixture.companyId}/license/suspend/dry-run`,
      {
        token: fixture.operatorToken,
        body: { reason: "Suspensao administrativa" },
      },
    );
    assert.equal(forbiddenSuspend.status, 403);

    const forbiddenReactivate = await requestJson(
      "POST",
      `/admin/companies/${fixture.companyId}/license/reactivate/dry-run`,
      {
        token: fixture.operatorToken,
        body: { reason: "Reativacao administrativa" },
      },
    );
    assert.equal(forbiddenReactivate.status, 403);
  });

  it("returns read-only company access summary without sensitive fields", async () => {
    const fixture = await createFixture({ plan: "BASIC" });
    const otherCompany = await createFixture({ plan: "PRO" });
    await createAccessArtifacts(fixture);
    await createAccessArtifacts(otherCompany);

    const forbidden = await requestJson(
      "GET",
      `/admin/companies/${fixture.companyId}/access-summary`,
      { token: fixture.operatorToken },
    );
    assert.equal(forbidden.status, 403);

    const response = await requestJson(
      "GET",
      `/admin/companies/${fixture.companyId}/access-summary`,
      { token: fixture.adminToken },
    );
    assert.equal(response.status, 200);
    const payload = response.data as {
      company: { license: { plan: string; pendingPlan: string | null } };
      summary: { owners: number; invitedEmployees: number };
      users: Array<{ isProtectedOwner: boolean }>;
      employees: Array<{
        status: string;
        effectivePermissions: string[];
        invitationStatus: string | null;
      }>;
      devices: Array<{ clientInstanceId: string; refreshTokenHash?: string }>;
    };
    assert.equal(payload.company.license.plan, "BASIC");
    assert.equal(payload.company.license.pendingPlan, "PRO");
    assert.equal(payload.summary.owners >= 1, true);
    assert.equal(payload.summary.invitedEmployees, 1);
    assert.equal(
      payload.users.some((user) => user.isProtectedOwner),
      true,
    );
    const disabled = payload.employees.find(
      (employee) => employee.status === "DISABLED",
    );
    assert.deepEqual(disabled?.effectivePermissions, []);
    assert.equal(
      payload.employees.some(
        (employee) => employee.invitationStatus === "PENDING",
      ),
      true,
    );
    assert.equal(payload.devices[0]?.refreshTokenHash, undefined);
    const serialized = JSON.stringify(payload);
    assert.equal(serialized.includes("passwordHash"), false);
    assert.equal(serialized.includes("resetToken"), false);
    assert.equal(serialized.includes("invite-token-secret"), false);
    assert.equal(serialized.includes("refresh-token-secret"), false);
    assert.equal(serialized.includes("Bearer secret"), false);
    assert.equal(serialized.includes(otherCompany.companyId), false);
    assert.equal(serialized.includes(otherCompany.ownerUserId), false);
    assert.equal(serialized.includes(otherCompany.operatorUserId), false);
  });

  it("returns read-only plan catalog with real entitlements", async () => {
    const freeFixture = await createFixture({ plan: "FREE" });
    const basicFixture = await createFixture({ plan: "BASIC" });
    const proFixture = await createFixture({ plan: "PRO" });

    const forbidden = await requestJson("GET", "/admin/plans", {
      token: basicFixture.operatorToken,
    });
    assert.equal(forbidden.status, 403);

    const response = await requestJson("GET", "/admin/plans", {
      token: proFixture.adminToken,
    });
    assert.equal(response.status, 200);

    const payload = response.data as {
      items: Array<{
        key: string;
        entitlements: {
          features: Record<string, boolean>;
          limits: { maxEmployees: number; maxDevices: number };
        };
        usage: { companiesCount: number; pendingPlanCount: number };
      }>;
      rules: {
        entitlementSource: string;
        pendingPlanReleasesFeatures: boolean;
      };
      usageSummary: {
        companiesByPlan: Record<string, number>;
        pendingCompaniesByPlan: Record<string, number>;
        pendingPlanCount: number;
      };
    };
    const byPlan = new Map(payload.items.map((item) => [item.key, item]));
    assert.equal(byPlan.get("FREE")?.entitlements.features.employees, false);
    assert.equal(byPlan.get("BASIC")?.entitlements.features.employees, false);
    assert.equal(byPlan.get("PRO")?.entitlements.features.employees, true);
    assert.equal(byPlan.get("PRO")?.entitlements.features.ownerWebPanel, true);
    assert.equal(byPlan.get("BASIC")?.entitlements.limits.maxEmployees, 0);
    assert.equal(byPlan.get("PRO")?.entitlements.limits.maxEmployees, 100);
    assert.equal(payload.rules.entitlementSource, "license.plan");
    assert.equal(payload.rules.pendingPlanReleasesFeatures, false);
    assert.equal((byPlan.get("FREE")?.usage.companiesCount ?? 0) >= 1, true);
    assert.equal((byPlan.get("BASIC")?.usage.companiesCount ?? 0) >= 1, true);
    assert.equal((byPlan.get("PRO")?.usage.companiesCount ?? 0) >= 1, true);
    assert.equal((byPlan.get("PRO")?.usage.pendingPlanCount ?? 0) >= 1, true);
    assert.equal(payload.usageSummary.companiesByPlan.BASIC >= 1, true);
    assert.equal(payload.usageSummary.companiesByPlan.PRO >= 1, true);
    assert.equal(payload.usageSummary.pendingCompaniesByPlan.PRO >= 1, true);
    assert.equal(payload.usageSummary.pendingPlanCount >= 1, true);
    assert.equal(
      JSON.stringify(payload).includes(freeFixture.providerId),
      false,
    );
  });

  it("lists billing companies with filters and masked provider id", async () => {
    const fixture = await createFixture();

    const response = await requestJson(
      "GET",
      `/admin/billing/companies?search=${encodeURIComponent("Admin Billing")}&plan=PRO&provider=mercadopago&hasProviderSubscription=true&page=1&pageSize=10`,
      { token: fixture.adminToken },
    );

    assert.equal(response.status, 200);
    const payload = response.data as {
      items: Array<{
        companyId: string;
        maskedProviderSubscriptionId: string | null;
        providerSubscriptionId?: string;
      }>;
    };
    assert.equal(payload.items.length, 1);
    assert.equal(payload.items[0]?.companyId, fixture.companyId);
    assert.equal(payload.items[0]?.maskedProviderSubscriptionId, "prea...9999");
    assert.equal(payload.items[0]?.providerSubscriptionId, undefined);
    assert.equal(JSON.stringify(payload).includes("test-mercado-token"), false);
  });

  it("keeps provider ids masked in general admin company and license payloads", async () => {
    const fixture = await createFixture();

    const companies = await requestJson("GET", "/admin/companies", {
      token: fixture.adminToken,
    });
    assert.equal(companies.status, 200);

    const licenses = await requestJson("GET", "/admin/licenses", {
      token: fixture.adminToken,
    });
    assert.equal(licenses.status, 200);

    const serialized = JSON.stringify({
      companies: companies.data,
      licenses: licenses.data,
    });
    assert.equal(serialized.includes(fixture.providerId), false);
    assert.equal(serialized.includes("prea...9999"), true);
    assert.equal(serialized.includes("providerSubscriptionId"), false);
    assert.equal(serialized.includes("maskedProviderSubscriptionId"), true);
  });

  it("returns internal status with masked provider id and sanitized summaries", async () => {
    const fixture = await createFixture();
    await createSensitiveBillingArtifacts(fixture);

    const response = await requestJson(
      "GET",
      `/admin/companies/${fixture.companyId}/billing/status`,
      { token: fixture.adminToken },
    );

    assert.equal(response.status, 200);
    const payload = response.data as {
      billing: {
        providerSubscriptionId?: string;
        maskedProviderSubscriptionId: string | null;
      };
      license: { providerSubscriptionId?: string };
      events: Array<{ payload: Record<string, unknown> }>;
      checkoutSessions: Array<{
        checkoutUrl: string | null;
        providerReference: string | null;
      }>;
    };
    assert.equal(payload.billing.providerSubscriptionId, undefined);
    assert.equal(payload.license.providerSubscriptionId, undefined);
    assert.equal(payload.billing.maskedProviderSubscriptionId, "prea...9999");
    assert.equal(payload.checkoutSessions[0]?.providerReference, "prea...9999");
    const serialized = JSON.stringify(payload);
    assert.equal(serialized.includes(fixture.providerId), false);
    assert.equal(serialized.includes("Bearer secret"), false);
    assert.equal(serialized.includes("access-secret"), false);
    assert.equal(serialized.includes("signature-secret"), false);
    assert.equal(serialized.includes("4111111111111111"), false);
    assert.equal(
      serialized.includes("https://mercadopago.test/checkout/full-url"),
      false,
    );
    assert.match(
      payload.checkoutSessions[0]?.checkoutUrl ?? "",
      /^https:\/\/mercadopago\.test\/\.\.\.#/,
    );
  });

  it("lists events ordered desc with recursively sanitized payloads", async () => {
    const fixture = await createFixture();
    await createSensitiveBillingArtifacts(fixture);

    const response = await requestJson(
      "GET",
      `/admin/companies/${fixture.companyId}/billing/events?page=1&pageSize=10`,
      { token: fixture.adminToken },
    );

    assert.equal(response.status, 200);
    const payload = response.data as {
      items: Array<{ eventType: string; payload: Record<string, unknown> }>;
    };
    assert.equal(payload.items[0]?.eventType, "newer");
    const serialized = JSON.stringify(payload);
    assert.equal(serialized.includes("Bearer secret"), false);
    assert.equal(serialized.includes("access-secret"), false);
    assert.equal(serialized.includes("signature-secret"), false);
    assert.equal(serialized.includes("4111111111111111"), false);
    assert.equal(
      serialized.includes("https://mercadopago.test/checkout/full-url"),
      false,
    );
  });

  it("lists billing admin audit logs ordered desc and sanitized", async () => {
    const fixture = await createFixture({ plan: "BASIC" });
    const otherCompany = await createFixture({ plan: "PRO" });

    await prisma.billingAdminAuditLog.createMany({
      data: [
        {
          actorUserId: fixture.ownerUserId,
          companyId: fixture.companyId,
          action: "license.suspend",
          reason: "Suspensao de suporte",
          before: {
            status: "ACTIVE",
            providerSubscriptionId: fixture.providerId,
          },
          after: {
            status: "SUSPENDED",
            providerSubscriptionId: fixture.providerId,
          },
          metadata: {
            Authorization: "Bearer secret",
            providerReference: fixture.providerId,
            headers: { token: "nested-secret" },
          },
          createdAt: new Date("2026-05-24T10:00:00.000Z"),
        },
        {
          actorUserId: fixture.ownerUserId,
          companyId: fixture.companyId,
          action: "billing.reconcile",
          reason: "Reconciliar provider",
          before: { billingSubscriptionStatus: "pending" },
          after: { billingSubscriptionStatus: "authorized" },
          metadata: {
            nested: { providerSubscriptionId: fixture.providerId },
          },
          createdAt: new Date("2026-05-24T11:00:00.000Z"),
        },
        {
          actorUserId: otherCompany.ownerUserId,
          companyId: otherCompany.companyId,
          action: "license.reactivate",
          reason: "Outra empresa",
          before: { providerSubscriptionId: otherCompany.providerId },
          after: { providerSubscriptionId: otherCompany.providerId },
          createdAt: new Date("2026-05-24T12:00:00.000Z"),
        },
      ],
    });

    const forbidden = await requestJson(
      "GET",
      `/admin/companies/${fixture.companyId}/billing/audit-logs`,
      { token: fixture.operatorToken },
    );
    assert.equal(forbidden.status, 403);

    const response = await requestJson(
      "GET",
      `/admin/companies/${fixture.companyId}/billing/audit-logs?page=1&pageSize=10`,
      { token: fixture.adminToken },
    );

    assert.equal(response.status, 200);
    const payload = response.data as {
      items: Array<{
        action: string;
        reason: string;
        actorName: string;
        before: Record<string, unknown>;
        after: Record<string, unknown>;
        metadata: Record<string, unknown>;
      }>;
      pagination: { total: number };
    };
    assert.equal(payload.pagination.total, 2);
    assert.equal(payload.items[0]?.action, "billing.reconcile");
    assert.equal(payload.items[1]?.action, "license.suspend");
    assert.equal(payload.items[0]?.actorName, "Billing Owner");

    const serialized = JSON.stringify(payload);
    assert.equal(serialized.includes(fixture.providerId), false);
    assert.equal(serialized.includes(otherCompany.providerId), false);
    assert.equal(serialized.includes("Bearer secret"), false);
    assert.equal(serialized.includes("nested-secret"), false);
    assert.match(serialized, /prea\.\.\.9999/);

    const emptyFixture = await createFixture({ plan: "FREE" });
    const empty = await requestJson(
      "GET",
      `/admin/companies/${emptyFixture.companyId}/billing/audit-logs`,
      { token: emptyFixture.adminToken },
    );
    assert.equal(empty.status, 200);
    assert.equal(
      (empty.data as { pagination: { total: number } }).pagination.total,
      0,
    );
  });

  it("lists checkout sessions without exposing full checkout URLs", async () => {
    const fixture = await createFixture();
    await createSensitiveBillingArtifacts(fixture);

    const response = await requestJson(
      "GET",
      `/admin/companies/${fixture.companyId}/billing/checkout-sessions?page=1&pageSize=10`,
      { token: fixture.adminToken },
    );

    assert.equal(response.status, 200);
    const payload = response.data as {
      items: Array<{
        checkoutUrl: string | null;
        sandboxCheckoutUrl: string | null;
      }>;
    };
    assert.match(
      payload.items[0]?.checkoutUrl ?? "",
      /^https:\/\/mercadopago\.test\/\.\.\.#/,
    );
    assert.match(
      payload.items[0]?.sandboxCheckoutUrl ?? "",
      /^https:\/\/sandbox\.mercadopago\.test\/\.\.\.#/,
    );
    assert.equal(JSON.stringify(payload).includes("full-url"), false);
  });

  it("dry-runs license emergency extension without mutating license", async () => {
    const fixture = await createFixture({ plan: "BASIC" });
    const activeWithoutExpiresAt = await requestJson(
      "POST",
      `/admin/companies/${fixture.companyId}/license/extension/dry-run`,
      {
        token: fixture.adminToken,
        body: { days: 3, reason: "Atendimento emergencial" },
      },
    );
    assert.equal(activeWithoutExpiresAt.status, 200);
    assert.equal(
      (activeWithoutExpiresAt.data as { allowed?: boolean }).allowed,
      false,
    );
    assert.equal(
      JSON.stringify(activeWithoutExpiresAt.data).includes(
        "Licenca ativa sem expiresAt nao precisa de extensao emergencial.",
      ),
      true,
    );

    const expiredAt = new Date(Date.now() - 24 * 60 * 60 * 1000);
    await prisma.license.update({
      where: { companyId: fixture.companyId },
      data: { status: "EXPIRED", expiresAt: expiredAt },
    });

    const missingReason = await requestJson(
      "POST",
      `/admin/companies/${fixture.companyId}/license/extension/dry-run`,
      { token: fixture.adminToken, body: { days: 3 } },
    );
    assert.equal(missingReason.status, 422);

    const invalidDays = await requestJson(
      "POST",
      `/admin/companies/${fixture.companyId}/license/extension/dry-run`,
      {
        token: fixture.adminToken,
        body: { days: 30, reason: "Atendimento emergencial" },
      },
    );
    assert.equal(invalidDays.status, 422);

    const response = await requestJson(
      "POST",
      `/admin/companies/${fixture.companyId}/license/extension/dry-run`,
      {
        token: fixture.adminToken,
        body: { days: 3, reason: "Atendimento emergencial" },
      },
    );
    assert.equal(response.status, 200);
    const payload = response.data as {
      allowed: boolean;
      expectedConfirmationText: string;
      maxAllowedDays: number;
      allowedDaysRange: { min: number; max: number };
      currentLicense: { plan: string; pendingPlan: string | null };
      proposedChange: {
        planAfter: string;
        pendingPlanAfter: string | null;
        statusAfter: string;
        expiresAtAfter: string;
      };
    };
    assert.equal(payload.allowed, true);
    assert.equal(payload.expectedConfirmationText, "ESTENDER");
    assert.equal(payload.maxAllowedDays, 7);
    assert.deepEqual(payload.allowedDaysRange, { min: 1, max: 7 });
    assert.equal(payload.currentLicense.plan, "BASIC");
    assert.equal(payload.currentLicense.pendingPlan, "PRO");
    assert.equal(payload.proposedChange.planAfter, "BASIC");
    assert.equal(payload.proposedChange.pendingPlanAfter, "PRO");
    assert.equal(payload.proposedChange.statusAfter, "ACTIVE");
    assert.equal(JSON.stringify(payload).includes(fixture.providerId), false);

    const license = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(license.status, "EXPIRED");
    assert.equal(license.expiresAt?.toISOString(), expiredAt.toISOString());
    assert.equal(license.plan, "BASIC");
    assert.equal(license.pendingPlan, "PRO");
    assert.equal(license.providerSubscriptionId, fixture.providerId);
  });

  it("applies license emergency extension with confirmation and sanitized audit", async () => {
    const fixture = await createFixture({ plan: "BASIC" });
    const beforeExpiresAt = new Date(Date.now() - 2 * 24 * 60 * 60 * 1000);
    const originalLicense = await prisma.license.update({
      where: { companyId: fixture.companyId },
      data: { status: "SUSPENDED", expiresAt: beforeExpiresAt },
    });

    const wrongConfirmation = await requestJson(
      "POST",
      `/admin/companies/${fixture.companyId}/license/extension`,
      {
        token: fixture.adminToken,
        body: {
          days: 2,
          reason: "Loja precisa concluir conciliacao",
          confirmationText: "CONFIRMAR",
        },
      },
    );
    assert.equal(wrongConfirmation.status, 422);

    const response = await requestJson(
      "POST",
      `/admin/companies/${fixture.companyId}/license/extension`,
      {
        token: fixture.adminToken,
        body: {
          days: 2,
          reason: "Loja precisa concluir conciliacao",
          note: "Chamado interno 123",
          confirmationText: "ESTENDER",
        },
      },
    );
    assert.equal(response.status, 200);
    const payload = response.data as {
      success: boolean;
      license: {
        plan: string;
        status: string;
        pendingPlan: string | null;
        providerSubscriptionId?: string;
      };
      proposedChange: { planAfter: string; pendingPlanAfter: string | null };
    };
    assert.equal(payload.success, true);
    assert.equal(payload.license.plan, "BASIC");
    assert.equal(payload.license.status, "ACTIVE");
    assert.equal(payload.license.pendingPlan, "PRO");
    assert.equal(payload.license.providerSubscriptionId, undefined);
    assert.equal(payload.proposedChange.planAfter, "BASIC");
    assert.equal(payload.proposedChange.pendingPlanAfter, "PRO");
    assert.equal(JSON.stringify(payload).includes(fixture.providerId), false);

    const license = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(license.status, "ACTIVE");
    assert.equal(license.plan, "BASIC");
    assert.equal(license.pendingPlan, "PRO");
    assert.equal(license.providerSubscriptionId, fixture.providerId);
    assert.equal(license.billingProvider, "mercadopago");
    assert.equal(
      license.currentPeriodEnd?.toISOString(),
      originalLicense.currentPeriodEnd?.toISOString(),
    );
    assert.notEqual(license.expiresAt, null);
    assert.equal(license.expiresAt!.getTime() > Date.now(), true);

    const audit = await prisma.billingAdminAuditLog.findFirstOrThrow({
      where: {
        companyId: fixture.companyId,
        action: "license.emergency_extension",
      },
      orderBy: { createdAt: "desc" },
    });
    assert.equal(audit.reason, "Loja precisa concluir conciliacao");
    const serializedAudit = JSON.stringify({
      before: audit.before,
      after: audit.after,
      metadata: audit.metadata,
    });
    assert.equal(serializedAudit.includes(fixture.providerId), false);
    assert.equal(serializedAudit.includes("Chamado interno 123"), true);
    assert.equal(serializedAudit.includes("ESTENDER"), true);
  });

  it("suspends license with dry-run, confirmation and sanitized audit", async () => {
    const fixture = await createFixture({ plan: "BASIC" });
    const before = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });

    const missingReason = await requestJson(
      "POST",
      `/admin/companies/${fixture.companyId}/license/suspend/dry-run`,
      { token: fixture.adminToken, body: {} },
    );
    assert.equal(missingReason.status, 422);

    const dryRun = await requestJson(
      "POST",
      `/admin/companies/${fixture.companyId}/license/suspend/dry-run`,
      {
        token: fixture.adminToken,
        body: { reason: "Fraude operacional em investigacao" },
      },
    );
    assert.equal(dryRun.status, 200);
    const dryRunPayload = dryRun.data as {
      allowed: boolean;
      expectedConfirmationText: string;
      currentLicense: { plan: string; pendingPlan: string | null };
      proposedChange: {
        statusBefore: string;
        statusAfter: string;
        planAfter: string;
        pendingPlanAfter: string | null;
      };
    };
    assert.equal(dryRunPayload.allowed, true);
    assert.equal(dryRunPayload.expectedConfirmationText, "SUSPENDER");
    assert.equal(dryRunPayload.currentLicense.plan, "BASIC");
    assert.equal(dryRunPayload.currentLicense.pendingPlan, "PRO");
    assert.equal(dryRunPayload.proposedChange.statusBefore, "ACTIVE");
    assert.equal(dryRunPayload.proposedChange.statusAfter, "SUSPENDED");
    assert.equal(dryRunPayload.proposedChange.planAfter, "BASIC");
    assert.equal(dryRunPayload.proposedChange.pendingPlanAfter, "PRO");
    assert.equal(
      JSON.stringify(dryRunPayload).includes(fixture.providerId),
      false,
    );

    const unchanged = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(unchanged.status, before.status);

    const wrongConfirmation = await requestJson(
      "POST",
      `/admin/companies/${fixture.companyId}/license/suspend`,
      {
        token: fixture.adminToken,
        body: {
          reason: "Fraude operacional em investigacao",
          confirmationText: "CONFIRMAR",
        },
      },
    );
    assert.equal(wrongConfirmation.status, 422);

    globalThis.fetch = failFetch("Mercado Pago nao deve ser chamado");
    const response = await requestJson(
      "POST",
      `/admin/companies/${fixture.companyId}/license/suspend`,
      {
        token: fixture.adminToken,
        body: {
          reason: "Fraude operacional em investigacao",
          note: "Chamado seguranca 789",
          confirmationText: "SUSPENDER",
        },
      },
    );
    assert.equal(response.status, 200);
    const payload = response.data as {
      success: boolean;
      license: {
        plan: string;
        status: string;
        pendingPlan: string | null;
        providerSubscriptionId?: string;
      };
      proposedChange: { statusAfter: string };
    };
    assert.equal(payload.success, true);
    assert.equal(payload.license.status, "SUSPENDED");
    assert.equal(payload.license.plan, "BASIC");
    assert.equal(payload.license.pendingPlan, "PRO");
    assert.equal(payload.license.providerSubscriptionId, undefined);
    assert.equal(payload.proposedChange.statusAfter, "SUSPENDED");
    assert.equal(JSON.stringify(payload).includes(fixture.providerId), false);

    const after = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(after.status, "SUSPENDED");
    assert.equal(after.plan, before.plan);
    assert.equal(after.pendingPlan, before.pendingPlan);
    assert.equal(after.providerSubscriptionId, before.providerSubscriptionId);
    assert.equal(after.billingProvider, before.billingProvider);
    assert.equal(
      after.currentPeriodEnd?.toISOString(),
      before.currentPeriodEnd?.toISOString(),
    );
    assert.equal(
      after.expiresAt?.toISOString(),
      before.expiresAt?.toISOString(),
    );

    const duplicate = await requestJson(
      "POST",
      `/admin/companies/${fixture.companyId}/license/suspend/dry-run`,
      {
        token: fixture.adminToken,
        body: { reason: "Suspender novamente" },
      },
    );
    assert.equal(duplicate.status, 200);
    assert.equal(
      JSON.stringify(duplicate.data).includes("Licenca ja esta suspensa."),
      true,
    );

    const audit = await prisma.billingAdminAuditLog.findFirstOrThrow({
      where: { companyId: fixture.companyId, action: "license.suspend" },
      orderBy: { createdAt: "desc" },
    });
    assert.equal(audit.reason, "Fraude operacional em investigacao");
    const serializedAudit = JSON.stringify({
      before: audit.before,
      after: audit.after,
      metadata: audit.metadata,
    });
    assert.equal(serializedAudit.includes(fixture.providerId), false);
    assert.equal(serializedAudit.includes("Chamado seguranca 789"), true);
    assert.equal(serializedAudit.includes("SUSPENDER"), true);
  });

  it("reactivates suspended license but blocks expired licenses", async () => {
    const fixture = await createFixture({ plan: "BASIC" });
    const futureExpiresAt = new Date(Date.now() + 3 * 24 * 60 * 60 * 1000);
    const before = await prisma.license.update({
      where: { companyId: fixture.companyId },
      data: { status: "SUSPENDED", expiresAt: futureExpiresAt },
    });

    const missingReason = await requestJson(
      "POST",
      `/admin/companies/${fixture.companyId}/license/reactivate/dry-run`,
      { token: fixture.adminToken, body: {} },
    );
    assert.equal(missingReason.status, 422);

    const dryRun = await requestJson(
      "POST",
      `/admin/companies/${fixture.companyId}/license/reactivate/dry-run`,
      {
        token: fixture.adminToken,
        body: { reason: "Cliente regularizado" },
      },
    );
    assert.equal(dryRun.status, 200);
    const dryRunPayload = dryRun.data as {
      allowed: boolean;
      expectedConfirmationText: string;
      proposedChange: {
        statusBefore: string;
        statusAfter: string;
        planAfter: string;
        pendingPlanAfter: string | null;
      };
    };
    assert.equal(dryRunPayload.allowed, true);
    assert.equal(dryRunPayload.expectedConfirmationText, "REATIVAR");
    assert.equal(dryRunPayload.proposedChange.statusBefore, "SUSPENDED");
    assert.equal(dryRunPayload.proposedChange.statusAfter, "ACTIVE");
    assert.equal(dryRunPayload.proposedChange.planAfter, "BASIC");
    assert.equal(dryRunPayload.proposedChange.pendingPlanAfter, "PRO");

    const wrongConfirmation = await requestJson(
      "POST",
      `/admin/companies/${fixture.companyId}/license/reactivate`,
      {
        token: fixture.adminToken,
        body: {
          reason: "Cliente regularizado",
          confirmationText: "CONFIRMAR",
        },
      },
    );
    assert.equal(wrongConfirmation.status, 422);

    globalThis.fetch = failFetch("Mercado Pago nao deve ser chamado");
    const response = await requestJson(
      "POST",
      `/admin/companies/${fixture.companyId}/license/reactivate`,
      {
        token: fixture.adminToken,
        body: {
          reason: "Cliente regularizado",
          note: "Chamado suporte 321",
          confirmationText: "REATIVAR",
        },
      },
    );
    assert.equal(response.status, 200);
    const payload = response.data as {
      success: boolean;
      license: {
        plan: string;
        status: string;
        pendingPlan: string | null;
        providerSubscriptionId?: string;
      };
    };
    assert.equal(payload.success, true);
    assert.equal(payload.license.status, "ACTIVE");
    assert.equal(payload.license.plan, "BASIC");
    assert.equal(payload.license.pendingPlan, "PRO");
    assert.equal(payload.license.providerSubscriptionId, undefined);
    assert.equal(JSON.stringify(payload).includes(fixture.providerId), false);

    const after = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(after.status, "ACTIVE");
    assert.equal(after.plan, before.plan);
    assert.equal(after.pendingPlan, before.pendingPlan);
    assert.equal(after.providerSubscriptionId, before.providerSubscriptionId);
    assert.equal(after.billingProvider, before.billingProvider);
    assert.equal(
      after.currentPeriodEnd?.toISOString(),
      before.currentPeriodEnd?.toISOString(),
    );
    assert.equal(
      after.expiresAt?.toISOString(),
      before.expiresAt?.toISOString(),
    );

    const alreadyActive = await requestJson(
      "POST",
      `/admin/companies/${fixture.companyId}/license/reactivate/dry-run`,
      {
        token: fixture.adminToken,
        body: { reason: "Ativar novamente" },
      },
    );
    assert.equal(alreadyActive.status, 200);
    assert.equal(
      JSON.stringify(alreadyActive.data).includes("Licenca ja esta ativa."),
      true,
    );

    const audit = await prisma.billingAdminAuditLog.findFirstOrThrow({
      where: { companyId: fixture.companyId, action: "license.reactivate" },
      orderBy: { createdAt: "desc" },
    });
    assert.equal(audit.reason, "Cliente regularizado");
    const serializedAudit = JSON.stringify({
      before: audit.before,
      after: audit.after,
      metadata: audit.metadata,
    });
    assert.equal(serializedAudit.includes(fixture.providerId), false);
    assert.equal(serializedAudit.includes("Chamado suporte 321"), true);
    assert.equal(serializedAudit.includes("REATIVAR"), true);

    const expiredFixture = await createFixture({ plan: "BASIC" });
    await prisma.license.update({
      where: { companyId: expiredFixture.companyId },
      data: {
        status: "SUSPENDED",
        expiresAt: new Date(Date.now() - 60 * 60 * 1000),
      },
    });
    const blockedExpired = await requestJson(
      "POST",
      `/admin/companies/${expiredFixture.companyId}/license/reactivate/dry-run`,
      {
        token: expiredFixture.adminToken,
        body: { reason: "Cliente regularizado" },
      },
    );
    assert.equal(blockedExpired.status, 200);
    assert.equal((blockedExpired.data as { allowed?: boolean }).allowed, false);
    assert.equal(
      JSON.stringify(blockedExpired.data).includes(
        "Use Extensao emergencial ou Reconciliar billing",
      ),
      true,
    );
  });

  it("dry-runs billing reconcile without mutating or exposing provider id", async () => {
    const fixture = await createFixture({ plan: "BASIC" });
    const before = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });

    const missingReason = await requestJson(
      "POST",
      `/admin/companies/${fixture.companyId}/billing/reconcile/dry-run`,
      { token: fixture.adminToken, body: {} },
    );
    assert.equal(missingReason.status, 422);

    const response = await requestJson(
      "POST",
      `/admin/companies/${fixture.companyId}/billing/reconcile/dry-run`,
      {
        token: fixture.adminToken,
        body: { reason: "Atualizar billing pelo provider" },
      },
    );
    assert.equal(response.status, 200);
    const payload = response.data as {
      allowed: boolean;
      expectedConfirmationText: string;
      currentBillingStatus: { plan: string; pendingPlan: string | null };
      providerCheckSummary: {
        consulted: boolean;
        maskedProviderSubscriptionId: string | null;
      };
      likelyActions: string[];
    };
    assert.equal(payload.allowed, true);
    assert.equal(payload.expectedConfirmationText, "RECONCILIAR");
    assert.equal(payload.currentBillingStatus.plan, "BASIC");
    assert.equal(payload.currentBillingStatus.pendingPlan, "PRO");
    assert.equal(payload.providerCheckSummary.consulted, false);
    assert.equal(
      payload.providerCheckSummary.maskedProviderSubscriptionId,
      "prea...9999",
    );
    assert.equal(payload.likelyActions.length > 0, true);
    assert.equal(JSON.stringify(payload).includes(fixture.providerId), false);

    const after = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(after.plan, before.plan);
    assert.equal(after.pendingPlan, before.pendingPlan);
    assert.equal(after.providerSubscriptionId, before.providerSubscriptionId);
    assert.equal(
      after.currentPeriodEnd?.toISOString(),
      before.currentPeriodEnd?.toISOString(),
    );
  });

  it("applies billing reconcile through provider refresh and audits safely", async () => {
    const fixture = await createFixture({ plan: "BASIC" });
    const before = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    globalThis.fetch = jsonFetch(async (url) => {
      if (url.includes("/authorized_payments/search")) {
        return {
          results: [
            {
              id: `${runId}-admin-reconcile-paid`,
              preapproval_id: fixture.providerId,
              status: "approved",
              transaction_amount: 35,
              currency_id: "BRL",
              external_resource_url:
                "https://mercadopago.test/invoices/admin-reconcile?token=secret",
              payment_date: "2026-05-07T10:00:00.000Z",
              card: { card_number: "4111111111111111", cvv: "123" },
              access_token: "secret",
            },
          ],
        };
      }
      return {
        id: fixture.providerId,
        status: "authorized",
        next_payment_date: before.currentPeriodEnd?.toISOString(),
        auto_recurring: { transaction_amount: 35 },
      };
    });

    const wrongConfirmation = await requestJson(
      "POST",
      `/admin/companies/${fixture.companyId}/billing/reconcile`,
      {
        token: fixture.adminToken,
        body: {
          reason: "Conciliar provider",
          confirmationText: "CONFIRMAR",
        },
      },
    );
    assert.equal(wrongConfirmation.status, 422);

    const response = await requestJson(
      "POST",
      `/admin/companies/${fixture.companyId}/billing/reconcile`,
      {
        token: fixture.adminToken,
        body: {
          reason: "Conciliar provider",
          note: "Chamado billing 456",
          confirmationText: "RECONCILIAR",
        },
      },
    );
    assert.equal(response.status, 200);
    const payload = response.data as {
      success: boolean;
      updatedStatus: {
        plan: string;
        pendingPlan: string | null;
        providerSubscriptionId?: string;
      };
      invoicesReconciled: number;
    };
    assert.equal(payload.success, true);
    assert.equal(payload.updatedStatus.plan, "BASIC");
    assert.equal(payload.updatedStatus.pendingPlan, "PRO");
    assert.equal(payload.updatedStatus.providerSubscriptionId, undefined);
    assert.equal(payload.invoicesReconciled, 1);
    assert.equal(JSON.stringify(payload).includes(fixture.providerId), false);
    assert.equal(JSON.stringify(payload).includes("4111111111111111"), false);

    const after = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(after.plan, "BASIC");
    assert.equal(after.pendingPlan, "PRO");
    assert.equal(after.providerSubscriptionId, before.providerSubscriptionId);
    assert.equal(after.billingProvider, before.billingProvider);
    assert.equal(
      after.currentPeriodEnd?.toISOString(),
      before.currentPeriodEnd?.toISOString(),
    );

    const invoice = await prisma.billingInvoice.findFirstOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(invoice.providerSubscriptionId, fixture.providerId);
    assert.equal(
      JSON.stringify(invoice.payload).includes("4111111111111111"),
      false,
    );

    const audit = await prisma.billingAdminAuditLog.findFirstOrThrow({
      where: { companyId: fixture.companyId, action: "billing.reconcile" },
      orderBy: { createdAt: "desc" },
    });
    assert.equal(audit.reason, "Conciliar provider");
    const serializedAudit = JSON.stringify({
      before: audit.before,
      after: audit.after,
      metadata: audit.metadata,
    });
    assert.equal(serializedAudit.includes(fixture.providerId), false);
    assert.equal(serializedAudit.includes("Chamado billing 456"), true);
    assert.equal(serializedAudit.includes("RECONCILIAR"), true);
  });

  it("requires reason for refresh and audits provider refresh failures without activating plan", async () => {
    const fixture = await createFixture({ plan: "free" });

    const missingReason = await requestJson(
      "POST",
      `/admin/companies/${fixture.companyId}/billing/refresh`,
      { token: fixture.adminToken, body: {} },
    );
    assert.equal(missingReason.status, 422);

    globalThis.fetch = failFetch("provider unavailable");
    const response = await requestJson(
      "POST",
      `/admin/companies/${fixture.companyId}/billing/refresh`,
      {
        token: fixture.adminToken,
        body: { reason: "Conferir falha de conciliacao" },
      },
    );

    assert.equal(response.status, 502);
    const license = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(license.plan, "free");

    const audit = await prisma.billingAdminAuditLog.findFirstOrThrow({
      where: {
        companyId: fixture.companyId,
        action: "billing.refresh.failed",
      },
      orderBy: { createdAt: "desc" },
    });
    assert.equal(audit.reason, "Conferir falha de conciliacao");
    assert.notEqual(audit.before, null);
    assert.notEqual(audit.after, null);
  });

  it("force-plan changes license plan, audits before/after and handles provider clearing", async () => {
    const fixture = await createFixture({ plan: "free" });
    const artifacts = await createSensitiveBillingArtifacts(fixture);

    const missingReason = await requestJson(
      "POST",
      `/admin/companies/${fixture.companyId}/billing/force-plan`,
      { token: fixture.adminToken, body: { plan: "BASIC" } },
    );
    assert.equal(missingReason.status, 422);

    const keepProvider = await requestJson(
      "POST",
      `/admin/companies/${fixture.companyId}/billing/force-plan`,
      {
        token: fixture.adminToken,
        body: { plan: "BASIC", reason: "Suporte manual" },
      },
    );
    assert.equal(keepProvider.status, 200);
    let license = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(license.plan, "BASIC");
    assert.equal(license.providerSubscriptionId, fixture.providerId);

    let audit = await prisma.billingAdminAuditLog.findFirstOrThrow({
      where: { companyId: fixture.companyId, action: "billing.force_plan" },
      orderBy: { createdAt: "desc" },
    });
    assert.notEqual(audit.before, null);
    assert.notEqual(audit.after, null);
    assert.equal(
      JSON.stringify(audit.metadata).includes("provider still linked"),
      true,
    );

    const clearProvider = await requestJson(
      "POST",
      `/admin/companies/${fixture.companyId}/billing/force-plan`,
      {
        token: fixture.adminToken,
        body: {
          plan: "PRO",
          status: "ACTIVE",
          reason: "Corrigir plano sem provider",
          clearProvider: true,
        },
      },
    );
    assert.equal(clearProvider.status, 200);
    license = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(license.plan, "PRO");
    assert.equal(license.status, "ACTIVE");
    assert.equal(license.billingSubscriptionStatus, "ACTIVE");
    assert.equal(license.providerSubscriptionId, null);
    assert.equal(
      await prisma.billingCheckoutSession.count({
        where: { id: artifacts.checkoutId },
      }),
      1,
    );
    assert.equal(
      await prisma.billingProviderEvent.count({
        where: { id: artifacts.eventId },
      }),
      1,
    );
    assert.equal(
      await prisma.billingInvoice.count({ where: { id: artifacts.invoiceId } }),
      1,
    );

    const bootstrap = await requestJson("GET", "/app/bootstrap", {
      token: fixture.ownerToken,
    });
    assert.equal(bootstrap.status, 200);
    assert.equal((bootstrap.data as { plan?: string }).plan, "PRO");

    const cancelled = await requestJson(
      "POST",
      `/admin/companies/${fixture.companyId}/billing/force-plan`,
      {
        token: fixture.adminToken,
        body: {
          plan: "BASIC",
          status: "CANCELLED",
          reason: "Registrar cancelamento administrativo",
        },
      },
    );
    assert.equal(cancelled.status, 200);
    license = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(license.status, "EXPIRED");
    assert.equal(license.billingSubscriptionStatus, "CANCELLED");

    const pastDue = await requestJson(
      "POST",
      `/admin/companies/${fixture.companyId}/billing/force-plan`,
      {
        token: fixture.adminToken,
        body: {
          plan: "BASIC",
          status: "PAST_DUE",
          reason: "Registrar inadimplencia administrativa",
        },
      },
    );
    assert.equal(pastDue.status, 200);
    license = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(license.status, "SUSPENDED");
    assert.equal(license.billingSubscriptionStatus, "PAST_DUE");
  });

  it("cancel-local schedules period-end cancellation, downgrades now, and preserves provider records", async () => {
    const fixture = await createFixture({ plan: "PRO" });
    const artifacts = await createSensitiveBillingArtifacts(fixture);

    const missingReason = await requestJson(
      "POST",
      `/admin/companies/${fixture.companyId}/billing/cancel-local`,
      { token: fixture.adminToken, body: { effective: "now" } },
    );
    assert.equal(missingReason.status, 422);

    const scheduled = await requestJson(
      "POST",
      `/admin/companies/${fixture.companyId}/billing/cancel-local`,
      {
        token: fixture.adminToken,
        body: {
          reason: "Cliente pediu fim do periodo",
          effective: "period_end",
        },
      },
    );
    assert.equal(scheduled.status, 200);
    assert.equal(
      (scheduled.data as { providerCancelled?: boolean }).providerCancelled,
      false,
    );
    let license = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(license.plan, "PRO");
    assert.equal(license.cancelAtPeriodEnd, true);
    assert.equal(license.providerSubscriptionId, fixture.providerId);

    const immediate = await requestJson(
      "POST",
      `/admin/companies/${fixture.companyId}/billing/cancel-local`,
      {
        token: fixture.adminToken,
        body: { reason: "Correcao imediata local", effective: "now" },
      },
    );
    assert.equal(immediate.status, 200);
    assert.equal(
      (immediate.data as { message?: string }).message,
      "Cancelamento local aplicado. A assinatura no Mercado Pago não foi cancelada por este endpoint.",
    );
    license = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(license.plan, "FREE");
    assert.equal(license.providerSubscriptionId, fixture.providerId);

    assert.equal(
      await prisma.billingCheckoutSession.count({
        where: { id: artifacts.checkoutId },
      }),
      1,
    );
    assert.equal(
      await prisma.billingProviderEvent.count({
        where: { id: artifacts.eventId },
      }),
      1,
    );
    assert.equal(
      await prisma.billingInvoice.count({ where: { id: artifacts.invoiceId } }),
      1,
    );
    assert.equal(
      await prisma.category.count({ where: { id: fixture.categoryId } }),
      1,
    );

    const audit = await prisma.billingAdminAuditLog.findFirstOrThrow({
      where: { companyId: fixture.companyId, action: "billing.cancel_local" },
      orderBy: { createdAt: "desc" },
    });
    assert.notEqual(audit.before, null);
    assert.notEqual(audit.after, null);
  });

  it("keeps app billing status from exposing full provider subscription id", async () => {
    const fixture = await createFixture();

    const response = await requestJson("GET", "/billing/status", {
      token: fixture.ownerToken,
    });

    assert.equal(response.status, 200);
    const payload = response.data as {
      hasProviderSubscription: boolean;
      maskedProviderSubscriptionId?: string;
      providerSubscriptionId?: string;
    };
    assert.equal(payload.hasProviderSubscription, true);
    assert.equal(payload.maskedProviderSubscriptionId, "prea...9999");
    assert.equal(payload.providerSubscriptionId, undefined);
  });
});

async function createFixture(options?: { plan?: string }) {
  const suffix = `${Date.now()}-${Math.random().toString(16).slice(2)}`;
  const company = await prisma.company.create({
    data: {
      name: `Admin Billing ${suffix}`,
      legalName: `Admin Billing ${suffix} LTDA`,
      slug: `${runId}-${suffix}`,
    },
  });
  const adminUser = await prisma.user.create({
    data: {
      email: `${runId}-admin-${suffix}@tatuzin.test`,
      name: "Billing Platform Admin",
      passwordHash: "not-used",
      isPlatformAdmin: true,
    },
  });
  const operatorUser = await prisma.user.create({
    data: {
      email: `${runId}-operator-${suffix}@tatuzin.test`,
      name: "Billing Operator",
      passwordHash: "not-used",
      isPlatformAdmin: false,
    },
  });
  const ownerUser = await prisma.user.create({
    data: {
      email: `${runId}-owner-${suffix}@tatuzin.test`,
      name: "Billing Owner",
      passwordHash: "not-used",
      isPlatformAdmin: false,
    },
  });
  const [adminMembership, operatorMembership, ownerMembership] =
    await prisma.$transaction([
      prisma.membership.create({
        data: {
          companyId: company.id,
          userId: adminUser.id,
          role: "OWNER",
          isDefault: true,
        },
      }),
      prisma.membership.create({
        data: {
          companyId: company.id,
          userId: operatorUser.id,
          role: "OPERATOR",
          isDefault: true,
        },
      }),
      prisma.membership.create({
        data: {
          companyId: company.id,
          userId: ownerUser.id,
          role: "OWNER",
          isDefault: true,
        },
      }),
    ]);
  const clientInstanceId = `${runId}-device-${suffix}`;
  await prisma.companyDevice.create({
    data: {
      companyId: company.id,
      userId: ownerUser.id,
      clientInstanceId,
      deviceLabel: "Billing Owner Device",
      platform: "node-test",
      appVersion: "admin-billing-test",
      status: "ACTIVE",
      approvedAt: new Date(),
      approvedByUserId: ownerUser.id,
      lastSeenAt: new Date(),
    },
  });
  const providerId = "preapproval-1234569999";
  await prisma.license.create({
    data: {
      companyId: company.id,
      plan: options?.plan ?? "PRO",
      status: "ACTIVE",
      startsAt: new Date("2026-05-01T00:00:00.000Z"),
      expiresAt: null,
      syncEnabled: true,
      billingProvider: "mercadopago",
      providerSubscriptionId: providerId,
      currentPeriodStart: new Date(Date.now() - 24 * 60 * 60 * 1000),
      currentPeriodEnd: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
      nextPaymentDate: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
      pendingPlan: options?.plan === "BASIC" ? "PRO" : null,
      pendingPlanRequestedAt:
        options?.plan === "BASIC" ? new Date("2026-05-20T00:00:00.000Z") : null,
    },
  });
  const category = await prisma.category.create({
    data: {
      companyId: company.id,
      localUuid: `${runId}-category-${suffix}`,
      name: "Categoria preservada",
    },
  });

  return {
    companyId: company.id,
    providerId,
    categoryId: category.id,
    ownerUserId: ownerUser.id,
    operatorUserId: operatorUser.id,
    ownerMembershipId: ownerMembership.id,
    operatorMembershipId: operatorMembership.id,
    adminToken: signToken({
      userId: adminUser.id,
      companyId: company.id,
      membershipId: adminMembership.id,
      email: adminUser.email,
      membershipRole: "OWNER",
      isPlatformAdmin: true,
    }),
    operatorToken: signToken({
      userId: operatorUser.id,
      companyId: company.id,
      membershipId: operatorMembership.id,
      email: operatorUser.email,
      membershipRole: "OPERATOR",
      isPlatformAdmin: false,
    }),
    ownerToken: signToken({
      userId: ownerUser.id,
      companyId: company.id,
      membershipId: ownerMembership.id,
      email: ownerUser.email,
      membershipRole: "OWNER",
      isPlatformAdmin: false,
      clientInstanceId,
    }),
  };
}

async function createAccessArtifacts(fixture: {
  companyId: string;
  ownerUserId: string;
  operatorUserId: string;
  ownerMembershipId: string;
  operatorMembershipId: string;
}) {
  await prisma.employeeProfile.createMany({
    data: [
      {
        companyId: fixture.companyId,
        userId: fixture.ownerUserId,
        membershipId: fixture.ownerMembershipId,
        name: "Billing Owner",
        email: `${runId}-owner-access@tatuzin.test`,
        emailNormalized: `${runId}-owner-access@tatuzin.test`,
        role: "OWNER",
        status: "ACTIVE",
        permissions: [],
      },
      {
        companyId: fixture.companyId,
        name: "Funcionario Convidado",
        email: `${runId}-invited-access@tatuzin.test`,
        emailNormalized: `${runId}-invited-access@tatuzin.test`,
        role: "CASHIER",
        status: "INVITED",
        permissions: ["sales.create"],
        invitedAt: new Date("2026-05-20T00:00:00.000Z"),
        inviteTokenHash: "invite-token-secret",
        inviteExpiresAt: new Date("2026-05-27T00:00:00.000Z"),
      },
      {
        companyId: fixture.companyId,
        userId: fixture.operatorUserId,
        membershipId: fixture.operatorMembershipId,
        name: "Funcionario Desativado",
        email: `${runId}-disabled-access@tatuzin.test`,
        emailNormalized: `${runId}-disabled-access@tatuzin.test`,
        role: "SELLER",
        status: "DISABLED",
        permissions: ["sales.create"],
        disabledAt: new Date("2026-05-21T00:00:00.000Z"),
      },
    ],
  });
  await prisma.deviceSession.create({
    data: {
      companyId: fixture.companyId,
      userId: fixture.ownerUserId,
      membershipId: fixture.ownerMembershipId,
      clientType: "MOBILE_APP",
      clientInstanceId: `${runId}-${fixture.companyId}-access-client-instance`,
      deviceLabel: "Access Android",
      platform: "android",
      appVersion: "1.2.3",
      refreshTokenHash: `${runId}-${fixture.companyId}-refresh-token-secret`,
      refreshTokenExpiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000),
      lastSeenAt: new Date("2026-05-24T12:00:00.000Z"),
    },
  });
  await prisma.adminAuditLog.create({
    data: {
      actorUserId: fixture.ownerUserId,
      targetCompanyId: fixture.companyId,
      action: "ACCESS_VIEW",
      details: {
        Authorization: "Bearer secret",
        public: "ok",
      },
    },
  });
}

async function createSensitiveBillingArtifacts(fixture: {
  companyId: string;
  providerId: string;
}) {
  const checkout = await prisma.billingCheckoutSession.create({
    data: {
      companyId: fixture.companyId,
      userId: (
        await prisma.membership.findFirstOrThrow({
          where: { companyId: fixture.companyId, role: "OWNER" },
        })
      ).userId,
      plan: "PRO",
      billingCycle: "monthly",
      status: "PENDING",
      provider: "mercadopago",
      providerReference: fixture.providerId,
      checkoutUrl: "https://mercadopago.test/checkout/full-url?token=secret",
      sandboxCheckoutUrl:
        "https://sandbox.mercadopago.test/checkout/full-url?token=secret",
      expiresAt: new Date(Date.now() + 30 * 60 * 1000),
    },
  });
  const older = await prisma.billingProviderEvent.create({
    data: {
      companyId: fixture.companyId,
      provider: "mercadopago",
      eventType: "older",
      providerEventId: `${runId}-older`,
      dedupeKey: `${runId}-older-${fixture.companyId}`,
      payload: { body: { ok: true } },
      status: "RECEIVED",
      createdAt: new Date("2026-05-01T00:00:00.000Z"),
    },
  });
  const newer = await prisma.billingProviderEvent.create({
    data: {
      companyId: fixture.companyId,
      provider: "mercadopago",
      eventType: "newer",
      providerEventId: `${runId}-newer`,
      dedupeKey: `${runId}-newer-${fixture.companyId}`,
      payload: {
        headers: {
          authorization: "Bearer secret",
          "x-signature": "signature-secret",
        },
        body: {
          access_token: "access-secret",
          checkoutUrl:
            "https://mercadopago.test/checkout/full-url?token=secret",
          card: {
            card_number: "4111111111111111",
            security_code: "123",
          },
          nested: [{ token: "nested-token" }],
        },
      },
      status: "RECEIVED",
      createdAt: new Date("2026-05-02T00:00:00.000Z"),
    },
  });
  const invoice = await prisma.billingInvoice.create({
    data: {
      companyId: fixture.companyId,
      provider: "mercadopago",
      providerInvoiceId: `${runId}-invoice-${fixture.companyId}`,
      providerSubscriptionId: fixture.providerId,
      plan: "PRO",
      status: "pending",
      amountCents: 8500,
      invoiceUrl: "https://mercadopago.test/invoice/full-url?token=secret",
      payload: { token: "invoice-token" },
    },
  });
  void older;
  return {
    checkoutId: checkout.id,
    eventId: newer.id,
    invoiceId: invoice.id,
  };
}

function signToken(input: {
  userId: string;
  companyId: string;
  membershipId: string;
  email: string;
  membershipRole: string;
  isPlatformAdmin: boolean;
  clientInstanceId?: string;
}) {
  return jwt.sign(
    {
      sub: input.userId,
      companyId: input.companyId,
      membershipId: input.membershipId,
      membershipRole: input.membershipRole,
      email: input.email,
      isPlatformAdmin: input.isPlatformAdmin,
      ...(input.clientInstanceId == null
        ? {}
        : { clientInstanceId: input.clientInstanceId }),
    },
    env.JWT_SECRET,
    { expiresIn: "15m" },
  );
}

async function requestJson(
  method: string,
  path: string,
  options?: {
    token?: string;
    body?: Record<string, unknown>;
  },
) {
  const response = await originalFetch(`${apiBaseUrl}${path}`, {
    method,
    headers: {
      ...(options?.token == null
        ? {}
        : { Authorization: `Bearer ${options.token}` }),
      ...(options?.body == null ? {} : { "Content-Type": "application/json" }),
    },
    body: options?.body == null ? undefined : JSON.stringify(options.body),
  });
  const rawBody = await response.text();
  return {
    status: response.status,
    data: rawBody.trim().length === 0 ? null : JSON.parse(rawBody),
  };
}

function failFetch(message: string) {
  return (async () => {
    throw new Error(message);
  }) as typeof globalThis.fetch;
}

function jsonFetch(
  handler: (
    url: string,
    init: { method?: string; body?: string },
  ) => Promise<Record<string, unknown>> | Record<string, unknown>,
) {
  return (async (url: string | URL | Request, init?: RequestInit) => {
    const payload = await handler(String(url), {
      method: init?.method,
      body: typeof init?.body === "string" ? init.body : undefined,
    });
    return new Response(JSON.stringify(payload), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }) as typeof globalThis.fetch;
}

async function cleanupFixtures() {
  await prisma.sessionAuditLog.deleteMany({
    where: {
      OR: [
        { company: { slug: { startsWith: `${runId}-` } } },
        { actorUser: { email: { startsWith: `${runId}-` } } },
        { subjectUser: { email: { startsWith: `${runId}-` } } },
      ],
    },
  });
  await prisma.adminAuditLog.deleteMany({
    where: {
      OR: [
        { targetCompany: { slug: { startsWith: `${runId}-` } } },
        { actorUser: { email: { startsWith: `${runId}-` } } },
      ],
    },
  });
  await prisma.billingAdminAuditLog.deleteMany({
    where: {
      OR: [
        { company: { slug: { startsWith: `${runId}-` } } },
        { actorUser: { email: { startsWith: `${runId}-` } } },
      ],
    },
  });
  await prisma.billingProviderEvent.deleteMany({
    where: {
      OR: [
        { company: { slug: { startsWith: `${runId}-` } } },
        { providerEventId: { startsWith: `${runId}-` } },
      ],
    },
  });
  await prisma.billingInvoice.deleteMany({
    where: { company: { slug: { startsWith: `${runId}-` } } },
  });
  await prisma.billingCheckoutSession.deleteMany({
    where: { company: { slug: { startsWith: `${runId}-` } } },
  });
  await prisma.company.deleteMany({
    where: { slug: { startsWith: `${runId}-` } },
  });
  await prisma.user.deleteMany({
    where: { email: { startsWith: `${runId}-` } },
  });
}
