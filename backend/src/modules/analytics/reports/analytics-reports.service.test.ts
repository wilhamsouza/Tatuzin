import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';

import { prisma } from '../../../database/prisma';
import { AnalyticsReportsService } from './analytics-reports.service';
import { AnalyticsSnapshotsService } from '../snapshots/analytics-snapshots.service';

const runId = `analytics-${Date.now()}`;

describe('analytics reports service', () => {
  const snapshotsService = new AnalyticsSnapshotsService();
  const reportsService = new AnalyticsReportsService(snapshotsService);

  before(async () => {
    await prisma.$connect();
  });

  beforeEach(async () => {
    await cleanupFixtures();
  });

  after(async () => {
    await cleanupFixtures();
    await prisma.$disconnect();
  });

  it('materializes daily snapshots and aggregates the first management reports', async () => {
    const fixture = await createFixture();

    const materialization = await snapshotsService.materializeCompanyRange({
      companyId: fixture.companyId,
      startDate: fixture.startDate,
      endDate: fixture.endDate,
      force: true,
    });

    assert.equal(materialization.period.dayCount, 2);
    assert.equal(materialization.coverage.companyDailyRows, 2);
    assert.equal(materialization.coverage.productDailyRows, 3);
    assert.equal(materialization.coverage.customerDailyRows, 2);

    const salesByDay = await reportsService.getSalesByDay({
      companyId: fixture.companyId,
      startDate: fixture.startDate,
      endDate: fixture.endDate,
      topN: 5,
      force: false,
    });
    assert.equal(salesByDay.totals.salesCount, 2);
    assert.equal(salesByDay.totals.salesAmountCents, 12000);
    assert.equal(salesByDay.totals.salesProfitCents, 7000);

    const salesByProduct = await reportsService.getSalesByProduct({
      companyId: fixture.companyId,
      startDate: fixture.startDate,
      endDate: fixture.endDate,
      topN: 5,
      force: false,
    });
    assert.equal(salesByProduct.items[0]?.productName, 'Burger Cloud');
    assert.equal(salesByProduct.items[0]?.revenueCents, 11000);
    assert.equal(salesByProduct.items[0]?.profitCents, 6500);

    const salesByCustomer = await reportsService.getSalesByCustomer({
      companyId: fixture.companyId,
      startDate: fixture.startDate,
      endDate: fixture.endDate,
      topN: 5,
      force: false,
    });
    assert.equal(salesByCustomer.items[0]?.customerName, 'Alice Cloud');
    assert.equal(salesByCustomer.items[0]?.revenueCents, 12000);
    assert.equal(salesByCustomer.items[0]?.fiadoPaymentsCents, 1500);

    const cash = await reportsService.getCashConsolidated({
      companyId: fixture.companyId,
      startDate: fixture.startDate,
      endDate: fixture.endDate,
      topN: 5,
      force: false,
    });
    assert.equal(cash.totals.cashInflowCents, 11000);
    assert.equal(cash.totals.cashOutflowCents, 1500);
    assert.equal(cash.totals.cashNetCents, 9500);

    const financialSummary = await reportsService.getFinancialSummary({
      companyId: fixture.companyId,
      startDate: fixture.startDate,
      endDate: fixture.endDate,
      topN: 5,
      force: false,
    });
    assert.equal(financialSummary.summary.salesAmountCents, 12000);
    assert.equal(financialSummary.summary.salesProfitCents, 7000);
    assert.equal(financialSummary.summary.purchasesAmountCents, 3000);
    assert.equal(financialSummary.summary.fiadoPaymentsAmountCents, 1500);
    assert.equal(financialSummary.summary.financialAdjustmentsCents, 500);
  });
});

async function createFixture() {
  const today = new Date();
  const todayUtc = new Date(
    Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate()),
  );
  const yesterdayUtc = new Date(todayUtc.getTime() - 24 * 60 * 60 * 1000);

  const company = await prisma.company.create({
    data: {
      name: 'Tatuzin Analytics Cloud',
      legalName: 'Tatuzin Analytics Cloud LTDA',
      slug: `${runId}-company`,
      documentNumber: null,
      isActive: true,
    },
  });

  const customer = await prisma.customer.create({
    data: {
      companyId: company.id,
      localUuid: `${runId}-customer`,
      name: 'Alice Cloud',
      phone: null,
      address: null,
      notes: null,
    },
  });

  const supplier = await prisma.supplier.create({
    data: {
      companyId: company.id,
      localUuid: `${runId}-supplier`,
      name: 'Fornecedor Cloud',
      tradeName: null,
      phone: null,
      email: null,
      address: null,
      document: null,
      contactPerson: null,
      notes: null,
    },
  });

  const productBurger = await prisma.product.create({
    data: {
      companyId: company.id,
      localUuid: `${runId}-burger`,
      name: 'Burger Cloud',
      salePriceCents: 5500,
      manualCostCents: 2200,
      costPriceCents: 2200,
    },
  });

  const productSoda = await prisma.product.create({
    data: {
      companyId: company.id,
      localUuid: `${runId}-soda`,
      name: 'Soda Cloud',
      salePriceCents: 1000,
      manualCostCents: 500,
      costPriceCents: 500,
    },
  });

  const fiadoSale = await prisma.sale.create({
    data: {
      companyId: company.id,
      localUuid: `${runId}-sale-fiado`,
      customerId: customer.id,
      paymentType: 'fiado',
      paymentMethod: 'fiado',
      status: 'active',
      totalAmountCents: 5000,
      totalCostCents: 2000,
      soldAt: yesterdayUtc,
      items: {
        create: [
          {
            productId: productBurger.id,
            productNameSnapshot: 'Burger Cloud',
            quantityMil: 2000,
            unitPriceCents: 2500,
            totalPriceCents: 5000,
            unitCostCents: 1000,
            totalCostCents: 2000,
            unitMeasure: 'un',
            productType: 'unidade',
          },
        ],
      },
    },
  });

  await prisma.sale.create({
    data: {
      companyId: company.id,
      localUuid: `${runId}-sale-vista`,
      customerId: customer.id,
      paymentType: 'vista',
      paymentMethod: 'pix',
      status: 'active',
      totalAmountCents: 7000,
      totalCostCents: 3000,
      soldAt: new Date(todayUtc.getTime() + 10 * 60 * 60 * 1000),
      items: {
        create: [
          {
            productId: productBurger.id,
            productNameSnapshot: 'Burger Cloud',
            quantityMil: 2000,
            unitPriceCents: 3000,
            totalPriceCents: 6000,
            unitCostCents: 1250,
            totalCostCents: 2500,
            unitMeasure: 'un',
            productType: 'unidade',
          },
          {
            productId: productSoda.id,
            productNameSnapshot: 'Soda Cloud',
            quantityMil: 1000,
            unitPriceCents: 1000,
            totalPriceCents: 1000,
            unitCostCents: 500,
            totalCostCents: 500,
            unitMeasure: 'un',
            productType: 'unidade',
          },
        ],
      },
    },
  });

  await prisma.sale.create({
    data: {
      companyId: company.id,
      localUuid: `${runId}-sale-canceled`,
      customerId: customer.id,
      paymentType: 'vista',
      paymentMethod: 'dinheiro',
      status: 'canceled',
      totalAmountCents: 1000,
      totalCostCents: 300,
      soldAt: new Date(todayUtc.getTime() + 12 * 60 * 60 * 1000),
      canceledAt: new Date(todayUtc.getTime() + 12 * 60 * 60 * 1000),
      items: {
        create: [
          {
            productId: productSoda.id,
            productNameSnapshot: 'Soda Cloud',
            quantityMil: 1000,
            unitPriceCents: 1000,
            totalPriceCents: 1000,
            unitCostCents: 300,
            totalCostCents: 300,
            unitMeasure: 'un',
            productType: 'unidade',
          },
        ],
      },
    },
  });

  await prisma.purchase.create({
    data: {
      companyId: company.id,
      localUuid: `${runId}-purchase`,
      supplierId: supplier.id,
      purchasedAt: yesterdayUtc,
      paymentMethod: 'pix',
      status: 'recebida',
      subtotalCents: 3000,
      finalAmountCents: 3000,
      pendingAmountCents: 0,
      items: {
        create: [
          {
            localUuid: `${runId}-purchase-item`,
            itemType: 'product',
            productId: productBurger.id,
            productNameSnapshot: 'Burger Cloud',
            unitMeasureSnapshot: 'un',
            quantityMil: 1000,
            unitCostCents: 3000,
            subtotalCents: 3000,
          },
        ],
      },
    },
  });

  await prisma.cashEvent.createMany({
    data: [
      {
        companyId: company.id,
        localUuid: `${runId}-cash-in-yesterday`,
        eventType: 'entrada',
        amountCents: 4000,
        paymentMethod: 'dinheiro',
        createdAt: yesterdayUtc,
      },
      {
        companyId: company.id,
        localUuid: `${runId}-cash-out-yesterday`,
        eventType: 'retirada',
        amountCents: 500,
        paymentMethod: 'dinheiro',
        createdAt: new Date(yesterdayUtc.getTime() + 30 * 60 * 1000),
      },
      {
        companyId: company.id,
        localUuid: `${runId}-cash-in-today`,
        eventType: 'entrada',
        amountCents: 7000,
        paymentMethod: 'pix',
        createdAt: new Date(todayUtc.getTime() + 10 * 60 * 60 * 1000),
      },
      {
        companyId: company.id,
        localUuid: `${runId}-cash-out-today`,
        eventType: 'saida',
        amountCents: 1000,
        paymentMethod: 'dinheiro',
        createdAt: new Date(todayUtc.getTime() + 11 * 60 * 60 * 1000),
      },
    ],
  });

  await prisma.fiadoPayment.create({
    data: {
      companyId: company.id,
      saleId: fiadoSale.id,
      localUuid: `${runId}-fiado-payment`,
      amountCents: 1500,
      paymentMethod: 'pix',
      createdAt: new Date(todayUtc.getTime() + 14 * 60 * 60 * 1000),
    },
  });

  await prisma.financialEvent.createMany({
    data: [
      {
        companyId: company.id,
        saleId: fiadoSale.id,
        fiadoId: 'fiado-cloud-1',
        eventType: 'fiado_payment',
        localUuid: `${runId}-financial-fiado`,
        amountCents: 1500,
        paymentType: 'pix',
        createdAt: new Date(todayUtc.getTime() + 14 * 60 * 60 * 1000),
      },
      {
        companyId: company.id,
        saleId: null,
        fiadoId: null,
        eventType: 'sale_canceled',
        localUuid: `${runId}-financial-cancel`,
        amountCents: 1000,
        paymentType: 'dinheiro',
        createdAt: new Date(todayUtc.getTime() + 15 * 60 * 60 * 1000),
      },
    ],
  });

  return {
    companyId: company.id,
    startDate: yesterdayUtc.toISOString().slice(0, 10),
    endDate: todayUtc.toISOString().slice(0, 10),
  };
}

async function cleanupFixtures() {
  await prisma.company.deleteMany({
    where: {
      slug: `${runId}-company`,
    },
  });
}
