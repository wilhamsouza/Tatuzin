import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';
import type { AddressInfo } from 'node:net';

import jwt from 'jsonwebtoken';
import type { Server } from 'http';

import { createApp } from '../../../app';
import { env } from '../../../config/env';
import { prisma } from '../../../database/prisma';

type JsonResponse = {
  status: number;
  data: unknown;
};

const runId = `tenant-analytics-${Date.now()}`;

let server: Server;
let apiBaseUrl = '';

describe('tenant analytics reports routes', () => {
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
      server.close((error) => {
        if (error != null) {
          reject(error);
          return;
        }
        resolve();
      });
    });
    await prisma.$disconnect();
  });

  it('allows a licensed tenant user to read the first mobile analytics reports', async () => {
    const fixture = await createTenantFixture();
    const query = `startDate=${fixture.startDate}&endDate=${fixture.endDate}&force=true&topN=5`;

    const salesByDay = await requestJson(
      'GET',
      `/analytics/reports/sales-by-day?${query}`,
      { token: fixture.operatorToken },
    );
    assert.equal(salesByDay.status, 200);
    assert.equal(
      (salesByDay.data as { totals: { salesCount: number } }).totals.salesCount,
      2,
    );

    const salesByProduct = await requestJson(
      'GET',
      `/analytics/reports/sales-by-product?${query}`,
      { token: fixture.operatorToken },
    );
    assert.equal(salesByProduct.status, 200);
    assert.equal(
      (
        salesByProduct.data as {
          items: Array<{ productName: string; revenueCents: number }>;
        }
      ).items[0]?.productName,
      'Produto Tenant',
    );

    const salesByCustomer = await requestJson(
      'GET',
      `/analytics/reports/sales-by-customer?${query}`,
      { token: fixture.operatorToken },
    );
    assert.equal(salesByCustomer.status, 200);
    assert.equal(
      (
        salesByCustomer.data as {
          items: Array<{ customerName: string; revenueCents: number }>;
        }
      ).items[0]?.customerName,
      'Cliente Tenant',
    );

    const financialSummary = await requestJson(
      'GET',
      `/analytics/reports/financial-summary?${query}`,
      { token: fixture.operatorToken },
    );
    assert.equal(financialSummary.status, 200);
    assert.equal(
      (
        financialSummary.data as {
          summary: { salesAmountCents: number; salesProfitCents: number };
        }
      ).summary.salesAmountCents,
      12000,
    );
  });

  it('rejects spoofed companyId query on tenant routes', async () => {
    const fixture = await createTenantFixture();

    const response = await requestJson(
      'GET',
      `/analytics/reports/sales-by-day?companyId=${fixture.otherCompanyId}&startDate=${fixture.startDate}&endDate=${fixture.endDate}`,
      { token: fixture.operatorToken },
    );

    assert.equal(response.status, 422);
    assert.equal((response.data as { code?: string }).code, 'VALIDATION_ERROR');
  });

  it('blocks tenant analytics when the company has no cloud license', async () => {
    const fixture = await createTenantFixture({ createLicense: false });

    const response = await requestJson(
      'GET',
      `/analytics/reports/financial-summary?startDate=${fixture.startDate}&endDate=${fixture.endDate}`,
      { token: fixture.operatorToken },
    );

    assert.equal(response.status, 403);
    assert.equal(
      (response.data as { code?: string }).code,
      'LICENSE_NOT_CONFIGURED',
    );
  });

  it('keeps admin analytics reports restricted to platform admins', async () => {
    const fixture = await createTenantFixture();

    const response = await requestJson(
      'GET',
      `/admin/analytics/reports/sales-by-day?companyId=${fixture.companyId}&startDate=${fixture.startDate}&endDate=${fixture.endDate}`,
      { token: fixture.operatorToken },
    );

    assert.equal(response.status, 403);
    assert.equal(
      (response.data as { code?: string }).code,
      'PLATFORM_ADMIN_REQUIRED',
    );
  });

  it('validates dates and topN on tenant analytics routes', async () => {
    const fixture = await createTenantFixture();

    const invalidDate = await requestJson(
      'GET',
      '/analytics/reports/sales-by-day?startDate=28-04-2026',
      { token: fixture.operatorToken },
    );
    assert.equal(invalidDate.status, 422);

    const invalidTopN = await requestJson(
      'GET',
      '/analytics/reports/sales-by-product?topN=1000',
      { token: fixture.operatorToken },
    );
    assert.equal(invalidTopN.status, 422);
  });
});

async function createTenantFixture(options?: { createLicense?: boolean }) {
  const today = new Date();
  const todayUtc = new Date(
    Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate()),
  );
  const yesterdayUtc = new Date(todayUtc.getTime() - 24 * 60 * 60 * 1000);

  const company = await prisma.company.create({
    data: {
      name: 'Tenant Analytics Mobile',
      legalName: 'Tenant Analytics Mobile LTDA',
      slug: `${runId}-company-${Date.now()}`,
    },
  });
  const otherCompany = await prisma.company.create({
    data: {
      name: 'Tenant Analytics Other',
      legalName: 'Tenant Analytics Other LTDA',
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
      name: 'Tenant Mobile User',
      passwordHash: 'not-used',
      isPlatformAdmin: false,
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

  const customer = await prisma.customer.create({
    data: {
      companyId: company.id,
      localUuid: `${runId}-customer-${Date.now()}`,
      name: 'Cliente Tenant',
    },
  });
  const product = await prisma.product.create({
    data: {
      companyId: company.id,
      localUuid: `${runId}-product-${Date.now()}`,
      name: 'Produto Tenant',
      salePriceCents: 6000,
      costPriceCents: 2500,
      manualCostCents: 2500,
    },
  });

  await prisma.sale.createMany({
    data: [
      {
        companyId: company.id,
        localUuid: `${runId}-sale-1-${Date.now()}`,
        customerId: customer.id,
        paymentType: 'vista',
        paymentMethod: 'pix',
        status: 'active',
        totalAmountCents: 7000,
        totalCostCents: 3000,
        soldAt: todayUtc,
      },
      {
        companyId: company.id,
        localUuid: `${runId}-sale-2-${Date.now()}`,
        customerId: customer.id,
        paymentType: 'vista',
        paymentMethod: 'dinheiro',
        status: 'active',
        totalAmountCents: 5000,
        totalCostCents: 2000,
        soldAt: yesterdayUtc,
      },
    ],
  });

  const sales = await prisma.sale.findMany({
    where: {
      companyId: company.id,
    },
    orderBy: {
      soldAt: 'asc',
    },
  });

  await prisma.saleItem.createMany({
    data: sales.map((sale, index) => ({
      saleId: sale.id,
      productId: product.id,
      productNameSnapshot: 'Produto Tenant',
      quantityMil: 1000,
      unitPriceCents: index === 0 ? 5000 : 7000,
      totalPriceCents: sale.totalAmountCents,
      unitCostCents: index === 0 ? 2000 : 3000,
      totalCostCents: sale.totalCostCents,
      unitMeasure: 'un',
      productType: 'unidade',
    })),
  });

  return {
    companyId: company.id,
    otherCompanyId: otherCompany.id,
    startDate: yesterdayUtc.toISOString().slice(0, 10),
    endDate: todayUtc.toISOString().slice(0, 10),
    operatorToken: signToken({
      userId: user.id,
      companyId: company.id,
      membershipId: membership.id,
      email: user.email,
      isPlatformAdmin: false,
    }),
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
      membershipRole: 'OPERATOR',
      email: input.email,
      isPlatformAdmin: input.isPlatformAdmin,
    },
    env.JWT_SECRET,
    { expiresIn: '15m' },
  );
}

async function requestJson(
  method: string,
  path: string,
  options?: { token?: string },
): Promise<JsonResponse> {
  const response = await fetch(`${apiBaseUrl}${path}`, {
    method,
    headers:
      options?.token == null
        ? undefined
        : {
            Authorization: `Bearer ${options.token}`,
          },
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
