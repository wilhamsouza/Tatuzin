import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { productUpsertSchema } from './products.schemas';

const basePayload = {
  localUuid: 'product-local-1',
  name: 'Produto base',
  salePriceCents: 9900,
};

describe('productUpsertSchema', () => {
  it('accepts matrix variants without manual modelName or variantLabel', () => {
    const parsed = productUpsertSchema.safeParse({
      ...basePayload,
      name: 'Camiseta Basic',
      niche: 'moda',
      catalogType: 'variant',
      variants: [
        {
          sku: 'CAM-BASIC-PRE-P',
          colorLabel: 'Preta',
          sizeLabel: 'P',
          stockMil: 2000,
          isActive: true,
        },
      ],
    });

    assert.equal(parsed.success, true);
    if (!parsed.success) {
      return;
    }

    assert.equal(parsed.data.name, 'Camiseta Basic');
    assert.equal(parsed.data.modelName, null);
    assert.equal(parsed.data.variantLabel, null);
  });

  it('still rejects parent product without name', () => {
    const parsed = productUpsertSchema.safeParse({
      ...basePayload,
      name: '   ',
      niche: 'moda',
      catalogType: 'variant',
      variants: [
        {
          sku: 'CAM-BASIC-PRE-P',
          colorLabel: 'Preta',
          sizeLabel: 'P',
        },
      ],
    });

    assert.equal(parsed.success, false);
    if (parsed.success) {
      return;
    }

    assert.ok(
      parsed.error.issues.some((issue) => issue.path.join('.') == 'name'),
    );
  });

  it('keeps requiring manual fields for variant products without matrix', () => {
    const parsed = productUpsertSchema.safeParse({
      ...basePayload,
      catalogType: 'variant',
      variants: [],
    });

    assert.equal(parsed.success, false);
    if (parsed.success) {
      return;
    }

    assert.ok(
      parsed.error.issues.some((issue) => issue.path.join('.') == 'modelName'),
    );
    assert.ok(
      parsed.error.issues.some(
        (issue) => issue.path.join('.') == 'variantLabel',
      ),
    );
  });

  it('rejects inconsistent matrix variants without sku, color, or size', () => {
    const parsed = productUpsertSchema.safeParse({
      ...basePayload,
      niche: 'moda',
      catalogType: 'variant',
      variants: [
        {
          sku: '',
          colorLabel: 'Preta',
          sizeLabel: 'P',
        },
      ],
    });

    assert.equal(parsed.success, false);
    if (parsed.success) {
      return;
    }

    assert.ok(
      parsed.error.issues.some((issue) => issue.path.join('.') == 'variants.0.sku'),
    );
  });
});
