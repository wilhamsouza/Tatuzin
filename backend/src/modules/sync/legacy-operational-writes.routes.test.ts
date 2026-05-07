import assert from "node:assert/strict";
import { after, before, beforeEach, describe, it } from "node:test";
import type { AddressInfo } from "node:net";

import type { Server } from "http";
import { SessionClientType } from "@prisma/client";
import jwt from "jsonwebtoken";

import { createApp } from "../../app";
import { env } from "../../config/env";
import { prisma } from "../../database/prisma";

const runId = `legacy-operational-writes-${Date.now()}`;
const pdvSyncErrorMessage =
  "Operações de PDV devem ser enviadas pela sincronização operacional.";

let server: Server;
let apiBaseUrl = "";

describe("legacy operational write routes", () => {
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

  it("blocks mobile_app from creating a sale directly outside sync push", async () => {
    const fixture = await createFixture(SessionClientType.MOBILE_APP);

    const response = await requestJson("POST", "/sales", {
      token: fixture.token,
      body: buildSaleBody("direct-sale-mobile"),
    });

    assert.equal(response.status, 403);
    assert.equal(
      (response.data as { code?: string }).code,
      "PDV_WRITES_MUST_USE_SYNC",
    );
    assert.equal((response.data as { message?: string }).message, pdvSyncErrorMessage);
    assert.equal(
      await prisma.sale.count({ where: { companyId: fixture.companyId } }),
      0,
    );
  });

  it("blocks mobile_app from creating a cash event directly outside sync push", async () => {
    const fixture = await createFixture(SessionClientType.MOBILE_APP);

    const response = await requestJson("POST", "/cash/events", {
      token: fixture.token,
      body: buildCashEventBody("direct-cash-mobile"),
    });

    assert.equal(response.status, 403);
    assert.equal(
      (response.data as { code?: string }).code,
      "PDV_WRITES_MUST_USE_SYNC",
    );
    assert.equal(
      await prisma.cashEvent.count({ where: { companyId: fixture.companyId } }),
      0,
    );
  });

  it("blocks mobile_app from creating legacy financial and fiado payments directly", async () => {
    const fixture = await createFixture(SessionClientType.MOBILE_APP);

    const financialResponse = await requestJson("POST", "/financial-events", {
      token: fixture.token,
      body: buildFinancialEventBody("direct-financial-mobile"),
    });
    const fiadoResponse = await requestJson("POST", "/fiado/payments", {
      token: fixture.token,
      body: buildFiadoPaymentBody("direct-fiado-mobile"),
    });

    assert.equal(financialResponse.status, 403);
    assert.equal(
      (financialResponse.data as { code?: string }).code,
      "PDV_WRITES_MUST_USE_SYNC",
    );
    assert.equal(fiadoResponse.status, 403);
    assert.equal(
      (fiadoResponse.data as { code?: string }).code,
      "PDV_WRITES_MUST_USE_SYNC",
    );
  });

  it("keeps admin_web direct sale writes available for legacy backoffice flows", async () => {
    const fixture = await createFixture(SessionClientType.ADMIN_WEB);

    const response = await requestJson("POST", "/sales", {
      token: fixture.token,
      body: buildSaleBody("direct-sale-admin"),
    });

    assert.equal(response.status, 201);
    assert.equal(
      await prisma.sale.count({ where: { companyId: fixture.companyId } }),
      1,
    );
  });

  it("keeps read endpoints available for mobile_app", async () => {
    const fixture = await createFixture(SessionClientType.MOBILE_APP);
    await prisma.sale.create({
      data: {
        companyId: fixture.companyId,
        localUuid: `${runId}-read-sale`,
        paymentType: "vista",
        paymentMethod: "dinheiro",
        status: "active",
        totalAmountCents: 1000,
        totalCostCents: 400,
        soldAt: new Date(),
      },
    });

    const response = await requestJson("GET", "/sales", {
      token: fixture.token,
    });

    assert.equal(response.status, 200);
    const payload = response.data as { items?: unknown[] };
    assert.equal(payload.items?.length, 1);
  });

  it("keeps sync materializers creating operational data", async () => {
    const fixture = await createFixture(SessionClientType.MOBILE_APP);

    const response = await requestJson("POST", "/sync/push", {
      token: fixture.token,
      body: {
        events: [
          buildSyncEvent("sync-sale-mobile", "sale", {
            status: "finalized",
            totalCents: 2500,
          }),
        ],
      },
    });

    assert.equal(response.status, 202);
    assert.equal(
      await prisma.sale.count({ where: { companyId: fixture.companyId } }),
      1,
    );
  });
});

async function createFixture(clientType: SessionClientType) {
  const company = await prisma.company.create({
    data: {
      name: "Legacy Operational Company",
      legalName: "Legacy Operational Company LTDA",
      slug: `${runId}-company-${Date.now()}-${Math.random()
        .toString(16)
        .slice(2)}`,
    },
  });
  const user = await prisma.user.create({
    data: {
      email: `${runId}-${Date.now()}-${Math.random()
        .toString(16)
        .slice(2)}@tatuzin.test`,
      name: "Legacy Operational User",
      passwordHash: "not-used",
    },
  });
  const membership = await prisma.membership.create({
    data: {
      userId: user.id,
      companyId: company.id,
      role: clientType === SessionClientType.ADMIN_WEB ? "ADMIN" : "OPERATOR",
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
      syncEnabled: true,
    },
  });

  const clientInstanceId = `${runId}-device-${Date.now()}-${Math.random()
    .toString(16)
    .slice(2)}`;
  await prisma.companyDevice.create({
    data: {
      companyId: company.id,
      userId: user.id,
      clientInstanceId,
      deviceLabel: "Legacy Operational Test Device",
      platform: "node-test",
      appVersion: "legacy-operational-test",
      status: "ACTIVE",
      approvedAt: new Date(),
      approvedByUserId: user.id,
      lastSeenAt: new Date(),
    },
  });

  const session = await prisma.deviceSession.create({
    data: {
      userId: user.id,
      companyId: company.id,
      membershipId: membership.id,
      clientType,
      clientInstanceId,
      deviceLabel: "Legacy Operational Test Device",
      platform: "node-test",
      appVersion: "legacy-operational-test",
      refreshTokenHash: `${runId}-refresh-${Date.now()}-${Math.random()
        .toString(16)
        .slice(2)}`,
      refreshTokenExpiresAt: new Date(Date.now() + 60 * 60 * 1000),
      lastSeenAt: new Date(),
    },
  });

  return {
    companyId: company.id,
    userId: user.id,
    membershipId: membership.id,
    email: user.email,
    clientInstanceId,
    sessionId: session.id,
    token: signToken({
      userId: user.id,
      companyId: company.id,
      membershipId: membership.id,
      membershipRole: membership.role,
      email: user.email,
      clientInstanceId,
      sessionId: session.id,
    }),
  };
}

function buildSaleBody(localUuid: string) {
  return {
    localUuid: `${runId}-${localUuid}`,
    receiptNumber: null,
    paymentType: "vista",
    paymentMethod: "dinheiro",
    status: "active",
    totalAmountCents: 1000,
    totalCostCents: 400,
    soldAt: new Date().toISOString(),
    notes: null,
    items: [
      {
        productId: null,
        productNameSnapshot: "Produto legado",
        quantityMil: 1000,
        unitPriceCents: 1000,
        totalPriceCents: 1000,
        unitCostCents: 400,
        totalCostCents: 400,
        unitMeasure: "un",
        productType: "simple",
      },
    ],
  };
}

function buildCashEventBody(localUuid: string) {
  return {
    localUuid: `${runId}-${localUuid}`,
    eventType: "entrada",
    amountCents: 1000,
    paymentMethod: "dinheiro",
    referenceType: null,
    referenceId: null,
    notes: null,
    createdAt: new Date().toISOString(),
  };
}

function buildFinancialEventBody(localUuid: string) {
  return {
    saleId: null,
    fiadoId: null,
    eventType: "fiado_payment",
    localUuid: `${runId}-${localUuid}`,
    amountCents: 1000,
    paymentType: "dinheiro",
    createdAt: new Date().toISOString(),
    metadata: null,
  };
}

function buildFiadoPaymentBody(localUuid: string) {
  return {
    saleId: "00000000-0000-0000-0000-000000000000",
    localUuid: `${runId}-${localUuid}`,
    amountCents: 1000,
    paymentMethod: "dinheiro",
    createdAt: new Date().toISOString(),
    notes: null,
  };
}

function buildSyncEvent(
  eventId: string,
  entity: string,
  payload: Record<string, unknown>,
) {
  return {
    eventId,
    feature: "pdv",
    entity,
    operation: "create",
    entityLocalId: `${runId}-${eventId}-local`,
    occurredAt: new Date().toISOString(),
    payload,
  };
}

function signToken(input: {
  userId: string;
  companyId: string;
  membershipId: string;
  membershipRole: string;
  email: string;
  clientInstanceId: string;
  sessionId: string;
}) {
  return jwt.sign(
    {
      sub: input.userId,
      companyId: input.companyId,
      membershipId: input.membershipId,
      membershipRole: input.membershipRole,
      email: input.email,
      isPlatformAdmin: false,
      clientInstanceId: input.clientInstanceId,
      sessionId: input.sessionId,
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
