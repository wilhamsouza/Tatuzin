import assert from 'node:assert/strict';
import { createHmac } from 'crypto';
import { after, before, beforeEach, describe, it } from 'node:test';
import type { AddressInfo } from 'node:net';

import type { Server } from 'http';
import jwt from 'jsonwebtoken';

import { createApp } from '../../app';
import { env } from '../../config/env';
import { prisma } from '../../database/prisma';

const runId = `billing-${Date.now()}`;
const webhookSecret = 'billing-webhook-secret';

let server: Server;
let apiBaseUrl = '';
let originalFetch: typeof globalThis.fetch;
const originalEnv = {
  accessToken: env.MERCADO_PAGO_ACCESS_TOKEN,
  webhookSecret: env.MERCADO_PAGO_WEBHOOK_SECRET,
  isProduction: env.isProduction,
};

describe('billing routes', () => {
  before(async () => {
    await prisma.$connect();
    originalFetch = globalThis.fetch;
    env.MERCADO_PAGO_ACCESS_TOKEN = 'test-mercado-token';
    env.MERCADO_PAGO_WEBHOOK_SECRET = webhookSecret;
    server = createApp().listen(0);
    const address = server.address() as AddressInfo;
    apiBaseUrl = `http://127.0.0.1:${address.port}/api`;
  });

  beforeEach(async () => {
    await cleanupFixtures();
    globalThis.fetch = originalFetch;
    env.MERCADO_PAGO_ACCESS_TOKEN = 'test-mercado-token';
    env.MERCADO_PAGO_WEBHOOK_SECRET = webhookSecret;
    env.isProduction = false;
  });

  after(async () => {
    await cleanupFixtures();
    env.MERCADO_PAGO_ACCESS_TOKEN = originalEnv.accessToken;
    env.MERCADO_PAGO_WEBHOOK_SECRET = originalEnv.webhookSecret;
    env.isProduction = originalEnv.isProduction;
    globalThis.fetch = originalFetch;
    await new Promise<void>((resolve, reject) => {
      server.close((error) => (error == null ? resolve() : reject(error)));
    });
    await prisma.$disconnect();
  });

  it('lists public FREE/BASIC/PRO billing plans with default prices', async () => {
    const response = await requestJson('GET', '/billing/plans');

    assert.equal(response.status, 200);
    const items = (response.data as { items: Array<{ key: string; priceCents: number }> }).items;
    assert.deepEqual(
      items.map((item) => [item.key, item.priceCents]),
      [
        ['FREE', 0],
        ['BASIC', 3500],
        ['PRO', 8500],
      ],
    );
  });

  it('returns billing status from local database without exposing full provider id', async () => {
    const fixture = await createFixture({
      plan: 'basic',
      providerSubscriptionId: 'preapproval-1234567890',
    });
    globalThis.fetch = failFetch('status must not call Mercado Pago');

    const response = await requestJson('GET', '/billing/status', {
      token: fixture.token,
    });

    assert.equal(response.status, 200);
    const payload = response.data as {
      plan: string;
      hasProviderSubscription: boolean;
      maskedProviderSubscriptionId?: string;
      providerSubscriptionId?: string;
    };
    assert.equal(payload.plan, 'BASIC');
    assert.equal(payload.hasProviderSubscription, true);
    assert.equal(payload.maskedProviderSubscriptionId, 'prea...7890');
    assert.equal(payload.providerSubscriptionId, undefined);
  });

  it('creates BASIC checkout session without changing license.plan', async () => {
    const fixture = await createFixture({ plan: 'free' });
    let capturedBody = {} as Record<string, any>;
    globalThis.fetch = jsonFetch(async (_url, init) => {
      capturedBody = JSON.parse(init.body ?? '{}') as Record<string, unknown>;
      return {
        id: 'mp-basic-1',
        init_point: 'https://mercadopago.test/basic',
        sandbox_init_point: 'https://sandbox.mercadopago.test/basic',
        status: 'pending',
      };
    });

    const response = await requestJson('POST', '/billing/subscribe', {
      token: fixture.token,
      body: { plan: 'BASIC' },
    });

    assert.equal(response.status, 201);
    const subscribeBody = capturedBody;
    const payload = response.data as {
      checkoutUrl: string;
      checkoutSessionId: string;
    };
    assert.equal(payload.checkoutUrl, 'https://mercadopago.test/basic');
    assert.ok(payload.checkoutSessionId);
    assert.equal(
      (subscribeBody.auto_recurring as { frequency?: number }).frequency,
      1,
    );
    assert.equal(
      (subscribeBody.auto_recurring as { frequency_type?: string })
        .frequency_type,
      'months',
    );
    assert.equal(
      (subscribeBody.auto_recurring as { transaction_amount?: number })
        .transaction_amount,
      35,
    );
    assert.equal(
      (subscribeBody.auto_recurring as { currency_id?: string }).currency_id,
      'BRL',
    );
    assert.equal(subscribeBody.external_reference, payload.checkoutSessionId);

    const session = await prisma.billingCheckoutSession.findUniqueOrThrow({
      where: { id: payload.checkoutSessionId },
    });
    assert.equal(session.providerReference, 'mp-basic-1');
    assert.equal(session.checkoutUrl, 'https://mercadopago.test/basic');
    assert.equal(
      session.sandboxCheckoutUrl,
      'https://sandbox.mercadopago.test/basic',
    );
    const license = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(license.plan, 'free');
  });

  it('keeps BASIC while PRO upgrade checkout is pending', async () => {
    const fixture = await createFixture({ plan: 'basic' });
    globalThis.fetch = jsonFetch(async () => ({
      id: 'mp-pro-pending',
      init_point: 'https://mercadopago.test/pro',
      status: 'pending',
    }));

    const response = await requestJson('POST', '/billing/subscribe', {
      token: fixture.token,
      body: { plan: 'PRO' },
    });

    assert.equal(response.status, 201);
    const license = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(license.plan, 'basic');
  });

  it('blocks non-owner subscription attempts', async () => {
    const fixture = await createFixture({ role: 'OPERATOR' });

    const response = await requestJson('POST', '/billing/subscribe', {
      token: fixture.token,
      body: { plan: 'BASIC' },
    });

    assert.equal(response.status, 403);
    assert.equal((response.data as { code?: string }).code, 'BILLING_OWNER_REQUIRED');
  });

  it('activates BASIC through signed approved webhook and is idempotent', async () => {
    const fixture = await createFixture({ plan: 'free' });
    const checkout = await createCheckoutSession(fixture, 'BASIC', 'mp-basic-ok');
    let fetchCount = 0;
    globalThis.fetch = jsonFetch(async () => {
      fetchCount += 1;
      return {
        id: 'mp-basic-ok',
        status: 'authorized',
        external_reference: checkout.id,
        next_payment_date: '2026-06-07T00:00:00.000Z',
      };
    });

    const first = await sendWebhook('mp-basic-ok', 'subscription_preapproval');
    const second = await sendWebhook('mp-basic-ok', 'subscription_preapproval');

    assert.equal(first.status, 200);
    assert.equal(second.status, 200);
    assert.equal(fetchCount, 1);
    const license = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(license.plan, 'BASIC');
    assert.equal(license.status, 'ACTIVE');
    assert.equal(license.providerSubscriptionId, 'mp-basic-ok');

    const bootstrap = await requestJson('GET', '/app/bootstrap', {
      token: fixture.token,
    });
    assert.equal((bootstrap.data as { plan?: string }).plan, 'BASIC');
  });

  it('activates PRO through approved webhook and unlocks second device limit', async () => {
    const fixture = await createFixture({ plan: 'free' });
    const checkout = await createCheckoutSession(fixture, 'PRO', 'mp-pro-ok');
    globalThis.fetch = jsonFetch(async () => ({
      id: 'mp-pro-ok',
      status: 'active',
      external_reference: checkout.id,
    }));

    const webhook = await sendWebhook('mp-pro-ok', 'subscription_preapproval');
    assert.equal(webhook.status, 200);

    const secondDevice = await requestJson('POST', '/app/device', {
      token: fixture.ownerTokenWithoutDevice,
      body: {
        clientInstanceId: `${runId}-second-device`,
        deviceLabel: 'Second Device',
        platform: 'android',
        appVersion: '1.0.0',
      },
    });
    assert.equal(secondDevice.status, 200);
  });

  it('does not change plan for pending rejected or unknown provider statuses', async () => {
    for (const [status, providerRef] of [
      ['pending', 'mp-pending'],
      ['in_process', 'mp-in-process'],
      ['rejected', 'mp-rejected'],
      ['paused', 'mp-unknown'],
    ]) {
      const fixture = await createFixture({ plan: 'basic' });
      const checkout = await createCheckoutSession(
        fixture,
        'PRO',
        providerRef,
      );
      globalThis.fetch = jsonFetch(async () => ({
        id: providerRef,
        status,
        external_reference: checkout.id,
      }));

      const webhook = await sendWebhook(providerRef, 'subscription_preapproval');
      assert.equal(webhook.status, 200);

      const license = await prisma.license.findUniqueOrThrow({
        where: { companyId: fixture.companyId },
      });
      assert.equal(license.plan, 'basic', status);
    }
  });

  it('downgrades to FREE on cancelled or expired without deleting data', async () => {
    for (const [status, providerRef] of [
      ['cancelled', 'mp-cancelled'],
      ['expired', 'mp-expired'],
    ]) {
      const fixture = await createFixture({
        plan: 'pro',
        providerSubscriptionId: providerRef,
      });
      const checkout = await createCheckoutSession(fixture, 'PRO', providerRef);
      await prisma.product.create({
        data: {
          companyId: fixture.companyId,
          localUuid: `${providerRef}-product`,
          name: 'Produto mantido',
          salePriceCents: 1000,
        },
      });
      globalThis.fetch = jsonFetch(async () => ({
        id: providerRef,
        status,
        external_reference: checkout.id,
      }));

      const webhook = await sendWebhook(providerRef, 'subscription_preapproval');
      assert.equal(webhook.status, 200);

      const license = await prisma.license.findUniqueOrThrow({
        where: { companyId: fixture.companyId },
      });
      const productCount = await prisma.product.count({
        where: { companyId: fixture.companyId },
      });
      assert.equal(license.plan, 'FREE');
      assert.equal(productCount, 1);
    }
  });

  it('marks webhook as retryable when Mercado Pago lookup fails', async () => {
    const fixture = await createFixture({ plan: 'free' });
    await createCheckoutSession(fixture, 'BASIC', 'mp-fail');
    globalThis.fetch = jsonFetch(async () => {
      throw new Error('provider unavailable');
    });

    const webhook = await sendWebhook('mp-fail', 'subscription_preapproval');

    assert.equal(webhook.status, 200);
    const event = await prisma.billingProviderEvent.findFirstOrThrow({
      where: { provider: 'mercadopago' },
      orderBy: { createdAt: 'desc' },
    });
    assert.equal(event.status, 'FAILED_RETRYABLE');
    const license = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(license.plan, 'free');
  });

  it('rejects unsigned Mercado Pago webhook in production', async () => {
    env.isProduction = true;
    env.MERCADO_PAGO_WEBHOOK_SECRET = webhookSecret;

    const response = await requestJson(
      'POST',
      '/webhooks/mercadopago?data.id=mp-no-signature',
      {
        body: {
          type: 'subscription_preapproval',
          data: { id: 'mp-no-signature' },
        },
      },
    );

    assert.equal(response.status, 401);
    assert.equal(
      (response.data as { code?: string }).code,
      'MERCADO_PAGO_WEBHOOK_SIGNATURE_INVALID',
    );
  });

  it('refresh reconciles explicitly and is rate limited', async () => {
    const fixture = await createFixture({ plan: 'free' });
    const checkout = await createCheckoutSession(fixture, 'BASIC', 'mp-refresh');
    globalThis.fetch = jsonFetch(async () => ({
      id: 'mp-refresh',
      status: 'approved',
      external_reference: checkout.id,
    }));

    const refreshed = await requestJson('POST', '/billing/refresh', {
      token: fixture.token,
    });
    assert.equal(refreshed.status, 200);
    assert.equal((refreshed.data as { plan?: string }).plan, 'BASIC');

    for (let index = 0; index < 3; index += 1) {
      await requestJson('POST', '/billing/refresh', { token: fixture.token });
    }
    const limited = await requestJson('POST', '/billing/refresh', {
      token: fixture.token,
    });
    assert.equal(limited.status, 429);
  });
});

async function createFixture(options?: {
  role?: 'OWNER' | 'ADMIN' | 'OPERATOR';
  plan?: string;
  providerSubscriptionId?: string;
}) {
  const unique = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
  const company = await prisma.company.create({
    data: {
      name: 'Billing Company',
      legalName: 'Billing Company LTDA',
      slug: `${runId}-company-${unique}`,
    },
  });
  const user = await prisma.user.create({
    data: {
      email: `${runId}-${unique}@tatuzin.test`,
      name: 'Billing Owner',
      passwordHash: 'not-used',
    },
  });
  const membership = await prisma.membership.create({
    data: {
      userId: user.id,
      companyId: company.id,
      role: options?.role ?? 'OWNER',
      isDefault: true,
    },
  });
  await prisma.license.create({
    data: {
      companyId: company.id,
      plan: options?.plan ?? 'free',
      status: 'ACTIVE',
      startsAt: new Date(),
      syncEnabled: true,
      billingProvider:
        options?.providerSubscriptionId == null ? null : 'mercadopago',
      providerSubscriptionId: options?.providerSubscriptionId ?? null,
    },
  });
  const clientInstanceId = `${runId}-device-${unique}`;
  await prisma.companyDevice.create({
    data: {
      companyId: company.id,
      userId: user.id,
      clientInstanceId,
      deviceLabel: 'Billing Test Device',
      platform: 'node-test',
      appVersion: 'billing-test',
      status: 'ACTIVE',
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
    token: signToken({
      userId: user.id,
      companyId: company.id,
      membershipId: membership.id,
      email: user.email,
      membershipRole: options?.role ?? 'OWNER',
      clientInstanceId,
    }),
    ownerTokenWithoutDevice: signToken({
      userId: user.id,
      companyId: company.id,
      membershipId: membership.id,
      email: user.email,
      membershipRole: 'OWNER',
    }),
  };
}

async function createCheckoutSession(
  fixture: { companyId: string; userId: string },
  plan: 'BASIC' | 'PRO',
  providerReference: string,
) {
  return prisma.billingCheckoutSession.create({
    data: {
      companyId: fixture.companyId,
      userId: fixture.userId,
      plan,
      billingCycle: 'monthly',
      status: 'PENDING',
      provider: 'mercadopago',
      providerReference,
      checkoutUrl: `https://mercadopago.test/${providerReference}`,
      sandboxCheckoutUrl: `https://sandbox.mercadopago.test/${providerReference}`,
      expiresAt: new Date(Date.now() + 30 * 60 * 1000),
    },
  });
}

function signToken(input: {
  userId: string;
  companyId: string;
  membershipId: string;
  email: string;
  membershipRole: string;
  clientInstanceId?: string;
}) {
  return jwt.sign(
    {
      sub: input.userId,
      companyId: input.companyId,
      membershipId: input.membershipId,
      membershipRole: input.membershipRole,
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

async function sendWebhook(providerReference: string, eventType: string) {
  const requestId = `${runId}-${providerReference}`;
  const ts = '1715000000';
  const signature = signWebhook(providerReference, requestId, ts);
  return requestJson(
    'POST',
    `/webhooks/mercadopago?data.id=${encodeURIComponent(providerReference)}&type=${eventType}`,
    {
      headers: {
        'x-request-id': requestId,
        'x-signature': signature,
      },
      body: {
        type: eventType,
        data: { id: providerReference },
      },
    },
  );
}

function signWebhook(dataId: string, requestId: string, ts: string) {
  const manifest = `id:${dataId};request-id:${requestId};ts:${ts};`;
  const v1 = createHmac('sha256', webhookSecret)
    .update(manifest)
    .digest('hex');
  return `ts=${ts},v1=${v1}`;
}

async function requestJson(
  method: string,
  path: string,
  options?: {
    token?: string;
    body?: Record<string, unknown>;
    headers?: Record<string, string>;
  },
) {
  const response = await originalFetch(`${apiBaseUrl}${path}`, {
    method,
    headers: {
      ...(options?.token == null
        ? {}
        : { Authorization: `Bearer ${options.token}` }),
      ...(options?.body == null ? {} : { 'Content-Type': 'application/json' }),
      ...(options?.headers ?? {}),
    },
    body: options?.body == null ? undefined : JSON.stringify(options.body),
  });
  const rawBody = await response.text();
  return {
    status: response.status,
    data: rawBody.trim().length === 0 ? null : JSON.parse(rawBody),
  };
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
      body: typeof init?.body === 'string' ? init.body : undefined,
    });
    return new Response(JSON.stringify(payload), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }) as typeof globalThis.fetch;
}

function failFetch(message: string) {
  return (async () => {
    throw new Error(message);
  }) as typeof globalThis.fetch;
}

async function cleanupFixtures() {
  await prisma.billingProviderEvent.deleteMany({
    where: {
      provider: 'mercadopago',
      providerEventId: { contains: runId },
    },
  });
  await prisma.rateLimitBucket.deleteMany({
    where: { scope: 'billing_refresh' },
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
