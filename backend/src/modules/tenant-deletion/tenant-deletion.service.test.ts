import assert from "node:assert/strict";
import { describe, it } from "node:test";

import type { TenantDeletionPermissionKey } from "../admin-permissions/admin-permissions.types";
import { TenantDeletionService } from "./tenant-deletion.service";
import type { TenantDeletionPersistedRequest } from "./tenant-deletion.types";

describe("tenant deletion persisted workflow", () => {
  it("cria solicitacao persistida com UUID e dupla auditoria sanitizada", async () => {
    const fixture = createFixture(["tenant.deletion.request.manage"]);

    const result = await fixture.service.createRequest({
      actorAdminId: "admin-1",
      companyId: "company-1",
      reason: "Solicitacao recebida pelo formulario publico",
      requesterEmail: "titular@example.com",
      requesterChannel: "web",
    });

    assert.equal(result.ok, true);
    assert.match(result.request?.requestId ?? "", uuidPattern);
    assert.equal(fixture.requests.length, 1);
    assert.equal(fixture.requests[0]?.status, "REQUESTED");
    assert.equal(fixture.requests[0]?.requestedByEmail, "titular@example.com");
    assert.equal(fixture.workflowEvents[0]?.eventType, "REQUEST_CREATED");
    assert.equal(fixture.adminAudits[0]?.action, "tenant.deletion.requested");
    assert.equal(fixture.destructiveCalls.length, 0);
  });

  it("reutiliza solicitacao ativa de forma idempotente", async () => {
    const fixture = createFixture(["tenant.deletion.request.manage"]);
    const first = await createRequest(fixture);
    const second = await createRequest(fixture);

    assert.equal(second.request?.requestId, first.request?.requestId);
    assert.equal(fixture.requests.length, 1);
    assert.equal(fixture.workflowEvents.at(-1)?.eventType, "REQUEST_VIEWED");
  });

  it("resolve corrida de criacao pela guarda unica da empresa", async () => {
    const fixture = createFixture(["tenant.deletion.request.manage"]);
    fixture.triggerCreateConflict();

    const result = await createRequest(fixture);

    assert.equal(result.ok, true);
    assert.equal(fixture.requests.length, 1);
    assert.equal(result.request?.requestId, fixture.requests[0]?.id);
    assert.equal(fixture.workflowEvents.at(-1)?.eventType, "REQUEST_VIEWED");
  });

  it("lista e busca detalhes a partir da tabela dedicada", async () => {
    const fixture = createFixture([
      "tenant.deletion.request.manage",
      "tenant.deletion.read",
    ]);
    const created = await createRequest(fixture);

    const listed = await fixture.service.listRequests({
      actorAdminId: "admin-1",
      companyId: "company-1",
    });
    const detail = await fixture.service.getRequest({
      actorAdminId: "admin-1",
      requestId: created.request!.requestId,
    });

    assert.equal(listed.requests?.length, 1);
    assert.equal(listed.requests?.[0]?.source, "web");
    assert.equal(detail.code, "TENANT_DELETION_REQUEST_FOUND");
    assert.equal(detail.request?.requestId, created.request?.requestId);
    assert.equal(fixture.workflowEvents.at(-1)?.eventType, "REQUEST_VIEWED");
  });

  it("marca identity pending e verifica identidade com atores persistidos", async () => {
    const fixture = createFixture([
      "tenant.deletion.request.manage",
      "tenant.deletion.identity.verify",
    ]);
    const created = await createRequest(fixture);

    const pending = await fixture.service.markIdentityPending({
      actorAdminId: "admin-1",
      companyId: "company-1",
      requestId: created.request!.requestId,
      reason: "Validacao documental iniciada pelo suporte",
      note: "Evidencia minimizada registrada",
    });
    const verified = await fixture.service.verifyIdentity({
      actorAdminId: "admin-2",
      companyId: "company-1",
      requestId: created.request!.requestId,
      reason: "Identidade e autoridade confirmadas",
      note: "Autoridade confirmada sem anexar documentos",
    });

    assert.equal(pending.request?.status, "IDENTITY_PENDING");
    assert.equal(pending.request?.identityStatus, "PENDING");
    assert.equal(verified.request?.status, "VERIFIED");
    assert.equal(verified.request?.identityStatus, "VERIFIED");
    assert.equal(fixture.requests[0]?.identityVerifiedByAdminUserId, "admin-2");
    assert.deepEqual(
      fixture.workflowEvents.map((event) => event.eventType),
      ["REQUEST_CREATED", "IDENTITY_PENDING_SET", "IDENTITY_VERIFIED"],
    );
  });

  it("cancela e rejeita somente com tenant.deletion.cancel", async () => {
    const cancelledFixture = createFixture([
      "tenant.deletion.request.manage",
      "tenant.deletion.cancel",
    ]);
    const cancelledRequest = await createRequest(cancelledFixture);
    const cancelled = await cancelledFixture.service.cancelRequest({
      actorAdminId: "admin-1",
      companyId: "company-1",
      requestId: cancelledRequest.request!.requestId,
      reason: "Solicitacao cancelada pelo titular validado",
    });

    const rejectedFixture = createFixture([
      "tenant.deletion.request.manage",
      "tenant.deletion.cancel",
    ]);
    const rejectedRequest = await createRequest(rejectedFixture);
    const rejected = await rejectedFixture.service.rejectRequest({
      actorAdminId: "admin-1",
      companyId: "company-1",
      requestId: rejectedRequest.request!.requestId,
      reason: "Autoridade sobre a empresa nao comprovada",
    });

    assert.equal(cancelled.request?.status, "CANCELLED");
    assert.equal(rejected.request?.status, "REJECTED");
    assert.equal(
      rejectedFixture.workflowEvents.at(-1)?.eventType,
      "REQUEST_REJECTED",
    );
  });

  it("gera dry-run read-only e salva snapshot minimizado no request", async () => {
    const fixture = createFixture([
      "tenant.deletion.request.manage",
      "tenant.deletion.read",
      "tenant.deletion.identity.verify",
    ]);
    const created = await createRequest(fixture);
    await fixture.service.markIdentityPending({
      actorAdminId: "admin-1",
      companyId: "company-1",
      requestId: created.request!.requestId,
      reason: "Validacao documental iniciada pelo suporte",
    });
    await fixture.service.verifyIdentity({
      actorAdminId: "admin-1",
      companyId: "company-1",
      requestId: created.request!.requestId,
      reason: "Identidade e autoridade confirmadas",
    });

    const result = await fixture.service.dryRun({
      actorAdminId: "admin-1",
      companyId: "company-1",
      requestId: created.request!.requestId,
      reason: "Inventario solicitado para triagem segura",
    });

    assert.equal(result.ok, true);
    assert.equal(result.request?.status, "DRY_RUN_READY");
    assert.equal(result.dryRun?.persistenceMode, "tenant_deletion_request");
    const snapshot = fixture.requests[0]?.dryRunSnapshotJson as Record<
      string,
      unknown
    >;
    assert.equal(snapshot.companyId, "company-1");
    assert.equal("documentNumber" in snapshot, false);
    assert.equal("legalName" in snapshot, false);
    assert.equal(fixture.workflowEvents.at(-1)?.eventType, "DRY_RUN_GENERATED");
    assert.equal(fixture.destructiveCalls.length, 0);
  });

  it("bloqueia dry-run antes da verificacao de identidade", async () => {
    const fixture = createFixture([
      "tenant.deletion.request.manage",
      "tenant.deletion.read",
    ]);
    const created = await createRequest(fixture);

    const result = await fixture.service.dryRun({
      actorAdminId: "admin-1",
      companyId: "company-1",
      requestId: created.request!.requestId,
      reason: "Inventario solicitado antes da verificacao",
    });

    assert.equal(result.code, "TENANT_DELETION_STATE_CONFLICT");
    assert.equal(fixture.requests[0]?.dryRunSnapshotJson, null);
    assert.equal(fixture.destructiveCalls.length, 0);
  });

  it("exige identidade verificada e dry-run antes da quarentena", async () => {
    const fixture = createFixture([
      "tenant.deletion.request.manage",
      "tenant.deletion.quarantine",
    ]);
    const created = await createRequest(fixture);

    const result = await fixture.service.quarantineRequest({
      actorAdminId: "admin-1",
      companyId: "company-1",
      requestId: created.request!.requestId,
      reason: "Quarentena aprovada apos analise operacional",
      confirmation: "QUARENTENA",
    });

    assert.equal(result.code, "TENANT_DELETION_STATE_CONFLICT");
    assert.equal(fixture.requests[0]?.status, "REQUESTED");
    assert.equal(fixture.revokedSessions(), 0);
  });

  it("coloca tenant em quarentena de forma auditada e idempotente", async () => {
    const fixture = createFixture([
      "tenant.deletion.request.manage",
      "tenant.deletion.read",
      "tenant.deletion.identity.verify",
      "tenant.deletion.quarantine",
    ]);
    const requestId = await advanceToDryRun(fixture);

    const first = await fixture.service.quarantineRequest({
      actorAdminId: "admin-1",
      companyId: "company-1",
      requestId,
      reason: "Quarentena aprovada apos analise operacional",
      confirmation: "QUARENTENA",
    });
    const second = await fixture.service.quarantineRequest({
      actorAdminId: "admin-1",
      companyId: "company-1",
      requestId,
      reason: "Repeticao idempotente da quarentena aprovada",
      confirmation: "QUARENTENA",
    });

    assert.equal(first.code, "TENANT_DELETION_QUARANTINED");
    assert.equal(second.code, "TENANT_DELETION_QUARANTINED");
    assert.equal(fixture.requests[0]?.status, "FUTURE_PENDING_DELETION");
    assert.equal(fixture.company.isActive, true);
    assert.equal(fixture.company.license.billingSubscriptionStatus, "active");
    assert.equal(fixture.revokedSessions(), 2);
    assert.equal(fixture.activePlatformAdminSessions(), 1);
    assert.equal(fixture.revokedTenantDevices(), 3);
    assert.equal(fixture.activePlatformAdminDevices(), 1);
    assert.deepEqual(
      fixture.workflowEvents.slice(-2).map((event) => event.eventType),
      ["QUARANTINE_STARTED", "QUARANTINE_STARTED"],
    );
    assert.equal(
      fixture.adminAudits.at(-1)?.action,
      "tenant.deletion.quarantined.idempotent",
    );
    assert.equal(fixture.destructiveCalls.length, 0);
  });

  it("nega quarentena sem permissao granular e exige confirmacao explicita", async () => {
    const fixture = createFixture([
      "tenant.deletion.request.manage",
      "tenant.deletion.read",
      "tenant.deletion.identity.verify",
    ]);
    const requestId = await advanceToDryRun(fixture);

    const denied = await fixture.service.quarantineRequest({
      actorAdminId: "admin-1",
      companyId: "company-1",
      requestId,
      reason: "Tentativa sem permissao granular persistida",
      confirmation: "QUARENTENA",
    });
    fixture.permissions.add("tenant.deletion.quarantine");
    const unconfirmed = await fixture.service.quarantineRequest({
      actorAdminId: "admin-1",
      companyId: "company-1",
      requestId,
      reason: "Tentativa sem confirmacao textual explicita",
      confirmation: "confirmo",
    });

    assert.equal(denied.code, "TENANT_DELETION_PERMISSION_REQUIRED");
    assert.equal(denied.requiredPermission, "tenant.deletion.quarantine");
    assert.equal(unconfirmed.code, "TENANT_DELETION_VALIDATION_ERROR");
    assert.equal(fixture.requests[0]?.status, "DRY_RUN_READY");
  });

  it("cancela quarentena, restaura dispositivos e exige novo login", async () => {
    const fixture = createFixture([
      "tenant.deletion.request.manage",
      "tenant.deletion.read",
      "tenant.deletion.identity.verify",
      "tenant.deletion.quarantine",
      "tenant.deletion.cancel",
    ]);
    const requestId = await advanceToDryRun(fixture);
    await fixture.service.quarantineRequest({
      actorAdminId: "admin-1",
      companyId: "company-1",
      requestId,
      reason: "Quarentena aprovada apos analise operacional",
      confirmation: "QUARENTENA",
    });

    const result = await fixture.service.cancelRequest({
      actorAdminId: "admin-2",
      companyId: "company-1",
      requestId,
      reason: "Solicitacao retirada pelo titular validado",
    });

    assert.equal(result.code, "TENANT_DELETION_CANCELLED");
    assert.equal(result.request?.status, "CANCELLED");
    assert.equal(fixture.revokedTenantDevices(), 0);
    assert.equal(fixture.restoredTenantDevices(), 3);
    assert.equal(fixture.revokedSessions(), 2);
    assert.equal(
      fixture.workflowEvents.at(-1)?.eventType,
      "QUARANTINE_CANCELLED",
    );
    assert.match(result.message, /novo login/);
  });

  it("nega leitura, criacao, verificacao e cancelamento sem RBAC granular", async () => {
    const fixture = createFixture(["tenant.deletion.request.manage"]);
    const created = await createRequest(fixture);

    fixture.permissions.clear();
    const readDenied = await fixture.service.listRequests({
      actorAdminId: "admin-1",
    });
    const verifyDenied = await fixture.service.verifyIdentity({
      actorAdminId: "admin-1",
      companyId: "company-1",
      requestId: created.request!.requestId,
      reason: "Tentativa sem permissao persistida",
    });
    const cancelDenied = await fixture.service.cancelRequest({
      actorAdminId: "admin-1",
      companyId: "company-1",
      requestId: created.request!.requestId,
      reason: "Tentativa sem permissao persistida",
    });
    const rejectDenied = await fixture.service.rejectRequest({
      actorAdminId: "admin-1",
      companyId: "company-1",
      requestId: created.request!.requestId,
      reason: "Tentativa sem permissao persistida",
    });

    const createFixtureDenied = createFixture([]);
    const createDenied = await createRequest(createFixtureDenied);

    for (const result of [
      readDenied,
      verifyDenied,
      cancelDenied,
      rejectDenied,
      createDenied,
    ]) {
      assert.equal(result.code, "TENANT_DELETION_PERMISSION_REQUIRED");
      assert.match(result.message, /isPlatformAdmin sozinho nao libera/);
    }
  });

  it("sanitiza secrets em request, workflow event e AdminAuditLog", async () => {
    const fixture = createFixture(["tenant.deletion.request.manage"]);

    await fixture.service.createRequest({
      actorAdminId: "admin-1",
      companyId: "company-1",
      reason: "Chamado com token Bearer eyJabc.def.ghi",
      requesterEmail: "titular@example.com",
      requesterChannel: "web",
    });

    assert.equal(fixture.requests[0]?.reason, "[redacted]");
    const serialized = JSON.stringify({
      workflowEvents: fixture.workflowEvents,
      adminAudits: fixture.adminAudits,
    });
    assert.doesNotMatch(serialized, /Bearer eyJabc|def\.ghi/);
    assert.doesNotMatch(serialized, /titular@example\.com/);
  });

  it("bloqueia transicao posterior a estado terminal", async () => {
    const fixture = createFixture([
      "tenant.deletion.request.manage",
      "tenant.deletion.cancel",
      "tenant.deletion.identity.verify",
    ]);
    const created = await createRequest(fixture);
    await fixture.service.cancelRequest({
      actorAdminId: "admin-1",
      companyId: "company-1",
      requestId: created.request!.requestId,
      reason: "Solicitacao cancelada pelo titular validado",
    });

    const result = await fixture.service.verifyIdentity({
      actorAdminId: "admin-1",
      companyId: "company-1",
      requestId: created.request!.requestId,
      reason: "Tentativa posterior ao cancelamento",
    });

    assert.equal(result.code, "TENANT_DELETION_STATE_CONFLICT");
    assert.equal(fixture.requests[0]?.status, "CANCELLED");
  });

  it("bloqueia cancelamento depois que a execucao irreversivel iniciou", async () => {
    const fixture = createFixture([
      "tenant.deletion.request.manage",
      "tenant.deletion.cancel",
    ]);
    const created = await createRequest(fixture);
    fixture.requests[0]!.status = "EXECUTION_IN_PROGRESS";

    const result = await fixture.service.cancelRequest({
      actorAdminId: "admin-1",
      companyId: "company-1",
      requestId: created.request!.requestId,
      reason: "Tentativa de cancelamento apos inicio irreversivel",
    });

    assert.equal(result.code, "TENANT_DELETION_STATE_CONFLICT");
    assert.equal(fixture.requests[0]?.status, "EXECUTION_IN_PROGRESS");
  });

  it("bloqueia transicao concorrente quando o status mudou", async () => {
    const fixture = createFixture([
      "tenant.deletion.request.manage",
      "tenant.deletion.cancel",
    ]);
    const created = await createRequest(fixture);
    fixture.triggerTransitionConflict();

    const result = await fixture.service.markIdentityPending({
      actorAdminId: "admin-1",
      companyId: "company-1",
      requestId: created.request!.requestId,
      reason: "Validacao documental iniciada pelo suporte",
    });

    assert.equal(result.code, "TENANT_DELETION_STATE_CONFLICT");
    assert.equal(fixture.requests[0]?.status, "CANCELLED");
    assert.equal(fixture.workflowEvents.length, 1);
  });
});

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

async function createRequest(fixture: ReturnType<typeof createFixture>) {
  return fixture.service.createRequest({
    actorAdminId: "admin-1",
    companyId: "company-1",
    reason: "Solicitacao recebida pelo formulario publico",
    requesterEmail: "titular@example.com",
    requesterChannel: "web",
  });
}

async function advanceToDryRun(fixture: ReturnType<typeof createFixture>) {
  const created = await createRequest(fixture);
  const requestId = created.request!.requestId;
  await fixture.service.markIdentityPending({
    actorAdminId: "admin-1",
    companyId: "company-1",
    requestId,
    reason: "Validacao documental iniciada pelo suporte",
  });
  await fixture.service.verifyIdentity({
    actorAdminId: "admin-1",
    companyId: "company-1",
    requestId,
    reason: "Identidade e autoridade confirmadas",
  });
  await fixture.service.dryRun({
    actorAdminId: "admin-1",
    companyId: "company-1",
    requestId,
    reason: "Inventario solicitado para triagem segura",
  });
  return requestId;
}

function createFixture(permissionKeys: TenantDeletionPermissionKey[]) {
  const permissions = new Set<TenantDeletionPermissionKey>(permissionKeys);
  const requests: TenantDeletionPersistedRequest[] = [];
  const workflowEvents: Array<{
    id: string;
    requestId: string;
    companyId: string;
    actorAdminUserId: string | null;
    eventType: string;
    reason: string | null;
    beforeJson: unknown;
    afterJson: unknown;
    metadataJson: unknown;
    createdAt: Date;
  }> = [];
  const adminAudits: Array<{
    action: string;
    details: unknown;
  }> = [];
  const destructiveCalls: string[] = [];
  const company = companyFixture();
  const sessions = [
    {
      revokedAt: null as Date | null,
      isPlatformAdmin: false,
      clientType: "MOBILE_APP",
    },
    {
      revokedAt: null as Date | null,
      isPlatformAdmin: false,
      clientType: "ADMIN_WEB",
    },
    {
      revokedAt: null as Date | null,
      isPlatformAdmin: true,
      clientType: "ADMIN_WEB",
    },
  ];
  const devices = [
    {
      status: "ACTIVE",
      revokedReason: null as string | null,
      isPlatformAdmin: false,
    },
    {
      status: "PENDING",
      revokedReason: null as string | null,
      isPlatformAdmin: false,
    },
    {
      status: "BLOCKED",
      revokedReason: null as string | null,
      isPlatformAdmin: false,
    },
    {
      status: "ACTIVE",
      revokedReason: null as string | null,
      isPlatformAdmin: true,
    },
  ];
  let conflictOnNextCreate = false;
  let conflictOnNextTransition = false;

  const client: Record<string, unknown> = {
    company: {
      async findUnique(input: { where: { id: string } }) {
        return input.where.id === company.id ? company : null;
      },
    },
    tenantDeletionRequest: {
      async findMany(input: Record<string, unknown>) {
        const where = (input.where ?? {}) as Record<string, unknown>;
        return requests
          .filter((request) => {
            if (
              where.companyId != null &&
              request.companyId !== where.companyId
            ) {
              return false;
            }
            if (where.status != null && request.status !== where.status) {
              return false;
            }
            return true;
          })
          .sort(
            (left, right) =>
              right.updatedAt.getTime() - left.updatedAt.getTime(),
          );
      },
      async findUnique(input: { where: { id: string } }) {
        return (
          requests.find((request) => request.id === input.where.id) ?? null
        );
      },
      async findFirst(input: Record<string, unknown>) {
        const where = input.where as {
          companyId: string;
          status?: { in?: string[] };
        };
        return (
          requests.find(
            (request) =>
              request.companyId === where.companyId &&
              (where.status?.in?.includes(request.status) ?? true),
          ) ?? null
        );
      },
      async create(input: Record<string, unknown>) {
        const data = input.data as Record<string, unknown>;
        if (conflictOnNextCreate) {
          conflictOnNextCreate = false;
          requests.push(
            persistedRequestFixture(
              {
                ...data,
                id: "22222222-2222-4222-8222-222222222222",
              },
              company,
            ),
          );
          throw Object.assign(new Error("unique constraint"), {
            code: "P2002",
          });
        }
        const request = persistedRequestFixture(data, company);
        requests.push(request);
        return request;
      },
      async update(input: Record<string, unknown>) {
        const where = input.where as { id: string };
        const data = input.data as Record<string, unknown>;
        const request = requests.find((item) => item.id === where.id);
        assert.ok(request);
        Object.assign(request, data);
        return request;
      },
      async updateMany(input: Record<string, unknown>) {
        const where = input.where as {
          id: string;
          status: string;
          activeCompanyGuard: string;
        };
        const data = input.data as Record<string, unknown>;
        const request = requests.find((item) => item.id === where.id);
        if (request == null) {
          return { count: 0 };
        }
        if (conflictOnNextTransition) {
          conflictOnNextTransition = false;
          request.status = "CANCELLED";
          request.activeCompanyGuard = null;
          return { count: 0 };
        }
        if (
          request.status !== where.status ||
          request.activeCompanyGuard !== where.activeCompanyGuard
        ) {
          return { count: 0 };
        }
        Object.assign(request, data);
        return { count: 1 };
      },
    },
    tenantDeletionAuditEvent: {
      async create(input: Record<string, unknown>) {
        const data = input.data as Record<string, unknown>;
        const event = {
          id: `workflow-audit-${workflowEvents.length + 1}`,
          requestId: String(data.requestId),
          companyId: String(data.companyId),
          actorAdminUserId:
            data.actorAdminUserId == null
              ? null
              : String(data.actorAdminUserId),
          eventType: String(data.eventType),
          reason: data.reason == null ? null : String(data.reason),
          beforeJson: data.beforeJson,
          afterJson: data.afterJson,
          metadataJson: data.metadataJson,
          createdAt: new Date("2026-06-09T12:00:00.000Z"),
        };
        workflowEvents.push(event);
        const request = requests.find((item) => item.id === event.requestId);
        request?.auditEvents.unshift(event);
        return event;
      },
    },
    adminAuditLog: {
      async create(input: Record<string, unknown>) {
        const data = input.data as {
          action: string;
          details?: unknown;
        };
        adminAudits.push({
          action: data.action,
          details: data.details,
        });
        return { id: `admin-audit-${adminAudits.length}` };
      },
    },
    async $transaction<T>(operation: (transaction: unknown) => Promise<T>) {
      return operation(client);
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
        return 3;
      },
    };
  }

  client.deviceSession = {
    async count(input: { where?: Record<string, unknown> }) {
      if (input.where?.revokedAt === null) {
        return sessions.filter((session) => session.revokedAt == null).length;
      }
      return sessions.length;
    },
    async updateMany(input: Record<string, unknown>) {
      const data = input.data as {
        revokedAt: Date;
      };
      let count = 0;
      for (const session of sessions) {
        if (
          session.revokedAt == null &&
          !(session.isPlatformAdmin && session.clientType === "ADMIN_WEB")
        ) {
          session.revokedAt = data.revokedAt;
          count++;
        }
      }
      return { count };
    },
  };
  client.companyDevice = {
    async count() {
      return devices.length;
    },
    async updateMany(input: Record<string, unknown>) {
      const where = input.where as {
        status: string;
        revokedReason?: string;
      };
      const data = input.data as {
        status: string;
        revokedReason: string | null;
      };
      let count = 0;
      for (const device of devices) {
        const matchesQuarantine =
          data.status === "REVOKED" &&
          device.status === where.status &&
          !device.isPlatformAdmin;
        const matchesRestore =
          data.status !== "REVOKED" &&
          device.status === where.status &&
          device.revokedReason === where.revokedReason;
        if (!matchesQuarantine && !matchesRestore) {
          continue;
        }
        device.status = data.status;
        device.revokedReason = data.revokedReason;
        count++;
      }
      return { count };
    },
  };

  const service = new TenantDeletionService(
    client as never,
    {
      async hasPermission(input: {
        permissionKey: TenantDeletionPermissionKey;
      }) {
        return permissions.has(input.permissionKey);
      },
    },
    () => new Date("2026-06-09T12:00:00.000Z"),
  );

  return {
    service,
    permissions,
    requests,
    workflowEvents,
    adminAudits,
    destructiveCalls,
    company,
    revokedSessions() {
      return sessions.filter(
        (session) => !session.isPlatformAdmin && session.revokedAt != null,
      ).length;
    },
    activePlatformAdminSessions() {
      return sessions.filter(
        (session) => session.isPlatformAdmin && session.revokedAt == null,
      ).length;
    },
    revokedTenantDevices() {
      return devices.filter(
        (device) => !device.isPlatformAdmin && device.status === "REVOKED",
      ).length;
    },
    restoredTenantDevices() {
      return devices.filter(
        (device) =>
          !device.isPlatformAdmin &&
          device.status !== "REVOKED" &&
          device.revokedReason == null,
      ).length;
    },
    activePlatformAdminDevices() {
      return devices.filter(
        (device) => device.isPlatformAdmin && device.status === "ACTIVE",
      ).length;
    },
    triggerCreateConflict() {
      conflictOnNextCreate = true;
    },
    triggerTransitionConflict() {
      conflictOnNextTransition = true;
    },
  };
}

function persistedRequestFixture(
  data: Record<string, unknown>,
  company: ReturnType<typeof companyFixture>,
): TenantDeletionPersistedRequest {
  const createdAt =
    data.createdAt instanceof Date
      ? data.createdAt
      : new Date("2026-06-09T12:00:00.000Z");
  return {
    id: String(data.id),
    companyId: String(data.companyId),
    activeCompanyGuard:
      data.activeCompanyGuard == null ? null : String(data.activeCompanyGuard),
    status: (data.status ??
      "REQUESTED") as TenantDeletionPersistedRequest["status"],
    requestedByAdminUserId:
      data.requestedByAdminUserId == null
        ? null
        : String(data.requestedByAdminUserId),
    requestedByEmail:
      data.requestedByEmail == null ? null : String(data.requestedByEmail),
    requestedCompanyNameSnapshot: String(data.requestedCompanyNameSnapshot),
    source: String(data.source),
    reason: String(data.reason),
    identityStatus: (data.identityStatus ??
      "NOT_STARTED") as TenantDeletionPersistedRequest["identityStatus"],
    identityVerifiedByAdminUserId: null,
    identityVerifiedAt: null,
    identityVerificationNotes: null,
    dryRunSnapshotJson: null,
    dryRunGeneratedAt: null,
    cancelledByAdminUserId: null,
    cancelledAt: null,
    cancellationReason: null,
    rejectedByAdminUserId: null,
    rejectedAt: null,
    rejectionReason: null,
    executionPlanJson: null,
    executionProgressJson: null,
    executionReceiptJson: null,
    executionStartedAt: null,
    executionCompletedAt: null,
    executionAttemptId: null,
    executionLockedAt: null,
    executedByAdminUserId: null,
    createdAt,
    updatedAt: data.updatedAt instanceof Date ? data.updatedAt : createdAt,
    company,
    auditEvents: [],
  };
}

function companyFixture() {
  return {
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
}
