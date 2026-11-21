import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, before, describe, it } from 'node:test';
import { PrismaClient } from '@prisma/client';
import { resolveIntegrationTestDatabaseConfig } from '../../shared/testing/integration-prisma';
import { CompanyOnboardingService } from './company-onboarding.service';
import type { AppContext } from './app-context.types';
import { AuthService } from '../auth/auth.service';
import type { AuthSessionService } from '../auth/auth-session.service';
import { registerSchema } from '../auth/auth.schemas';

const config = resolveIntegrationTestDatabaseConfig();
const integrationDescribe = config.enabled ? describe : describe.skip;

integrationDescribe('company onboarding isolated integration', () => {
  let db: PrismaClient;
  const companies: string[] = [];
  const users: string[] = [];
  before(() => {
    if (config.enabled) db = new PrismaClient({ datasources: { db: { url: config.databaseUrl } } });
  });
  after(async () => {
    if (!db) return;
    await db.company.deleteMany({ where: { id: { in: companies } } });
    await db.user.deleteMany({ where: { id: { in: users } } });
    await db.$disconnect();
  });
  async function company() {
    const row = await db.company.create({ data: { name: 'Onboarding test', legalName: 'Onboarding test', slug: randomUUID() } });
    companies.push(row.id);
    return row;
  }
  function context(companyId: string): AppContext {
    return { company: { id: companyId }, membership: { role: 'OWNER' } } as AppContext;
  }

  it('reconciles actual records, shares progress across devices and preserves completion after cancellation', async () => {
    const row = await company();
    const other = await company();
    const service = new CompanyOnboardingService(db, () => true);
    assert.deepEqual(await service.reconcile(context(row.id)), {
      enabled: true, productReady: false, cashReady: false, completedAt: null,
    });
    await db.product.create({ data: { companyId: row.id, localUuid: randomUUID(), name: 'Camiseta', niche: 'moda', salePriceCents: 1000 } });
    await db.cashSession.create({ data: { companyId: row.id, localUuid: randomUUID(), openedAt: new Date() } });
    assert.deepEqual(await service.reconcile(context(row.id)), {
      enabled: true, productReady: true, cashReady: true, completedAt: null,
    });
    const soldAt = new Date();
    const sale = await db.sale.create({ data: { companyId: row.id, localUuid: randomUUID(),
      paymentType: 'cash', paymentMethod: 'pix', totalAmountCents: 1000, totalCostCents: 0, soldAt } });
    assert.equal((await service.reconcile(context(row.id))).completedAt, soldAt.toISOString());
    await db.sale.update({ where: { id: sale.id }, data: { status: 'cancelled' } });
    assert.equal((await service.reconcile({ ...context(row.id), clientInstanceId: 'another-device' })).completedAt, soldAt.toISOString());
    assert.deepEqual(await service.reconcile(context(other.id)), {
      enabled: true, productReady: false, cashReady: false, completedAt: null,
    });
  });

  it('recognizes existing sales without requiring a new product or new cash session', async () => {
    const row = await company();
    await db.sale.create({ data: { companyId: row.id, localUuid: randomUUID(), paymentType: 'cash', paymentMethod: 'card',
      totalAmountCents: 1000, totalCostCents: 0, soldAt: new Date('2026-01-01T12:00:00Z') } });
    const result = await new CompanyOnboardingService(db, () => true).reconcile(context(row.id));
    assert.equal(result.productReady, true);
    assert.equal(result.cashReady, true);
    assert.equal(result.completedAt, '2026-01-01T12:00:00.000Z');
  });

  it('creates an owner without a slug and retries generated collisions, keeping explicit conflicts unchanged', async () => {
    const existing = await company();
    const generated = `new-${randomUUID()}`;
    let attempts = 0;
    const sessions = { createSession: async () => ({ session: { id: 'test-session' } }) } as unknown as AuthSessionService;
    const service = new AuthService(sessions, undefined, db, () => ++attempts === 1 ? existing.slug : generated);
    const input = registerSchema.parse({ companyName: 'São João Moda', userName: 'Dono',
      email: `${randomUUID()}@example.test`, password: 'OwnerPass123!', clientInstanceId: 'test-device' });
    const result = await service.register(input);
    companies.push(result.company.id);
    users.push(result.user.id);
    assert.equal(result.company.slug, generated);
    assert.equal(attempts, 2);
    const stored = await db.company.findUniqueOrThrow({ where: { id: result.company.id } });
    assert.equal(stored.experienceProfile, 'moda');
    await assert.rejects(service.register({ ...input, email: `${randomUUID()}@example.test`, companySlug: existing.slug }),
      { code: 'COMPANY_SLUG_ALREADY_IN_USE' });
  });
});
