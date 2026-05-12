import assert from "node:assert/strict";
import { after, before, beforeEach, describe, it } from "node:test";
import type { AddressInfo } from "node:net";
import type { Server } from "http";

import jwt from "jsonwebtoken";

import { createApp } from "../../app";
import { env } from "../../config/env";
import { prisma } from "../../database/prisma";

const runId = `admin-sync-center-${Date.now()}`;

let server: Server;
let apiBaseUrl = "";

describe("admin sync center routes", () => {
  before(async () => {
    await prisma.$connect();
    server = createApp().listen(0);
    const address = server.address() as AddressInfo;
    apiBaseUrl = `http://127.0.0.1:${address.port}/api`;
  });

  beforeEach(async () => {
    await cleanupFixtures();
  });

  after(async () => {
    await cleanupFixtures();
    await new Promise<void>((resolve, reject) => {
      server.close((error) => (error == null ? resolve() : reject(error)));
    });
    await prisma.$disconnect();
  });

  it("requires platform admin auth for sync center routes", async () => {
    const fixture = await createFixture();

    const unauthenticated = await requestJson("GET", "/admin/sync/companies");
    assert.equal(unauthenticated.status, 401);

    const forbidden = await requestJson("GET", "/admin/sync/companies", {
      token: fixture.operatorToken,
    });
    assert.equal(forbidden.status, 403);
    assert.equal(
      (forbidden.data as { code?: string }).code,
      "PLATFORM_ADMIN_REQUIRED",
    );
  });

  it("lists only companies with sync problems when requires_review is selected", async () => {
    const fixture = await createFixture();

    const response = await requestJson(
      "GET",
      `/admin/sync/companies?search=${encodeURIComponent(runId)}&status=requires_review&page=1&pageSize=10`,
      { token: fixture.adminToken },
    );

    assert.equal(response.status, 200);
    const payload = response.data as {
      items: Array<{
        companyId: string;
        syncStatus: string;
        conflictCount: number;
        failedCount: number;
        openConflictCount: number;
        requiresReview: boolean;
      }>;
      pagination: { total: number };
    };
    assert.equal(payload.pagination.total, 1);
    assert.equal(payload.items[0]?.companyId, fixture.companyId);
    assert.equal(payload.items[0]?.syncStatus, "failed");
    assert.equal(payload.items[0]?.conflictCount, 1);
    assert.equal(payload.items[0]?.failedCount, 2);
    assert.equal(payload.items[0]?.openConflictCount, 1);
    assert.equal(payload.items[0]?.requiresReview, true);
  });

  it("returns company summary counters and safe classified latest events", async () => {
    const fixture = await createFixture();

    const response = await requestJson(
      "GET",
      `/admin/sync/companies/${fixture.companyId}/summary`,
      { token: fixture.adminToken },
    );

    assert.equal(response.status, 200);
    const payload = response.data as {
      eventStatusCounts: {
        accepted: number;
        duplicate: number;
        conflict: number;
        failed: number;
      };
      entityOperationStatusCounts: Array<{
        entity: string;
        operation: string;
        status: string;
        count: number;
      }>;
      conflictCounts: Array<{ code: string; entity: string; count: number }>;
      latestConflicts: Array<{
        classification: string;
        recommendedAction: string;
      }>;
      requiresReview: boolean;
    };

    assert.equal(payload.eventStatusCounts.accepted, 1);
    assert.equal(payload.eventStatusCounts.duplicate, 1);
    assert.equal(payload.eventStatusCounts.conflict, 1);
    assert.equal(payload.eventStatusCounts.failed, 2);
    assert.ok(
      payload.entityOperationStatusCounts.some(
        (item) =>
          item.entity === "stockDeduction" &&
          item.operation === "create" &&
          item.status === "conflict" &&
          item.count === 1,
      ),
    );
    assert.ok(
      payload.conflictCounts.some(
        (item) =>
          item.code === "STOCK_VARIANT_NOT_FOUND" &&
          item.entity === "stockDeduction" &&
          item.count === 1,
      ),
    );
    assert.equal(
      payload.latestConflicts[0]?.classification,
      "IRRECOVERABLE_LEGACY_EVENT",
    );
    assert.equal(
      payload.latestConflicts[0]?.recommendedAction,
      "ARCHIVE_LEGACY",
    );
    assert.equal(payload.requiresReview, true);
  });

  it("lists events and conflicts with safe previews isolated by company", async () => {
    const fixture = await createFixture();

    const events = await requestJson(
      "GET",
      `/admin/sync/companies/${fixture.companyId}/events?page=1&pageSize=10`,
      { token: fixture.adminToken },
    );
    const conflicts = await requestJson(
      "GET",
      `/admin/sync/companies/${fixture.companyId}/conflicts?page=1&pageSize=10`,
      { token: fixture.adminToken },
    );
    const healthyEvents = await requestJson(
      "GET",
      `/admin/sync/companies/${fixture.healthyCompanyId}/events?page=1&pageSize=10`,
      { token: fixture.adminToken },
    );
    const wrongCompanyDetail = await requestJson(
      "GET",
      `/admin/sync/events/${fixture.legacyEventId}?companyId=${fixture.healthyCompanyId}`,
      { token: fixture.adminToken },
    );

    assert.equal(events.status, 200);
    assert.equal(conflicts.status, 200);
    assert.equal(healthyEvents.status, 200);
    assert.equal(wrongCompanyDetail.status, 404);

    const eventsPayload = events.data as {
      items: Array<{
        id: string;
        relatedConflictId: string | null;
        classification: string;
        safePayloadPreview: Record<string, unknown>;
      }>;
      pagination: { total: number };
    };
    const conflictsPayload = conflicts.data as {
      items: Array<{
        conflictId: string;
        classification: string;
        safePayloadPreview: Record<string, unknown>;
      }>;
      pagination: { total: number };
    };
    const healthyEventsPayload = healthyEvents.data as {
      items: Array<{ id: string; entity: string }>;
      pagination: { total: number };
    };

    assert.equal(eventsPayload.pagination.total, 5);
    assert.ok(
      eventsPayload.items.some(
        (item) =>
          item.id === fixture.legacyEventId &&
          item.relatedConflictId === fixture.legacyConflictId &&
          item.classification === "IRRECOVERABLE_LEGACY_EVENT" &&
          item.safePayloadPreview.productId === 5,
      ),
    );
    assert.ok(
      eventsPayload.items.some(
        (item) =>
          item.id === fixture.sensitiveEventId &&
          item.classification === "DANGEROUS",
      ),
    );
    assert.equal(conflictsPayload.pagination.total, 1);
    assert.equal(
      conflictsPayload.items[0]?.classification,
      "IRRECOVERABLE_LEGACY_EVENT",
    );
    assert.equal(conflictsPayload.items[0]?.safePayloadPreview.productId, 5);
    assert.equal(healthyEventsPayload.pagination.total, 1);
    assert.equal(healthyEventsPayload.items[0]?.entity, "sale");
    assert.doesNotMatch(JSON.stringify(events.data), /Bearer secret-token/);
    assert.doesNotMatch(JSON.stringify(events.data), /api-key-secret/);
    assert.doesNotMatch(JSON.stringify(events.data), /url-token-secret/);
  });

  it("classifies cafe oliveira legacy stockDeduction as not automatically reprocessable", async () => {
    const fixture = await createFixture();

    const response = await requestJson(
      "GET",
      `/admin/sync/conflicts/${fixture.legacyConflictId}?companyId=${fixture.companyId}`,
      { token: fixture.adminToken },
    );

    assert.equal(response.status, 200);
    const payload = response.data as {
      classification: string;
      recommendedAction: string;
      canReprocess: boolean;
      canArchive: boolean;
      message: string;
      event: { safePayloadPreview: Record<string, unknown> };
    };

    assert.equal(payload.classification, "IRRECOVERABLE_LEGACY_EVENT");
    assert.equal(payload.recommendedAction, "ARCHIVE_LEGACY");
    assert.equal(payload.canReprocess, false);
    assert.equal(payload.canArchive, true);
    assert.match(
      payload.message,
      /Evento antigo sem identificacao remota segura/,
    );
    assert.equal(payload.event.safePayloadPreview.productId, 5);
    assert.equal(payload.event.safePayloadPreview.productVariantId, null);
  });

  it("classifies stockDeduction remote identities without unsafe local-id fallback", async () => {
    const fixture = await createFixture();
    const productWithoutVariants = await createProduct(fixture, {
      name: "Produto simples remoto",
      stockMil: 100000,
    });
    const productWithVariants = await createProduct(fixture, {
      name: "Produto com variante remota",
      stockMil: 100000,
    });
    const variant = await createProductVariant(productWithVariants, {
      stockMil: 50000,
    });

    const validVariantEvent = await createStockDiagnosticEvent(fixture, {
      productId: productWithVariants.id,
      productVariantId: variant.id,
    });
    const validProductEvent = await createStockDiagnosticEvent(fixture, {
      productId: productWithoutVariants.id,
      productVariantId: null,
    });
    const missingVariantEvent = await createStockDiagnosticEvent(fixture, {
      productId: productWithVariants.id,
      productVariantId: null,
    });
    const missingRemoteEvent = await createStockDiagnosticEvent(fixture, {
      productId: "11111111-1111-4111-8111-111111111111",
      productVariantId: null,
    });

    const validVariant = await getEventDiagnostic(
      fixture,
      validVariantEvent.id,
    );
    const validProduct = await getEventDiagnostic(
      fixture,
      validProductEvent.id,
    );
    const missingVariant = await getEventDiagnostic(
      fixture,
      missingVariantEvent.id,
    );
    const missingRemote = await getEventDiagnostic(
      fixture,
      missingRemoteEvent.id,
    );

    assert.equal(validVariant.classification, "REPROCESSABLE");
    assert.equal(validVariant.canReprocess, true);
    assert.equal(validProduct.classification, "REPROCESSABLE");
    assert.equal(validProduct.canReprocess, true);
    assert.equal(missingVariant.classification, "NEEDS_PRODUCT_MAPPING");
    assert.equal(missingVariant.canReprocess, false);
    assert.equal(missingRemote.classification, "NEEDS_PRODUCT_MAPPING");
    assert.equal(missingRemote.canReprocess, false);
  });

  it("classifies old cashSession update failure as reprocessable", async () => {
    const fixture = await createFixture();

    const response = await requestJson(
      "GET",
      `/admin/sync/events/${fixture.cashSessionEventId}?companyId=${fixture.companyId}`,
      { token: fixture.adminToken },
    );

    assert.equal(response.status, 200);
    const payload = response.data as {
      classification: string;
      recommendedAction: string;
      canReprocess: boolean;
      event: { safePayloadPreview: Record<string, unknown> };
    };
    assert.equal(payload.classification, "REPROCESSABLE");
    assert.equal(payload.recommendedAction, "REPROCESS");
    assert.equal(payload.canReprocess, true);
    assert.equal(payload.event.safePayloadPreview.status, "aberto");
    assert.equal(payload.event.safePayloadPreview.expectedBalanceCents, 130400);
  });

  it("sanitizes payloads and blocks sensitive events as dangerous", async () => {
    const fixture = await createFixture();

    const response = await requestJson(
      "GET",
      `/admin/sync/events/${fixture.sensitiveEventId}?companyId=${fixture.companyId}`,
      { token: fixture.adminToken },
    );

    assert.equal(response.status, 200);
    const serialized = JSON.stringify(response.data);
    const payload = response.data as { classification: string };
    assert.equal(payload.classification, "DANGEROUS");
    assert.match(serialized, /\[redacted\]/);
    assert.doesNotMatch(serialized, /Bearer secret-token/);
    assert.doesNotMatch(serialized, /api-key-secret/);
    assert.doesNotMatch(serialized, /url-token-secret/);
  });

  it("dry-run does not change events or conflicts", async () => {
    const fixture = await createFixture();

    const before = await readEventAndConflictState(fixture);
    const response = await requestJson(
      "POST",
      `/admin/sync/events/${fixture.legacyEventId}/reprocess-dry-run`,
      {
        token: fixture.adminToken,
        body: {
          companyId: fixture.companyId,
          reason: "avaliar sem alterar",
        },
      },
    );
    const after = await readEventAndConflictState(fixture);

    assert.equal(response.status, 200);
    assert.equal(
      (response.data as { wouldReprocess: boolean }).wouldReprocess,
      false,
    );
    assert.deepEqual(after, before);
  });

  it("requires companyId, reason and confirmationText for write actions", async () => {
    const fixture = await createFixture();

    const missingCompany = await requestJson(
      "POST",
      `/admin/sync/events/${fixture.legacyEventId}/reprocess-dry-run`,
      { token: fixture.adminToken, body: { reason: "sem company" } },
    );
    assert.equal(missingCompany.status, 422);

    const missingReason = await requestJson(
      "POST",
      `/admin/sync/events/${fixture.legacyEventId}/reprocess`,
      {
        token: fixture.adminToken,
        body: {
          companyId: fixture.companyId,
          confirmationText: "REPROCESSAR",
        },
      },
    );
    assert.equal(missingReason.status, 422);

    const missingConfirmation = await requestJson(
      "POST",
      `/admin/sync/conflicts/${fixture.legacyConflictId}/archive`,
      {
        token: fixture.adminToken,
        body: {
          companyId: fixture.companyId,
          reason: "arquivar legado",
        },
      },
    );
    assert.equal(missingConfirmation.status, 422);
  });

  it("blocks reprocess for irrecoverable legacy stock events", async () => {
    const fixture = await createFixture();

    const response = await requestJson(
      "POST",
      `/admin/sync/events/${fixture.legacyEventId}/reprocess`,
      {
        token: fixture.adminToken,
        body: {
          companyId: fixture.companyId,
          reason: "nao deve reprocessar legado",
          confirmationText: "REPROCESSAR",
        },
      },
    );

    assert.equal(response.status, 409);
    assert.equal(
      (response.data as { code?: string }).code,
      "SYNC_REPROCESS_BLOCKED",
    );
    const event = await prisma.syncEvent.findUniqueOrThrow({
      where: { id: fixture.legacyEventId },
    });
    assert.equal(event.status, "CONFLICT");
  });

  it("reprocesses safe cashSession update and records audit", async () => {
    const fixture = await createFixture();

    const response = await requestJson(
      "POST",
      `/admin/sync/events/${fixture.cashSessionEventId}/reprocess`,
      {
        token: fixture.adminToken,
        body: {
          companyId: fixture.companyId,
          reason: "corrigir falha antiga de caixa",
          confirmationText: "REPROCESSAR",
        },
      },
    );

    assert.equal(response.status, 200);
    const [event, cashSession, audit] = await Promise.all([
      prisma.syncEvent.findUniqueOrThrow({
        where: { id: fixture.cashSessionEventId },
      }),
      prisma.cashSession.findUniqueOrThrow({
        where: {
          companyId_localUuid: {
            companyId: fixture.companyId,
            localUuid: "1778110868189821-7df2cc20",
          },
        },
      }),
      prisma.adminAuditLog.findFirstOrThrow({
        where: {
          targetCompanyId: fixture.companyId,
          action: "sync.event.reprocess",
        },
      }),
    ]);

    assert.equal(event.status, "ACCEPTED");
    assert.equal(event.rejectionCode, null);
    assert.equal(cashSession.status, "open");
    assert.equal(cashSession.expectedBalanceCents, 130400);
    assert.match(JSON.stringify(audit.details), /corrigir falha antiga/);
  });

  it("archives legacy conflicts without deleting events and records resolution/audit", async () => {
    const fixture = await createFixture();

    const dryRun = await requestJson(
      "POST",
      `/admin/sync/conflicts/${fixture.legacyConflictId}/archive-dry-run`,
      {
        token: fixture.adminToken,
        body: {
          companyId: fixture.companyId,
          reason: "avaliar arquivamento",
        },
      },
    );
    assert.equal(dryRun.status, 200);
    assert.equal((dryRun.data as { wouldArchive: boolean }).wouldArchive, true);

    const response = await requestJson(
      "POST",
      `/admin/sync/conflicts/${fixture.legacyConflictId}/archive`,
      {
        token: fixture.adminToken,
        body: {
          companyId: fixture.companyId,
          reason: "evento legado de teste",
          confirmationText: "ARQUIVAR",
          note: "revisado pelo suporte",
        },
      },
    );

    assert.equal(response.status, 200);
    const [conflict, event, incident, audit] = await Promise.all([
      prisma.syncConflict.findUniqueOrThrow({
        where: { id: fixture.legacyConflictId },
      }),
      prisma.syncEvent.findUniqueOrThrow({
        where: { id: fixture.legacyEventId },
      }),
      prisma.syncIncident.findUniqueOrThrow({
        where: { id: fixture.legacyIncidentId },
      }),
      prisma.adminAuditLog.findFirstOrThrow({
        where: {
          targetCompanyId: fixture.companyId,
          action: "sync.conflict.archive",
        },
      }),
    ]);
    assert.equal(conflict.status, "RESOLVED");
    assert.equal(event.status, "CONFLICT");
    assert.equal(incident.syncEventId, fixture.legacyEventId);
    assert.match(JSON.stringify(conflict.resolution), /admin_sync_center/);
    assert.match(JSON.stringify(conflict.resolution), /evento legado de teste/);
    assert.match(JSON.stringify(audit.details), /SyncConflict/);
  });

  it("keeps manual stock adjustment write disabled when no audited mechanism exists", async () => {
    const fixture = await createFixture();

    const dryRun = await requestJson(
      "POST",
      `/admin/sync/conflicts/${fixture.legacyConflictId}/manual-stock-adjustment-dry-run`,
      {
        token: fixture.adminToken,
        body: {
          companyId: fixture.companyId,
          reason: "avaliar ajuste",
        },
      },
    );
    assert.equal(dryRun.status, 200);
    assert.equal(
      (dryRun.data as { canCreateManualStockAdjustment: boolean })
        .canCreateManualStockAdjustment,
      false,
    );

    const write = await requestJson(
      "POST",
      `/admin/sync/conflicts/${fixture.legacyConflictId}/manual-stock-adjustment`,
      {
        token: fixture.adminToken,
        body: {
          companyId: fixture.companyId,
          reason: "ajuste",
          confirmationText: "AJUSTAR_ESTOQUE",
          productId: "11111111-1111-4111-8111-111111111111",
          quantityDeltaMil: -1000,
        },
      },
    );
    assert.equal(write.status, 501);
    assert.equal(
      (write.data as { code?: string }).code,
      "MANUAL_STOCK_ADJUSTMENT_NOT_IMPLEMENTED",
    );
  });
});

async function createFixture() {
  const now = new Date();
  const company = await prisma.company.create({
    data: {
      name: `${runId} cafe oliveira`,
      legalName: `${runId} cafe oliveira LTDA`,
      slug: `${runId}-cafe-${Date.now()}-${Math.random()
        .toString(16)
        .slice(2)}`,
    },
  });
  const healthyCompany = await prisma.company.create({
    data: {
      name: `${runId} healthy`,
      legalName: `${runId} healthy LTDA`,
      slug: `${runId}-healthy-${Date.now()}-${Math.random()
        .toString(16)
        .slice(2)}`,
    },
  });
  const adminUser = await prisma.user.create({
    data: {
      email: `${runId}-admin-${Date.now()}@tatuzin.test`,
      name: "Sync Center Admin",
      passwordHash: "not-used",
      isPlatformAdmin: true,
    },
  });
  const operatorUser = await prisma.user.create({
    data: {
      email: `${runId}-operator-${Date.now()}@tatuzin.test`,
      name: "Operador local",
      passwordHash: "not-used",
      isPlatformAdmin: false,
    },
  });
  const adminMembership = await prisma.membership.create({
    data: {
      companyId: company.id,
      userId: adminUser.id,
      role: "OWNER",
      isDefault: true,
    },
  });
  const operatorMembership = await prisma.membership.create({
    data: {
      companyId: company.id,
      userId: operatorUser.id,
      role: "OPERATOR",
      isDefault: true,
    },
  });
  await prisma.license.create({
    data: {
      companyId: company.id,
      plan: "PRO",
      status: "ACTIVE",
      startsAt: now,
      maxDevices: 5,
      syncEnabled: true,
    },
  });
  await prisma.license.create({
    data: {
      companyId: healthyCompany.id,
      plan: "PRO",
      status: "ACTIVE",
      startsAt: now,
      maxDevices: 5,
      syncEnabled: true,
    },
  });
  await prisma.companySyncState.create({
    data: {
      companyId: company.id,
      currentVersion: 25n,
      serverFirstSnapshotVersion: 0n,
      updatedAt: now,
    },
  });
  await prisma.companySyncState.create({
    data: {
      companyId: healthyCompany.id,
      currentVersion: 1n,
      serverFirstSnapshotVersion: 0n,
      updatedAt: now,
    },
  });
  const device = await prisma.companyDevice.create({
    data: {
      companyId: company.id,
      userId: operatorUser.id,
      clientInstanceId: `${runId}-pdv`,
      deviceLabel: "PDV cafe oliveira",
      platform: "android",
      appVersion: "2.0.0",
      status: "ACTIVE",
      approvedAt: now,
      approvedByUserId: adminUser.id,
      lastSeenAt: now,
    },
  });
  const healthyDevice = await prisma.companyDevice.create({
    data: {
      companyId: healthyCompany.id,
      userId: operatorUser.id,
      clientInstanceId: `${runId}-healthy-pdv`,
      deviceLabel: "PDV healthy",
      status: "ACTIVE",
      approvedAt: now,
      approvedByUserId: adminUser.id,
    },
  });

  await prisma.syncEvent.create({
    data: {
      companyId: healthyCompany.id,
      deviceId: healthyDevice.id,
      userId: operatorUser.id,
      eventId: `${runId}-healthy-sale`,
      feature: "pdv",
      entity: "sale",
      operation: "create",
      entityLocalId: `${runId}-healthy-sale`,
      occurredAt: now,
      payload: { totalCents: 1000 },
      status: "ACCEPTED",
      serverVersion: 1n,
      materializedAt: now,
    },
  });
  await prisma.syncEvent.create({
    data: {
      companyId: company.id,
      deviceId: device.id,
      userId: operatorUser.id,
      eventId: `${runId}-sale-accepted`,
      feature: "pdv",
      entity: "sale",
      operation: "create",
      entityLocalId: `${runId}-sale-accepted`,
      occurredAt: now,
      payload: { totalCents: 1000 },
      status: "ACCEPTED",
      serverVersion: 17n,
      materializedAt: now,
    },
  });
  await prisma.syncEvent.create({
    data: {
      companyId: company.id,
      deviceId: device.id,
      userId: operatorUser.id,
      eventId: `${runId}-receipt-duplicate`,
      feature: "pdv",
      entity: "receipt",
      operation: "create",
      entityLocalId: `${runId}-receipt-duplicate`,
      occurredAt: now,
      payload: { receiptNumber: "R-1" },
      status: "DUPLICATE",
    },
  });
  const legacyEvent = await prisma.syncEvent.create({
    data: {
      companyId: company.id,
      deviceId: device.id,
      userId: operatorUser.id,
      eventId: `${runId}-legacy-stock`,
      feature: "pdv",
      entity: "stockDeduction",
      operation: "create",
      entityLocalId: "1778111101212016-10299ac7:5:0",
      occurredAt: now,
      payload: {
        saleUuid: "1778111101212016-10299ac7",
        saleLocalId: 23,
        productId: 5,
        productVariantId: null,
        quantityDeltaMil: -21000,
        stockBeforeMil: 200000,
        stockAfterMil: 179000,
        occurredAt: "2026-05-06T20:45:01.211999",
      },
      status: "CONFLICT",
      serverVersion: 25n,
    },
  });
  const legacyConflict = await prisma.syncConflict.create({
    data: {
      companyId: company.id,
      deviceId: device.id,
      userId: operatorUser.id,
      syncEventId: legacyEvent.id,
      entity: "stockDeduction",
      entityLocalId: legacyEvent.entityLocalId,
      code: "STOCK_VARIANT_NOT_FOUND",
      message:
        "Produto/variante remoto nao encontrado para estoque operacional.",
      payload: {
        saleUuid: "1778111101212016-10299ac7",
        saleLocalId: 23,
        productId: 5,
        productVariantId: null,
        quantityDeltaMil: -21000,
        stockBeforeMil: 200000,
        stockAfterMil: 179000,
        occurredAt: "2026-05-06T20:45:01.211999",
      },
    },
  });
  const legacyIncident = await prisma.syncIncident.create({
    data: {
      companyId: company.id,
      deviceId: device.id,
      userId: operatorUser.id,
      syncEventId: legacyEvent.id,
      code: "SYNC_CONFLICT_CREATED",
      message: "Conflito legado criado para revisao.",
      severity: "warn",
      details: { source: "admin_sync_center_test" },
    },
  });
  const cashSessionEvent = await prisma.syncEvent.create({
    data: {
      companyId: company.id,
      deviceId: device.id,
      userId: operatorUser.id,
      eventId: `${runId}-cash-session-failed`,
      feature: "cash",
      entity: "cashSession",
      operation: "update",
      entityLocalId: "1778110868189821-7df2cc20",
      occurredAt: now,
      payload: {
        uuid: "1778110868189821-7df2cc20",
        status: "aberto",
        localId: 3,
        closedAt: null,
        openedAt: "2026-05-06T20:41:08.169407Z",
        operatorName: "Operador local",
        expectedBalanceCents: 130400,
        initialFloatCents: 0,
        countedBalanceCents: null,
        differenceCents: null,
      },
      status: "FAILED",
      rejectionCode: "SYNC_MATERIALIZATION_FAILED",
      rejectionMessage: "Falha inesperada ao materializar evento operacional.",
    },
  });
  const sensitiveEvent = await prisma.syncEvent.create({
    data: {
      companyId: company.id,
      deviceId: device.id,
      userId: operatorUser.id,
      eventId: `${runId}-sensitive-failed`,
      feature: "pdv",
      entity: "payment",
      operation: "create",
      entityLocalId: `${runId}-sensitive-payment`,
      occurredAt: now,
      payload: {
        amountCents: 1000,
        headers: { authorization: "Bearer secret-token" },
        apiKey: "api-key-secret",
        callbackUrl:
          "https://payments.example.test/return?token=url-token-secret",
      },
      status: "FAILED",
      rejectionCode: "SYNC_MATERIALIZATION_FAILED",
      rejectionMessage: "Falha inesperada.",
    },
  });

  return {
    companyId: company.id,
    healthyCompanyId: healthyCompany.id,
    adminToken: signToken({
      userId: adminUser.id,
      companyId: company.id,
      membershipId: adminMembership.id,
      email: adminUser.email,
      isPlatformAdmin: true,
    }),
    operatorToken: signToken({
      userId: operatorUser.id,
      companyId: company.id,
      membershipId: operatorMembership.id,
      email: operatorUser.email,
      isPlatformAdmin: false,
    }),
    legacyEventId: legacyEvent.id,
    legacyConflictId: legacyConflict.id,
    legacyIncidentId: legacyIncident.id,
    cashSessionEventId: cashSessionEvent.id,
    sensitiveEventId: sensitiveEvent.id,
    deviceId: device.id,
    operatorUserId: operatorUser.id,
  };
}

async function createProduct(
  fixture: { companyId: string },
  options: { name: string; stockMil?: number },
) {
  return prisma.product.create({
    data: {
      companyId: fixture.companyId,
      localUuid: `${runId}-product-${Date.now()}-${Math.random()
        .toString(16)
        .slice(2)}`,
      name: options.name,
      salePriceCents: 1000,
      stockMil: options.stockMil ?? 0,
    },
  });
}

async function createProductVariant(
  product: { id: string },
  options?: { stockMil?: number },
) {
  return prisma.productVariant.create({
    data: {
      productId: product.id,
      sku: `${runId}-variant-${Date.now()}-${Math.random()
        .toString(16)
        .slice(2)}`,
      colorLabel: "Padrao",
      sizeLabel: "Unico",
      stockMil: options?.stockMil ?? 0,
      isActive: true,
    },
  });
}

async function createStockDiagnosticEvent(
  fixture: { companyId: string; deviceId: string; operatorUserId: string },
  payload: { productId: string; productVariantId: string | null },
) {
  return prisma.syncEvent.create({
    data: {
      companyId: fixture.companyId,
      deviceId: fixture.deviceId,
      userId: fixture.operatorUserId,
      eventId: `${runId}-stock-${Date.now()}-${Math.random()
        .toString(16)
        .slice(2)}`,
      feature: "pdv",
      entity: "stockDeduction",
      operation: "create",
      entityLocalId: `${runId}-stock-local`,
      occurredAt: new Date(),
      payload: {
        saleUuid: `${runId}-sale`,
        saleLocalId: 42,
        productId: payload.productId,
        productVariantId: payload.productVariantId,
        quantityDeltaMil: -1000,
        stockBeforeMil: 100000,
        stockAfterMil: 99000,
        occurredAt: "2026-05-06T20:45:01.211999",
      },
      status: "FAILED",
      rejectionCode: "STOCK_VARIANT_NOT_FOUND",
      rejectionMessage: "Produto/variante remoto nao encontrado.",
    },
  });
}

async function getEventDiagnostic(
  fixture: { companyId: string; adminToken: string },
  eventId: string,
) {
  const response = await requestJson(
    "GET",
    `/admin/sync/events/${eventId}?companyId=${fixture.companyId}`,
    { token: fixture.adminToken },
  );
  assert.equal(response.status, 200);
  return response.data as {
    classification: string;
    recommendedAction: string;
    canReprocess: boolean;
  };
}

function signToken(input: {
  userId: string;
  companyId: string;
  membershipId: string;
  email: string;
  isPlatformAdmin: boolean;
}) {
  return jwt.sign(
    {
      sub: input.userId,
      companyId: input.companyId,
      membershipId: input.membershipId,
      membershipRole: "OWNER",
      email: input.email,
      isPlatformAdmin: input.isPlatformAdmin,
    },
    env.JWT_SECRET,
    { expiresIn: "15m" },
  );
}

async function requestJson(
  method: string,
  path: string,
  options?: { token?: string; body?: unknown },
) {
  const response = await fetch(`${apiBaseUrl}${path}`, {
    method,
    headers: {
      ...(options?.token == null
        ? {}
        : { Authorization: `Bearer ${options.token}` }),
      ...(options?.body === undefined
        ? {}
        : { "Content-Type": "application/json" }),
    },
    body:
      options?.body === undefined ? undefined : JSON.stringify(options.body),
  });
  const rawBody = await response.text();
  return {
    status: response.status,
    data: rawBody.trim().length === 0 ? null : JSON.parse(rawBody),
  };
}

async function readEventAndConflictState(input: {
  legacyEventId: string;
  legacyConflictId: string;
}) {
  const [event, conflict, auditCount] = await Promise.all([
    prisma.syncEvent.findUniqueOrThrow({ where: { id: input.legacyEventId } }),
    prisma.syncConflict.findUniqueOrThrow({
      where: { id: input.legacyConflictId },
    }),
    prisma.adminAuditLog.count(),
  ]);
  return {
    eventStatus: event.status,
    eventRejectionCode: event.rejectionCode,
    conflictStatus: conflict.status,
    conflictResolution: conflict.resolution,
    auditCount,
  };
}

async function cleanupFixtures() {
  await prisma.adminAuditLog.deleteMany({
    where: {
      actorUser: {
        email: {
          startsWith: `${runId}-`,
        },
      },
    },
  });
  await prisma.company.deleteMany({
    where: {
      slug: {
        startsWith: `${runId}-`,
      },
    },
  });
  await prisma.user.deleteMany({
    where: {
      email: {
        startsWith: `${runId}-`,
      },
    },
  });
}
