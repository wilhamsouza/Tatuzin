import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';
import type { AddressInfo } from 'node:net';
import type { Server } from 'http';

import jwt from 'jsonwebtoken';
import type { Prisma } from '@prisma/client';

import { createApp } from '../../app';
import { env } from '../../config/env';
import { prisma } from '../../database/prisma';
import { getPlanEntitlements } from '../plans/plan-catalog.service';

const runId = `owner-routes-${Date.now()}`;

let server: Server;
let apiBaseUrl = '';
let originalFetch: typeof globalThis.fetch;

describe('owner routes', () => {
  before(async () => {
    await prisma.$connect();
    originalFetch = globalThis.fetch;
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

  it('keeps ownerWebPanel as an existing PRO-only entitlement', () => {
    assert.equal(getPlanEntitlements('FREE').features.ownerWebPanel, false);
    assert.equal(getPlanEntitlements('BASIC').features.ownerWebPanel, false);
    assert.equal(getPlanEntitlements('PRO').features.ownerWebPanel, true);
  });

  it('requires app context before owner membership', async () => {
    const response = await requestJson('GET', '/owner/company');

    assert.equal(response.status, 401);
    assert.equal((response.data as { code?: string }).code, 'AUTH_REQUIRED');
  });

  it('returns OWNER_REQUIRED for non-owner before checking ownerWebPanel entitlement', async () => {
    const fixture = await createFixture({ plan: 'FREE', role: 'OPERATOR' });

    const response = await requestJson('GET', '/owner/company', {
      token: fixture.token,
    });

    assert.equal(response.status, 403);
    assert.equal((response.data as { code?: string }).code, 'OWNER_REQUIRED');
  });

  it('does not allow platform admin access without OWNER app context', async () => {
    const fixture = await createFixture({
      plan: 'PRO',
      role: 'OPERATOR',
      isPlatformAdmin: true,
    });

    const response = await requestJson('GET', '/owner/company', {
      token: fixture.token,
    });

    assert.equal(response.status, 403);
    assert.equal((response.data as { code?: string }).code, 'OWNER_REQUIRED');
  });

  it('blocks OWNER in FREE or BASIC with FEATURE_NOT_AVAILABLE', async () => {
    for (const plan of ['FREE', 'BASIC'] as const) {
      const fixture = await createFixture({ plan, role: 'OWNER' });

      const response = await requestJson('GET', '/owner/company', {
        token: fixture.token,
      });

      assert.equal(response.status, 403, plan);
      assert.equal(
        (response.data as { code?: string }).code,
        'FEATURE_NOT_AVAILABLE',
        plan,
      );
    }
  });

  it('does not unlock owner panel with pendingPlan PRO', async () => {
    const fixture = await createFixture({
      plan: 'FREE',
      role: 'OWNER',
      pendingPlan: 'PRO',
    });

    const response = await requestJson('GET', '/owner/company', {
      token: fixture.token,
    });

    assert.equal(response.status, 403);
    assert.equal(
      (response.data as { code?: string }).code,
      'FEATURE_NOT_AVAILABLE',
    );
  });

  it('allows OWNER in PRO to read safe company and billing summaries', async () => {
    const fixture = await createFixture({
      plan: 'PRO',
      role: 'OWNER',
      providerSubscriptionId: 'preapproval-owner-secret-9999',
    });

    const company = await requestJson('GET', '/owner/company', {
      token: fixture.token,
    });
    const status = await requestJson('GET', '/owner/billing/status', {
      token: fixture.token,
    });

    assert.equal(company.status, 200);
    assert.equal(status.status, 200);
    const serialized = JSON.stringify({ company: company.data, status: status.data });
    assert.equal(serialized.includes('preapproval-owner-secret-9999'), false);
    assert.equal(serialized.includes('prea...9999'), true);
    assert.equal((status.data as { providerSubscriptionId?: string }).providerSubscriptionId, undefined);
  });

  it('lists only safe owner invoices for the current company', async () => {
    const fixture = await createFixture({
      plan: 'PRO',
      role: 'OWNER',
      providerSubscriptionId: 'preapproval-owner-secret-9999',
    });
    await createInvoice(fixture, {
      status: 'paid',
      providerInvoiceId: `${runId}-invoice-current`,
      invoiceUrl: 'https://mercadopago.test/invoices/current?token=secret',
      payload: { token: 'invoice-token' },
    });
    const otherFixture = await createFixture({ plan: 'PRO', role: 'OWNER' });
    await createInvoice(otherFixture, {
      status: 'paid',
      providerInvoiceId: `${runId}-invoice-other`,
      invoiceUrl: 'https://mercadopago.test/invoices/other',
      payload: { token: 'other-token' },
    });

    const response = await requestJson(
      'GET',
      '/owner/billing/invoices?status=paid&page=1&pageSize=10',
      { token: fixture.token },
    );

    assert.equal(response.status, 200);
    const payload = response.data as {
      items: Array<{
        id: string;
        status: string;
        invoiceUrl: string | null;
        payload?: unknown;
        providerSubscriptionId?: string;
      }>;
      total: number;
    };
    assert.equal(payload.items.length, 1);
    assert.equal(payload.items[0]?.status, 'paid');
    assert.equal(payload.items[0]?.invoiceUrl, null);
    assert.equal(payload.items[0]?.payload, undefined);
    assert.equal(payload.items[0]?.providerSubscriptionId, undefined);
    const serialized = JSON.stringify(payload);
    assert.equal(serialized.includes('invoice-token'), false);
    assert.equal(serialized.includes('other-token'), false);
    assert.equal(serialized.includes('preapproval-owner-secret-9999'), false);
  });

  it('rejects invalid owner invoice status filters safely', async () => {
    const fixture = await createFixture({ plan: 'PRO', role: 'OWNER' });

    const response = await requestJson(
      'GET',
      '/owner/billing/invoices?status=approved&page=1&pageSize=10',
      { token: fixture.token },
    );

    assert.equal(response.status, 422);
    assert.equal((response.data as { code?: string }).code, 'VALIDATION_ERROR');
  });

  it('returns a safe employees placeholder while EmployeeProfile is absent', async () => {
    const fixture = await createFixture({ plan: 'PRO', role: 'OWNER' });

    const response = await requestJson('GET', '/owner/employees', {
      token: fixture.token,
    });

    assert.equal(response.status, 200);
    assert.deepEqual(response.data, {
      items: [],
      count: 0,
      available: false,
      reason: 'EMPLOYEES_NOT_IMPLEMENTED',
    });
  });

  it('lists devices without exposing full clientInstanceId', async () => {
    const fixture = await createFixture({ plan: 'PRO', role: 'OWNER' });

    const response = await requestJson('GET', '/owner/devices', {
      token: fixture.token,
    });

    assert.equal(response.status, 200);
    const serialized = JSON.stringify(response.data);
    assert.equal(serialized.includes(fixture.clientInstanceId), false);
    assert.equal(serialized.includes(`${fixture.clientInstanceId.slice(0, 4)}...`), true);
  });

  it('returns a lightweight dashboard with nullable optional summaries', async () => {
    const fixture = await createFixture({ plan: 'PRO', role: 'OWNER' });

    const response = await requestJson('GET', '/owner/dashboard', {
      token: fixture.token,
    });

    assert.equal(response.status, 200);
    const payload = response.data as {
      reports: null;
      employees: { available: boolean; reason: string };
      billing: { plan: string };
    };
    assert.equal(payload.billing.plan, 'PRO');
    assert.equal(payload.employees.available, false);
    assert.equal(payload.employees.reason, 'EMPLOYEES_NOT_IMPLEMENTED');
    assert.equal(payload.reports, null);
  });
});

async function createFixture(options: {
  plan: 'FREE' | 'BASIC' | 'PRO';
  role: 'OWNER' | 'ADMIN' | 'OPERATOR';
  pendingPlan?: string | null;
  providerSubscriptionId?: string | null;
  isPlatformAdmin?: boolean;
}) {
  const suffix = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
  const company = await prisma.company.create({
    data: {
      name: `Owner Routes ${suffix}`,
      legalName: `Owner Routes ${suffix} LTDA`,
      slug: `${runId}-${suffix}`,
    },
  });
  const user = await prisma.user.create({
    data: {
      email: `${runId}-${suffix}@tatuzin.test`,
      name: 'Owner Routes User',
      passwordHash: 'not-used',
      isPlatformAdmin: options.isPlatformAdmin ?? false,
    },
  });
  const membership = await prisma.membership.create({
    data: {
      userId: user.id,
      companyId: company.id,
      role: options.role,
      isDefault: true,
    },
  });
  await prisma.license.create({
    data: {
      companyId: company.id,
      plan: options.plan,
      status: 'ACTIVE',
      startsAt: new Date('2026-05-01T00:00:00.000Z'),
      syncEnabled: true,
      billingProvider:
        options.providerSubscriptionId == null ? null : 'mercadopago',
      providerSubscriptionId: options.providerSubscriptionId ?? null,
      currentPeriodStart: new Date('2026-05-01T00:00:00.000Z'),
      currentPeriodEnd: new Date('2026-06-01T00:00:00.000Z'),
      nextPaymentDate: new Date('2026-06-01T00:00:00.000Z'),
      pendingPlan: options.pendingPlan ?? null,
      pendingPlanRequestedAt:
        options.pendingPlan == null ? null : new Date('2026-05-02T00:00:00.000Z'),
    },
  });
  const clientInstanceId = `${runId}-device-${suffix}`;
  await prisma.companyDevice.create({
    data: {
      companyId: company.id,
      userId: user.id,
      clientInstanceId,
      deviceLabel: 'Owner Routes Device',
      platform: 'node-test',
      appVersion: 'owner-routes-test',
      status: 'ACTIVE',
      approvedAt: new Date(),
      approvedByUserId: user.id,
      lastSeenAt: new Date(),
    },
  });

  return {
    companyId: company.id,
    userId: user.id,
    token: signToken({
      userId: user.id,
      companyId: company.id,
      membershipId: membership.id,
      membershipRole: options.role,
      email: user.email,
      clientInstanceId,
      isPlatformAdmin: options.isPlatformAdmin ?? false,
    }),
    clientInstanceId,
  };
}

async function createInvoice(
  fixture: { companyId: string },
  input: {
    status: string;
    providerInvoiceId: string;
    invoiceUrl: string;
    payload: Record<string, unknown>;
  },
) {
  await prisma.billingInvoice.create({
    data: {
      companyId: fixture.companyId,
      provider: 'mercadopago',
      providerInvoiceId: input.providerInvoiceId,
      providerSubscriptionId: 'preapproval-owner-secret-9999',
      plan: 'PRO',
      status: input.status,
      amountCents: 8500,
      currency: 'BRL',
      invoiceUrl: input.invoiceUrl,
      payload: input.payload as Prisma.InputJsonValue,
      paidAt: new Date('2026-05-03T00:00:00.000Z'),
    },
  });
}

function signToken(input: {
  userId: string;
  companyId: string;
  membershipId: string;
  membershipRole: string;
  email: string;
  clientInstanceId: string;
  isPlatformAdmin?: boolean;
}) {
  return jwt.sign(
    {
      sub: input.userId,
      companyId: input.companyId,
      membershipId: input.membershipId,
      membershipRole: input.membershipRole,
      email: input.email,
      isPlatformAdmin: input.isPlatformAdmin ?? false,
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
  const response = await originalFetch(`${apiBaseUrl}${path}`, {
    method,
    headers:
      options?.token == null
        ? undefined
        : { Authorization: `Bearer ${options.token}` },
  });
  const rawBody = await response.text();
  return {
    status: response.status,
    data: rawBody.trim().length === 0 ? null : JSON.parse(rawBody),
  };
}

async function cleanupFixtures() {
  await prisma.billingInvoice.deleteMany({
    where: { company: { slug: { startsWith: `${runId}-` } } },
  });
  await prisma.company.deleteMany({
    where: { slug: { startsWith: `${runId}-` } },
  });
  await prisma.user.deleteMany({
    where: { email: { startsWith: `${runId}-` } },
  });
}
