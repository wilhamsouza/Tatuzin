import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';
import type { AddressInfo } from 'node:net';
import type { Server } from 'http';
import { readFileSync } from 'node:fs';

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

  it('returns a safe employees overview without temporary password secrets', async () => {
    const fixture = await createFixture({ plan: 'PRO', role: 'OWNER' });

    const response = await requestJson('GET', '/owner/employees', {
      token: fixture.token,
    });

    assert.equal(response.status, 200);
    const payload = response.data as {
      available: boolean;
      summary: { total: number; active: number; maxEmployees: number };
      items: Array<{ name: string; temporaryPassword?: string }>;
    };
    assert.equal(payload.available, true);
    assert.equal(payload.summary.maxEmployees, 100);
    assert.equal(payload.summary.total >= 1, true);
    assert.equal(JSON.stringify(payload).includes('"temporaryPassword":'), false);
  });

  it('returns owner commission summary through the read-only owner endpoint', async () => {
    const fixture = await createFixture({ plan: 'PRO', role: 'OWNER' });

    const response = await requestJson(
      'GET',
      '/owner/commissions?startDate=2026-05-01&endDate=2026-05-31',
      { token: fixture.token },
    );

    assert.equal(response.status, 200);
    const payload = response.data as {
      period: { from: string; to: string };
      totals: { totalCommissionCents: number };
      rows: unknown[];
    };
    assert.equal(payload.period.from, '2026-05-01');
    assert.equal(payload.period.to, '2026-05-31');
    assert.equal(payload.totals.totalCommissionCents, 0);
    assert.equal(Array.isArray(payload.rows), true);
  });

  it('rejects long owner commission periods with validation error', async () => {
    const fixture = await createFixture({ plan: 'PRO', role: 'OWNER' });

    const response = await requestJson(
      'GET',
      '/owner/commissions?startDate=2026-01-01&endDate=2026-05-31',
      { token: fixture.token },
    );

    assert.equal(response.status, 422);
    assert.equal((response.data as { code?: string }).code, 'VALIDATION_ERROR');
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
      employees: { available: boolean; active: number; maxEmployees: number };
      billing: { plan: string };
    };
    assert.equal(payload.billing.plan, 'PRO');
    assert.equal(payload.employees.available, true);
    assert.equal(payload.employees.maxEmployees, 100);
    assert.equal(payload.reports, null);
  });

  it('protects new business reports with owner and ownerWebPanel checks', async () => {
    const unauthenticated = await requestJson('GET', '/owner/dashboard/business');
    assert.equal(unauthenticated.status, 401);
    assert.equal(
      (unauthenticated.data as { code?: string }).code,
      'AUTH_REQUIRED',
    );

    const operator = await createFixture({ plan: 'PRO', role: 'OPERATOR' });
    const operatorResponse = await requestJson(
      'GET',
      '/owner/dashboard/business',
      { token: operator.token },
    );
    assert.equal(operatorResponse.status, 403);
    assert.equal(
      (operatorResponse.data as { code?: string }).code,
      'OWNER_REQUIRED',
    );

    const freeOwner = await createFixture({ plan: 'FREE', role: 'OWNER' });
    const freeResponse = await requestJson(
      'GET',
      '/owner/dashboard/business',
      { token: freeOwner.token },
    );
    assert.equal(freeResponse.status, 403);
    assert.equal(
      (freeResponse.data as { code?: string }).code,
      'FEATURE_NOT_AVAILABLE',
    );

    const pendingOwner = await createFixture({
      plan: 'BASIC',
      role: 'OWNER',
      pendingPlan: 'PRO',
    });
    const pendingResponse = await requestJson(
      'GET',
      '/owner/reports/sales-summary',
      { token: pendingOwner.token },
    );
    assert.equal(pendingResponse.status, 403);
    assert.equal(
      (pendingResponse.data as { code?: string }).code,
      'FEATURE_NOT_AVAILABLE',
    );
  });

  it('returns real business dashboard, sales, products and stock summaries', async () => {
    const fixture = await createFixture({ plan: 'PRO', role: 'OWNER' });
    await createBusinessData(fixture);
    const otherFixture = await createFixture({ plan: 'PRO', role: 'OWNER' });
    await createBusinessData(otherFixture);

    const dashboard = await requestJson('GET', '/owner/dashboard/business', {
      token: fixture.token,
    });
    const sales = await requestJson(
      'GET',
      `/owner/reports/sales-summary?startDate=${todayDate()}&endDate=${todayDate()}&groupBy=day&page=1&pageSize=10`,
      { token: fixture.token },
    );
    const products = await requestJson(
      'GET',
      `/owner/reports/products?startDate=${todayDate()}&endDate=${todayDate()}&limit=5`,
      { token: fixture.token },
    );
    const stock = await requestJson('GET', '/owner/stock/summary?limit=10', {
      token: fixture.token,
    });

    assert.equal(dashboard.status, 200);
    assert.equal(sales.status, 200);
    assert.equal(products.status, 200);
    assert.equal(stock.status, 200);

    const dashboardPayload = dashboard.data as {
      sales: { todayAmountCents: number; todayCount: number };
      receivables: { openAmountCents: number };
      products: { outOfStock: number; lowStock: number };
      employees: { available: boolean; topPerformers: unknown[] };
    };
    assert.equal(dashboardPayload.sales.todayAmountCents, 16000);
    assert.equal(dashboardPayload.sales.todayCount, 3);
    assert.equal(dashboardPayload.receivables.openAmountCents, 3000);
    assert.equal(dashboardPayload.products.outOfStock, 1);
    assert.equal(dashboardPayload.products.lowStock, 1);
    assert.equal(dashboardPayload.employees.available, true);
    assert.equal(dashboardPayload.employees.topPerformers.length, 1);

    const salesPayload = sales.data as {
      totalAmountCents: number;
      totalCount: number;
      averageTicketCents: number;
      byPaymentMethod: Array<{ label: string; totalAmountCents: number }>;
      recentSales: { items: Array<Record<string, unknown>> };
    };
    assert.equal(salesPayload.totalAmountCents, 16000);
    assert.equal(salesPayload.totalCount, 3);
    assert.equal(salesPayload.averageTicketCents, 5333);
    assert.equal(
      salesPayload.byPaymentMethod.some(
        (item) => item.label === 'Dinheiro' && item.totalAmountCents === 10000,
      ),
      true,
    );
    const serializedSales = JSON.stringify(salesPayload.recentSales.items);
    assert.equal(serializedSales.includes('localUuid'), false);
    assert.equal(serializedSales.includes('owner-routes-sale'), false);

    const productsPayload = products.data as {
      topSellingProducts: Array<{ productName: string; amountCents: number }>;
      stockSummary: { outOfStockCount: number; lowStockCount: number };
    };
    assert.equal(productsPayload.topSellingProducts[0]?.productName, 'Cafe coado');
    assert.equal(productsPayload.topSellingProducts[0]?.amountCents, 15000);
    assert.equal(productsPayload.stockSummary.outOfStockCount, 1);
    assert.equal(productsPayload.stockSummary.lowStockCount, 1);

    const stockPayload = stock.data as {
      totalProducts: number;
      lowStockCount: number;
      outOfStockCount: number;
      itemsLowStock: Array<{ name: string }>;
      itemsOutOfStock: Array<{ name: string }>;
    };
    assert.equal(stockPayload.totalProducts, 3);
    assert.equal(stockPayload.lowStockCount, 1);
    assert.equal(stockPayload.outOfStockCount, 1);
    assert.equal(stockPayload.itemsLowStock[0]?.name, 'Acucar cristal');
    assert.equal(stockPayload.itemsOutOfStock[0]?.name, 'Leite integral');
  });

  it('limits owner report date windows safely', async () => {
    const fixture = await createFixture({ plan: 'PRO', role: 'OWNER' });

    const response = await requestJson(
      'GET',
      '/owner/reports/sales-summary?startDate=2026-01-01&endDate=2026-05-10',
      { token: fixture.token },
    );

    assert.equal(response.status, 422);
    assert.equal(
      (response.data as { code?: string }).code,
      'OWNER_REPORT_DATE_RANGE_TOO_LONG',
    );
  });

  it('returns CRM summaries, paginated customers and blocks cross-company customer detail', async () => {
    const fixture = await createFixture({ plan: 'PRO', role: 'OWNER' });
    const business = await createBusinessData(fixture);
    const otherFixture = await createFixture({ plan: 'PRO', role: 'OWNER' });
    const otherBusiness = await createBusinessData(otherFixture);

    const summary = await requestJson('GET', '/owner/crm/summary?limit=5', {
      token: fixture.token,
    });
    const customers = await requestJson(
      'GET',
      '/owner/crm/customers?status=with_receivables&page=1&pageSize=10',
      { token: fixture.token },
    );
    const searchCustomers = await requestJson(
      'GET',
      '/owner/crm/customers?search=ana&page=1&pageSize=10',
      { token: fixture.token },
    );
    const detail = await requestJson(
      'GET',
      `/owner/crm/customers/${business.bobCustomerId}`,
      { token: fixture.token },
    );
    const crossCompany = await requestJson(
      'GET',
      `/owner/crm/customers/${otherBusiness.aliceCustomerId}`,
      { token: fixture.token },
    );

    assert.equal(summary.status, 200);
    const summaryPayload = summary.data as {
      totalCustomers: number;
      activeCustomers: number;
      inactiveCustomers: number;
      newCustomersThisMonth: number;
      customersWithReceivables: number;
      topCustomers: Array<{ name: string; totalPurchasedCents: number }>;
    };
    assert.equal(summaryPayload.totalCustomers, 3);
    assert.equal(summaryPayload.activeCustomers, 2);
    assert.equal(summaryPayload.inactiveCustomers, 1);
    assert.equal(summaryPayload.newCustomersThisMonth, 3);
    assert.equal(summaryPayload.customersWithReceivables, 1);
    assert.equal(summaryPayload.topCustomers[0]?.name, 'Ana Cliente');

    assert.equal(customers.status, 200);
    const customersPayload = customers.data as {
      items: Array<{ name: string; openReceivableAmountCents: number }>;
      total: number;
    };
    assert.equal(customersPayload.total, 1);
    assert.equal(customersPayload.items[0]?.name, 'Bruno Fiado');
    assert.equal(customersPayload.items[0]?.openReceivableAmountCents, 3000);

    assert.equal(searchCustomers.status, 200);
    const searchPayload = searchCustomers.data as {
      items: Array<{ name: string }>;
      total: number;
    };
    assert.equal(searchPayload.total, 1);
    assert.equal(searchPayload.items[0]?.name, 'Ana Cliente');

    assert.equal(detail.status, 200);
    const detailPayload = detail.data as {
      customer: { name: string; openReceivableAmountCents: number };
      topProducts: Array<{ productName: string }>;
      recentPurchases: Array<{ receiptNumber: string | null }>;
      receivables: { openAmountCents: number };
    };
    assert.equal(detailPayload.customer.name, 'Bruno Fiado');
    assert.equal(detailPayload.customer.openReceivableAmountCents, 3000);
    assert.equal(detailPayload.topProducts[0]?.productName, 'Cafe coado');
    assert.equal(detailPayload.recentPurchases[0]?.receiptNumber, 'F-101');
    assert.equal(detailPayload.receivables.openAmountCents, 3000);

    assert.equal(crossCompany.status, 404);
    assert.equal(
      (crossCompany.data as { code?: string }).code,
      'OWNER_CUSTOMER_NOT_FOUND',
    );
  });

  it('returns receivables, report catalog and employee reports safely', async () => {
    const fixture = await createFixture({ plan: 'PRO', role: 'OWNER' });
    await createBusinessData(fixture);
    const emptyFixture = await createFixture({ plan: 'PRO', role: 'OWNER' });

    const receivables = await requestJson(
      'GET',
      '/owner/financial/receivables?status=open&page=1&pageSize=10',
      { token: fixture.token },
    );
    const employees = await requestJson(
      'GET',
      `/owner/reports/employees?startDate=${todayDate()}&endDate=${todayDate()}&limit=5`,
      { token: fixture.token },
    );
    const emptyEmployees = await requestJson(
      'GET',
      '/owner/reports/employees?limit=5',
      { token: emptyFixture.token },
    );
    const catalog = await requestJson('GET', '/owner/reports/catalog', {
      token: fixture.token,
    });

    assert.equal(receivables.status, 200);
    const receivablesPayload = receivables.data as {
      summary: {
        openAmountCents: number;
        overdueAmountCents: number;
        openCount: number;
        receivedThisMonthCents: number;
      };
      items: { items: Array<{ customerName: string; status: string }> };
    };
    assert.equal(receivablesPayload.summary.openAmountCents, 3000);
    assert.equal(receivablesPayload.summary.overdueAmountCents, 0);
    assert.equal(receivablesPayload.summary.openCount, 1);
    assert.equal(receivablesPayload.summary.receivedThisMonthCents, 3000);
    assert.equal(receivablesPayload.items.items[0]?.customerName, 'Bruno Fiado');
    assert.equal(receivablesPayload.items.items[0]?.status, 'open');

    assert.equal(employees.status, 200);
    const employeesPayload = employees.data as {
      available: boolean;
      topEmployees: Array<{
        name: string;
        salesAmountCents: number;
        salesCount: number;
        averageTicketCents: number;
      }>;
    };
    assert.equal(employeesPayload.available, true);
    assert.equal(employeesPayload.topEmployees[0]?.name, 'Owner Routes User');
    assert.equal(employeesPayload.topEmployees[0]?.salesAmountCents, 16000);
    assert.equal(employeesPayload.topEmployees[0]?.salesCount, 3);
    assert.equal(employeesPayload.topEmployees[0]?.averageTicketCents, 5333);

    assert.equal(emptyEmployees.status, 200);
    assert.deepEqual(emptyEmployees.data, {
      available: false,
      reason: 'EMPLOYEE_REPORTS_NOT_AVAILABLE',
      period: (emptyEmployees.data as { period: unknown }).period,
      topEmployees: [],
    });

    assert.equal(catalog.status, 200);
    const catalogPayload = catalog.data as {
      items: Array<{ key: string; title: string; available: boolean }>;
    };
    const reportKeys = catalogPayload.items.map((item) => item.key);
    assert.deepEqual(reportKeys, [
      'sales',
      'products',
      'cash',
      'stock',
      'customers',
      'purchases',
      'profitability',
      'employees',
    ]);
    assert.equal(
      catalogPayload.items.some(
        (item) => item.key === 'employees' && item.available,
      ),
      true,
    );
  });

  it('keeps owner reporting GET-only and free from admin API usage', () => {
    const routesSource = readFileSync(
      'src/modules/owner/owner.routes.ts',
      'utf8',
    );
    const serviceSource = readFileSync(
      'src/modules/owner/owner-reporting.service.ts',
      'utf8',
    );

    assert.equal(routesSource.includes('/api/admin'), false);
    assert.equal(serviceSource.includes('/api/admin'), false);
    assert.equal(/ownerRouter\.(post|put|patch|delete)\(/.test(routesSource), false);
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
    membershipId: membership.id,
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

async function createBusinessData(fixture: {
  companyId: string;
  userId: string;
  membershipId: string;
}) {
  await prisma.employeeProfile.create({
    data: {
      companyId: fixture.companyId,
      userId: fixture.userId,
      membershipId: fixture.membershipId,
      name: 'Owner Routes User',
      email: `${fixture.userId}@tatuzin.test`,
      emailNormalized: `${fixture.userId}@tatuzin.test`,
      role: 'OWNER',
      status: 'ACTIVE',
      permissions: ['employees.manage'] as Prisma.InputJsonValue,
      createdByUserId: fixture.userId,
      updatedByUserId: fixture.userId,
    },
  });

  const [coffee, sugar, milk] = await Promise.all([
    prisma.product.create({
      data: {
        companyId: fixture.companyId,
        localUuid: `${runId}-product-coffee`,
        name: 'Cafe coado',
        salePriceCents: 5000,
        costPriceCents: 2000,
        stockMil: 5000,
      },
    }),
    prisma.product.create({
      data: {
        companyId: fixture.companyId,
        localUuid: `${runId}-product-sugar`,
        name: 'Acucar cristal',
        salePriceCents: 1000,
        costPriceCents: 400,
        stockMil: 500,
      },
    }),
    prisma.product.create({
      data: {
        companyId: fixture.companyId,
        localUuid: `${runId}-product-milk`,
        name: 'Leite integral',
        salePriceCents: 700,
        costPriceCents: 350,
        stockMil: 0,
      },
    }),
  ]);

  const [alice, bob, inactive] = await Promise.all([
    prisma.customer.create({
      data: {
        companyId: fixture.companyId,
        localUuid: `${runId}-customer-alice`,
        name: 'Ana Cliente',
        phone: '11999990000',
      },
    }),
    prisma.customer.create({
      data: {
        companyId: fixture.companyId,
        localUuid: `${runId}-customer-bob`,
        name: 'Bruno Fiado',
        phone: '11888880000',
      },
    }),
    prisma.customer.create({
      data: {
        companyId: fixture.companyId,
        localUuid: `${runId}-customer-inactive`,
        name: 'Carla Sem Compra',
      },
    }),
  ]);

  const cashSession = await prisma.cashSession.create({
    data: {
      companyId: fixture.companyId,
      userId: fixture.userId,
      localUuid: `${runId}-cash-session`,
      status: 'open',
      openedAt: new Date(),
    },
  });

  const cashSale = await prisma.sale.create({
    data: {
      companyId: fixture.companyId,
      cashSessionId: cashSession.id,
      localUuid: `${runId}-sale-cash`,
      customerId: alice.id,
      receiptNumber: 'F-100',
      paymentType: 'vista',
      paymentMethod: 'dinheiro',
      status: 'active',
      totalAmountCents: 10000,
      totalCostCents: 4000,
      soldAt: new Date(),
      items: {
        create: [
          {
            productId: coffee.id,
            productNameSnapshot: coffee.name,
            quantityMil: 2000,
            unitPriceCents: 5000,
            totalPriceCents: 10000,
            unitCostCents: 2000,
            totalCostCents: 4000,
            unitMeasure: 'un',
            productType: 'unidade',
          },
        ],
      },
    },
  });

  const openFiadoSale = await prisma.sale.create({
    data: {
      companyId: fixture.companyId,
      cashSessionId: cashSession.id,
      localUuid: `${runId}-sale-fiado-open`,
      customerId: bob.id,
      receiptNumber: 'F-101',
      paymentType: 'fiado',
      paymentMethod: 'fiado',
      status: 'active',
      totalAmountCents: 5000,
      totalCostCents: 2000,
      soldAt: new Date(),
      items: {
        create: [
          {
            productId: coffee.id,
            productNameSnapshot: coffee.name,
            quantityMil: 1000,
            unitPriceCents: 5000,
            totalPriceCents: 5000,
            unitCostCents: 2000,
            totalCostCents: 2000,
            unitMeasure: 'un',
            productType: 'unidade',
          },
        ],
      },
    },
  });

  const paidFiadoSale = await prisma.sale.create({
    data: {
      companyId: fixture.companyId,
      cashSessionId: cashSession.id,
      localUuid: `${runId}-sale-fiado-paid`,
      customerId: alice.id,
      receiptNumber: 'F-102',
      paymentType: 'fiado',
      paymentMethod: 'fiado',
      status: 'active',
      totalAmountCents: 1000,
      totalCostCents: 400,
      soldAt: new Date(),
      items: {
        create: [
          {
            productId: sugar.id,
            productNameSnapshot: sugar.name,
            quantityMil: 1000,
            unitPriceCents: 1000,
            totalPriceCents: 1000,
            unitCostCents: 400,
            totalCostCents: 400,
            unitMeasure: 'un',
            productType: 'unidade',
          },
        ],
      },
    },
  });

  await prisma.fiadoPayment.createMany({
    data: [
      {
        companyId: fixture.companyId,
        saleId: openFiadoSale.id,
        localUuid: `${runId}-fiado-payment-open`,
        amountCents: 2000,
        paymentMethod: 'pix',
        createdAt: new Date(),
      },
      {
        companyId: fixture.companyId,
        saleId: paidFiadoSale.id,
        localUuid: `${runId}-fiado-payment-paid`,
        amountCents: 1000,
        paymentMethod: 'dinheiro',
        createdAt: new Date(),
      },
    ],
  });

  return {
    aliceCustomerId: alice.id,
    bobCustomerId: bob.id,
    inactiveCustomerId: inactive.id,
    cashSaleId: cashSale.id,
  };
}

function todayDate() {
  return new Date().toISOString().slice(0, 10);
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
