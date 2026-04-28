import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';
import type { AddressInfo } from 'node:net';

import type { Server } from 'http';
import jwt from 'jsonwebtoken';

import { createApp } from '../../app';
import { env } from '../../config/env';
import { prisma } from '../../database/prisma';

const runId = `tenant-costs-${Date.now()}`;

let server: Server;
let apiBaseUrl = '';

describe('tenant costs routes', () => {
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

  it('creates, lists, updates, pays and cancels tenant costs', async () => {
    const fixture = await createFixture();

    const create = await requestJson('POST', '/costs', {
      token: fixture.token,
      body: {
        localUuid: `${runId}-local-create`,
        description: 'Aluguel',
        type: 'fixed',
        category: 'Operacional',
        amountCents: 10000,
        referenceDate: fixture.today,
        isRecurring: true,
      },
    });
    assert.equal(create.status, 201);
    const created = (create.data as { cost: { id: string } }).cost;

    const idempotent = await requestJson('POST', '/costs', {
      token: fixture.token,
      body: {
        localUuid: `${runId}-local-create`,
        description: 'Aluguel divergente',
        type: 'fixed',
        amountCents: 999,
        referenceDate: fixture.today,
      },
    });
    assert.equal(idempotent.status, 201);
    assert.equal((idempotent.data as { cost: { id: string } }).cost.id, created.id);

    const list = await requestJson('GET', '/costs?type=fixed&page=1&pageSize=20', {
      token: fixture.token,
    });
    assert.equal(list.status, 200);
    assert.equal(
      (list.data as { items: Array<{ description: string }> }).items[0]
        ?.description,
      'Aluguel',
    );

    const update = await requestJson('PUT', `/costs/${created.id}`, {
      token: fixture.token,
      body: {
        description: 'Aluguel atualizado',
        amountCents: 11000,
      },
    });
    assert.equal(update.status, 200);
    assert.equal(
      (update.data as { cost: { amountCents: number } }).cost.amountCents,
      11000,
    );

    const pay = await requestJson('POST', `/costs/${created.id}/pay`, {
      token: fixture.token,
      body: {
        paidAt: fixture.today,
        paymentMethod: 'pix',
        registerInCash: false,
      },
    });
    assert.equal(pay.status, 200);
    assert.equal((pay.data as { cost: { status: string } }).cost.status, 'paid');

    const cancelCreate = await requestJson('POST', '/costs', {
      token: fixture.token,
      body: {
        localUuid: `${runId}-local-cancel`,
        description: 'Internet',
        type: 'variable',
        amountCents: 5000,
        referenceDate: fixture.today,
      },
    });
    const cancelId = (cancelCreate.data as { cost: { id: string } }).cost.id;
    const cancel = await requestJson('DELETE', `/costs/${cancelId}`, {
      token: fixture.token,
      body: { notes: 'Cancelado no teste' },
    });
    assert.equal(cancel.status, 200);
    assert.equal(
      (cancel.data as { cost: { status: string } }).cost.status,
      'canceled',
    );
  });

  it('summarizes pending, paid and overdue costs', async () => {
    const fixture = await createFixture();
    await seedCosts(fixture.companyId);

    const summary = await requestJson(
      'GET',
      `/costs/summary?startDate=${fixture.monthStart}&endDate=${fixture.nextMonth}`,
      { token: fixture.token },
    );

    assert.equal(summary.status, 200);
    const data = (summary.data as {
      summary: {
        pendingFixedCents: number;
        overdueVariableCents: number;
        paidFixedThisMonthCents: number;
      };
    }).summary;
    assert.equal(data.pendingFixedCents, 10000);
    assert.equal(data.overdueVariableCents, 3000);
    assert.equal(data.paidFixedThisMonthCents, 7000);
  });

  it('rejects companyId, invalid payloads, unlicensed access and tenant leaks', async () => {
    const fixture = await createFixture();

    const querySpoof = await requestJson(
      'GET',
      `/costs?companyId=${fixture.otherCompanyId}`,
      { token: fixture.token },
    );
    assert.equal(querySpoof.status, 422);

    const bodySpoof = await requestJson('POST', '/costs', {
      token: fixture.token,
      body: {
        companyId: fixture.otherCompanyId,
        localUuid: `${runId}-spoof`,
        description: 'Spoof',
        type: 'fixed',
        amountCents: 100,
        referenceDate: fixture.today,
      },
    });
    assert.equal(bodySpoof.status, 422);

    const invalid = await requestJson('POST', '/costs', {
      token: fixture.token,
      body: {
        localUuid: `${runId}-invalid`,
        description: '',
        type: 'fixed',
        amountCents: 0,
        referenceDate: fixture.today,
      },
    });
    assert.equal(invalid.status, 422);

    await prisma.cost.create({
      data: {
        companyId: fixture.otherCompanyId,
        localUuid: `${runId}-other-cost`,
        description: 'Custo de outro tenant',
        type: 'fixed',
        amountCents: 30000,
        referenceDate: new Date(fixture.today),
      },
    });
    const list = await requestJson('GET', '/costs', { token: fixture.token });
    assert.equal(
      (list.data as { items: Array<{ description: string }> }).items.some(
        (item) => item.description.includes('outro tenant'),
      ),
      false,
    );

    const unlicensed = await createFixture({ createLicense: false });
    const blocked = await requestJson('GET', '/costs/summary', {
      token: unlicensed.token,
    });
    assert.equal(blocked.status, 403);
  });
});

async function createFixture(options?: { createLicense?: boolean }) {
  const now = new Date();
  const monthStart = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1),
  );
  const nextMonth = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1),
  );
  const company = await prisma.company.create({
    data: {
      name: 'Tenant Costs',
      legalName: 'Tenant Costs LTDA',
      slug: `${runId}-company-${Date.now()}`,
    },
  });
  const otherCompany = await prisma.company.create({
    data: {
      name: 'Tenant Costs Other',
      legalName: 'Tenant Costs Other LTDA',
      slug: `${runId}-other-${Date.now()}`,
    },
  });

  if (options?.createLicense !== false) {
    await prisma.license.create({
      data: {
        companyId: company.id,
        plan: 'pro',
        status: 'ACTIVE',
        startsAt: new Date(),
        syncEnabled: true,
      },
    });
  }

  const user = await prisma.user.create({
    data: {
      email: `${runId}-${Date.now()}@tatuzin.test`,
      name: 'Costs User',
      passwordHash: 'not-used',
    },
  });
  const membership = await prisma.membership.create({
    data: {
      userId: user.id,
      companyId: company.id,
      role: 'OPERATOR',
      isDefault: true,
    },
  });

  return {
    companyId: company.id,
    otherCompanyId: otherCompany.id,
    today: now.toISOString(),
    monthStart: monthStart.toISOString(),
    nextMonth: nextMonth.toISOString(),
    token: signToken({
      userId: user.id,
      companyId: company.id,
      membershipId: membership.id,
      email: user.email,
    }),
  };
}

async function seedCosts(companyId: string) {
  const now = new Date();
  const overdue = new Date(now.getTime() - 24 * 60 * 60 * 1000);
  await prisma.cost.createMany({
    data: [
      {
        companyId,
        localUuid: `${runId}-pending-fixed`,
        description: 'Pendente fixo',
        type: 'fixed',
        amountCents: 10000,
        referenceDate: now,
      },
      {
        companyId,
        localUuid: `${runId}-overdue-variable`,
        description: 'Vencido variavel',
        type: 'variable',
        amountCents: 3000,
        referenceDate: overdue,
      },
      {
        companyId,
        localUuid: `${runId}-paid-fixed`,
        description: 'Pago fixo',
        type: 'fixed',
        amountCents: 7000,
        referenceDate: now,
        status: 'paid',
        paidAt: now,
        paymentMethod: 'pix',
      },
    ],
  });
}

function signToken(input: {
  userId: string;
  companyId: string;
  membershipId: string;
  email: string;
}) {
  return jwt.sign(
    {
      sub: input.userId,
      companyId: input.companyId,
      membershipId: input.membershipId,
      membershipRole: 'OPERATOR',
      email: input.email,
      isPlatformAdmin: false,
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

