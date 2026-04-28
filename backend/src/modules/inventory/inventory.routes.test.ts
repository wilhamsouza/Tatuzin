import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';
import type { AddressInfo } from 'node:net';

import type { Server } from 'http';
import jwt from 'jsonwebtoken';

import { createApp } from '../../app';
import { env } from '../../config/env';
import { prisma } from '../../database/prisma';

const runId = `tenant-inventory-${Date.now()}`;

let server: Server;
let apiBaseUrl = '';

describe('tenant inventory routes', () => {
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

  it('allows a licensed tenant user to list inventory and summary', async () => {
    const fixture = await createFixture();

    const list = await requestJson('GET', '/inventory?page=1&pageSize=20', {
      token: fixture.token,
    });
    assert.equal(list.status, 200);
    assert.equal(
      (list.data as { items: unknown[]; pagination: { total: number } })
        .pagination.total,
      3,
    );

    const summary = await requestJson('GET', '/inventory/summary', {
      token: fixture.token,
    });
    assert.equal(summary.status, 200);
    assert.equal(
      (summary.data as { summary: { totalItemsCount: number } }).summary
        .totalItemsCount,
      3,
    );
  });

  it('rejects companyId query and blocks companies without cloud license', async () => {
    const fixture = await createFixture();
    const spoof = await requestJson(
      'GET',
      `/inventory?companyId=${fixture.otherCompanyId}`,
      { token: fixture.token },
    );
    assert.equal(spoof.status, 422);

    const unlicensed = await createFixture({ createLicense: false });
    const blocked = await requestJson('GET', '/inventory/summary', {
      token: unlicensed.token,
    });
    assert.equal(blocked.status, 403);
  });

  it('filters zeroed and below minimum items and paginates results', async () => {
    const fixture = await createFixture();

    const zeroed = await requestJson('GET', '/inventory?filter=zeroed', {
      token: fixture.token,
    });
    assert.equal(zeroed.status, 200);
    assert.deepEqual(
      (zeroed.data as { items: Array<{ status: string }> }).items.map(
        (item) => item.status,
      ),
      ['zeroed'],
    );

    const belowMinimum = await requestJson(
      'GET',
      '/inventory?filter=belowMinimum',
      { token: fixture.token },
    );
    assert.equal(belowMinimum.status, 200);
    assert.equal((belowMinimum.data as { items: unknown[] }).items.length, 0);

    const page = await requestJson('GET', '/inventory?page=2&pageSize=1', {
      token: fixture.token,
    });
    assert.equal(page.status, 200);
    assert.equal(
      (page.data as { items: unknown[]; pagination: { page: number; total: number } })
        .items.length,
      1,
    );
    assert.equal(
      (page.data as { pagination: { page: number } }).pagination.page,
      2,
    );
  });

  it('does not leak inventory between tenants', async () => {
    const fixture = await createFixture();
    const list = await requestJson('GET', '/inventory?query=Outro', {
      token: fixture.token,
    });

    assert.equal(list.status, 200);
    assert.equal((list.data as { items: unknown[] }).items.length, 0);
  });
});

async function createFixture(options?: { createLicense?: boolean }) {
  const company = await prisma.company.create({
    data: {
      name: 'Tenant Inventory',
      legalName: 'Tenant Inventory LTDA',
      slug: `${runId}-company-${Date.now()}`,
    },
  });
  const otherCompany = await prisma.company.create({
    data: {
      name: 'Tenant Inventory Other',
      legalName: 'Tenant Inventory Other LTDA',
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
      name: 'Inventory User',
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

  await prisma.product.createMany({
    data: [
      {
        companyId: company.id,
        localUuid: `${runId}-active-${Date.now()}`,
        name: 'Produto Ativo',
        salePriceCents: 2000,
        costPriceCents: 1000,
        stockMil: 3000,
      },
      {
        companyId: company.id,
        localUuid: `${runId}-zero-${Date.now()}`,
        name: 'Produto Zerado',
        salePriceCents: 2000,
        costPriceCents: 1000,
        stockMil: 0,
      },
      {
        companyId: otherCompany.id,
        localUuid: `${runId}-other-product-${Date.now()}`,
        name: 'Outro Produto',
        salePriceCents: 2000,
        costPriceCents: 1000,
        stockMil: 9000,
      },
    ],
  });

  const variantProduct = await prisma.product.create({
    data: {
      companyId: company.id,
      localUuid: `${runId}-variant-${Date.now()}`,
      name: 'Produto Grade',
      salePriceCents: 3000,
      costPriceCents: 1500,
      stockMil: 0,
    },
  });
  await prisma.productVariant.create({
    data: {
      productId: variantProduct.id,
      sku: `${runId}-sku`,
      colorLabel: 'Preto',
      sizeLabel: 'M',
      stockMil: 2000,
    },
  });

  return {
    otherCompanyId: otherCompany.id,
    token: signToken({
      userId: user.id,
      companyId: company.id,
      membershipId: membership.id,
      email: user.email,
    }),
  };
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
  options?: { token?: string },
) {
  const response = await fetch(`${apiBaseUrl}${path}`, {
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
  await prisma.company.deleteMany({
    where: { slug: { startsWith: `${runId}-` } },
  });
  await prisma.user.deleteMany({
    where: { email: { startsWith: `${runId}-` } },
  });
}

