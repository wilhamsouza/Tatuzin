import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, before, describe, it } from 'node:test';
import { prisma } from '../../database/prisma';
import { ProductsService } from './products.service';
import { productUpsertSchema, productUpdateSchema } from './products.schemas';

const service = new ProductsService();
const companies: string[] = [];
let companyId: string;
let otherCompanyId: string;
const payload = (extra: Record<string, unknown> = {}) => productUpsertSchema.parse({
  localUuid: randomUUID(), name: 'Camiseta', salePriceCents: 5000,
  costPriceCents: 2200, niche: 'moda', metadataOnly: true, ...extra,
});
const matrix = () => payload({ catalogType: 'variant', variants: [
  { sku: `CAM-P-${randomUUID()}`, colorLabel: 'Preta', sizeLabel: 'P', stockMil: 9000 },
  { sku: `CAM-M-${randomUUID()}`, colorLabel: 'Preta', sizeLabel: 'M', stockMil: 9000 },
] });

describe('catalog identity and inventory isolation', () => {
  before(async () => {
    for (let i = 0; i < 2; i++) {
      const c = await prisma.company.create({ data: { name: 'Catalog integration fixture', legalName: 'Catalog integration fixture', slug: `catalog-test-${randomUUID()}` } });
      companies.push(c.id);
    }
    [companyId, otherCompanyId] = companies as [string, string];
  });
  after(async () => {
    for (const id of companies) await prisma.company.delete({ where: { id } });
    await prisma.$disconnect();
  });
  it('creates new metadata products at zero stock and retries without replacing SKUs', async () => {
    const input = matrix();
    const p = await service.create(companyId, input);
    assert.equal(p.stockMil, 0);
    assert.ok(p.variants.every(v => v.stockMil === 0));
    const first = p.variants[0]!;
    await prisma.productVariant.update({ where: { id: first.id }, data: { stockMil: 3000 } });
    const retry = await service.create(companyId, input);
    assert.equal(retry.id, p.id);
    assert.deepEqual(retry.variants.map(v => v.id), p.variants.map(v => v.id));
    assert.equal(retry.variants[0]!.stockMil, 3000);
  });
  it('merges partial metadata without resetting costs, category, modifiers or stock', async () => {
    const p = await service.create(companyId, payload({ metadataOnly: false, stockMil: 7000, description: 'Preservar descrição' }));
    const saved = await service.update(companyId, p.id, productUpdateSchema.parse({ metadataOnly: true, expectedCatalogRevision: p.catalogRevision, name: 'Camiseta nova', salePriceCents: 6000 }));
    assert.equal(saved.stockMil, 7000);
    assert.equal(saved.description, 'Preservar descrição');
    assert.equal((saved as { costPriceCents?: number }).costPriceCents, 2200);
    assert.equal(saved.catalogRevision, p.catalogRevision + 1);
    await assert.rejects(service.update(companyId, p.id, { metadataOnly: true, expectedCatalogRevision: p.catalogRevision, name: 'Versão antiga' }), (e: any) => e.code === 'PRODUCT_CATALOG_REVISION_CONFLICT');
  });
  it('preserves variant identities on rename and inactivates omitted variants', async () => {
    const p = await service.create(companyId, matrix());
    const first = p.variants[0]!;
    const second = p.variants[1]!;
    const updated = await service.update(companyId, p.id, { metadataOnly: true, variants: [{ ...first, sku: `NEW-${randomUUID()}` }] });
    assert.ok(updated.variants.some(v => v.id === first.id && v.isActive));
    assert.ok(updated.variants.some(v => v.id === second.id && !v.isActive));
    assert.equal(updated.variants.length, 2);
  });
  it('does not overwrite a stock change that occurred after a legacy product read', async () => {
    const p = await service.create(companyId, payload({ metadataOnly: false, stockMil: 7000 }));
    await prisma.product.update({ where: { id: p.id }, data: { stockMil: 6000 } });
    await assert.rejects(service.update(companyId, p.id, { name: 'Old form', stockMil: p.stockMil }), (e: any) => e.code === 'PRODUCT_STOCK_CONFLICT');
    const current = await service.getById(companyId, p.id);
    assert.equal(current.stockMil, 6000);
    const safe = await service.update(companyId, p.id, { metadataOnly: true, name: 'Safe form', expectedCatalogRevision: p.catalogRevision });
    assert.equal(safe.stockMil, 6000);
  });
  it('rejects cross-product and cross-company variant IDs without changing data', async () => {
    const a = await service.create(companyId, matrix());
    const b = await service.create(otherCompanyId, matrix());
    await assert.rejects(service.update(companyId, a.id, { metadataOnly: true, variants: [b.variants[0]!] }), (e: any) => e.code === 'PRODUCT_VARIANT_ID_INVALID');
    await assert.rejects(service.update(otherCompanyId, a.id, { metadataOnly: true, name: 'Cross tenant' }), (e: any) => e.code === 'PRODUCT_NOT_FOUND');
    assert.equal((await service.getById(companyId, a.id)).name, a.name);
  });
  it('retains legacy variant IDs when an old client supplies the unchanged SKU', async () => {
    const p = await service.create(companyId, matrix());
    const variants = p.variants.map(({ id: _id, ...variant }) => variant);
    const updated = await service.update(companyId, p.id, { metadataOnly: false, stockMil: 0, variants });
    assert.deepEqual(updated.variants.map(v => v.id), p.variants.map(v => v.id));
  });
  it('allows only one concurrent edit at the expected catalog revision', async () => {
    const p = await service.create(companyId, payload());
    const results = await Promise.allSettled(['A', 'B'].map(name => service.update(companyId, p.id, {
      metadataOnly: true, name, expectedCatalogRevision: p.catalogRevision,
    })));
    assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
    const rejected = results.find(r => r.status === 'rejected') as PromiseRejectedResult;
    assert.equal(rejected.reason.code, 'PRODUCT_CATALOG_REVISION_CONFLICT');
  });
  it('does not erase operational negative stock during a metadata edit', async () => {
    const p = await service.create(companyId, payload());
    await prisma.product.update({ where: { id: p.id }, data: { stockMil: -1000 } });
    const changed = await service.update(companyId, p.id, { metadataOnly: true, name: 'Saldo em conferência' });
    assert.equal(changed.stockMil, -1000);
  });
  it('filters and paginates real catalog data and hides sensitive costs for read-only callers', async () => {
    const input = payload({ name: `Search-${randomUUID()}` });
    const p = await service.create(companyId, input);
    const result = await service.listForCompany(companyId, { search: input.name, includeDeleted: false, page: 1, pageSize: 1, isActive: true });
    assert.equal(result.total, 1);
    assert.equal(result.items[0]!.id, p.id);
    assert.equal('costPriceCents' in result.items[0]!, false);
    await service.softDelete(companyId, p.id);
    const inactive = await service.listForCompany(companyId, { search: input.name, includeDeleted: true, page: 1, pageSize: 20, isActive: false });
    assert.equal(inactive.total, 1);
  });
});
