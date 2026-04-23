import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';

import { prisma } from '../../database/prisma';
import { HybridGovernanceService } from './hybrid-governance.service';

const runId = `hybrid-governance-${Date.now()}`;

describe('hybrid governance service', () => {
  const service = new HybridGovernanceService();

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

  it('builds hybrid governance overview without blocking local-first operation', async () => {
    const fixture = await createFixture();

    const overview = await service.getOverview({
      companyId: fixture.companyId,
    });

    assert.equal(overview.company.name, 'Tatuzin Hybrid Company');
    assert.equal(overview.catalog.productsWithoutCategory, 1);
    assert.equal(overview.catalog.productsWithBlankVariantSku, 1);
    assert.equal(overview.pricing.productsBelowMarginPolicy, 1);
    assert.equal(overview.stock.variantAggregationMismatchCount, 1);
    assert.equal(overview.customers.duplicatePhoneConflictCount, 2);
    assert.equal(overview.capabilities.remoteImageMirrorAvailable, false);
    assert.equal(overview.truthRules[0]?.domain, 'catalog');
    assert.equal(
      overview.alerts.some((alert) => alert.code == 'catalog_missing_category'),
      true,
    );
    assert.equal(
      overview.alerts.some((alert) => alert.code == 'platform_offline_sale_preserved'),
      true,
    );

    const profileResponse = await service.updateProfile({
      companyId: fixture.companyId,
      pricePolicyMode: 'governed',
      minMarginBasisPoints: 1800,
      requireRemoteImageForGovernedCatalog: true,
      promotionMode: 'scheduled_review',
      requireCustomerConflictReview: true,
    });

    assert.equal(profileResponse.profile.pricePolicyMode, 'governed');
    assert.equal(profileResponse.profile.minMarginBasisPoints, 1800);
    assert.equal(
      profileResponse.profile.requireRemoteImageForGovernedCatalog,
      true,
    );
    assert.equal(profileResponse.profile.promotionMode, 'scheduled_review');
    assert.equal(profileResponse.profile.requireCustomerConflictReview, true);
  });
});

async function createFixture() {
  const company = await prisma.company.create({
    data: {
      name: 'Tatuzin Hybrid Company',
      legalName: 'Tatuzin Hybrid Company LTDA',
      slug: `${runId}-company`,
      documentNumber: null,
    },
  });

  const category = await prisma.category.create({
    data: {
      companyId: company.id,
      localUuid: `${runId}-category`,
      name: 'Bebidas',
    },
  });

  await prisma.product.create({
    data: {
      companyId: company.id,
      localUuid: `${runId}-product-without-category`,
      categoryId: null,
      name: 'Produto sem categoria',
      salePriceCents: 900,
      costPriceCents: 1200,
      manualCostCents: 1200,
      stockMil: 3000,
      isActive: true,
      unitMeasure: 'un',
    },
  });

  const variantProduct = await prisma.product.create({
    data: {
      companyId: company.id,
      localUuid: `${runId}-variant-product`,
      categoryId: category.id,
      name: 'Produto com variantes',
      catalogType: 'variant',
      salePriceCents: 2400,
      costPriceCents: 900,
      manualCostCents: 900,
      stockMil: 1000,
      isActive: true,
      unitMeasure: 'un',
    },
  });

  await prisma.productVariant.createMany({
    data: [
      {
        productId: variantProduct.id,
        sku: '',
        colorLabel: 'Preto',
        sizeLabel: 'M',
        priceAdditionalCents: 0,
        stockMil: 1500,
        sortOrder: 0,
        isActive: true,
      },
      {
        productId: variantProduct.id,
        sku: `${runId}-SKU-02`,
        colorLabel: 'Preto',
        sizeLabel: 'G',
        priceAdditionalCents: 0,
        stockMil: 1000,
        sortOrder: 1,
        isActive: true,
      },
    ],
  });

  const customerOne = await prisma.customer.create({
    data: {
      companyId: company.id,
      localUuid: `${runId}-customer-one`,
      name: 'Alice Hybrid',
      phone: '(11) 99999-1111',
      notes: 'Observacao local operacional',
    },
  });

  await prisma.customer.create({
    data: {
      companyId: company.id,
      localUuid: `${runId}-customer-two`,
      name: 'Alice Hybrid',
      phone: '11999991111',
      notes: null,
    },
  });

  await prisma.customer.create({
    data: {
      companyId: company.id,
      localUuid: `${runId}-customer-three`,
      name: 'Cliente sem telefone',
      phone: null,
      notes: null,
    },
  });

  await prisma.customerNote.create({
    data: {
      companyId: company.id,
      customerId: customerOne.id,
      body: 'Cliente no CRM para governanca hibrida.',
    },
  });

  return {
    companyId: company.id,
  };
}

async function cleanupFixtures() {
  await prisma.company.deleteMany({
    where: {
      slug: `${runId}-company`,
    },
  });
}
