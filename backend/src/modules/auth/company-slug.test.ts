import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { generateCompanySlug } from './company-slug';
import { registerSchema } from './auth.schemas';

describe('automatic registration slug', () => {
  it('normalizes accents, bounds length and handles symbol-only names', () => {
    assert.match(generateCompanySlug('São João & Moda'), /^sao-joao-moda-[a-f0-9]{12}$/);
    assert.match(generateCompanySlug('✨✨✨'), /^loja-[a-f0-9]{12}$/);
    assert.ok(generateCompanySlug('a'.repeat(120)).length <= 60);
    assert.equal(new Set(Array.from({ length: 100 }, () => generateCompanySlug('Loja'))).size, 100);
  });
  it('accepts omitted slugs while preserving legacy validation', () => {
    const input = { companyName: 'Loja', userName: 'Dono', email: 'owner@example.test',
      password: 'OwnerPass123!', clientInstanceId: 'device' };
    assert.equal(registerSchema.parse(input).companySlug, undefined);
    assert.equal(registerSchema.parse({ ...input, companySlug: 'LOJA-LEGADA' }).companySlug, 'loja-legada');
    assert.equal(registerSchema.safeParse({ ...input, companySlug: '' }).success, false);
    assert.equal(registerSchema.safeParse({ ...input, companySlug: 'slug inválido' }).success, false);
  });
});
