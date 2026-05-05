import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';
import type { AddressInfo } from 'node:net';

import type { Server } from 'http';
import jwt from 'jsonwebtoken';

import { createApp } from '../../app';
import { env } from '../../config/env';
import { prisma } from '../../database/prisma';

const runId = `operational-orders-${Date.now()}`;

let server: Server;
let apiBaseUrl = '';

describe('operational orders read routes', () => {
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

  it('lists only orders from the authenticated company', async () => {
    const fixture = await createFixture();

    const response = await requestJson('GET', '/operational-orders', {
      token: fixture.token,
    });

    assert.equal(response.status, 200);
    const payload = response.data as {
      items: Array<{ id: string; localUuid: string; itemsCount: number }>;
      total: number;
      count: number;
    };
    assert.equal(payload.total, 3);
    assert.equal(payload.count, 3);
    assert.ok(payload.items.every((item) => item.localUuid.startsWith('tenant-a-')));
    assert.ok(
      payload.items.every((item) => item.id !== fixture.otherCompanyOrderId),
    );
    assert.ok(payload.items.some((item) => item.itemsCount === 2));
  });

  it('filters operational orders by status', async () => {
    const fixture = await createFixture();

    const response = await requestJson(
      'GET',
      '/operational-orders?status=closed',
      { token: fixture.token },
    );

    assert.equal(response.status, 200);
    const payload = response.data as {
      items: Array<{ id: string; status: string }>;
      total: number;
    };
    assert.equal(payload.total, 1);
    assert.equal(payload.items[0]?.id, fixture.closedOrderId);
    assert.equal(payload.items[0]?.status, 'closed');
  });

  it('filters operational orders by cashSessionId', async () => {
    const fixture = await createFixture();

    const response = await requestJson(
      'GET',
      `/operational-orders?cashSessionId=${encodeURIComponent(fixture.cashSessionId)}`,
      { token: fixture.token },
    );

    assert.equal(response.status, 200);
    const payload = response.data as {
      items: Array<{ id: string; cashSessionId: string | null }>;
      total: number;
    };
    assert.equal(payload.total, 2);
    assert.ok(
      payload.items.every((item) => item.cashSessionId === fixture.cashSessionId),
    );
  });

  it('returns order details with items and related basic data', async () => {
    const fixture = await createFixture();

    const response = await requestJson(
      'GET',
      `/operational-orders/${fixture.closedOrderId}`,
      { token: fixture.token },
    );

    assert.equal(response.status, 200);
    const payload = response.data as {
      order: {
        id: string;
        companyId: string;
        items: Array<{
          localUuid: string;
          description: string;
          quantityMil: number;
        }>;
        convertedSale: { id: string; localUuid: string } | null;
        customer: { id: string; name: string } | null;
        sellerUser: { id: string; name: string } | null;
        device: { id: string; clientInstanceId: string } | null;
      };
    };
    assert.equal(payload.order.id, fixture.closedOrderId);
    assert.equal(payload.order.companyId, fixture.companyId);
    assert.equal(payload.order.items.length, 2);
    assert.deepEqual(
      payload.order.items.map((item) => item.localUuid).sort(),
      ['tenant-a-item-1', 'tenant-a-item-2'],
    );
    assert.equal(payload.order.convertedSale?.id, fixture.convertedSaleId);
    assert.equal(payload.order.customer?.id, fixture.customerId);
    assert.equal(payload.order.customer?.name, 'Cliente Operacional');
    assert.equal(payload.order.sellerUser?.id, fixture.userId);
    assert.equal(payload.order.device?.id, fixture.deviceId);
  });

  it('lists items for an operational order', async () => {
    const fixture = await createFixture();

    const response = await requestJson(
      'GET',
      `/operational-orders/${fixture.closedOrderId}/items`,
      { token: fixture.token },
    );

    assert.equal(response.status, 200);
    const payload = response.data as {
      items: Array<{
        id: string;
        localUuid: string;
        productId: string | null;
        productVariantId: string | null;
        description: string;
        quantityMil: number;
        unitPriceCents: number;
        totalCents: number;
        createdAt: string;
        updatedAt: string;
      }>;
      count: number;
    };
    assert.equal(payload.count, 2);
    const cafe = payload.items.find((item) => item.localUuid === 'tenant-a-item-1');
    assert.ok(cafe);
    assert.equal(cafe.description, 'Cafe');
    assert.equal(cafe.quantityMil, 1000);
    assert.equal(cafe.unitPriceCents, 500);
    assert.equal(cafe.totalCents, 500);
    assert.equal(cafe.productId, null);
    assert.equal(cafe.productVariantId, null);
    assert.ok(cafe.createdAt);
    assert.ok(cafe.updatedAt);
  });

  it('finds an operational order by companyId and localUuid', async () => {
    const fixture = await createFixture();

    const response = await requestJson(
      'GET',
      '/operational-orders/by-local/tenant-a-open',
      { token: fixture.token },
    );

    assert.equal(response.status, 200);
    const payload = response.data as {
      order: { id: string; localUuid: string; status: string };
    };
    assert.equal(payload.order.id, fixture.openOrderId);
    assert.equal(payload.order.localUuid, 'tenant-a-open');
    assert.equal(payload.order.status, 'open');
  });

  it('returns 404 for an order from another company', async () => {
    const fixture = await createFixture();

    const detail = await requestJson(
      'GET',
      `/operational-orders/${fixture.otherCompanyOrderId}`,
      { token: fixture.token },
    );
    const items = await requestJson(
      'GET',
      `/operational-orders/${fixture.otherCompanyOrderId}/items`,
      { token: fixture.token },
    );
    const byLocal = await requestJson(
      'GET',
      '/operational-orders/by-local/tenant-b-open',
      { token: fixture.token },
    );

    assert.equal(detail.status, 404);
    assert.equal((detail.data as { code?: string }).code, 'OPERATIONAL_ORDER_NOT_FOUND');
    assert.equal(items.status, 404);
    assert.equal(byLocal.status, 404);
  });

  it('fails without app context', async () => {
    const response = await requestJson('GET', '/operational-orders');

    assert.equal(response.status, 401);
    assert.equal((response.data as { code?: string }).code, 'AUTH_REQUIRED');
  });

  it('does not create products or customers through read endpoints', async () => {
    const fixture = await createFixture();
    const before = await countProductsAndCustomers(fixture.companyId);

    await requestJson('GET', '/operational-orders', { token: fixture.token });
    await requestJson('GET', `/operational-orders/${fixture.closedOrderId}`, {
      token: fixture.token,
    });
    await requestJson(
      'GET',
      `/operational-orders/${fixture.closedOrderId}/items`,
      { token: fixture.token },
    );
    await requestJson('GET', '/operational-orders/by-local/tenant-a-open', {
      token: fixture.token,
    });

    const afterCounts = await countProductsAndCustomers(fixture.companyId);
    assert.deepEqual(afterCounts, before);
  });

  it('paginates operational order lists with limit and page', async () => {
    const fixture = await createFixture();

    const pageOne = await requestJson('GET', '/operational-orders?limit=2&page=1', {
      token: fixture.token,
    });
    const pageTwo = await requestJson('GET', '/operational-orders?limit=2&page=2', {
      token: fixture.token,
    });

    assert.equal(pageOne.status, 200);
    assert.equal(pageTwo.status, 200);
    const firstPayload = pageOne.data as {
      items: Array<{ id: string }>;
      page: number;
      pageSize: number;
      total: number;
      count: number;
      hasNext: boolean;
      hasPrevious: boolean;
    };
    const secondPayload = pageTwo.data as {
      items: Array<{ id: string }>;
      page: number;
      pageSize: number;
      total: number;
      count: number;
      hasNext: boolean;
      hasPrevious: boolean;
    };
    assert.equal(firstPayload.page, 1);
    assert.equal(firstPayload.pageSize, 2);
    assert.equal(firstPayload.total, 3);
    assert.equal(firstPayload.count, 2);
    assert.equal(firstPayload.hasNext, true);
    assert.equal(firstPayload.hasPrevious, false);
    assert.equal(secondPayload.page, 2);
    assert.equal(secondPayload.pageSize, 2);
    assert.equal(secondPayload.total, 3);
    assert.equal(secondPayload.count, 1);
    assert.equal(secondPayload.hasNext, false);
    assert.equal(secondPayload.hasPrevious, true);
    assert.notDeepEqual(
      firstPayload.items.map((item) => item.id),
      secondPayload.items.map((item) => item.id),
    );
  });
});

async function createFixture() {
  const company = await createCompany('tenant-a');
  const otherCompany = await createCompany('tenant-b');
  const user = await createUser('operator', false);
  const otherUser = await createUser('other-operator', false);

  const membership = await prisma.membership.create({
    data: {
      userId: user.id,
      companyId: company.id,
      role: 'OPERATOR',
      isDefault: true,
    },
  });
  await prisma.membership.create({
    data: {
      userId: otherUser.id,
      companyId: otherCompany.id,
      role: 'OPERATOR',
      isDefault: true,
    },
  });
  await createLicense(company.id);
  await createLicense(otherCompany.id);

  const device = await prisma.companyDevice.create({
    data: {
      companyId: company.id,
      userId: user.id,
      clientInstanceId: `${runId}-tenant-a-device`,
      deviceLabel: 'PDV Tenant A',
      platform: 'android',
      appVersion: 'orders-test',
      status: 'ACTIVE',
      approvedAt: new Date(),
      approvedByUserId: user.id,
      lastSeenAt: new Date(),
    },
  });
  const otherDevice = await prisma.companyDevice.create({
    data: {
      companyId: otherCompany.id,
      userId: otherUser.id,
      clientInstanceId: `${runId}-tenant-b-device`,
      deviceLabel: 'PDV Tenant B',
      platform: 'android',
      appVersion: 'orders-test',
      status: 'ACTIVE',
      approvedAt: new Date(),
      approvedByUserId: otherUser.id,
      lastSeenAt: new Date(),
    },
  });

  const customer = await prisma.customer.create({
    data: {
      companyId: company.id,
      localUuid: 'tenant-a-customer',
      name: 'Cliente Operacional',
      phone: '11999990000',
    },
  });
  await prisma.product.create({
    data: {
      companyId: company.id,
      localUuid: 'tenant-a-product',
      name: 'Produto existente',
      salePriceCents: 1000,
    },
  });

  const cashSession = await prisma.cashSession.create({
    data: {
      companyId: company.id,
      deviceId: device.id,
      userId: user.id,
      localUuid: 'tenant-a-cash-session',
      status: 'open',
      openedAt: new Date(Date.now() - 60 * 60 * 1000),
    },
  });

  const convertedSale = await prisma.sale.create({
    data: {
      companyId: company.id,
      cashSessionId: cashSession.id,
      localUuid: 'tenant-a-converted-sale',
      customerId: customer.id,
      paymentType: 'vista',
      paymentMethod: 'pix',
      status: 'active',
      totalAmountCents: 1000,
      totalCostCents: 0,
      soldAt: new Date(),
    },
  });

  const openOrder = await prisma.operationalOrder.create({
    data: {
      companyId: company.id,
      localUuid: 'tenant-a-open',
      cashSessionId: cashSession.id,
      customerId: customer.id,
      sellerUserId: user.id,
      deviceId: device.id,
      status: 'open',
      subtotalCents: 700,
      discountCents: 0,
      totalCents: 700,
      notes: 'Pedido em aberto',
      createdAt: new Date(Date.now() - 30 * 60 * 1000),
    },
  });
  const closedOrder = await prisma.operationalOrder.create({
    data: {
      companyId: company.id,
      localUuid: 'tenant-a-closed',
      cashSessionId: cashSession.id,
      customerId: customer.id,
      sellerUserId: user.id,
      deviceId: device.id,
      status: 'closed',
      subtotalCents: 1000,
      discountCents: 100,
      totalCents: 900,
      notes: 'Pedido convertido',
      closedAt: new Date(),
      convertedSaleId: convertedSale.id,
      createdAt: new Date(Date.now() - 20 * 60 * 1000),
    },
  });
  const cancelledOrder = await prisma.operationalOrder.create({
    data: {
      companyId: company.id,
      localUuid: 'tenant-a-cancelled',
      sellerUserId: user.id,
      deviceId: device.id,
      status: 'cancelled',
      subtotalCents: 300,
      discountCents: 0,
      totalCents: 300,
      cancelledAt: new Date(),
      createdAt: new Date(Date.now() - 10 * 60 * 1000),
    },
  });
  const otherCompanyOrder = await prisma.operationalOrder.create({
    data: {
      companyId: otherCompany.id,
      localUuid: 'tenant-b-open',
      sellerUserId: otherUser.id,
      deviceId: otherDevice.id,
      status: 'open',
      subtotalCents: 999,
      discountCents: 0,
      totalCents: 999,
    },
  });

  await prisma.operationalOrderItem.createMany({
    data: [
      {
        companyId: company.id,
        operationalOrderId: closedOrder.id,
        localUuid: 'tenant-a-item-1',
        description: 'Cafe',
        quantityMil: 1000,
        unitPriceCents: 500,
        totalCents: 500,
      },
      {
        companyId: company.id,
        operationalOrderId: closedOrder.id,
        localUuid: 'tenant-a-item-2',
        description: 'Pao',
        quantityMil: 1000,
        unitPriceCents: 500,
        totalCents: 500,
      },
      {
        companyId: company.id,
        operationalOrderId: openOrder.id,
        localUuid: 'tenant-a-item-open',
        description: 'Suco',
        quantityMil: 1000,
        unitPriceCents: 700,
        totalCents: 700,
      },
    ],
  });

  return {
    companyId: company.id,
    otherCompanyId: otherCompany.id,
    userId: user.id,
    deviceId: device.id,
    customerId: customer.id,
    cashSessionId: cashSession.id,
    convertedSaleId: convertedSale.id,
    openOrderId: openOrder.id,
    closedOrderId: closedOrder.id,
    cancelledOrderId: cancelledOrder.id,
    otherCompanyOrderId: otherCompanyOrder.id,
    token: signToken({
      userId: user.id,
      companyId: company.id,
      membershipId: membership.id,
      email: user.email,
      clientInstanceId: device.clientInstanceId,
    }),
  };
}

async function createCompany(label: string) {
  return prisma.company.create({
    data: {
      name: `Operational Orders ${label}`,
      legalName: `Operational Orders ${label} LTDA`,
      slug: `${runId}-${label}-${Date.now()}-${Math.random()
        .toString(16)
        .slice(2)}`,
    },
  });
}

async function createUser(label: string, isPlatformAdmin: boolean) {
  return prisma.user.create({
    data: {
      email: `${runId}-${label}-${Date.now()}-${Math.random()
        .toString(16)
        .slice(2)}@tatuzin.test`,
      name: `Operational Orders ${label}`,
      passwordHash: 'not-used',
      isPlatformAdmin,
    },
  });
}

async function createLicense(companyId: string) {
  await prisma.license.create({
    data: {
      companyId,
      plan: 'pro',
      status: 'ACTIVE',
      startsAt: new Date(),
      maxDevices: 5,
      syncEnabled: true,
    },
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
      membershipRole: 'OPERATOR',
      email: input.email,
      isPlatformAdmin: false,
      clientInstanceId: input.clientInstanceId,
    },
    env.JWT_SECRET,
    { expiresIn: '15m' },
  );
}

async function requestJson(
  method: string,
  path: string,
  options?: { token?: string },
) {
  const response = await fetch(`${apiBaseUrl}${path}`, {
    method,
    headers: {
      ...(options?.token == null
        ? {}
        : { Authorization: `Bearer ${options.token}` }),
    },
  });
  const rawBody = await response.text();
  return {
    status: response.status,
    data: rawBody.trim().length === 0 ? null : JSON.parse(rawBody),
  };
}

async function countProductsAndCustomers(companyId: string) {
  const [products, customers] = await Promise.all([
    prisma.product.count({ where: { companyId } }),
    prisma.customer.count({ where: { companyId } }),
  ]);

  return { products, customers };
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
