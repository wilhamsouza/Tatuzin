import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { after, before, describe, it } from 'node:test';
import { PrismaClient } from '@prisma/client';
import { resolveIntegrationTestDatabaseConfig } from '../../shared/testing/integration-prisma';
import type { AppContext } from '../app/app-context.types';
import { ProductJourneyService, purgeExpiredJourneyEvents } from './product-journey.service';
import { journeyBatchSchema, journeyReportQuerySchema } from './product-journey.schemas';

const config = resolveIntegrationTestDatabaseConfig();
const integrationDescribe = config.enabled ? describe : describe.skip;

integrationDescribe('product journey isolated PostgreSQL integration', () => {
  let db: PrismaClient;
  let companyId: string;
  let service: ProductJourneyService;
  let context: AppContext;

  before(async () => {
    if (!config.enabled) return;
    db = new PrismaClient({ datasources: { db: { url: config.databaseUrl } } });
    const company = await db.company.create({ data: {
      name: 'Journey integration', legalName: 'Journey integration', slug: `journey-${randomUUID()}`,
    } });
    companyId = company.id;
    assert.equal(company.experienceProfile, 'moda');
    service = new ProductJourneyService(db);
    context = { company: { id: companyId }, device: { id: 'test-device' } } as AppContext;
  });

  after(async () => {
    if (!db) return;
    if (companyId) await db.company.delete({ where: { id: companyId } });
    await db.$disconnect();
  });

  it('persists retries once and calculates filtered counts and median on real SQL', async () => {
    const events = [1000, 3000].map((durationMs, index) => ({
      eventId: `complete-${index}`, attemptId: `attempt-${index}`,
      name: 'checkout_completed', durationMs,
      occurredAt: new Date().toISOString(), appVersion: 'test-1',
      plan: 'FREE', experienceProfile: 'moda',
    }));
    const batch = journeyBatchSchema.parse({ companyId, events });
    await service.ingest(context, batch);
    await service.ingest(context, batch);
    assert.equal(await db.productJourneyEvent.count({ where: { companyId } }), 2);
    const report = await service.report(journeyReportQuerySchema.parse({ companyId, appVersion: 'test-1' }));
    assert.deepEqual(report.steps, [{
      name: 'checkout_completed', events: 2, companies: 1, attempts: 2, medianDurationMs: 2000,
    }]);
    const empty = await service.report(journeyReportQuerySchema.parse({ companyId, plan: 'PRO' }));
    assert.deepEqual(empty.steps, []);
  });

  it('allows the same event id on another device and keeps the company boundary', async () => {
    const batch = journeyBatchSchema.parse({ companyId, events: [{
      eventId: 'complete-0', attemptId: 'attempt-0', name: 'checkout_completed', durationMs: 1000,
      occurredAt: new Date().toISOString(), appVersion: 'test-1', plan: 'FREE', experienceProfile: 'moda',
    }] });
    await service.ingest({ ...context, device: { ...context.device, id: 'other-device' } }, batch);
    assert.equal(await db.productJourneyEvent.count({ where: { companyId } }), 3);
    await assert.rejects(service.ingest(context, { ...batch, companyId: 'other-company' }),
      { code: 'JOURNEY_COMPANY_MISMATCH' });
  });

  it('purges after ninety days by server receipt time, independent of client clock', async () => {
    const now = new Date();
    await db.productJourneyEvent.createMany({ data: [
      { eventId: 'expired', receivedAt: new Date(now.getTime() - 91 * 86400000) },
      { eventId: 'keep', receivedAt: now },
    ].map((event) => ({
      ...event, companyId, deviceId: 'test-device', name: 'plans_viewed',
      occurredAt: new Date('2020-01-01T00:00:00Z'), appVersion: 'test-1',
      plan: 'FREE', experienceProfile: 'moda',
    })) });
    const result = await purgeExpiredJourneyEvents(db, now);
    assert.equal(result.count, 1);
    assert.equal(await db.productJourneyEvent.count({ where: { companyId, eventId: 'keep' } }), 1);
    assert.equal(await db.productJourneyEvent.count({ where: { companyId, eventId: 'expired' } }), 0);
  });

  it('backfills existing fashion, food, mixed and empty catalogues without editing products', async () => {
    const fixtures: Array<{ id: string; expected: string }> = [];
    try {
      for (const niches of [['moda'], ['alimentacao'], ['moda', 'alimentacao'], []]) {
        const company = await db.company.create({ data: {
          name: 'Profile migration test', legalName: 'Profile migration test', slug: randomUUID(),
          products: { create: niches.map((niche) => ({
            localUuid: randomUUID(), name: 'Existing product', niche, salePriceCents: 100,
          })) },
        } });
        fixtures.push({ id: company.id, expected: niches.length === 1 ? niches[0] : 'misto' });
      }
      const sql = readFileSync(resolve(__dirname,
        '../../../prisma/migrations/20261112120000_company_experience_profile/migration.sql'), 'utf8');
      const update = sql.slice(sql.indexOf('UPDATE "Company"'), sql.indexOf('ALTER TABLE "Company" ADD CONSTRAINT'));
      // Trusted migration SQL, executed only behind the isolated integration DB guard.
      await db.$executeRawUnsafe(update);
      for (const fixture of fixtures) {
        const company = await db.company.findUniqueOrThrow({ where: { id: fixture.id } });
        assert.equal(company.experienceProfile, fixture.expected);
      }
      assert.equal(await db.product.count({ where: { companyId: { in: fixtures.map((fixture) => fixture.id) } } }), 4);
    } finally {
      await db.company.deleteMany({ where: { id: { in: fixtures.map((fixture) => fixture.id) } } });
    }
  });
});
