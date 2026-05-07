import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';
import type { AddressInfo } from 'node:net';

import type { Server } from 'http';
import jwt from 'jsonwebtoken';

import { createApp } from '../../app';
import { env } from '../../config/env';
import { prisma } from '../../database/prisma';

const runId = `plan-routes-${Date.now()}`;

let server: Server;
let apiBaseUrl = '';

describe('plan entitlement route gates', () => {
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

  it('allows FREE operational reads and daily reports', async () => {
    const fixture = await createFixture('free');
    const query = `startDate=${fixture.today}&endDate=${fixture.today}`;

    for (const path of [
      '/sales',
      '/products',
      '/categories',
      `/analytics/reports/sales-by-day?${query}`,
    ]) {
      const response = await requestJson('GET', path, {
        token: fixture.token,
      });
      assert.equal(response.status, 200, path);
    }
  });

  it('blocks FREE from paid plan features', async () => {
    const fixture = await createFixture('free');
    const protectedGets = [
      ['/supplies', 'supplies'],
      ['/costs', 'costs'],
      ['/suppliers', 'suppliers'],
      ['/purchases', 'purchases'],
      ['/employees', 'employees'],
    ] as const;

    for (const [path, feature] of protectedGets) {
      const response = await requestJson('GET', path, {
        token: fixture.token,
      });
      assertFeatureBlocked(response, feature);
    }

    const fiadoPayment = await requestJson('POST', '/fiado/payments', {
      token: fixture.token,
      body: {},
    });
    assertFeatureBlocked(fiadoPayment, 'fiadoManagement');
  });

  it('allows BASIC management features and basic period reports', async () => {
    const fixture = await createFixture('basic');
    const query = `startDate=${fixture.monthStart}&endDate=${fixture.monthEnd}`;

    for (const path of ['/supplies', '/costs', '/suppliers', '/purchases']) {
      const response = await requestJson('GET', path, {
        token: fixture.token,
      });
      assert.equal(response.status, 200, path);
    }

    const basicReport = await requestJson(
      'GET',
      `/analytics/reports/sales-by-day?${query}`,
      { token: fixture.token },
    );
    assert.equal(basicReport.status, 200);

    const fiadoPayment = await requestJson('POST', '/fiado/payments', {
      token: fixture.token,
      body: {},
    });
    assert.notEqual(fiadoPayment.status, 403);
  });

  it('blocks BASIC from employee and advanced report features', async () => {
    const fixture = await createFixture('basic');

    const employees = await requestJson('GET', '/employees', {
      token: fixture.token,
    });
    assertFeatureBlocked(employees, 'employees');

    const advancedReport = await requestJson(
      'GET',
      `/analytics/reports/top-variants?startDate=${fixture.monthStart}&endDate=${fixture.monthEnd}`,
      { token: fixture.token },
    );
    assertFeatureBlocked(advancedReport, 'reportsAdvanced');
  });

  it('allows PRO to access all initial gated routes', async () => {
    const fixture = await createFixture('pro');

    for (const path of [
      '/supplies',
      '/costs',
      '/suppliers',
      '/purchases',
      '/employees',
      `/analytics/reports/top-variants?startDate=${fixture.monthStart}&endDate=${fixture.monthEnd}`,
    ]) {
      const response = await requestJson('GET', path, {
        token: fixture.token,
      });
      assert.equal(response.status, 200, path);
    }

    const employees = await requestJson('GET', '/employees', {
      token: fixture.token,
    });
    assert.deepEqual(employees.data, { items: [], count: 0 });
  });
});

async function createFixture(plan: string) {
  const now = new Date();
  const today = now.toISOString().slice(0, 10);
  const monthStart = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1),
  )
    .toISOString()
    .slice(0, 10);
  const monthEnd = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 28),
  )
    .toISOString()
    .slice(0, 10);
  const unique = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
  const company = await prisma.company.create({
    data: {
      name: 'Plan Routes',
      legalName: 'Plan Routes LTDA',
      slug: `${runId}-company-${unique}`,
    },
  });
  const user = await prisma.user.create({
    data: {
      email: `${runId}-${unique}@tatuzin.test`,
      name: 'Plan Routes User',
      passwordHash: 'not-used',
    },
  });
  const membership = await prisma.membership.create({
    data: {
      userId: user.id,
      companyId: company.id,
      role: 'OWNER',
      isDefault: true,
    },
  });
  await prisma.license.create({
    data: {
      companyId: company.id,
      plan,
      status: 'ACTIVE',
      startsAt: new Date(),
      syncEnabled: true,
    },
  });
  const clientInstanceId = `${runId}-device-${unique}`;
  await prisma.companyDevice.create({
    data: {
      companyId: company.id,
      userId: user.id,
      clientInstanceId,
      deviceLabel: 'Plan Routes Test',
      platform: 'node-test',
      appVersion: 'plan-routes-test',
      status: 'ACTIVE',
      approvedAt: new Date(),
      approvedByUserId: user.id,
      lastSeenAt: new Date(),
    },
  });

  return {
    today,
    monthStart,
    monthEnd,
    token: signToken({
      userId: user.id,
      companyId: company.id,
      membershipId: membership.id,
      email: user.email,
      clientInstanceId,
    }),
  };
}

function assertFeatureBlocked(
  response: { status: number; data: unknown },
  feature: string,
) {
  assert.equal(response.status, 403);
  const payload = response.data as {
    code?: string;
    message?: string;
    details?: { feature?: string; requiredPlan?: string };
  };
  assert.equal(payload.code, 'FEATURE_NOT_AVAILABLE');
  assert.equal(
    payload.message,
    'Este recurso não está disponível no seu plano atual.',
  );
  assert.equal(payload.details?.feature, feature);
  assert.ok(payload.details?.requiredPlan);
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
      membershipRole: 'OWNER',
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
