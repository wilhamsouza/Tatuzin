import assert from "node:assert/strict";
import { after, before, beforeEach, describe, it } from "node:test";
import type { AddressInfo } from "node:net";

import type { Server } from "http";
import jwt from "jsonwebtoken";

import { createApp } from "../../app";
import { env } from "../../config/env";
import { prisma } from "../../database/prisma";

const runId = `sync-real-${Date.now()}`;

let server: Server;
let apiBaseUrl = "";

type PullResponse = {
  hasMore: boolean;
  nextSinceVersion: string;
  events: PullChange[];
  changes: PullChange[];
};

type PullChange = {
  eventId: string;
  entity: string;
  entityServerId: string | null;
  projection: Record<string, any> | null;
  projectionWarning: string | null;
};

describe("operational local-first sync routes", () => {
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

  it("rejects push without app context", async () => {
    const response = await requestJson("POST", "/sync/push", {
      body: { events: [] },
    });

    assert.equal(response.status, 401);
    assert.equal((response.data as { code?: string }).code, "AUTH_REQUIRED");
  });

  it("rejects push when sync is disabled by license", async () => {
    const fixture = await createFixture({ syncEnabled: false });
    const response = await push(fixture, [buildEvent("sale-disabled", "sale")]);

    assert.equal(response.status, 403);
    assert.equal((response.data as { code?: string }).code, "SYNC_DISABLED");
  });

  it("delivers support commands with app context even when sync is disabled", async () => {
    const fixture = await createFixture({ syncEnabled: false });
    const command = await prisma.syncSupportCommand.create({
      data: {
        companyId: fixture.companyId,
        deviceId: fixture.deviceId,
        actorUserId: fixture.userId,
        command: "REFRESH_SYNC_STATUS",
        reason: "recalcular status local mesmo com sync bloqueado",
        confirmationText: "RECALCULAR",
        expiresAt: new Date(Date.now() + 60_000),
      },
    });

    const pull = await requestJson("GET", "/sync/support-commands", {
      token: fixture.token,
    });
    const started = await requestJson(
      "POST",
      `/sync/support-commands/${command.id}/start`,
      { token: fixture.token },
    );

    assert.equal(pull.status, 200);
    assert.deepEqual(
      (
        pull.data as {
          items: Array<{ id: string; command: string; status: string }>;
        }
      ).items.map((item) => [item.id, item.command, item.status]),
      [[command.id, "REFRESH_SYNC_STATUS", "PENDING"]],
    );
    assert.equal(started.status, 200);
    assert.equal(
      (started.data as { command: { status: string } }).command.status,
      "RUNNING",
    );
  });

  it("accepts valid sale and cashSession events", async () => {
    const fixture = await createFixture();
    const response = await push(fixture, [
      buildEvent("sale-accepted", "sale", {
        entityLocalId: `${runId}-sale-local`,
        payload: { status: "finalized", totalCents: 4500 },
      }),
      buildEvent("cash-session-accepted", "cashSession", {
        feature: "cash",
        entityLocalId: `${runId}-cash-session`,
        payload: { status: "open", openedAt: new Date().toISOString() },
      }),
    ]);

    assert.equal(response.status, 202);
    const payload = response.data as {
      accepted: Array<{
        eventId: string;
        serverVersion: string;
        entityServerId: string | null;
      }>;
      summary: { accepted: number };
    };
    assert.equal(payload.summary.accepted, 2);
    assert.deepEqual(
      payload.accepted.map((item) => item.eventId),
      ["sale-accepted", "cash-session-accepted"],
    );
    assert.ok(payload.accepted.every((item) => item.entityServerId != null));

    const persisted = await prisma.syncEvent.findMany({
      where: { companyId: fixture.companyId, status: "ACCEPTED" },
      orderBy: { serverVersion: "asc" },
    });
    assert.equal(persisted.length, 2);
    assert.equal(persisted[0]?.serverVersion?.toString(), "1");
    assert.equal(persisted[1]?.serverVersion?.toString(), "2");

    const [salesCount, cashSessionsCount] = await Promise.all([
      prisma.sale.count({ where: { companyId: fixture.companyId } }),
      prisma.cashSession.count({ where: { companyId: fixture.companyId } }),
    ]);
    assert.equal(salesCount, 1);
    assert.equal(cashSessionsCount, 1);
  });

  it("returns duplicates without processing the same event twice", async () => {
    const fixture = await createFixture();
    const event = buildEvent("sale-duplicate", "sale");
    const first = await push(fixture, [event]);
    assert.equal(first.status, 202);

    const second = await push(fixture, [event]);

    assert.equal(second.status, 202);
    const payload = second.data as {
      duplicates: Array<{ eventId: string }>;
      summary: { duplicates: number };
    };
    assert.equal(payload.summary.duplicates, 1);
    assert.equal(payload.duplicates[0]?.eventId, "sale-duplicate");

    const count = await prisma.syncEvent.count({
      where: {
        companyId: fixture.companyId,
        eventId: "sale-duplicate",
      },
    });
    assert.equal(count, 1);
  });

  it("rejects server-first entities sent to sync push", async () => {
    const fixture = await createFixture();
    const response = await push(fixture, [
      buildEvent("product-rejected", "product"),
      buildEvent("customer-rejected", "customer"),
      buildEvent("supplier-rejected", "supplier"),
      buildEvent("purchase-rejected", "purchase"),
      buildEvent("cost-rejected", "cost"),
      buildEvent("report-rejected", "report"),
      buildEvent("fiado-rejected", "fiado"),
    ]);

    assert.equal(response.status, 202);
    const payload = response.data as {
      rejected: Array<{ eventId: string; code: string }>;
      summary: { rejected: number };
    };
    assert.equal(payload.summary.rejected, 7);
    assert.deepEqual(
      payload.rejected.map((item) => [item.eventId, item.code]),
      [
        ["product-rejected", "ENTITY_NOT_LOCAL_FIRST"],
        ["customer-rejected", "ENTITY_NOT_LOCAL_FIRST"],
        ["supplier-rejected", "ENTITY_NOT_LOCAL_FIRST"],
        ["purchase-rejected", "ENTITY_NOT_LOCAL_FIRST"],
        ["cost-rejected", "ENTITY_NOT_LOCAL_FIRST"],
        ["report-rejected", "ENTITY_NOT_LOCAL_FIRST"],
        ["fiado-rejected", "ENTITY_NOT_LOCAL_FIRST"],
      ],
    );
  });

  it("rejects invalid operations with INVALID_OPERATION", async () => {
    const fixture = await createFixture();
    const response = await push(fixture, [
      buildEvent("sale-invalid-operation", "sale", {
        operation: "merge",
      }),
    ]);

    assert.equal(response.status, 202);
    const rejected = (
      response.data as {
        rejected: Array<{ code: string }>;
      }
    ).rejected;
    assert.equal(rejected[0]?.code, "INVALID_OPERATION");
  });

  it("creates a conflict when a finalized sale receives an update", async () => {
    const fixture = await createFixture();
    const entityLocalId = `${runId}-finalized-sale`;
    const createSale = await push(fixture, [
      buildEvent("sale-finalized-create", "sale", {
        entityLocalId,
        payload: { status: "finalized", totalCents: 9900 },
      }),
    ]);
    assert.equal(createSale.status, 202);

    const updateSale = await push(fixture, [
      buildEvent("sale-finalized-update", "sale", {
        operation: "update",
        entityLocalId,
        payload: { status: "finalized", totalCents: 8900 },
      }),
    ]);

    assert.equal(updateSale.status, 202);
    const payload = updateSale.data as {
      conflicts: Array<{ code: string; eventId: string }>;
    };
    assert.equal(payload.conflicts[0]?.eventId, "sale-finalized-update");
    assert.equal(payload.conflicts[0]?.code, "SALE_IMMUTABLE");

    const conflict = await prisma.syncConflict.findFirst({
      where: { companyId: fixture.companyId },
    });
    assert.equal(conflict?.status, "OPEN");
  });

  it("materializes cashSession/create without duplicating the domain record", async () => {
    const fixture = await createFixture();
    const entityLocalId = `${runId}-cash-session-domain`;

    const first = await push(fixture, [
      buildEvent("cash-session-domain-create", "cashSession", {
        feature: "cash",
        entityLocalId,
        payload: {
          status: "open",
          openedAt: "2026-05-06T20:41:08.169407Z",
          openingBalanceCents: 1200,
        },
      }),
    ]);
    const second = await push(fixture, [
      buildEvent("cash-session-domain-duplicate", "cashSession", {
        feature: "cash",
        entityLocalId,
        payload: {
          status: "open",
          openedAt: "2026-05-06T20:41:08.169407Z",
          openingBalanceCents: 1200,
        },
      }),
    ]);

    assert.equal(first.status, 202);
    assert.equal(second.status, 202);
    assert.equal(
      (second.data as { summary: { duplicates: number } }).summary.duplicates,
      1,
    );

    const [cashSessionsCount, duplicateEventsCount] = await Promise.all([
      prisma.cashSession.count({ where: { companyId: fixture.companyId } }),
      prisma.syncEvent.count({
        where: { companyId: fixture.companyId, status: "DUPLICATE" },
      }),
    ]);
    assert.equal(cashSessionsCount, 1);
    assert.equal(duplicateEventsCount, 1);
  });

  it("materializes cashSession/create with app localSequence metadata without generic failure", async () => {
    const fixture = await createFixture();
    const entityLocalId = "1778846414191398-2d1accbd";

    const response = await push(fixture, [
      buildEvent("cash-session-app-sequence-create", "cashSession", {
        feature: "pdv",
        entityLocalId,
        payload: {
          localId: 3,
          uuid: entityLocalId,
          status: "aberto",
          openedAt: "2026-05-15T09:00:14.191397",
          closedAt: null,
          operatorName: "wilham",
          initialFloatCents: 0,
          _sync: {
            eventId: "cash-session-app-sequence-create",
            entityLocalId,
            localSequence: 1778846414191398,
            idempotencyKey: "cash-session-app-sequence-create",
          },
        },
      }),
    ]);

    assert.equal(response.status, 202);
    assert.equal(
      (response.data as { summary: { accepted: number; rejected: number } })
        .summary.accepted,
      1,
    );
    assert.equal(
      (response.data as { summary: { accepted: number; rejected: number } })
        .summary.rejected,
      0,
    );

    const [cashSession, failedCount] = await Promise.all([
      prisma.cashSession.findUniqueOrThrow({
        where: {
          companyId_localUuid: {
            companyId: fixture.companyId,
            localUuid: entityLocalId,
          },
        },
      }),
      prisma.syncEvent.count({
        where: {
          companyId: fixture.companyId,
          eventId: "cash-session-app-sequence-create",
          status: "FAILED",
        },
      }),
    ]);

    assert.equal(cashSession.status, "open");
    assert.equal(cashSession.localId, "3");
    assert.equal(cashSession.openingBalanceCents, 0);
    assert.equal(cashSession.lastLocalSequence, null);
    assert.equal(
      (cashSession.payload as Record<string, unknown> | null)?.operatorName,
      "wilham",
    );
    assert.equal(failedCount, 0);
  });

  it("materializes cashSession/update closing cash and blocks reopening", async () => {
    const fixture = await createFixture();
    const entityLocalId = `${runId}-cash-session-close`;
    await push(fixture, [
      buildEvent("cash-session-close-create", "cashSession", {
        feature: "cash",
        entityLocalId,
        payload: {
          status: "open",
          openedAt: "2026-05-06T20:41:08.169407Z",
          openingBalanceCents: 1000,
        },
      }),
    ]);

    const closeResponse = await push(fixture, [
      buildEvent("cash-session-close-update", "cashSession", {
        feature: "cash",
        operation: "update",
        entityLocalId,
        payload: {
          status: "closed",
          countedBalanceCents: 1500,
          expectedBalanceCents: 1400,
          differenceCents: 100,
        },
      }),
    ]);
    assert.equal(closeResponse.status, 202);

    const cashSession = await prisma.cashSession.findUniqueOrThrow({
      where: {
        companyId_localUuid: {
          companyId: fixture.companyId,
          localUuid: entityLocalId,
        },
      },
    });
    assert.equal(cashSession.status, "closed");
    assert.equal(cashSession.closingBalanceCents, 1500);
    assert.equal(cashSession.expectedBalanceCents, 1400);
    assert.equal(
      (cashSession.payload as Record<string, unknown> | null)?.differenceCents,
      100,
    );
    assert.equal(cashSession.lastLocalSequence, null);

    const reopenResponse = await push(fixture, [
      buildEvent("cash-session-reopen-conflict", "cashSession", {
        feature: "cash",
        operation: "update",
        entityLocalId,
        payload: { status: "open" },
      }),
    ]);

    const payload = reopenResponse.data as {
      conflicts: Array<{ code: string }>;
    };
    assert.equal(payload.conflicts[0]?.code, "CASH_SESSION_CLOSED");
  });

  it("does not let a cashier close another employee cash session", async () => {
    const fixture = await createFixture();
    const otherUser = await prisma.user.create({
      data: {
        email: `${runId}-other-cash-${Date.now()}@tatuzin.test`,
        name: "Other Cashier",
        passwordHash: "not-used",
      },
    });
    const cashSession = await prisma.cashSession.create({
      data: {
        companyId: fixture.companyId,
        userId: otherUser.id,
        localUuid: `${runId}-other-cash-session`,
        status: "open",
        openedAt: new Date("2026-05-20T10:00:00.000Z"),
        openingBalanceCents: 1000,
      },
    });

    const response = await push(fixture, [
      buildEvent("cash-session-close-other-forbidden", "cashSession", {
        operation: "update",
        entityLocalId: cashSession.localUuid,
        payload: {
          status: "closed",
          closedAt: new Date("2026-05-20T18:00:00.000Z").toISOString(),
          closingBalanceCents: 1200,
        },
      }),
    ]);

    assert.equal(response.status, 202);
    const payload = response.data as {
      rejected: Array<{ code: string; message: string }>;
      summary: { rejected: number };
    };
    assert.equal(payload.summary.rejected, 1);
    assert.equal(payload.rejected[0]?.code, "CASH_CLOSE_OTHER_FORBIDDEN");
    assert.equal(
      payload.rejected[0]?.message,
      "Voce nao tem permissao para fechar o caixa de outro funcionario.",
    );

    const stored = await prisma.cashSession.findUniqueOrThrow({
      where: { id: cashSession.id },
    });
    assert.equal(stored.status, "open");
    assert.equal(stored.userId, otherUser.id);
  });

  it("lets a cashier close own cash session and OWNER close another user's session", async () => {
    const cashier = await createFixture();
    await push(cashier, [
      buildEvent("cash-session-own-open", "cashSession", {
        entityLocalId: `${runId}-own-cash-session`,
        payload: {
          status: "open",
          openedAt: new Date("2026-05-20T10:00:00.000Z").toISOString(),
          openingBalanceCents: 1000,
        },
      }),
    ]);
    const ownClose = await push(cashier, [
      buildEvent("cash-session-own-close", "cashSession", {
        operation: "update",
        entityLocalId: `${runId}-own-cash-session`,
        payload: {
          status: "closed",
          closedAt: new Date("2026-05-20T18:00:00.000Z").toISOString(),
          closingBalanceCents: 1300,
        },
      }),
    ]);
    assert.equal(ownClose.status, 202);
    assert.equal(
      (ownClose.data as { summary: { accepted: number } }).summary.accepted,
      1,
    );

    const owner = await createFixture({ role: "OWNER" });
    const otherUser = await prisma.user.create({
      data: {
        email: `${runId}-owner-close-other-${Date.now()}@tatuzin.test`,
        name: "Owner Other Cashier",
        passwordHash: "not-used",
      },
    });
    const otherSession = await prisma.cashSession.create({
      data: {
        companyId: owner.companyId,
        userId: otherUser.id,
        localUuid: `${runId}-owner-close-other-session`,
        status: "open",
        openedAt: new Date("2026-05-20T10:00:00.000Z"),
        openingBalanceCents: 1000,
      },
    });

    const ownerClose = await push(owner, [
      buildEvent("cash-session-owner-close-other", "cashSession", {
        operation: "update",
        entityLocalId: otherSession.localUuid,
        payload: {
          status: "closed",
          closedAt: new Date("2026-05-20T18:00:00.000Z").toISOString(),
          closingBalanceCents: 1400,
        },
      }),
    ]);

    assert.equal(ownerClose.status, 202);
    assert.equal(
      (ownerClose.data as { summary: { accepted: number } }).summary.accepted,
      1,
    );
    const stored = await prisma.cashSession.findUniqueOrThrow({
      where: { id: otherSession.id },
    });
    assert.equal(stored.status, "closed");
    assert.equal(stored.userId, otherUser.id);
  });

  it("guards cashSession updates with lastLocalSequence", async () => {
    const fixture = await createFixture();
    const entityLocalId = `${runId}-cash-session-sequence`;
    await push(fixture, [
      buildEvent("cash-session-sequence-create", "cashSession", {
        feature: "cash",
        entityLocalId,
        payload: {
          status: "open",
          openedAt: "2026-05-06T20:41:08.169407Z",
          openingBalanceCents: 1000,
          _sync: { entityLocalId, localSequence: 1 },
        },
      }),
    ]);
    const created = await prisma.cashSession.findUniqueOrThrow({
      where: {
        companyId_localUuid: {
          companyId: fixture.companyId,
          localUuid: entityLocalId,
        },
      },
    });
    assert.equal(created.lastLocalSequence, 1);

    const update = await push(fixture, [
      buildEvent("cash-session-sequence-update-newer", "cashSession", {
        feature: "cash",
        operation: "update",
        entityLocalId,
        payload: {
          status: "open",
          expectedBalanceCents: 1500,
          _sync: { entityLocalId, localSequence: 3 },
        },
      }),
    ]);

    assert.equal(
      (update.data as { summary: { accepted: number } }).summary.accepted,
      1,
    );
    const afterUpdate = await prisma.cashSession.findUniqueOrThrow({
      where: {
        companyId_localUuid: {
          companyId: fixture.companyId,
          localUuid: entityLocalId,
        },
      },
    });
    assert.equal(afterUpdate.expectedBalanceCents, 1500);
    assert.equal(afterUpdate.lastLocalSequence, 3);

    const stale = await push(fixture, [
      buildEvent("cash-session-sequence-update-stale", "cashSession", {
        feature: "cash",
        operation: "update",
        entityLocalId,
        payload: {
          status: "open",
          expectedBalanceCents: 900,
          _sync: { entityLocalId, localSequence: 2 },
        },
      }),
    ]);

    assert.equal(
      (stale.data as { conflicts: Array<{ code: string }> }).conflicts[0]?.code,
      "STALE_LOCAL_SEQUENCE",
    );
    const afterStale = await prisma.cashSession.findUniqueOrThrow({
      where: {
        companyId_localUuid: {
          companyId: fixture.companyId,
          localUuid: entityLocalId,
        },
      },
    });
    assert.equal(afterStale.expectedBalanceCents, 1500);
    assert.equal(afterStale.lastLocalSequence, 3);
  });

  it("normalizes cashSession/update status aberto for an existing open session", async () => {
    const fixture = await createFixture();
    const entityLocalId = `${runId}-cash-session-aberto`;
    await push(fixture, [
      buildEvent("cash-session-aberto-create", "cashSession", {
        feature: "cash",
        entityLocalId,
        payload: {
          status: "open",
          openedAt: "2026-05-06T20:41:08.169407Z",
          initialFloatCents: 0,
        },
      }),
    ]);

    const response = await push(fixture, [
      buildEvent("cash-session-aberto-update", "cashSession", {
        feature: "cash",
        operation: "update",
        entityLocalId,
        payload: {
          uuid: entityLocalId,
          status: "aberto",
          openedAt: "2026-05-06T20:41:08.169407Z",
          expectedBalanceCents: 130400,
        },
      }),
    ]);

    assert.equal(
      (response.data as { summary: { accepted: number } }).summary.accepted,
      1,
    );
    const cashSession = await prisma.cashSession.findUniqueOrThrow({
      where: {
        companyId_localUuid: {
          companyId: fixture.companyId,
          localUuid: entityLocalId,
        },
      },
    });
    assert.equal(cashSession.status, "open");
    assert.equal(cashSession.expectedBalanceCents, 130400);
    assert.equal(
      cashSession.openedAt?.toISOString(),
      "2026-05-06T20:41:08.169Z",
    );
  });

  it("creates a missing open cashSession update idempotently when opening metadata is present", async () => {
    const fixture = await createFixture();
    const entityLocalId = `${runId}-cash-session-open-update-create`;
    const event = buildEvent("cash-session-open-update-create", "cashSession", {
      feature: "cash",
      operation: "update",
      entityLocalId,
      payload: {
        uuid: entityLocalId,
        status: "aberto",
        localId: 3,
        openedAt: "2026-05-06T20:41:08.169407Z",
        operatorName: "Operador local",
        expectedBalanceCents: 130400,
        initialFloatCents: 0,
      },
    });

    const first = await push(fixture, [event]);
    const duplicate = await push(fixture, [event]);

    assert.equal(
      (first.data as { summary: { accepted: number; rejected: number } })
        .summary.accepted,
      1,
    );
    assert.equal(
      (first.data as { summary: { accepted: number; rejected: number } })
        .summary.rejected,
      0,
    );
    assert.equal(
      (duplicate.data as { summary: { duplicates: number } }).summary
        .duplicates,
      1,
    );
    const [cashSessionsCount, failedCount] = await Promise.all([
      prisma.cashSession.count({
        where: { companyId: fixture.companyId, localUuid: entityLocalId },
      }),
      prisma.syncEvent.count({
        where: {
          companyId: fixture.companyId,
          eventId: "cash-session-open-update-create",
          status: "FAILED",
        },
      }),
    ]);
    assert.equal(cashSessionsCount, 1);
    assert.equal(failedCount, 0);
  });

  it("upserts a missing closed cashSession update and keeps a later create from reopening it", async () => {
    const fixture = await createFixture();
    const entityLocalId = "1778846414191398-2d1accbd";
    const updateResponse = await push(fixture, [
      buildEvent("cash-session-missing-close-update", "cashSession", {
        feature: "cash",
        operation: "update",
        entityLocalId,
        payload: {
          uuid: entityLocalId,
          status: "fechado",
          openedAt: "2026-05-14T12:29:31.566712",
          closedAt: "2026-05-15T08:59:26.391953",
          initialFloatCents: 0,
          expectedBalanceCents: 130400,
          countedBalanceCents: 130400,
          differenceCents: 0,
          operatorName: "wilham",
          _sync: {
            eventId: "cash-session-missing-close-update",
            entityLocalId,
            localSequence: 1778846414191399,
            idempotencyKey: "cash-session-missing-close-update",
          },
        },
      }),
    ]);

    assert.equal(updateResponse.status, 202);
    assert.equal(
      (updateResponse.data as { summary: { accepted: number } }).summary
        .accepted,
      1,
    );

    const cashSessionAfterUpdate = await prisma.cashSession.findUniqueOrThrow({
      where: {
        companyId_localUuid: {
          companyId: fixture.companyId,
          localUuid: entityLocalId,
        },
      },
    });
    assert.equal(cashSessionAfterUpdate.status, "closed");
    assert.equal(cashSessionAfterUpdate.openingBalanceCents, 0);
    assert.equal(cashSessionAfterUpdate.expectedBalanceCents, 130400);
    assert.equal(cashSessionAfterUpdate.closingBalanceCents, 130400);
    assert.equal(
      cashSessionAfterUpdate.openedAt?.toISOString(),
      "2026-05-14T15:29:31.566Z",
    );
    assert.equal(
      cashSessionAfterUpdate.closedAt?.toISOString(),
      "2026-05-15T11:59:26.391Z",
    );
    assert.equal(
      (cashSessionAfterUpdate.payload as Record<string, unknown> | null)
        ?.operatorName,
      "wilham",
    );

    const createResponse = await push(fixture, [
      buildEvent("cash-session-create-after-closed-update", "cashSession", {
        feature: "cash",
        entityLocalId,
        payload: {
          uuid: entityLocalId,
          status: "aberto",
          openedAt: "2026-05-14T12:29:31.566712",
          initialFloatCents: 0,
          operatorName: "wilham",
          _sync: {
            eventId: "cash-session-create-after-closed-update",
            entityLocalId,
            localSequence: 1778846414191400,
            idempotencyKey: "cash-session-create-after-closed-update",
          },
        },
      }),
    ]);

    assert.equal(
      (createResponse.data as { summary: { duplicates: number } }).summary
        .duplicates,
      1,
    );
    const cashSessionAfterCreate = await prisma.cashSession.findUniqueOrThrow({
      where: {
        companyId_localUuid: {
          companyId: fixture.companyId,
          localUuid: entityLocalId,
        },
      },
    });
    assert.equal(cashSessionAfterCreate.status, "closed");
    assert.equal(cashSessionAfterCreate.closingBalanceCents, 130400);
  });

  it("rejects missing cashSession opening metadata with a specific payload error", async () => {
    const fixture = await createFixture();
    const entityLocalId = `${runId}-cash-session-invalid-payload`;
    const response = await push(fixture, [
      buildEvent("cash-session-invalid-payload", "cashSession", {
        feature: "cash",
        operation: "update",
        entityLocalId,
        payload: {
          uuid: entityLocalId,
          status: "fechado",
          closedAt: "2026-05-06T22:41:08.169407Z",
          countedBalanceCents: 130400,
        },
      }),
    ]);

    const payload = response.data as {
      rejected: Array<{ code: string }>;
    };
    assert.equal(payload.rejected[0]?.code, "CASH_SESSION_INVALID_PAYLOAD");
    const failedCount = await prisma.syncEvent.count({
      where: {
        companyId: fixture.companyId,
        eventId: "cash-session-invalid-payload",
        status: "FAILED",
      },
    });
    assert.equal(failedCount, 0);
  });

  it("rejects cashSession payloads without status with a specific payload error", async () => {
    const fixture = await createFixture();
    const entityLocalId = `${runId}-cash-session-missing-status`;
    const response = await push(fixture, [
      buildEvent("cash-session-missing-status", "cashSession", {
        feature: "cash",
        operation: "update",
        entityLocalId,
        payload: {
          uuid: entityLocalId,
          openedAt: "2026-05-06T20:41:08.169407Z",
          countedBalanceCents: 130400,
        },
      }),
    ]);

    const payload = response.data as {
      rejected: Array<{ code: string; details?: { missingFields?: string[] } }>;
    };
    assert.equal(payload.rejected[0]?.code, "CASH_SESSION_INVALID_PAYLOAD");
    assert.deepEqual(payload.rejected[0]?.details?.missingFields, ["status"]);
    const failedCount = await prisma.syncEvent.count({
      where: {
        companyId: fixture.companyId,
        eventId: "cash-session-missing-status",
        status: "FAILED",
      },
    });
    assert.equal(failedCount, 0);
  });

  it("rejects cashSession updates with invalid status without generic failure", async () => {
    const fixture = await createFixture();
    const response = await push(fixture, [
      buildEvent("cash-session-invalid-status", "cashSession", {
        feature: "cash",
        operation: "update",
        entityLocalId: `${runId}-cash-session-invalid-status`,
        payload: {
          status: "em_conferencia",
          openedAt: "2026-05-06T20:41:08.169407Z",
        },
      }),
    ]);

    const rejected = (response.data as { rejected: Array<{ code: string }> })
      .rejected;
    assert.equal(rejected[0]?.code, "CASH_SESSION_INVALID_STATUS");
    const failedCount = await prisma.syncEvent.count({
      where: {
        companyId: fixture.companyId,
        eventId: "cash-session-invalid-status",
        status: "FAILED",
      },
    });
    assert.equal(failedCount, 0);
  });

  it("returns materialized cashSession data in app snapshot after closing", async () => {
    const fixture = await createFixture();
    const entityLocalId = `${runId}-cash-session-snapshot`;
    await push(fixture, [
      buildEvent("cash-session-snapshot-create", "cashSession", {
        feature: "pdv",
        entityLocalId,
        payload: {
          uuid: entityLocalId,
          status: "aberto",
          openedAt: "2026-05-15T09:00:14.191397",
          operatorName: "wilham",
          initialFloatCents: 0,
        },
      }),
      buildEvent("cash-session-snapshot-close", "cashSession", {
        feature: "pdv",
        operation: "update",
        entityLocalId,
        payload: {
          uuid: entityLocalId,
          status: "fechado",
          openedAt: "2026-05-15T09:00:14.191397",
          closedAt: "2026-05-15T10:59:26.391953",
          operatorName: "wilham",
          initialFloatCents: 0,
          expectedBalanceCents: 8000,
          countedBalanceCents: 8000,
          differenceCents: 0,
        },
      }),
    ]);

    const response = await requestJson(
      "GET",
      "/app/snapshot?features=cash_sessions",
      { token: fixture.token },
    );

    assert.equal(response.status, 200);
    const cashSessions = (
      response.data as {
        features: {
          cash_sessions: {
            items: Array<Record<string, unknown>>;
          };
        };
      }
    ).features.cash_sessions.items;
    assert.equal(cashSessions.length, 1);
    assert.equal(cashSessions[0]?.localUuid, entityLocalId);
    assert.equal(cashSessions[0]?.status, "closed");
    assert.equal(cashSessions[0]?.operatorName, "wilham");
    assert.equal(cashSessions[0]?.openingBalanceCents, 0);
    assert.equal(cashSessions[0]?.closingBalanceCents, 8000);
    assert.equal(cashSessions[0]?.expectedBalanceCents, 8000);
  });

  it("backfills localId on late cashSession/create after a closed update upsert", async () => {
    const fixture = await createFixture();
    const entityLocalId = `${runId}-cash-session-backfill-local-id`;

    const updateResponse = await push(fixture, [
      buildEvent("cash-session-backfill-update", "cashSession", {
        feature: "pdv",
        operation: "update",
        entityLocalId,
        payload: {
          uuid: entityLocalId,
          status: "fechado",
          openedAt: "2026-05-14T12:29:31.566712",
          closedAt: "2026-05-15T08:59:26.391953",
          countedBalanceCents: 8000,
          expectedBalanceCents: 8000,
          differenceCents: 0,
        },
      }),
    ]);
    assert.equal(updateResponse.status, 202);

    const createResponse = await push(fixture, [
      buildEvent("cash-session-backfill-create", "cashSession", {
        feature: "pdv",
        entityLocalId,
        payload: {
          localId: 3,
          uuid: entityLocalId,
          status: "aberto",
          openedAt: "2026-05-14T12:29:31.566712",
          operatorName: "wilham",
        },
      }),
    ]);
    assert.equal(
      (createResponse.data as { summary: { duplicates: number } }).summary
        .duplicates,
      1,
    );

    const cashSession = await prisma.cashSession.findUniqueOrThrow({
      where: {
        companyId_localUuid: {
          companyId: fixture.companyId,
          localUuid: entityLocalId,
        },
      },
    });
    assert.equal(cashSession.status, "closed");
    assert.equal(cashSession.localId, "3");

    const movementResponse = await push(fixture, [
      buildEvent("cash-session-backfill-movement", "cashMovement", {
        feature: "pdv",
        entityLocalId: `${entityLocalId}-movement`,
        payload: {
          uuid: `${entityLocalId}-movement`,
          sessionId: 3,
          amountCents: -500,
          type: "sangria",
        },
      }),
    ]);

    const movementPayload = movementResponse.data as {
      conflicts: Array<{ code: string }>;
    };
    assert.equal(movementPayload.conflicts[0]?.code, "CASH_SESSION_CLOSED");
  });

  it("materializes cashMovement/create and keeps it idempotent", async () => {
    const fixture = await createFixture();
    const cashSessionLocalId = `${runId}-movement-cash-session`;
    const movementLocalId = `${runId}-cash-movement`;
    await push(fixture, [
      buildEvent("movement-cash-session-create", "cashSession", {
        feature: "cash",
        entityLocalId: cashSessionLocalId,
        payload: {
          status: "open",
          openedAt: "2026-05-06T20:41:08.169407Z",
        },
      }),
    ]);

    await push(fixture, [
      buildEvent("cash-movement-create", "cashMovement", {
        feature: "cash",
        entityLocalId: movementLocalId,
        payload: {
          cashSessionLocalId,
          amountCents: -500,
          eventType: "sangria",
        },
      }),
    ]);
    const duplicate = await push(fixture, [
      buildEvent("cash-movement-domain-duplicate", "cashMovement", {
        feature: "cash",
        entityLocalId: movementLocalId,
        payload: {
          cashSessionLocalId,
          amountCents: -500,
          eventType: "sangria",
        },
      }),
    ]);

    assert.equal(
      (duplicate.data as { summary: { duplicates: number } }).summary
        .duplicates,
      1,
    );
    const cashEventsCount = await prisma.cashEvent.count({
      where: { companyId: fixture.companyId },
    });
    assert.equal(cashEventsCount, 1);
  });

  it("deduplicates cashMovement/create by _sync idempotencyKey", async () => {
    const fixture = await createFixture();
    const cashSessionLocalId = `${runId}-movement-sync-cash-session`;
    const idempotencyKey = `${runId}-cash-movement-sync-key`;
    await push(fixture, [
      buildEvent("movement-sync-cash-session-create", "cashSession", {
        feature: "cash",
        entityLocalId: cashSessionLocalId,
        payload: {
          status: "open",
          openedAt: "2026-05-06T20:41:08.169407Z",
        },
      }),
    ]);

    await push(fixture, [
      buildEvent("cash-movement-sync-create-a", "cashMovement", {
        feature: "cash",
        entityLocalId: `${runId}-cash-movement-sync-a`,
        payload: {
          cashSessionLocalId,
          amountCents: -500,
          eventType: "sangria",
          _sync: { idempotencyKey, localSequence: 1 },
        },
      }),
    ]);
    const duplicate = await push(fixture, [
      buildEvent("cash-movement-sync-create-b", "cashMovement", {
        feature: "cash",
        entityLocalId: `${runId}-cash-movement-sync-b`,
        payload: {
          cashSessionLocalId,
          amountCents: -500,
          eventType: "sangria",
          _sync: { idempotencyKey, localSequence: 2 },
        },
      }),
    ]);

    assert.equal(
      (duplicate.data as { summary: { duplicates: number } }).summary
        .duplicates,
      1,
    );
    const cashEventsCount = await prisma.cashEvent.count({
      where: { companyId: fixture.companyId, localUuid: idempotencyKey },
    });
    assert.equal(cashEventsCount, 1);
  });

  it("materializes sale/create without duplicating the sale domain record", async () => {
    const fixture = await createFixture();
    const entityLocalId = `${runId}-sale-domain`;

    const first = await push(fixture, [
      buildEvent("sale-domain-create", "sale", {
        entityLocalId,
        payload: { status: "finalized", totalCents: 8800 },
      }),
    ]);
    const second = await push(fixture, [
      buildEvent("sale-domain-duplicate", "sale", {
        entityLocalId,
        payload: { status: "finalized", totalCents: 8800 },
      }),
    ]);

    assert.equal(first.status, 202);
    assert.equal(
      (second.data as { summary: { duplicates: number } }).summary.duplicates,
      1,
    );
    const salesCount = await prisma.sale.count({
      where: { companyId: fixture.companyId, localUuid: entityLocalId },
    });
    assert.equal(salesCount, 1);
  });

  it("links sale/create to the cashSession when the app sends the session uuid", async () => {
    const fixture = await createFixture();
    const cashSessionLocalId = `${runId}-sale-cash-session`;
    const saleLocalId = `${runId}-sale-linked-cash`;

    await push(fixture, [
      buildEvent("sale-linked-cash-session-create", "cashSession", {
        feature: "pdv",
        entityLocalId: cashSessionLocalId,
        payload: {
          uuid: cashSessionLocalId,
          status: "aberto",
          openedAt: "2026-05-15T09:00:14.191397",
          operatorName: "wilham",
          initialFloatCents: 0,
        },
      }),
    ]);

    const response = await push(fixture, [
      buildEvent("sale-linked-cash-create", "sale", {
        feature: "pdv",
        entityLocalId: saleLocalId,
        payload: {
          uuid: saleLocalId,
          status: "finalized",
          totalCents: 8800,
          cashSessionLocalId,
          cashSessionUuid: cashSessionLocalId,
          soldAt: "2026-05-15T09:05:00.000Z",
        },
      }),
    ]);

    assert.equal(response.status, 202);
    assert.equal(
      (response.data as { summary: { accepted: number } }).summary.accepted,
      1,
    );

    const [sale, cashSession] = await Promise.all([
      prisma.sale.findUniqueOrThrow({
        where: {
          companyId_localUuid: {
            companyId: fixture.companyId,
            localUuid: saleLocalId,
          },
        },
      }),
      prisma.cashSession.findUniqueOrThrow({
        where: {
          companyId_localUuid: {
            companyId: fixture.companyId,
            localUuid: cashSessionLocalId,
          },
        },
      }),
    ]);
    assert.equal(sale.cashSessionId, cashSession.id);
  });

  it("deduplicates sale/create by _sync entityLocalId with different eventIds", async () => {
    const fixture = await createFixture();
    const entityLocalId = `${runId}-sale-sync-domain`;

    const first = await push(fixture, [
      buildEvent("sale-sync-domain-create-a", "sale", {
        entityLocalId: `${entityLocalId}-transport-a`,
        payload: {
          status: "finalized",
          totalCents: 8800,
          _sync: { entityLocalId, localSequence: 1 },
        },
      }),
    ]);
    const second = await push(fixture, [
      buildEvent("sale-sync-domain-create-b", "sale", {
        entityLocalId: `${entityLocalId}-transport-b`,
        payload: {
          status: "finalized",
          totalCents: 8800,
          _sync: { entityLocalId, localSequence: 2 },
        },
      }),
    ]);

    assert.equal(first.status, 202);
    assert.equal(
      (second.data as { summary: { duplicates: number } }).summary.duplicates,
      1,
    );
    const salesCount = await prisma.sale.count({
      where: { companyId: fixture.companyId, localUuid: entityLocalId },
    });
    const syncEvent = await prisma.syncEvent.findFirstOrThrow({
      where: {
        companyId: fixture.companyId,
        eventId: "sale-sync-domain-create-a",
      },
    });
    assert.equal(salesCount, 1);
    assert.equal(syncEvent.entityLocalId, entityLocalId);
  });

  it("creates SALE_NOT_FOUND conflicts for saleItem and payment without sale", async () => {
    const fixture = await createFixture();
    const response = await push(fixture, [
      buildEvent("sale-item-missing-sale", "saleItem", {
        entityLocalId: `${runId}-sale-item-missing`,
        payload: { saleLocalId: `${runId}-missing-sale`, quantityMil: 1000 },
      }),
      buildEvent("payment-missing-sale", "payment", {
        entityLocalId: `${runId}-payment-missing`,
        payload: {
          saleLocalId: `${runId}-missing-sale`,
          amountCents: 2500,
        },
      }),
    ]);

    assert.equal(response.status, 202);
    const conflicts = (
      response.data as {
        conflicts: Array<{
          eventId: string;
          code: string;
          details?: Record<string, unknown>;
        }>;
      }
    ).conflicts;
    assert.deepEqual(
      conflicts.map((item) => [item.eventId, item.code]),
      [
        ["sale-item-missing-sale", "SALE_NOT_FOUND"],
        ["payment-missing-sale", "SALE_NOT_FOUND"],
      ],
    );
  });

  it("materializes duplicate payment as idempotent duplicate", async () => {
    const fixture = await createFixture();
    const saleLocalId = `${runId}-payment-sale`;
    const paymentLocalId = `${runId}-payment-local`;
    await push(fixture, [
      buildEvent("payment-sale-create", "sale", {
        entityLocalId: saleLocalId,
        payload: { status: "finalized", totalCents: 2500 },
      }),
    ]);
    await push(fixture, [
      buildEvent("payment-create", "payment", {
        entityLocalId: paymentLocalId,
        payload: {
          saleLocalId,
          amountCents: 2500,
          paymentMethod: "pix",
          idempotencyKey: paymentLocalId,
        },
      }),
    ]);

    const duplicate = await push(fixture, [
      buildEvent("payment-domain-duplicate", "payment", {
        entityLocalId: `${paymentLocalId}-retry`,
        payload: {
          saleLocalId,
          amountCents: 2500,
          paymentMethod: "pix",
          idempotencyKey: paymentLocalId,
        },
      }),
    ]);

    assert.equal(
      (duplicate.data as { summary: { duplicates: number } }).summary
        .duplicates,
      1,
    );
    const paymentsCount = await prisma.financialEvent.count({
      where: { companyId: fixture.companyId, eventType: "sale_payment" },
    });
    assert.equal(paymentsCount, 1);
  });

  it("deduplicates payment/create by _sync idempotencyKey", async () => {
    const fixture = await createFixture();
    const saleLocalId = `${runId}-payment-sync-sale`;
    const idempotencyKey = `${runId}-payment-sync-key`;
    await push(fixture, [
      buildEvent("payment-sync-sale-create", "sale", {
        entityLocalId: saleLocalId,
        payload: { status: "finalized", totalCents: 2500 },
      }),
    ]);
    await push(fixture, [
      buildEvent("payment-sync-create-a", "payment", {
        entityLocalId: `${runId}-payment-sync-a`,
        payload: {
          saleLocalId,
          amountCents: 2500,
          paymentMethod: "pix",
          _sync: { idempotencyKey, localSequence: 1 },
        },
      }),
    ]);

    const duplicate = await push(fixture, [
      buildEvent("payment-sync-create-b", "payment", {
        entityLocalId: `${runId}-payment-sync-b`,
        payload: {
          saleLocalId,
          amountCents: 2500,
          paymentMethod: "pix",
          _sync: { idempotencyKey, localSequence: 2 },
        },
      }),
    ]);

    assert.equal(
      (duplicate.data as { summary: { duplicates: number } }).summary
        .duplicates,
      1,
    );
    const paymentsCount = await prisma.financialEvent.count({
      where: { companyId: fixture.companyId, localUuid: idempotencyKey },
    });
    assert.equal(paymentsCount, 1);
  });

  it("treats repeated receipt for the same sale as idempotent", async () => {
    const fixture = await createFixture();
    const saleLocalId = `${runId}-receipt-same-sale`;
    const receiptNumber = `${runId}-R-001`;
    await push(fixture, [
      buildEvent("receipt-sale-create", "sale", {
        entityLocalId: saleLocalId,
        payload: { status: "finalized", totalCents: 1200 },
      }),
    ]);
    await push(fixture, [
      buildEvent("receipt-create", "receipt", {
        entityLocalId: `${runId}-receipt-local`,
        payload: { saleLocalId, receiptNumber },
      }),
    ]);

    const duplicate = await push(fixture, [
      buildEvent("receipt-same-sale-duplicate", "receipt", {
        entityLocalId: `${runId}-receipt-local-2`,
        payload: { saleLocalId, receiptNumber },
      }),
    ]);

    assert.equal(
      (duplicate.data as { summary: { duplicates: number } }).summary
        .duplicates,
      1,
    );
    const sale = await prisma.sale.findUniqueOrThrow({
      where: {
        companyId_localUuid: {
          companyId: fixture.companyId,
          localUuid: saleLocalId,
        },
      },
    });
    assert.equal(sale.receiptNumber, receiptNumber);
  });

  it("creates DUPLICATE_RECEIPT when receipt number belongs to another sale", async () => {
    const fixture = await createFixture();
    const receiptNumber = `${runId}-R-002`;
    await push(fixture, [
      buildEvent("receipt-sale-a-create", "sale", {
        entityLocalId: `${runId}-receipt-sale-a`,
        payload: { status: "finalized", totalCents: 1200 },
      }),
      buildEvent("receipt-sale-b-create", "sale", {
        entityLocalId: `${runId}-receipt-sale-b`,
        payload: { status: "finalized", totalCents: 1400 },
      }),
    ]);
    await push(fixture, [
      buildEvent("receipt-sale-a-receipt", "receipt", {
        entityLocalId: `${runId}-receipt-a`,
        payload: { saleLocalId: `${runId}-receipt-sale-a`, receiptNumber },
      }),
    ]);

    const conflict = await push(fixture, [
      buildEvent("receipt-sale-b-conflict", "receipt", {
        entityLocalId: `${runId}-receipt-b`,
        payload: { saleLocalId: `${runId}-receipt-sale-b`, receiptNumber },
      }),
    ]);

    assert.equal(
      (conflict.data as { conflicts: Array<{ code: string }> }).conflicts[0]
        ?.code,
      "DUPLICATE_RECEIPT",
    );
  });

  it("creates stock conflicts for unavailable stock and missing remote variant", async () => {
    const fixture = await createFixture();
    const product = await createProduct(fixture, { stockMil: 0 });

    const response = await push(fixture, [
      buildEvent("stock-reservation-unavailable", "stockReservation", {
        entityLocalId: `${runId}-stock-reservation`,
        payload: { productId: product.id, quantityMil: 1000 },
      }),
      buildEvent("stock-deduction-missing-variant", "stockDeduction", {
        entityLocalId: `${runId}-stock-deduction`,
        payload: {
          productVariantId: "11111111-1111-4111-8111-111111111111",
          quantityMil: 1000,
        },
      }),
    ]);

    const conflicts = (
      response.data as {
        conflicts: Array<{
          eventId: string;
          code: string;
          details?: Record<string, unknown>;
        }>;
      }
    ).conflicts;
    assert.deepEqual(
      conflicts.map((item) => [item.eventId, item.code]),
      [
        ["stock-reservation-unavailable", "STOCK_UNAVAILABLE"],
        ["stock-deduction-missing-variant", "STOCK_VARIANT_NOT_FOUND"],
      ],
    );
    assert.deepEqual(conflicts[1]?.details, {
      entity: "stockDeduction",
      operation: "create",
      entityLocalId: `${runId}-stock-deduction`,
      productId: null,
      productVariantId: "11111111-1111-4111-8111-111111111111",
      productLocalId: null,
      productVariantLocalId: null,
    });
  });

  it("materializes stockDeduction/create with a valid remote variant id", async () => {
    const fixture = await createFixture();
    const product = await createProduct(fixture, { stockMil: 10_000 });
    const variant = await createProductVariant(product, { stockMil: 5_000 });

    const response = await push(fixture, [
      buildEvent("stock-deduction-valid-variant", "stockDeduction", {
        entityLocalId: `${runId}-stock-deduction-valid-variant`,
        payload: {
          productVariantId: variant.id,
          quantityDeltaMil: -2_000,
        },
      }),
    ]);

    assert.equal(
      (response.data as { summary: { accepted: number } }).summary.accepted,
      1,
    );
    const [deduction, updatedVariant] = await Promise.all([
      prisma.stockDeduction.findFirstOrThrow({
        where: {
          companyId: fixture.companyId,
          localUuid: `${runId}-stock-deduction-valid-variant`,
        },
      }),
      prisma.productVariant.findUniqueOrThrow({ where: { id: variant.id } }),
    ]);
    assert.equal(deduction.productId, product.id);
    assert.equal(deduction.productVariantId, variant.id);
    assert.equal(updatedVariant.stockMil, 3_000);
  });

  it("materializes stockDeduction/create with a remote product id only when the product has no active variants", async () => {
    const fixture = await createFixture();
    const product = await createProduct(fixture, { stockMil: 10_000 });

    const response = await push(fixture, [
      buildEvent("stock-deduction-valid-product", "stockDeduction", {
        entityLocalId: `${runId}-stock-deduction-valid-product`,
        payload: {
          productId: product.id,
          quantityDeltaMil: -1_500,
        },
      }),
    ]);

    assert.equal(
      (response.data as { summary: { accepted: number } }).summary.accepted,
      1,
    );
    const [deduction, updatedProduct] = await Promise.all([
      prisma.stockDeduction.findFirstOrThrow({
        where: {
          companyId: fixture.companyId,
          localUuid: `${runId}-stock-deduction-valid-product`,
        },
      }),
      prisma.product.findUniqueOrThrow({ where: { id: product.id } }),
    ]);
    assert.equal(deduction.productId, product.id);
    assert.equal(deduction.productVariantId, null);
    assert.equal(updatedProduct.stockMil, 8_500);
  });

  it("does not deduct product-level stock for a product with active variants when variant identity is missing", async () => {
    const fixture = await createFixture();
    const product = await createProduct(fixture, { stockMil: 10_000 });
    const variant = await createProductVariant(product, { stockMil: 5_000 });

    const response = await push(fixture, [
      buildEvent("stock-deduction-product-with-variants", "stockDeduction", {
        entityLocalId: `${runId}-stock-deduction-product-with-variants`,
        payload: {
          productId: product.id,
          quantityDeltaMil: -1_000,
        },
      }),
    ]);

    const payload = response.data as {
      conflicts: Array<{ code: string; details?: Record<string, unknown> }>;
    };
    assert.equal(
      payload.conflicts[0]?.code,
      "STOCK_DEDUCTION_REMOTE_ID_REQUIRED",
    );
    assert.equal(
      payload.conflicts[0]?.details?.reason,
      "PRODUCT_VARIANT_REMOTE_ID_REQUIRED",
    );

    const [updatedProduct, updatedVariant, deductionsCount] = await Promise.all(
      [
        prisma.product.findUniqueOrThrow({ where: { id: product.id } }),
        prisma.productVariant.findUniqueOrThrow({ where: { id: variant.id } }),
        prisma.stockDeduction.count({
          where: { companyId: fixture.companyId },
        }),
      ],
    );
    assert.equal(updatedProduct.stockMil, 10_000);
    assert.equal(updatedVariant.stockMil, 5_000);
    assert.equal(deductionsCount, 0);
  });

  it("creates a safe stock conflict for local numeric product ids in deduction remote fields", async () => {
    const fixture = await createFixture();

    const response = await push(fixture, [
      buildEvent("stock-deduction-local-product-id", "stockDeduction", {
        entityLocalId: `${runId}-stock-deduction-local-id`,
        payload: {
          productId: 1,
          productLocalId: 1,
          productVariantLocalId: 10,
          quantityMil: 1000,
        },
      }),
    ]);

    const conflicts = (
      response.data as {
        conflicts: Array<{
          eventId: string;
          code: string;
          details?: Record<string, unknown>;
        }>;
      }
    ).conflicts;
    assert.deepEqual(
      conflicts.map((item) => [item.eventId, item.code]),
      [
        [
          "stock-deduction-local-product-id",
          "STOCK_DEDUCTION_REMOTE_ID_REQUIRED",
        ],
      ],
    );
    assert.equal(conflicts[0]?.details?.productId, "1");
    assert.equal(conflicts[0]?.details?.productLocalId, "1");
  });

  it("keeps sale materialization accepted when stockDeduction needs review", async () => {
    const fixture = await createFixture();
    const product = await createProduct(fixture, { stockMil: 10_000 });
    const saleLocalId = `${runId}-stock-conflict-sale`;

    const response = await push(fixture, [
      buildEvent("stock-conflict-sale-create", "sale", {
        entityLocalId: saleLocalId,
        payload: { status: "finalized", totalCents: 1000 },
      }),
      buildEvent("stock-conflict-sale-item-create", "saleItem", {
        entityLocalId: `${runId}-stock-conflict-sale-item`,
        payload: {
          saleLocalId,
          productId: product.id,
          productNameSnapshot: "Produto com estoque pendente",
          quantityMil: 1000,
          unitPriceCents: 1000,
          subtotalCents: 1000,
        },
      }),
      buildEvent("stock-conflict-payment-create", "payment", {
        entityLocalId: `${runId}-stock-conflict-payment`,
        payload: {
          saleLocalId,
          amountCents: 1000,
          paymentMethod: "pix",
        },
      }),
      buildEvent("stock-conflict-deduction-create", "stockDeduction", {
        entityLocalId: `${runId}-stock-conflict-deduction`,
        payload: {
          saleLocalId,
          productId: 5,
          productLocalId: 5,
          quantityDeltaMil: -1000,
        },
      }),
    ]);

    const payload = response.data as {
      summary: { accepted: number; conflicts: number };
      conflicts: Array<{ code: string }>;
    };
    assert.equal(payload.summary.accepted, 3);
    assert.equal(payload.summary.conflicts, 1);
    assert.equal(
      payload.conflicts[0]?.code,
      "STOCK_DEDUCTION_REMOTE_ID_REQUIRED",
    );

    const [salesCount, saleItemsCount, paymentsCount, deductionsCount] =
      await Promise.all([
        prisma.sale.count({ where: { companyId: fixture.companyId } }),
        prisma.saleItem.count({
          where: { sale: { companyId: fixture.companyId } },
        }),
        prisma.financialEvent.count({
          where: { companyId: fixture.companyId, eventType: "sale_payment" },
        }),
        prisma.stockDeduction.count({
          where: { companyId: fixture.companyId },
        }),
      ]);
    assert.equal(salesCount, 1);
    assert.equal(saleItemsCount, 1);
    assert.equal(paymentsCount, 1);
    assert.equal(deductionsCount, 0);
  });

  it("creates STOCK_PRODUCT_NOT_FOUND for missing remote product ids", async () => {
    const fixture = await createFixture();

    const response = await push(fixture, [
      buildEvent("stock-deduction-missing-product", "stockDeduction", {
        entityLocalId: `${runId}-stock-deduction-missing-product`,
        payload: {
          productId: "11111111-1111-4111-8111-111111111111",
          quantityDeltaMil: -1000,
        },
      }),
    ]);

    const conflicts = (
      response.data as {
        conflicts: Array<{ eventId: string; code: string }>;
      }
    ).conflicts;
    assert.deepEqual(
      conflicts.map((item) => [item.eventId, item.code]),
      [["stock-deduction-missing-product", "STOCK_PRODUCT_NOT_FOUND"]],
    );
  });

  it("deduplicates stockReservation/create and stockDeduction/create by _sync idempotencyKey", async () => {
    const fixture = await createFixture();
    const product = await createProduct(fixture, { stockMil: 10_000 });
    const reservationKey = `${runId}-stock-reservation-sync-key`;
    const deductionKey = `${runId}-stock-deduction-sync-key`;

    await push(fixture, [
      buildEvent("stock-reservation-sync-create-a", "stockReservation", {
        entityLocalId: `${runId}-stock-reservation-sync-a`,
        payload: {
          productId: product.id,
          quantityMil: 1000,
          _sync: { idempotencyKey: reservationKey, localSequence: 1 },
        },
      }),
      buildEvent("stock-deduction-sync-create-a", "stockDeduction", {
        entityLocalId: `${runId}-stock-deduction-sync-a`,
        payload: {
          productId: product.id,
          quantityDeltaMil: -1000,
          _sync: { idempotencyKey: deductionKey, localSequence: 1 },
        },
      }),
    ]);

    const duplicate = await push(fixture, [
      buildEvent("stock-reservation-sync-create-b", "stockReservation", {
        entityLocalId: `${runId}-stock-reservation-sync-b`,
        payload: {
          productId: product.id,
          quantityMil: 1000,
          _sync: { idempotencyKey: reservationKey, localSequence: 2 },
        },
      }),
      buildEvent("stock-deduction-sync-create-b", "stockDeduction", {
        entityLocalId: `${runId}-stock-deduction-sync-b`,
        payload: {
          productId: product.id,
          quantityDeltaMil: -1000,
          _sync: { idempotencyKey: deductionKey, localSequence: 2 },
        },
      }),
    ]);

    assert.equal(
      (duplicate.data as { summary: { duplicates: number } }).summary
        .duplicates,
      2,
    );
    const [reservationsCount, deductionsCount, updatedProduct] =
      await Promise.all([
        prisma.stockReservation.count({
          where: { companyId: fixture.companyId, localUuid: reservationKey },
        }),
        prisma.stockDeduction.count({
          where: { companyId: fixture.companyId, localUuid: deductionKey },
        }),
        prisma.product.findUniqueOrThrow({ where: { id: product.id } }),
      ]);
    assert.equal(reservationsCount, 1);
    assert.equal(deductionsCount, 1);
    assert.equal(updatedProduct.stockMil, 9000);
  });

  it("creates SyncIncident when materialization fails unexpectedly", async () => {
    const fixture = await createFixture();
    const saleLocalId = `${runId}-payment-overflow-sale`;
    await push(fixture, [
      buildEvent("payment-overflow-sale-create", "sale", {
        entityLocalId: saleLocalId,
        payload: { status: "finalized", totalCents: 1000 },
      }),
    ]);

    const response = await push(fixture, [
      buildEvent("payment-overflow-failure", "payment", {
        entityLocalId: `${runId}-payment-overflow`,
        payload: {
          saleLocalId,
          amountCents: 3_000_000_000,
        },
      }),
    ]);

    const rejected = (
      response.data as {
        rejected: Array<{ code: string }>;
      }
    ).rejected;
    assert.equal(rejected[0]?.code, "SYNC_MATERIALIZATION_FAILED");

    const [failedEvent, incident] = await Promise.all([
      prisma.syncEvent.findFirst({
        where: {
          companyId: fixture.companyId,
          eventId: "payment-overflow-failure",
          status: "FAILED",
        },
      }),
      prisma.syncIncident.findFirst({
        where: {
          companyId: fixture.companyId,
          code: "SYNC_MATERIALIZATION_FAILED",
        },
      }),
    ]);
    assert.notEqual(failedEvent, null);
    assert.notEqual(incident, null);
  });

  it("materializes operationalOrder/create", async () => {
    const fixture = await createFixture({ role: "ADMIN" });
    const orderLocalId = `${runId}-operational-order`;

    const response = await push(fixture, [
      buildEvent("operational-order-create", "operationalOrder", {
        entityLocalId: orderLocalId,
        payload: {
          status: "open",
          subtotalCents: 3200,
          discountCents: 200,
          totalCents: 3000,
          notes: "Mesa 4",
        },
      }),
    ]);

    assert.equal(response.status, 202);
    const accepted = (
      response.data as {
        accepted: Array<{ entityServerId: string | null }>;
      }
    ).accepted;
    assert.notEqual(accepted[0]?.entityServerId, null);

    const order = await prisma.operationalOrder.findUniqueOrThrow({
      where: {
        companyId_localUuid: {
          companyId: fixture.companyId,
          localUuid: orderLocalId,
        },
      },
    });
    assert.equal(order.status, "open");
    assert.equal(order.totalCents, 3000);
    assert.equal(order.deviceId, fixture.deviceId);
    assert.equal(order.sellerUserId, fixture.userId);
  });

  it("keeps duplicate operationalOrder/create idempotent", async () => {
    const fixture = await createFixture();
    const orderLocalId = `${runId}-operational-order-duplicate`;

    await push(fixture, [
      buildEvent("operational-order-duplicate-a", "operationalOrder", {
        entityLocalId: orderLocalId,
        payload: { status: "open", totalCents: 1800 },
      }),
    ]);
    const duplicate = await push(fixture, [
      buildEvent("operational-order-duplicate-b", "operationalOrder", {
        entityLocalId: orderLocalId,
        payload: { status: "open", totalCents: 1800 },
      }),
    ]);

    assert.equal(
      (duplicate.data as { summary: { duplicates: number } }).summary
        .duplicates,
      1,
    );
    const ordersCount = await prisma.operationalOrder.count({
      where: { companyId: fixture.companyId, localUuid: orderLocalId },
    });
    assert.equal(ordersCount, 1);
  });

  it("materializes operationalOrder/update status changes", async () => {
    const fixture = await createFixture();
    const orderLocalId = `${runId}-operational-order-update`;
    await push(fixture, [
      buildEvent("operational-order-update-create", "operationalOrder", {
        entityLocalId: orderLocalId,
        payload: { status: "open", totalCents: 1800 },
      }),
    ]);

    const response = await push(fixture, [
      buildEvent("operational-order-update-close", "operationalOrder", {
        operation: "update",
        entityLocalId: orderLocalId,
        payload: { status: "closed", totalCents: 2000, notes: "Fechado" },
      }),
    ]);

    assert.equal(response.status, 202);
    const order = await prisma.operationalOrder.findUniqueOrThrow({
      where: {
        companyId_localUuid: {
          companyId: fixture.companyId,
          localUuid: orderLocalId,
        },
      },
    });
    assert.equal(order.status, "closed");
    assert.equal(order.totalCents, 2000);
    assert.equal(order.lastLocalSequence, null);
    assert.notEqual(order.closedAt, null);
  });

  it("accepts two operationalOrder updates with increasing localSequence", async () => {
    const fixture = await createFixture();
    const orderLocalId = `${runId}-operational-order-sequence`;
    await push(fixture, [
      buildEvent("operational-order-sequence-create", "operationalOrder", {
        entityLocalId: orderLocalId,
        payload: {
          status: "open",
          totalCents: 1000,
          _sync: { entityLocalId: orderLocalId, localSequence: 1 },
        },
      }),
    ]);
    const created = await prisma.operationalOrder.findUniqueOrThrow({
      where: {
        companyId_localUuid: {
          companyId: fixture.companyId,
          localUuid: orderLocalId,
        },
      },
    });
    assert.equal(created.lastLocalSequence, 1);

    const firstUpdate = await push(fixture, [
      buildEvent("operational-order-sequence-update-a", "operationalOrder", {
        operation: "update",
        entityLocalId: orderLocalId,
        payload: {
          status: "open",
          totalCents: 1200,
          _sync: { entityLocalId: orderLocalId, localSequence: 2 },
        },
      }),
    ]);
    const secondUpdate = await push(fixture, [
      buildEvent("operational-order-sequence-update-b", "operationalOrder", {
        operation: "update",
        entityLocalId: orderLocalId,
        payload: {
          status: "open",
          totalCents: 1500,
          _sync: { entityLocalId: orderLocalId, localSequence: 3 },
        },
      }),
    ]);

    assert.equal(
      (firstUpdate.data as { summary: { accepted: number } }).summary.accepted,
      1,
    );
    assert.equal(
      (secondUpdate.data as { summary: { accepted: number } }).summary.accepted,
      1,
    );
    const order = await prisma.operationalOrder.findUniqueOrThrow({
      where: {
        companyId_localUuid: {
          companyId: fixture.companyId,
          localUuid: orderLocalId,
        },
      },
    });
    assert.equal(order.totalCents, 1500);
    assert.equal(order.lastLocalSequence, 3);
  });

  it("does not let stale operationalOrder localSequence overwrite newer state", async () => {
    const fixture = await createFixture();
    const orderLocalId = `${runId}-operational-order-stale-sequence`;
    await push(fixture, [
      buildEvent("operational-order-stale-create", "operationalOrder", {
        entityLocalId: orderLocalId,
        payload: {
          status: "open",
          totalCents: 1000,
          _sync: { entityLocalId: orderLocalId, localSequence: 10 },
        },
      }),
    ]);
    await push(fixture, [
      buildEvent("operational-order-stale-update-newer", "operationalOrder", {
        operation: "update",
        entityLocalId: orderLocalId,
        payload: {
          status: "open",
          totalCents: 2000,
          _sync: { entityLocalId: orderLocalId, localSequence: 20 },
        },
      }),
    ]);

    const stale = await push(fixture, [
      buildEvent("operational-order-stale-update-older", "operationalOrder", {
        operation: "update",
        entityLocalId: orderLocalId,
        payload: {
          status: "open",
          totalCents: 1500,
          _sync: { entityLocalId: orderLocalId, localSequence: 15 },
        },
      }),
    ]);

    assert.equal(
      (stale.data as { conflicts: Array<{ code: string }> }).conflicts[0]?.code,
      "STALE_LOCAL_SEQUENCE",
    );
    const order = await prisma.operationalOrder.findUniqueOrThrow({
      where: {
        companyId_localUuid: {
          companyId: fixture.companyId,
          localUuid: orderLocalId,
        },
      },
    });
    assert.equal(order.totalCents, 2000);
    assert.equal(order.lastLocalSequence, 20);
  });

  it("materializes operationalOrderItem/create", async () => {
    const fixture = await createFixture();
    const orderLocalId = `${runId}-order-item-order`;
    const itemLocalId = `${runId}-order-item`;
    await push(fixture, [
      buildEvent("order-item-order-create", "operationalOrder", {
        entityLocalId: orderLocalId,
        payload: { status: "open", totalCents: 1500 },
      }),
    ]);

    const response = await push(fixture, [
      buildEvent("order-item-create", "operationalOrderItem", {
        entityLocalId: itemLocalId,
        payload: {
          operationalOrderLocalId: orderLocalId,
          description: "Item avulso",
          quantityMil: 1000,
          unitPriceCents: 1500,
          totalCents: 1500,
        },
      }),
    ]);

    assert.equal(response.status, 202);
    const item = await prisma.operationalOrderItem.findUniqueOrThrow({
      where: {
        companyId_localUuid: {
          companyId: fixture.companyId,
          localUuid: itemLocalId,
        },
      },
    });
    assert.equal(item.description, "Item avulso");
    assert.equal(item.quantityMil, 1000);
    assert.equal(item.totalCents, 1500);
  });

  it("normalizes legacy operationalOrderItem/create without totalCents", async () => {
    const fixture = await createFixture();
    const orderLocalId = `${runId}-order-item-legacy-total-order`;
    const itemLocalId = `${runId}-order-item-legacy-total`;
    await push(fixture, [
      buildEvent("order-item-legacy-total-order-create", "operationalOrder", {
        entityLocalId: orderLocalId,
        payload: { status: "open", totalCents: 1800 },
      }),
    ]);

    const response = await push(fixture, [
      buildEvent("order-item-legacy-total-create", "operationalOrderItem", {
        entityLocalId: itemLocalId,
        payload: {
          operationalOrderLocalId: orderLocalId,
          description: "Produto legado",
          quantityMil: 1000,
          unitPriceCents: 1800,
        },
      }),
    ]);

    assert.equal(response.status, 202);
    const item = await prisma.operationalOrderItem.findUniqueOrThrow({
      where: {
        companyId_localUuid: {
          companyId: fixture.companyId,
          localUuid: itemLocalId,
        },
      },
    });
    assert.equal(item.totalCents, 1800);
  });

  it("rejects operationalOrderItem/create with negative totalCents", async () => {
    const fixture = await createFixture();
    const orderLocalId = `${runId}-order-item-negative-total-order`;
    await push(fixture, [
      buildEvent("order-item-negative-total-order-create", "operationalOrder", {
        entityLocalId: orderLocalId,
        payload: { status: "open", totalCents: 1000 },
      }),
    ]);

    const response = await push(fixture, [
      buildEvent("order-item-negative-total-create", "operationalOrderItem", {
        entityLocalId: `${runId}-order-item-negative-total`,
        payload: {
          operationalOrderLocalId: orderLocalId,
          description: "Total invalido",
          quantityMil: 1000,
          unitPriceCents: 1000,
          totalCents: -1,
        },
      }),
    ]);

    const payload = response.data as {
      rejected: Array<{ code: string; message: string }>;
    };
    assert.equal(payload.rejected[0]?.code, "INVALID_TOTAL");
    assert.match(payload.rejected[0]?.message ?? "", /maior ou igual a zero/);
  });

  it("rejects operationalOrderItem/create without enough data to derive totalCents", async () => {
    const fixture = await createFixture();
    const orderLocalId = `${runId}-order-item-missing-total-order`;
    await push(fixture, [
      buildEvent("order-item-missing-total-order-create", "operationalOrder", {
        entityLocalId: orderLocalId,
        payload: { status: "open", totalCents: 1000 },
      }),
    ]);

    const response = await push(fixture, [
      buildEvent("order-item-missing-total-create", "operationalOrderItem", {
        entityLocalId: `${runId}-order-item-missing-total`,
        payload: {
          operationalOrderLocalId: orderLocalId,
          description: "Sem total",
          quantityMil: 1000,
        },
      }),
    ]);

    const payload = response.data as {
      rejected: Array<{ code: string; message: string }>;
    };
    assert.equal(payload.rejected[0]?.code, "INVALID_TOTAL");
    assert.match(payload.rejected[0]?.message ?? "", /dados suficientes/);
  });

  it("defers operationalOrderItem before parent and materializes after operationalOrder arrives", async () => {
    const fixture = await createFixture();
    const orderLocalId = `${runId}-order-item-deferred-order`;
    const itemLocalId = `${runId}-order-item-deferred`;

    const response = await push(fixture, [
      buildEvent("order-item-deferred-create", "operationalOrderItem", {
        entityLocalId: itemLocalId,
        payload: {
          operationalOrderLocalId: orderLocalId,
          description: "Item em espera",
          quantityMil: 1000,
          unitPriceCents: 12500,
          totalCents: 12500,
        },
      }),
      buildEvent("order-item-deferred-order-create", "operationalOrder", {
        entityLocalId: orderLocalId,
        payload: { status: "open", totalCents: 12500 },
      }),
    ]);

    assert.equal(response.status, 202);
    assert.equal(
      (response.data as { summary: { conflicts: number } }).summary.conflicts,
      0,
    );

    const item = await prisma.operationalOrderItem.findUniqueOrThrow({
      where: {
        companyId_localUuid: {
          companyId: fixture.companyId,
          localUuid: itemLocalId,
        },
      },
    });
    assert.equal(item.description, "Item em espera");

    const pending = await prisma.syncEvent.count({
      where: {
        companyId: fixture.companyId,
        eventId: "order-item-deferred-create",
        status: "PENDING",
      },
    });
    assert.equal(pending, 0);
  });

  it("keeps operationalOrderItem with missing local parent pending instead of final conflict", async () => {
    const fixture = await createFixture();

    const response = await push(fixture, [
      buildEvent("order-item-without-order", "operationalOrderItem", {
        entityLocalId: `${runId}-order-item-without-order`,
        payload: {
          operationalOrderLocalId: `${runId}-missing-order`,
          description: "Item perdido",
          quantityMil: 1000,
          totalCents: 1000,
        },
      }),
    ]);

    assert.equal(
      (response.data as { summary: { conflicts: number; accepted: number } })
        .summary.conflicts,
      0,
    );
    assert.equal(
      (response.data as { summary: { conflicts: number; accepted: number } })
        .summary.accepted,
      1,
    );

    const pending = await prisma.syncEvent.findFirstOrThrow({
      where: {
        companyId: fixture.companyId,
        eventId: "order-item-without-order",
      },
    });
    assert.equal(pending.status, "PENDING");
    assert.equal(pending.rejectionCode, "OPERATIONAL_ORDER_NOT_FOUND");
  });

  it("creates a clear conflict when operationalOrderItem has no order reference", async () => {
    const fixture = await createFixture();

    const response = await push(fixture, [
      buildEvent("order-item-no-order-reference", "operationalOrderItem", {
        entityLocalId: `${runId}-order-item-no-order-reference`,
        payload: {
          description: "Item sem pedido",
          quantityMil: 1000,
          totalCents: 1000,
        },
      }),
    ]);

    assert.equal(
      (response.data as { conflicts: Array<{ code: string }> }).conflicts[0]
        ?.code,
      "OPERATIONAL_ORDER_REFERENCE_REQUIRED",
    );
  });

  it("blocks operationalOrderItem that references another company order", async () => {
    const fixture = await createFixture();
    const otherFixture = await createFixture();
    const otherOrderLocalId = `${runId}-other-company-order`;
    await push(otherFixture, [
      buildEvent("other-company-order-create", "operationalOrder", {
        entityLocalId: otherOrderLocalId,
        payload: { status: "open", totalCents: 1000 },
      }),
    ]);
    const otherOrder = await prisma.operationalOrder.findUniqueOrThrow({
      where: {
        companyId_localUuid: {
          companyId: otherFixture.companyId,
          localUuid: otherOrderLocalId,
        },
      },
    });

    const response = await push(fixture, [
      buildEvent("order-item-other-company-order", "operationalOrderItem", {
        entityLocalId: `${runId}-order-item-other-company-order`,
        payload: {
          operationalOrderId: otherOrder.id,
          description: "Item cruzado",
          quantityMil: 1000,
          totalCents: 1000,
        },
      }),
    ]);

    assert.equal(
      (response.data as { conflicts: Array<{ code: string }> }).conflicts[0]
        ?.code,
      "OPERATIONAL_ORDER_COMPANY_MISMATCH",
    );
  });

  it("keeps duplicate operationalOrderItem/create idempotent", async () => {
    const fixture = await createFixture();
    const orderLocalId = `${runId}-order-item-duplicate-order`;
    const itemLocalId = `${runId}-order-item-duplicate`;
    await push(fixture, [
      buildEvent("order-item-duplicate-order-create", "operationalOrder", {
        entityLocalId: orderLocalId,
        payload: { status: "open", totalCents: 1000 },
      }),
    ]);
    await push(fixture, [
      buildEvent("order-item-duplicate-a", "operationalOrderItem", {
        entityLocalId: itemLocalId,
        payload: {
          operationalOrderLocalId: orderLocalId,
          description: "Cafe",
          quantityMil: 1000,
          totalCents: 1000,
        },
      }),
    ]);

    const duplicate = await push(fixture, [
      buildEvent("order-item-duplicate-b", "operationalOrderItem", {
        entityLocalId: itemLocalId,
        payload: {
          operationalOrderLocalId: orderLocalId,
          description: "Cafe",
          quantityMil: 1000,
          totalCents: 1000,
        },
      }),
    ]);

    assert.equal(
      (duplicate.data as { summary: { duplicates: number } }).summary
        .duplicates,
      1,
    );
    const count = await prisma.operationalOrderItem.count({
      where: { companyId: fixture.companyId, localUuid: itemLocalId },
    });
    assert.equal(count, 1);
  });

  it("deduplicates operationalOrderItem/create by _sync idempotencyKey", async () => {
    const fixture = await createFixture();
    const orderLocalId = `${runId}-order-item-sync-order`;
    const itemKey = `${runId}-order-item-sync-key`;
    await push(fixture, [
      buildEvent("order-item-sync-order-create", "operationalOrder", {
        entityLocalId: orderLocalId,
        payload: { status: "open", totalCents: 1000 },
      }),
    ]);
    await push(fixture, [
      buildEvent("order-item-sync-create-a", "operationalOrderItem", {
        entityLocalId: `${runId}-order-item-sync-a`,
        payload: {
          operationalOrderLocalId: orderLocalId,
          description: "Cafe",
          quantityMil: 1000,
          totalCents: 1000,
          _sync: { idempotencyKey: itemKey, localSequence: 1 },
        },
      }),
    ]);

    const duplicate = await push(fixture, [
      buildEvent("order-item-sync-create-b", "operationalOrderItem", {
        entityLocalId: `${runId}-order-item-sync-b`,
        payload: {
          operationalOrderLocalId: orderLocalId,
          description: "Cafe",
          quantityMil: 1000,
          totalCents: 1000,
          _sync: { idempotencyKey: itemKey, localSequence: 2 },
        },
      }),
    ]);

    assert.equal(
      (duplicate.data as { summary: { duplicates: number } }).summary
        .duplicates,
      1,
    );
    const count = await prisma.operationalOrderItem.count({
      where: { companyId: fixture.companyId, localUuid: itemKey },
    });
    assert.equal(count, 1);
  });

  it("marks operationalOrder as converted when sale/create references it", async () => {
    const fixture = await createFixture();
    const orderLocalId = `${runId}-order-sale-conversion`;
    const saleLocalId = `${runId}-sale-from-order`;
    await push(fixture, [
      buildEvent("order-sale-conversion-create", "operationalOrder", {
        entityLocalId: orderLocalId,
        payload: { status: "open", totalCents: 4500 },
      }),
    ]);

    const response = await push(fixture, [
      buildEvent("sale-from-operational-order", "sale", {
        entityLocalId: saleLocalId,
        payload: {
          status: "finalized",
          totalCents: 4500,
          operationalOrderLocalId: orderLocalId,
        },
      }),
    ]);

    assert.equal(response.status, 202);
    const [order, sale] = await Promise.all([
      prisma.operationalOrder.findUniqueOrThrow({
        where: {
          companyId_localUuid: {
            companyId: fixture.companyId,
            localUuid: orderLocalId,
          },
        },
      }),
      prisma.sale.findUniqueOrThrow({
        where: {
          companyId_localUuid: {
            companyId: fixture.companyId,
            localUuid: saleLocalId,
          },
        },
      }),
    ]);
    assert.equal(order.status, "converted");
    assert.equal(order.convertedSaleId, sale.id);
    assert.notEqual(order.closedAt, null);
  });

  it("creates OPERATIONAL_ORDER_IMMUTABLE when updating a converted order", async () => {
    const fixture = await createFixture();
    const orderLocalId = `${runId}-converted-order`;
    await push(fixture, [
      buildEvent("converted-order-create", "operationalOrder", {
        entityLocalId: orderLocalId,
        payload: { status: "open", totalCents: 4500 },
      }),
    ]);
    await push(fixture, [
      buildEvent("converted-order-sale", "sale", {
        entityLocalId: `${runId}-converted-order-sale`,
        payload: {
          status: "finalized",
          totalCents: 4500,
          operationalOrderLocalId: orderLocalId,
        },
      }),
    ]);

    const response = await push(fixture, [
      buildEvent("converted-order-update-conflict", "operationalOrder", {
        operation: "update",
        entityLocalId: orderLocalId,
        payload: { status: "open", totalCents: 4000 },
      }),
    ]);

    assert.equal(
      (response.data as { conflicts: Array<{ code: string }> }).conflicts[0]
        ?.code,
      "OPERATIONAL_ORDER_IMMUTABLE",
    );
  });

  it("does not create product or customer records from operational sync events", async () => {
    const fixture = await createFixture();
    const orderLocalId = `${runId}-free-description-order`;
    const missingCustomerId = "22222222-2222-4222-8222-222222222222";
    const missingProductId = "33333333-3333-4333-8333-333333333333";
    await push(fixture, [
      buildEvent("free-description-order-create", "operationalOrder", {
        entityLocalId: orderLocalId,
        payload: {
          status: "open",
          totalCents: 1000,
          customerId: missingCustomerId,
        },
      }),
      buildEvent("free-description-item-create", "operationalOrderItem", {
        entityLocalId: `${runId}-free-description-item`,
        payload: {
          operationalOrderLocalId: orderLocalId,
          productId: missingProductId,
          description: "Produto digitado no PDV",
          quantityMil: 1000,
          totalCents: 1000,
        },
      }),
    ]);

    const [customersCount, productsCount, order] = await Promise.all([
      prisma.customer.count({
        where: { companyId: fixture.companyId, id: missingCustomerId },
      }),
      prisma.product.count({
        where: { companyId: fixture.companyId, id: missingProductId },
      }),
      prisma.operationalOrder.findUniqueOrThrow({
        where: {
          companyId_localUuid: {
            companyId: fixture.companyId,
            localUuid: orderLocalId,
          },
        },
      }),
    ]);

    assert.equal(customersCount, 0);
    assert.equal(productsCount, 0);
    assert.equal(order.customerId, null);
  });

  it("pulls operationalOrder event only for the same company with entityServerId", async () => {
    const fixture = await createFixture();
    const otherFixture = await createFixture();
    await push(fixture, [
      buildEvent("pull-operational-order", "operationalOrder", {
        entityLocalId: `${runId}-pull-operational-order`,
        payload: { status: "open", totalCents: 1000 },
      }),
    ]);
    await push(otherFixture, [
      buildEvent("pull-other-operational-order", "operationalOrder", {
        entityLocalId: `${runId}-pull-other-operational-order`,
        payload: { status: "open", totalCents: 1000 },
      }),
    ]);

    const response = await requestJson("GET", "/sync/pull?sinceVersion=0", {
      token: fixture.token,
    });

    const events = (
      response.data as {
        events: Array<{
          eventId: string;
          entity: string;
          entityServerId: string | null;
        }>;
      }
    ).events;
    assert.deepEqual(
      events.map((event) => event.eventId),
      ["pull-operational-order"],
    );
    assert.equal(events[0]?.entity, "operationalOrder");
    assert.notEqual(events[0]?.entityServerId, null);
  });

  it("device B pulls a sale created by device A with projection", async () => {
    const deviceA = await createFixture({ role: "ADMIN" });
    const deviceB = await createAdditionalDevice(deviceA);
    await push(deviceA, [
      buildEvent("pull-sale-projection", "sale", {
        entityLocalId: `${runId}-pull-sale-projection`,
        payload: {
          status: "finalized",
          totalCents: 4500,
          receiptNumber: `${runId}-receipt-sale-projection`,
        },
      }),
    ]);

    const response = await pull(deviceB, {
      sinceVersion: 0,
      includeOwnEvents: false,
    });

    assert.equal(response.status, 200);
    const events = (response.data as PullResponse).events;
    assert.equal(events.length, 1);
    assert.equal(events[0]?.eventId, "pull-sale-projection");
    assert.equal(events[0]?.entity, "sale");
    assert.equal(events[0]?.projectionWarning, null);
    assert.notEqual(events[0]?.entityServerId, null);
    assert.equal(
      events[0]?.projection?.entityServerId,
      events[0]?.entityServerId,
    );
    assert.equal(events[0]?.projection?.total.totalAmountCents, 4500);
    assert.equal(
      events[0]?.projection?.receiptNumber,
      `${runId}-receipt-sale-projection`,
    );
  });

  it("device B pulls an operationalOrder created by device A with projection", async () => {
    const deviceA = await createFixture({ role: "ADMIN" });
    const deviceB = await createAdditionalDevice(deviceA);
    await push(deviceA, [
      buildEvent("pull-order-projection", "operationalOrder", {
        entityLocalId: `${runId}-pull-order-projection`,
        payload: {
          status: "open",
          subtotalCents: 2000,
          discountCents: 100,
          totalCents: 1900,
        },
      }),
    ]);

    const response = await pull(deviceB, {
      sinceVersion: 0,
      includeOwnEvents: false,
    });

    const events = (response.data as PullResponse).events;
    assert.equal(events.length, 1);
    assert.equal(events[0]?.entity, "operationalOrder");
    assert.equal(
      events[0]?.projection?.entityServerId,
      events[0]?.entityServerId,
    );
    assert.equal(events[0]?.projection?.status, "open");
    assert.equal(events[0]?.projection?.totals.totalCents, 1900);
    assert.equal(events[0]?.projection?.itemsCount, 0);
  });

  it("device B pulls cashSession and cashMovement projections", async () => {
    const deviceA = await createFixture();
    const deviceB = await createAdditionalDevice(deviceA);
    const cashSessionLocalId = `${runId}-cash-session-pull`;
    await push(deviceA, [
      buildEvent("pull-cash-session-projection", "cashSession", {
        feature: "cash",
        entityLocalId: cashSessionLocalId,
        payload: {
          status: "open",
          operatorName: "Operadora A",
          openingBalanceCents: 1000,
          openedAt: new Date().toISOString(),
        },
      }),
      buildEvent("pull-cash-movement-projection", "cashMovement", {
        feature: "cash",
        entityLocalId: `${runId}-cash-movement-pull`,
        payload: {
          cashSessionLocalId,
          type: "cash_in",
          amountCents: 2500,
          reason: "reforco",
        },
      }),
    ]);

    const response = await pull(deviceB, {
      sinceVersion: 0,
      features: "cash",
      includeOwnEvents: false,
    });

    const events = (response.data as PullResponse).events;
    assert.deepEqual(
      events.map((event) => event.entity),
      ["cashSession", "cashMovement"],
    );
    assert.equal(events[0]?.projection?.totals.openingBalanceCents, 1000);
    assert.equal(events[0]?.projection?.operatorName, "Operadora A");
    assert.equal(events[1]?.projection?.amountCents, 2500);
    assert.equal(
      events[1]?.projection?.cashSessionId,
      events[0]?.entityServerId,
    );
  });

  it("device B pulls stockDeduction projection from device A", async () => {
    const deviceA = await createFixture();
    const deviceB = await createAdditionalDevice(deviceA);
    const product = await createProduct(deviceA, { stockMil: 5000 });
    await push(deviceA, [
      buildEvent("pull-stock-deduction-projection", "stockDeduction", {
        entityLocalId: `${runId}-stock-deduction-pull`,
        payload: {
          productId: product.id,
          productLocalId: 1,
          quantityMil: 1000,
        },
      }),
    ]);

    const response = await pull(deviceB, {
      sinceVersion: 0,
      includeOwnEvents: false,
    });

    const events = (response.data as PullResponse).events;
    assert.equal(events.length, 1);
    assert.equal(events[0]?.entity, "stockDeduction");
    assert.equal(events[0]?.projection?.productId, product.id);
    assert.equal(events[0]?.projection?.productVariantId, null);
    assert.equal(events[0]?.projection?.quantityMil, 1000);
  });

  it("pulls only local-first PDV events from the same company", async () => {
    const fixture = await createFixture();
    const otherFixture = await createFixture();
    await push(fixture, [
      buildEvent("pull-sale", "sale"),
      buildEvent("pull-product-rejected", "product"),
      buildEvent("pull-customer-rejected", "customer"),
    ]);
    await push(otherFixture, [buildEvent("other-company-sale", "sale")]);

    const response = await requestJson("GET", "/sync/pull?sinceVersion=0", {
      token: fixture.token,
    });

    assert.equal(response.status, 200);
    const events = (
      response.data as {
        events: Array<{ eventId: string; entity: string }>;
      }
    ).events;
    assert.deepEqual(
      events.map((event) => event.eventId),
      ["pull-sale"],
    );
    assert.ok(events.every((event) => event.entity !== "product"));
    assert.ok(events.every((event) => event.entity !== "customer"));
  });

  it("pull respects sinceVersion and limit", async () => {
    const fixture = await createFixture();
    const firstPush = await push(fixture, [
      buildEvent("pull-version-first", "sale"),
    ]);
    await push(fixture, [buildEvent("pull-version-second", "sale")]);

    const firstVersion = (
      firstPush.data as {
        accepted: Array<{ serverVersion: string }>;
      }
    ).accepted[0]!.serverVersion;

    const sinceResponse = await pull(fixture, {
      sinceVersion: Number(firstVersion),
    });
    assert.deepEqual(
      (sinceResponse.data as PullResponse).events.map((event) => event.eventId),
      ["pull-version-second"],
    );

    const limitedResponse = await pull(fixture, { sinceVersion: 0, limit: 1 });
    const limitedPayload = limitedResponse.data as PullResponse;
    assert.equal(limitedPayload.events.length, 1);
    assert.equal(limitedPayload.hasMore, true);
    assert.equal(limitedPayload.nextSinceVersion, firstVersion);
  });

  it("returns projection null with warning for materialized events without projection", async () => {
    const fixture = await createFixture();
    await push(fixture, [
      buildEvent("pull-offline-log-no-projection", "offlineOperationLog", {
        payload: { message: "diagnostic only" },
      }),
    ]);

    const response = await pull(fixture, { sinceVersion: 0 });
    const events = (response.data as PullResponse).events;

    assert.equal(events.length, 1);
    assert.equal(events[0]?.entity, "offlineOperationLog");
    assert.equal(events[0]?.projection, null);
    assert.equal(
      events[0]?.projectionWarning,
      "PROJECTION_NOT_AVAILABLE_FOR_ENTITY",
    );
  });

  it("returns sync status counters and review/error flags", async () => {
    const fixture = await createFixture();
    await push(fixture, [
      buildEvent("status-sale", "sale", {
        entityLocalId: `${runId}-status-sale`,
        payload: { status: "finalized", totalCents: 1000 },
      }),
    ]);
    await push(fixture, [
      buildEvent("status-stock-conflict", "stockDeduction", {
        payload: {
          productId: 1,
          productLocalId: 1,
          quantityDeltaMil: -1000,
        },
      }),
    ]);
    await push(fixture, [
      buildEvent("status-payment-failure", "payment", {
        payload: {
          saleLocalId: `${runId}-status-sale`,
          amountCents: 3_000_000_000,
        },
      }),
    ]);

    const response = await requestJson("GET", "/sync/status", {
      token: fixture.token,
    });

    assert.equal(response.status, 200);
    const payload = response.data as {
      currentServerVersion: string;
      checkpoints: Array<{ feature: string; lastServerVersion: string }>;
      openConflictsCount: number;
      requiresReviewCount: number;
      pendingCount: number;
      acceptedCount: number;
      duplicateCount: number;
      conflictCount: number;
      rejectedCount: number;
      failedCount: number;
      errorCount: number;
      requiresReview: boolean;
      hasError: boolean;
      lastMaterializedAt: string | null;
    };
    assert.equal(payload.currentServerVersion, "2");
    assert.equal(payload.checkpoints[0]?.feature, "pdv");
    assert.equal(payload.checkpoints[0]?.lastServerVersion, "2");
    assert.equal(payload.openConflictsCount, 1);
    assert.equal(payload.requiresReviewCount, 1);
    assert.equal(payload.pendingCount, 0);
    assert.equal(payload.acceptedCount, 1);
    assert.equal(payload.duplicateCount, 0);
    assert.equal(payload.conflictCount, 1);
    assert.equal(payload.rejectedCount, 0);
    assert.equal(payload.failedCount, 1);
    assert.equal(payload.errorCount, 1);
    assert.equal(payload.requiresReview, true);
    assert.equal(payload.hasError, true);
    assert.notEqual(payload.lastMaterializedAt, null);
  });

  it("resolves open PDV conflicts", async () => {
    const fixture = await createFixture();
    const entityLocalId = `${runId}-resolve-conflict-sale`;
    await push(fixture, [
      buildEvent("resolve-sale-create", "sale", {
        entityLocalId,
        payload: { status: "finalized" },
      }),
    ]);
    await push(fixture, [
      buildEvent("resolve-sale-update", "sale", {
        operation: "update",
        entityLocalId,
      }),
    ]);
    const conflict = await prisma.syncConflict.findFirstOrThrow({
      where: { companyId: fixture.companyId },
    });

    const response = await requestJson(
      "POST",
      `/sync/conflicts/${conflict.id}/resolve`,
      {
        token: fixture.token,
        body: { resolution: { action: "ignored_local_update" } },
      },
    );

    assert.equal(response.status, 200);
    assert.equal(
      (response.data as { conflict: { status: string } }).conflict.status,
      "RESOLVED",
    );
  });

  it("upserts device sync diagnostics without counting resolved conflicts as active", async () => {
    const fixture = await createFixture();

    const response = await requestJson("POST", "/sync/diagnostics", {
      token: fixture.token,
      body: {
        pendingCount: 0,
        failedCount: 3,
        openConflictCount: 0,
        resolvedConflictCount: 4,
        ignoredConflictCount: 1,
        lastLocalError:
          "operationalOrderItem precisa de totalCents maior ou igual a zero.",
        lastLocalErrorEntity: "operationalOrderItem",
        appVersion: "2.1.0",
        platform: "android",
        safeDetails: {
          eventIds: ["safe-event-id"],
          headers: { authorization: "Bearer secret" },
        },
      },
    });

    assert.equal(response.status, 200);
    const diagnostic = await prisma.deviceSyncDiagnostic.findUniqueOrThrow({
      where: {
        companyId_deviceId: {
          companyId: fixture.companyId,
          deviceId: fixture.deviceId,
        },
      },
    });
    assert.equal(diagnostic.failedCount, 3);
    assert.equal(diagnostic.openConflictCount, 0);
    assert.equal(diagnostic.resolvedConflictCount, 4);
    assert.equal(diagnostic.ignoredConflictCount, 1);
    assert.equal(diagnostic.lastLocalErrorEntity, "operationalOrderItem");
    assert.equal(diagnostic.clientType, "MOBILE_APP");
    assert.equal(diagnostic.appVersion, "2.1.0");
    assert.equal(diagnostic.platform, "android");
    assert.doesNotMatch(
      JSON.stringify(diagnostic.safeDetails),
      /Bearer secret/,
    );
  });

  it("delivers support commands only to the matching device and records completion", async () => {
    const fixture = await createFixture();
    const otherDevice = await createAdditionalDevice(fixture);
    const command = await prisma.syncSupportCommand.create({
      data: {
        companyId: fixture.companyId,
        deviceId: fixture.deviceId,
        actorUserId: fixture.userId,
        command: "CLEAR_RESOLVED_CONFLICT_CACHE",
        reason: "limpar cache antigo",
        confirmationText: "LIMPAR",
        expiresAt: new Date(Date.now() + 60_000),
      },
    });
    await prisma.syncSupportCommand.create({
      data: {
        companyId: fixture.companyId,
        deviceId: otherDevice.deviceId,
        actorUserId: fixture.userId,
        command: "FORCE_SYNC_PULL",
        reason: "outro device",
        confirmationText: "ATUALIZAR",
        expiresAt: new Date(Date.now() + 60_000),
      },
    });

    const pullOwn = await requestJson("GET", "/sync/support-commands", {
      token: fixture.token,
    });
    const pullOther = await requestJson("GET", "/sync/support-commands", {
      token: otherDevice.token,
    });

    assert.equal(pullOwn.status, 200);
    assert.equal(pullOther.status, 200);
    assert.deepEqual(
      (
        pullOwn.data as {
          items: Array<{ id: string; command: string; status: string }>;
        }
      ).items.map((item) => [item.id, item.command, item.status]),
      [[command.id, "CLEAR_RESOLVED_CONFLICT_CACHE", "PENDING"]],
    );
    assert.equal(
      (
        pullOther.data as {
          items: Array<{ command: string }>;
        }
      ).items[0]?.command,
      "FORCE_SYNC_PULL",
    );

    const wrongDeviceComplete = await requestJson(
      "POST",
      `/sync/support-commands/${command.id}/complete`,
      {
        token: otherDevice.token,
        body: { result: { shouldNotApply: true } },
      },
    );
    assert.equal(wrongDeviceComplete.status, 404);

    const started = await requestJson(
      "POST",
      `/sync/support-commands/${command.id}/start`,
      {
        token: fixture.token,
      },
    );
    assert.equal(started.status, 200);
    assert.equal(
      (started.data as { command: { status: string } }).command.status,
      "RUNNING",
    );

    const complete = await requestJson(
      "POST",
      `/sync/support-commands/${command.id}/complete`,
      {
        token: fixture.token,
        body: { result: { clearedConflicts: 4 } },
      },
    );
    assert.equal(complete.status, 200);
    const stored = await prisma.syncSupportCommand.findUniqueOrThrow({
      where: { id: command.id },
    });
    assert.equal(stored.status, "SUCCEEDED");
    assert.notEqual(stored.completedAt, null);
  });

  it("does not deliver expired support commands and rejects expired completion", async () => {
    const fixture = await createFixture();
    const expiredPending = await prisma.syncSupportCommand.create({
      data: {
        companyId: fixture.companyId,
        deviceId: fixture.deviceId,
        actorUserId: fixture.userId,
        command: "REFRESH_SYNC_STATUS",
        reason: "expirado antes da coleta",
        confirmationText: "RECALCULAR",
        expiresAt: new Date(Date.now() - 60_000),
      },
    });
    const expiredRunning = await prisma.syncSupportCommand.create({
      data: {
        companyId: fixture.companyId,
        deviceId: fixture.deviceId,
        actorUserId: fixture.userId,
        command: "FORCE_SYNC_PULL",
        status: "RUNNING",
        reason: "expirado em execucao",
        confirmationText: "ATUALIZAR",
        pickedUpAt: new Date(Date.now() - 120_000),
        expiresAt: new Date(Date.now() - 60_000),
      },
    });

    const completeExpired = await requestJson(
      "POST",
      `/sync/support-commands/${expiredRunning.id}/complete`,
      {
        token: fixture.token,
        body: { result: { completedAfterExpiry: true } },
      },
    );
    assert.equal(completeExpired.status, 409);
    assert.equal(
      (completeExpired.data as { code?: string }).code,
      "SYNC_SUPPORT_COMMAND_EXPIRED",
    );

    const pull = await requestJson("GET", "/sync/support-commands", {
      token: fixture.token,
    });
    assert.equal(pull.status, 200);
    assert.deepEqual((pull.data as { items: unknown[] }).items, []);

    const [pendingAfter, runningAfter] = await Promise.all([
      prisma.syncSupportCommand.findUniqueOrThrow({
        where: { id: expiredPending.id },
      }),
      prisma.syncSupportCommand.findUniqueOrThrow({
        where: { id: expiredRunning.id },
      }),
    ]);
    assert.equal(pendingAfter.status, "EXPIRED");
    assert.equal(runningAfter.status, "EXPIRED");
  });

  it("reprocesses existing OPERATIONAL_ORDER_NOT_FOUND when parent order exists", async () => {
    const fixture = await createFixture();
    const orderLocalUuid = `${runId}-reprocess-order`;
    const legacyOrderLocalId = 4;
    await push(fixture, [
      buildEvent("reprocess-order-create", "operationalOrder", {
        entityLocalId: orderLocalUuid,
        payload: {
          localId: legacyOrderLocalId,
          uuid: orderLocalUuid,
          status: "open",
          totalCents: 12500,
        },
      }),
    ]);

    const syncEvent = await prisma.syncEvent.create({
      data: {
        companyId: fixture.companyId,
        deviceId: fixture.deviceId,
        userId: fixture.userId,
        eventId: "reprocess-order-item-conflict",
        feature: "pdv",
        entity: "operationalOrderItem",
        operation: "create",
        entityLocalId: `${runId}-reprocess-order-item`,
        occurredAt: new Date(),
        payload: {
          uuid: `${runId}-reprocess-order-item`,
          operationalOrderId: legacyOrderLocalId,
          description: "Item legado",
          quantityMil: 1000,
          totalCents: 12500,
        },
        status: "CONFLICT",
        serverVersion: BigInt(99),
      },
    });
    const conflict = await prisma.syncConflict.create({
      data: {
        companyId: fixture.companyId,
        deviceId: fixture.deviceId,
        userId: fixture.userId,
        syncEventId: syncEvent.id,
        entity: "operationalOrderItem",
        entityLocalId: `${runId}-reprocess-order-item`,
        code: "OPERATIONAL_ORDER_NOT_FOUND",
        message: "Pedido operacional nao encontrado para materializar item.",
        payload: { operationalOrderId: legacyOrderLocalId },
      },
    });

    const response = await requestJson(
      "POST",
      `/sync/conflicts/${conflict.id}/reprocess`,
      { token: fixture.token },
    );

    assert.equal(response.status, 200);
    assert.equal((response.data as { status: string }).status, "reprocessed");

    const item = await prisma.operationalOrderItem.findUniqueOrThrow({
      where: {
        companyId_localUuid: {
          companyId: fixture.companyId,
          localUuid: `${runId}-reprocess-order-item`,
        },
      },
    });
    assert.equal(item.totalCents, 12500);

    const resolved = await prisma.syncConflict.findUniqueOrThrow({
      where: { id: conflict.id },
    });
    assert.equal(resolved.status, "RESOLVED");
  });

  it("enforces the initial 100 events per push limit", async () => {
    const fixture = await createFixture();
    const events = Array.from({ length: 101 }, (_value, index) =>
      buildEvent(`too-many-${index}`, "sale"),
    );

    const response = await push(fixture, events);

    assert.equal(response.status, 413);
    assert.equal(
      (response.data as { code?: string }).code,
      "SYNC_BATCH_TOO_LARGE",
    );
  });
});

async function createFixture(options?: {
  syncEnabled?: boolean;
  role?: "OWNER" | "ADMIN" | "OPERATOR";
}) {
  const company = await prisma.company.create({
    data: {
      name: "Sync Real Company",
      legalName: "Sync Real Company LTDA",
      slug: `${runId}-company-${Date.now()}-${Math.random().toString(16).slice(2)}`,
    },
  });
  const user = await prisma.user.create({
    data: {
      email: `${runId}-${Date.now()}-${Math.random().toString(16).slice(2)}@tatuzin.test`,
      name: "Sync Real User",
      passwordHash: "not-used",
    },
  });
  const membership = await prisma.membership.create({
    data: {
      userId: user.id,
      companyId: company.id,
      role: options?.role ?? "OPERATOR",
      isDefault: true,
    },
  });
  await prisma.license.create({
    data: {
      companyId: company.id,
      plan: "pro",
      status: "ACTIVE",
      startsAt: new Date(),
      maxDevices: 5,
      syncEnabled: options?.syncEnabled ?? true,
    },
  });

  const clientInstanceId = `${runId}-device-${Date.now()}-${Math.random()
    .toString(16)
    .slice(2)}`;
  const device = await prisma.companyDevice.create({
    data: {
      companyId: company.id,
      userId: user.id,
      clientInstanceId,
      deviceLabel: "Sync Real Test Device",
      platform: "node-test",
      appVersion: "sync-real-test",
      status: "ACTIVE",
      approvedAt: new Date(),
      approvedByUserId: user.id,
      lastSeenAt: new Date(),
    },
  });

  return {
    companyId: company.id,
    userId: user.id,
    membershipId: membership.id,
    email: user.email,
    deviceId: device.id,
    clientInstanceId,
    token: signToken({
      userId: user.id,
      companyId: company.id,
      membershipId: membership.id,
      email: user.email,
      clientInstanceId,
    }),
  };
}

async function createAdditionalDevice(fixture: {
  companyId: string;
  userId: string;
  membershipId: string;
  email: string;
}) {
  const clientInstanceId = `${runId}-device-b-${Date.now()}-${Math.random()
    .toString(16)
    .slice(2)}`;
  const device = await prisma.companyDevice.create({
    data: {
      companyId: fixture.companyId,
      userId: fixture.userId,
      clientInstanceId,
      deviceLabel: "Sync Real Test Device B",
      platform: "node-test",
      appVersion: "sync-real-test",
      status: "ACTIVE",
      approvedAt: new Date(),
      approvedByUserId: fixture.userId,
      lastSeenAt: new Date(),
    },
  });

  return {
    companyId: fixture.companyId,
    userId: fixture.userId,
    membershipId: fixture.membershipId,
    email: fixture.email,
    deviceId: device.id,
    clientInstanceId,
    token: signToken({
      userId: fixture.userId,
      companyId: fixture.companyId,
      membershipId: fixture.membershipId,
      email: fixture.email,
      clientInstanceId,
    }),
  };
}

async function createProduct(
  fixture: { companyId: string },
  options?: { stockMil?: number },
) {
  return prisma.product.create({
    data: {
      companyId: fixture.companyId,
      localUuid: `${runId}-product-${Date.now()}-${Math.random()
        .toString(16)
        .slice(2)}`,
      name: "Produto Sync Materializer",
      salePriceCents: 1000,
      stockMil: options?.stockMil ?? 0,
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

function buildEvent(
  eventId: string,
  entity: string,
  overrides?: Partial<{
    feature: string;
    operation: string;
    entityLocalId: string;
    entityServerId: string;
    payload: Record<string, unknown>;
  }>,
) {
  return {
    eventId,
    feature: overrides?.feature ?? "pdv",
    entity,
    operation: overrides?.operation ?? "create",
    entityLocalId: overrides?.entityLocalId ?? `${eventId}-local`,
    entityServerId: overrides?.entityServerId,
    occurredAt: new Date().toISOString(),
    payload: overrides?.payload ?? { status: "finalized" },
  };
}

async function push(
  fixture: { token: string },
  events: Array<Record<string, unknown>>,
) {
  return requestJson("POST", "/sync/push", {
    token: fixture.token,
    body: { events },
  });
}

async function pull(
  fixture: { token: string },
  query: {
    sinceVersion: number;
    features?: string;
    limit?: number;
    includeOwnEvents?: boolean;
  },
) {
  const params = new URLSearchParams({
    sinceVersion: query.sinceVersion.toString(),
  });
  if (query.features != null) {
    params.set("features", query.features);
  }
  if (query.limit != null) {
    params.set("limit", query.limit.toString());
  }
  if (query.includeOwnEvents != null) {
    params.set("includeOwnEvents", String(query.includeOwnEvents));
  }
  return requestJson("GET", `/sync/pull?${params.toString()}`, {
    token: fixture.token,
  });
}

function signToken(input: {
  userId: string;
  companyId: string;
  membershipId: string;
  email: string;
  clientInstanceId: string;
}) {
  return jwt.sign(
    {
      sub: input.userId,
      companyId: input.companyId,
      membershipId: input.membershipId,
      membershipRole: "OPERATOR",
      email: input.email,
      isPlatformAdmin: false,
      clientInstanceId: input.clientInstanceId,
    },
    env.JWT_SECRET,
    { expiresIn: "15m" },
  );
}

async function requestJson(
  method: string,
  path: string,
  options?: { token?: string; body?: Record<string, unknown> },
) {
  const response = await fetch(`${apiBaseUrl}${path}`, {
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

async function cleanupFixtures() {
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
