import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { TenantDeletionService } from "./tenant-deletion.service";
import type { TenantDeletionPermissionKey } from "../admin-permissions/admin-permissions.types";

describe("tenant deletion service", () => {
  it("gera dry-run read-only com permissao granular e auditoria", async () => {
    const client = createClient();
    const service = createService(client, ["tenant.deletion.read"]);

    const result = await service.dryRun({
      actorAdminId: "admin-1",
      companyId: "company-1",
      reason: "Triagem inicial de exclusao LGPD",
      requestId: "tdr_1",
    });

    assert.equal(result.ok, true);
    assert.equal(result.code, "TENANT_DELETION_DRY_RUN_READY");
    assert.equal(result.dryRun?.dryRun, true);
    assert.equal(result.dryRun?.persistenceMode, "admin_audit_log_foundation");
    assert.ok(
      result.dryRun?.blockers.some(
        (blocker) => blocker.key === "company_physical_delete_forbidden",
      ),
    );
    assert.equal(client.audits.length, 1);
    assert.equal(client.audits[0]?.data.action, "tenant.deletion.dry_run");
    assert.equal(client.mutations.length, 0);
  });

  it("nao libera dry-run somente por isPlatformAdmin sem permissao persistida", async () => {
    const client = createClient();
    const service = createService(client, []);

    const result = await service.dryRun({
      actorAdminId: "admin-1",
      companyId: "company-1",
      reason: "Triagem inicial de exclusao LGPD",
    });

    assert.equal(result.ok, false);
    assert.equal(result.code, "TENANT_DELETION_PERMISSION_REQUIRED");
    assert.equal(result.requiredPermission, "tenant.deletion.read");
    assert.match(result.message, /isPlatformAdmin sozinho nao libera/);
    assert.equal(client.audits[0]?.data.action, "tenant.deletion.dry_run.denied");
    assert.equal(client.mutations.length, 0);
  });

  it("registra solicitacao com motivo obrigatorio e sem alterar Company", async () => {
    const client = createClient();
    const service = createService(client, [
      "tenant.deletion.request.manage",
    ]);

    const result = await service.createRequest({
      actorAdminId: "admin-1",
      companyId: "company-1",
      reason: "Solicitacao recebida pelo formulario publico",
      requesterName: "Titular",
      requesterEmail: "titular@example.com",
      requesterChannel: "web",
    });

    assert.equal(result.ok, true);
    assert.equal(result.code, "TENANT_DELETION_REQUEST_RECORDED");
    assert.equal(result.request?.status, "REQUESTED");
    assert.equal(result.request?.requester.channel, "web");
    assert.equal(client.audits[0]?.data.action, "tenant.deletion.requested");
    assert.equal(client.mutations.length, 0);
  });

  it("exige permissao especifica para registrar identidade verificada", async () => {
    const client = createClient();
    const service = createService(client, [
      "tenant.deletion.request.manage",
    ]);

    const result = await service.verifyIdentity({
      actorAdminId: "admin-1",
      companyId: "company-1",
      requestId: "tdr_1",
      reason: "Documento e autoridade validados pelo suporte",
    });

    assert.equal(result.ok, false);
    assert.equal(result.code, "TENANT_DELETION_PERMISSION_REQUIRED");
    assert.equal(result.requiredPermission, "tenant.deletion.identity.verify");
    assert.equal(client.audits[0]?.data.action, "tenant.deletion.verified.denied");
  });
});

function createService(
  client: ReturnType<typeof createClient>,
  permissions: TenantDeletionPermissionKey[],
) {
  return new TenantDeletionService(
    client as never,
    {
      async hasPermission(input: { permissionKey: TenantDeletionPermissionKey }) {
        return permissions.includes(input.permissionKey);
      },
    },
    () => new Date("2026-06-07T12:00:00.000Z"),
  );
}

function createClient() {
  const audits: Array<{
    data: {
      actorType: "USER";
      actorUserId: string;
      actorLabel?: string | null;
      targetCompanyId?: string | null;
      action: string;
      details?: unknown;
    };
  }> = [];
  const mutations: string[] = [];
  const company = {
    id: "company-1",
    name: "Tatuzin Loja",
    legalName: "Tatuzin Loja LTDA",
    documentNumber: "00000000000000",
    slug: "tatuzin-loja",
    isActive: true,
    createdAt: new Date("2026-01-01T00:00:00.000Z"),
    updatedAt: new Date("2026-06-01T00:00:00.000Z"),
    license: {
      status: "ACTIVE",
      plan: "PRO",
      syncEnabled: true,
      billingProvider: "mercado_pago",
      providerSubscriptionId: "sub_123",
      cancelAtPeriodEnd: false,
      cancelRequestedAt: null,
      canceledAt: null,
      billingSubscriptionStatus: "active",
    },
  };

  const client: Record<string, unknown> = {
    audits,
    mutations,
    company: {
      async findUnique(input: { where: { id: string } }) {
        return input.where.id === company.id ? company : null;
      },
    },
    adminAuditLog: {
      async create(input: {
        data: {
          actorType: "USER";
          actorUserId: string;
          actorLabel?: string | null;
          targetCompanyId?: string | null;
          action: string;
          details?: unknown;
        };
        select: { id: true };
      }) {
        audits.push({ data: input.data });
        return { id: `audit-${audits.length}` };
      },
      async findMany() {
        return [];
      },
    },
  };

  for (const model of [
    "membership",
    "employeeProfile",
    "companyDevice",
    "deviceSession",
    "syncEvent",
    "syncConflict",
    "syncIncident",
    "syncSupportCommand",
    "deviceSyncDiagnostic",
    "billingCheckoutSession",
    "billingInvoice",
    "billingProviderEvent",
    "billingAdminAuditLog",
    "customer",
    "customerTag",
    "customerNote",
    "customerTask",
    "customerTimelineEvent",
    "category",
    "product",
    "supplier",
    "supply",
    "purchase",
    "sale",
    "financialEvent",
    "cost",
    "fiadoPayment",
    "cashEvent",
    "cashSession",
    "operationalOrder",
    "stockReservation",
    "stockDeduction",
    "supplyCostHistory",
    "analyticsCompanyDailySnapshot",
    "analyticsProductDailySnapshot",
    "analyticsCustomerDailySnapshot",
  ]) {
    client[model] = {
      async count(input: { where?: Record<string, unknown> }) {
        if (model === "deviceSession" && input.where?.revokedAt === null) {
          return 2;
        }
        if (
          model === "billingCheckoutSession" &&
          input.where?.status === "PENDING"
        ) {
          return 1;
        }
        return 3;
      },
    };
  }

  return client as typeof client & {
    audits: typeof audits;
    mutations: typeof mutations;
  };
}
