import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';
import type { AddressInfo } from 'node:net';

import type { Server } from 'http';
import jwt from 'jsonwebtoken';

import { createApp } from '../../app';
import { env } from '../../config/env';
import { prisma } from '../../database/prisma';

const runId = `app-context-${Date.now()}`;

let server: Server;
let apiBaseUrl = '';

describe('app context bootstrap and guards', () => {
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

  it('rejects bootstrap without token', async () => {
    const response = await requestJson('GET', '/app/bootstrap');

    assert.equal(response.status, 401);
    assert.equal((response.data as { code?: string }).code, 'AUTH_REQUIRED');
  });

  it('rejects app snapshot without token', async () => {
    const response = await requestJson('GET', '/app/snapshot');

    assert.equal(response.status, 401);
    assert.equal((response.data as { code?: string }).code, 'AUTH_REQUIRED');
  });

  it('rejects bootstrap without clientInstanceId', async () => {
    const fixture = await createFixture();
    const token = signToken({
      userId: fixture.userId,
      companyId: fixture.companyId,
      membershipId: fixture.membershipId,
      email: fixture.email,
    });

    const response = await requestJson('GET', '/app/bootstrap', { token });

    assert.equal(response.status, 400);
    assert.equal((response.data as { code?: string }).code, 'DEVICE_REQUIRED');
  });

  it('returns complete bootstrap context for an ACTIVE device', async () => {
    const fixture = await createFixture({ deviceStatus: 'ACTIVE' });

    const response = await requestJson('GET', '/app/bootstrap', {
      token: fixture.token,
    });

    assert.equal(response.status, 200);
    const payload = response.data as {
      user: { id: string; email: string };
      company: { id: string; setupCompleted: boolean };
      membership: { id: string; role: string; permissions: string[] };
      license: { id: string; syncEnabled: boolean; maxDevices: number | null };
      plan: string;
      features: Record<string, boolean>;
      limits: {
        maxDevices: number;
        maxEmployees: number;
        reportPeriods: string[];
      };
      device: { id: string; clientInstanceId: string; status: string };
      sync: { enabled: boolean; serverVersion: string; pullRequired: boolean };
    };
    assert.equal(payload.user.id, fixture.userId);
    assert.equal(payload.company.id, fixture.companyId);
    assert.equal(payload.company.setupCompleted, true);
    assert.equal(payload.membership.id, fixture.membershipId);
    assert.equal(payload.license.syncEnabled, true);
    assert.equal(payload.plan, 'PRO');
    assert.equal(payload.features.sales, true);
    assert.equal(payload.features.employees, true);
    assert.deepEqual(payload.limits, {
      maxDevices: 100,
      maxEmployees: 100,
      reportPeriods: ['daily', 'weekly', 'monthly', 'yearly', 'custom'],
    });
    assert.equal(payload.device.clientInstanceId, fixture.clientInstanceId);
    assert.equal(payload.device.status, 'ACTIVE');
    assert.equal(payload.sync.enabled, true);
    assert.equal(payload.sync.pullRequired, false);
    assert.ok(payload.membership.permissions.length > 0);
  });

  it('returns app snapshot records for the authenticated company only', async () => {
    const fixture = await createFixture({ deviceStatus: 'ACTIVE' });
    const otherFixture = await createFixture({ deviceStatus: 'ACTIVE' });
    const snapshotData = await seedSnapshotData(
      fixture.companyId,
      fixture.userId,
      'main',
    );
    const otherData = await seedSnapshotData(
      otherFixture.companyId,
      otherFixture.userId,
      'other',
    );

    const response = await requestJson(
      'GET',
      '/app/snapshot?features=categories,products,customers,suppliers,cash_sessions,cash_movements',
      { token: fixture.token },
    );

    assert.equal(response.status, 200);
    const payload = response.data as {
      companyId: string;
      serverFirstSnapshotVersion: string;
      features: Record<
        string,
        {
          count: number;
          items?: Array<Record<string, unknown>>;
        }
      >;
    };
    assert.equal(payload.companyId, fixture.companyId);
    assert.notEqual(payload.serverFirstSnapshotVersion, '0');

    assert.equal(payload.features.categories.count, 1);
    assert.equal(payload.features.products.count, 1);
    assert.equal(payload.features.customers.count, 1);
    assert.equal(payload.features.suppliers.count, 1);
    assert.equal(payload.features.cash_sessions.count, 1);
    assert.equal(payload.features.cash_movements.count, 1);
    assert.deepEqual(
      payload.features.categories.items?.map((item) => item.id),
      [snapshotData.categoryId],
    );
    assert.deepEqual(payload.features.products.items?.map((item) => item.id), [
      snapshotData.productId,
    ]);
    assert.deepEqual(payload.features.customers.items?.map((item) => item.id), [
      snapshotData.customerId,
    ]);
    assert.deepEqual(payload.features.suppliers.items?.map((item) => item.id), [
      snapshotData.supplierId,
    ]);
    assert.deepEqual(
      payload.features.cash_sessions.items?.map((item) => item.id),
      [snapshotData.cashSessionId],
    );
    assert.deepEqual(
      payload.features.cash_movements.items?.map((item) => item.id),
      [snapshotData.cashMovementId],
    );
    const cashSession = payload.features.cash_sessions.items?.[0] as {
      operatorName?: string | null;
    };
    const cashMovement = payload.features.cash_movements.items?.[0] as {
      referenceType?: string | null;
      referenceId?: string | null;
    };
    assert.equal(cashSession.operatorName, 'App Context User');
    assert.equal(cashMovement.referenceType, 'venda');
    assert.equal(cashMovement.referenceId, snapshotData.cashMovementReferenceId);
    assert.ok(
      !JSON.stringify(payload).includes(otherData.productId),
      'snapshot must not leak records from another company',
    );
    assert.ok(!JSON.stringify(payload).toLowerCase().includes('password'));
    assert.ok(!JSON.stringify(payload).toLowerCase().includes('token'));

    const product = payload.features.products.items?.[0] as {
      variants?: Array<{ id: string }>;
    };
    assert.equal(product.variants?.[0]?.id, snapshotData.variantId);
  });

  it('blocks app snapshot when license is expired', async () => {
    const fixture = await createFixture({
      deviceStatus: 'ACTIVE',
      licenseStatus: 'EXPIRED',
    });

    const response = await requestJson('GET', '/app/snapshot', {
      token: fixture.token,
    });

    assert.equal(response.status, 403);
    assert.equal((response.data as { code?: string }).code, 'LICENSE_EXPIRED');
  });

  it('blocks bootstrap for a BLOCKED device', async () => {
    const fixture = await createFixture({ deviceStatus: 'BLOCKED' });

    const response = await requestJson('GET', '/app/bootstrap', {
      token: fixture.token,
    });

    assert.equal(response.status, 403);
    assert.equal((response.data as { code?: string }).code, 'DEVICE_BLOCKED');
  });

  it('blocks sync for a REVOKED device', async () => {
    const fixture = await createFixture({ deviceStatus: 'REVOKED' });

    const response = await requestJson('GET', '/sync/status', {
      token: fixture.token,
    });

    assert.equal(response.status, 403);
    assert.equal((response.data as { code?: string }).code, 'DEVICE_REVOKED');
  });

  it('rejects sync without app context', async () => {
    const response = await requestJson('GET', '/sync/status');

    assert.equal(response.status, 401);
    assert.equal((response.data as { code?: string }).code, 'AUTH_REQUIRED');
  });

  it('rejects sync when license sync is disabled', async () => {
    const fixture = await createFixture({
      deviceStatus: 'ACTIVE',
      syncEnabled: false,
    });

    const response = await requestJson('GET', '/sync/status', {
      token: fixture.token,
    });

    assert.equal(response.status, 403);
    assert.equal((response.data as { code?: string }).code, 'SYNC_DISABLED');
  });

  it('rejects operational endpoints without an ACTIVE device', async () => {
    const fixture = await createFixture();

    const response = await requestJson('GET', '/categories', {
      token: fixture.token,
    });

    assert.equal(response.status, 403);
    assert.equal((response.data as { code?: string }).code, 'DEVICE_REQUIRED');
  });

  it('activates the first OWNER device and rejects devices above maxDevices', async () => {
    const fixture = await createFixture({
      role: 'OWNER',
      plan: 'free',
      createDevice: false,
    });
    const ownerToken = signToken({
      userId: fixture.userId,
      companyId: fixture.companyId,
      membershipId: fixture.membershipId,
      email: fixture.email,
      membershipRole: 'OWNER',
    });

    const firstDevice = await requestJson('POST', '/app/device', {
      token: ownerToken,
      body: {
        clientInstanceId: `${runId}-owner-first`,
        deviceLabel: 'Owner First',
        platform: 'android',
        appVersion: '1.0.0',
      },
    });
    assert.equal(firstDevice.status, 200);
    assert.equal(
      (firstDevice.data as { device: { status: string } }).device.status,
      'ACTIVE',
    );

    const secondDevice = await requestJson('POST', '/app/device', {
      token: ownerToken,
      body: {
        clientInstanceId: `${runId}-owner-second`,
        deviceLabel: 'Owner Second',
        platform: 'android',
        appVersion: '1.0.0',
      },
    });
    assert.equal(secondDevice.status, 409);
    assert.equal(
      (secondDevice.data as { code?: string }).code,
      'DEVICE_LIMIT_REACHED',
    );
  });

  it('rejects a second BASIC device above plan limit', async () => {
    const fixture = await createFixture({
      role: 'OWNER',
      plan: 'basic',
      createDevice: false,
    });
    const ownerToken = signToken({
      userId: fixture.userId,
      companyId: fixture.companyId,
      membershipId: fixture.membershipId,
      email: fixture.email,
      membershipRole: 'OWNER',
    });

    const firstDevice = await requestJson('POST', '/app/device', {
      token: ownerToken,
      body: {
        clientInstanceId: `${runId}-basic-first`,
        deviceLabel: 'Basic First',
        platform: 'android',
        appVersion: '1.0.0',
      },
    });
    assert.equal(firstDevice.status, 200);

    const secondDevice = await requestJson('POST', '/app/device', {
      token: ownerToken,
      body: {
        clientInstanceId: `${runId}-basic-second`,
        deviceLabel: 'Basic Second',
        platform: 'android',
        appVersion: '1.0.0',
      },
    });
    assert.equal(secondDevice.status, 409);
    assert.equal(
      (secondDevice.data as { code?: string }).code,
      'DEVICE_LIMIT_REACHED',
    );
  });

  it('allows a second device for PRO companies', async () => {
    const fixture = await createFixture({
      role: 'OWNER',
      plan: 'pro',
      createDevice: false,
    });
    const ownerToken = signToken({
      userId: fixture.userId,
      companyId: fixture.companyId,
      membershipId: fixture.membershipId,
      email: fixture.email,
      membershipRole: 'OWNER',
    });

    const firstDevice = await requestJson('POST', '/app/device', {
      token: ownerToken,
      body: {
        clientInstanceId: `${runId}-pro-first`,
        deviceLabel: 'Pro First',
        platform: 'android',
        appVersion: '1.0.0',
      },
    });
    assert.equal(firstDevice.status, 200);

    const secondDevice = await requestJson('POST', '/app/device', {
      token: ownerToken,
      body: {
        clientInstanceId: `${runId}-pro-second`,
        deviceLabel: 'Pro Second',
        platform: 'android',
        appVersion: '1.0.0',
      },
    });
    assert.equal(secondDevice.status, 200);
    assert.equal(
      (secondDevice.data as { device: { status: string } }).device.status,
      'ACTIVE',
    );
  });
});

async function createFixture(options?: {
  role?: 'OWNER' | 'ADMIN' | 'OPERATOR';
  plan?: string;
  licenseStatus?: 'ACTIVE' | 'TRIAL' | 'EXPIRED' | 'SUSPENDED';
  maxDevices?: number | null;
  syncEnabled?: boolean;
  deviceStatus?: 'PENDING' | 'ACTIVE' | 'BLOCKED' | 'REVOKED';
  createDevice?: boolean;
}) {
  const company = await prisma.company.create({
    data: {
      name: 'App Context Company',
      legalName: 'App Context Company LTDA',
      slug: `${runId}-company-${Date.now()}`,
    },
  });
  const user = await prisma.user.create({
    data: {
      email: `${runId}-${Date.now()}@tatuzin.test`,
      name: 'App Context User',
      passwordHash: 'not-used',
    },
  });
  const membership = await prisma.membership.create({
    data: {
      userId: user.id,
      companyId: company.id,
      role: options?.role ?? 'OPERATOR',
      isDefault: true,
    },
  });
  await prisma.license.create({
    data: {
      companyId: company.id,
      plan: options?.plan ?? 'pro',
      status: options?.licenseStatus ?? 'ACTIVE',
      startsAt: new Date(),
      maxDevices: options?.maxDevices ?? 5,
      syncEnabled: options?.syncEnabled ?? true,
    },
  });

  const clientInstanceId = `${runId}-device-${Date.now()}`;
  if (options?.createDevice !== false && options?.deviceStatus != null) {
    await prisma.companyDevice.create({
      data: {
        companyId: company.id,
        userId: user.id,
        clientInstanceId,
        deviceLabel: 'App Context Test Device',
        platform: 'node-test',
        appVersion: 'app-context-test',
        status: options.deviceStatus,
        approvedAt: options.deviceStatus === 'ACTIVE' ? new Date() : undefined,
        approvedByUserId:
          options.deviceStatus === 'ACTIVE' ? user.id : undefined,
        lastSeenAt: new Date(),
        revokedAt:
          options.deviceStatus === 'REVOKED' ? new Date() : undefined,
        revokedReason:
          options.deviceStatus === 'REVOKED' ? 'test_revoked' : undefined,
      },
    });
  }

  return {
    userId: user.id,
    companyId: company.id,
    membershipId: membership.id,
    email: user.email,
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

async function seedSnapshotData(
  companyId: string,
  userId: string,
  suffix: string,
) {
  const category = await prisma.category.create({
    data: {
      companyId,
      localUuid: `${runId}-${suffix}-category-local`,
      name: `Categoria ${suffix}`,
      description: `Categoria ${suffix}`,
    },
  });
  const customer = await prisma.customer.create({
    data: {
      companyId,
      localUuid: `${runId}-${suffix}-customer-local`,
      name: `Cliente ${suffix}`,
      phone: '11999990000',
      address: 'Rua Teste',
      notes: 'Cliente de teste',
    },
  });
  const supplier = await prisma.supplier.create({
    data: {
      companyId,
      localUuid: `${runId}-${suffix}-supplier-local`,
      name: `Fornecedor ${suffix}`,
      tradeName: `Forn ${suffix}`,
      phone: '11888880000',
      email: `${suffix}@supplier.test`,
      address: 'Rua Fornecedor',
      document: `${suffix}-doc`,
      contactPerson: 'Contato',
      notes: 'Fornecedor de teste',
    },
  });
  const product = await prisma.product.create({
    data: {
      companyId,
      localUuid: `${runId}-${suffix}-product-local`,
      categoryId: category.id,
      name: `Produto ${suffix}`,
      description: 'Produto de teste',
      productType: 'unidade',
      niche: 'alimentacao',
      catalogType: 'simple',
      unitMeasure: 'un',
      costPriceCents: 500,
      manualCostCents: 500,
      costSource: 'manual',
      salePriceCents: 1200,
      stockMil: 10000,
      variants: {
        create: {
          sku: `${suffix.toUpperCase()}-SKU`,
          colorLabel: 'Unica',
          sizeLabel: 'P',
          stockMil: 3000,
          sortOrder: 0,
        },
      },
    },
    include: { variants: true },
  });
  const cashSession = await prisma.cashSession.create({
    data: {
      companyId,
      userId,
      localUuid: `${runId}-${suffix}-cash-session-local`,
      status: 'closed',
      openedAt: new Date('2026-05-10T12:00:00.000Z'),
      closedAt: new Date('2026-05-10T18:00:00.000Z'),
      openingBalanceCents: 5000,
      expectedBalanceCents: 8200,
      closingBalanceCents: 8200,
      notes: `Sessao ${suffix}`,
    },
  });
  const cashMovement = await prisma.cashEvent.create({
    data: {
      companyId,
      cashSessionId: cashSession.id,
      localUuid: `${runId}-${suffix}-cash-movement-local`,
      eventType: 'venda',
      amountCents: 3200,
      paymentMethod: 'dinheiro',
      referenceType: 'venda',
      referenceId: `${runId}-${suffix}-sale-ref`,
      notes: `Venda ${suffix}`,
      createdAt: new Date('2026-05-10T13:00:00.000Z'),
    },
  });

  return {
    categoryId: category.id,
    customerId: customer.id,
    supplierId: supplier.id,
    productId: product.id,
    variantId: product.variants[0]!.id,
    cashSessionId: cashSession.id,
    cashMovementId: cashMovement.id,
    cashMovementReferenceId: cashMovement.referenceId!,
  };
}

function signToken(input: {
  userId: string;
  companyId: string;
  membershipId: string;
  email: string;
  membershipRole?: string;
  clientInstanceId?: string;
}) {
  return jwt.sign(
    {
      sub: input.userId,
      companyId: input.companyId,
      membershipId: input.membershipId,
      membershipRole: input.membershipRole ?? 'OPERATOR',
      email: input.email,
      isPlatformAdmin: false,
      ...(input.clientInstanceId == null
        ? {}
        : { clientInstanceId: input.clientInstanceId }),
    },
    env.JWT_SECRET,
    { expiresIn: '15m' },
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
      ...(options?.body == null ? {} : { 'Content-Type': 'application/json' }),
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
    where: { slug: { startsWith: `${runId}-` } },
  });
  await prisma.user.deleteMany({
    where: { email: { startsWith: `${runId}-` } },
  });
}
