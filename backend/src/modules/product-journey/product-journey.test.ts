import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import type { PrismaClient } from '@prisma/client';
import type { AppContext } from '../app/app-context.types';
import { ProductJourneyService } from './product-journey.service';
import { journeyBatchSchema, journeyReportQuerySchema } from './product-journey.schemas';

const event = {
  eventId: 'event-1', name: 'checkout_completed', attemptId: 'attempt-1', durationMs: 1500,
  occurredAt: '2026-11-12T12:00:00.000Z', appVersion: '1.0.0', plan: 'FREE', experienceProfile: 'moda',
};
const context = {
  company: { id: 'company-a' }, device: { id: 'server-device-a' },
} as AppContext;

describe('product journey contracts', () => {
  it('accepts bounded batches and rejects arbitrary content and personal data', () => {
    assert.equal(journeyBatchSchema.safeParse({ companyId: 'company-a', events: [event] }).success, true);
    for (const invalid of [
      { ...event, email: 'person@example.com' }, { ...event, notes: 'sensitive' },
      { ...event, durationMs: -1 }, { ...event, attemptId: undefined },
      { ...event, durationMs: undefined }, { ...event, name: 'arbitrary' },
    ]) {
      assert.equal(journeyBatchSchema.safeParse({ companyId: 'company-a', events: [invalid] }).success, false);
    }
    assert.equal(journeyBatchSchema.safeParse({ companyId: 'company-a', events: Array(51).fill(event) }).success, false);
    assert.equal(journeyReportQuerySchema.safeParse({ days: 91 }).success, false);
  });

  it('rejects a stale tenant snapshot before persistence', async () => {
    const service = new ProductJourneyService({} as PrismaClient);
    await assert.rejects(service.ingest(context,
      journeyBatchSchema.parse({ companyId: 'company-b', events: [event] })),
      { code: 'JOURNEY_COMPANY_MISMATCH', statusCode: 403 });
  });

  it('deduplicates retries and binds storage to authenticated company and device', async () => {
    const stored = new Map<string, Record<string, unknown>>();
    const service = new ProductJourneyService({ productJourneyEvent: {
      createMany: async ({ data, skipDuplicates }: { data: Array<Record<string, unknown>>; skipDuplicates: boolean }) => {
        assert.equal(skipDuplicates, true);
        for (const row of data) stored.set(`${row.companyId}:${row.deviceId}:${row.eventId}`, row);
      },
    } } as unknown as PrismaClient);
    const input = journeyBatchSchema.parse({ companyId: 'company-a', events: [event] });
    assert.deepEqual(await service.ingest(context, input), { acknowledgedEventIds: ['event-1'] });
    assert.deepEqual(await service.ingest(context, input), { acknowledgedEventIds: ['event-1'] });
    assert.equal(stored.size, 1);
    assert.equal([...stored.values()][0].deviceId, 'server-device-a');
    assert.equal([...stored.values()][0].companyId, 'company-a');
    assert.ok([...stored.values()][0].occurredAt instanceof Date);
    await service.ingest({ ...context, device: { ...context.device, id: 'server-device-b' } }, input);
    assert.equal(stored.size, 2);
  });

  it('propagates persistence errors without acknowledging events', async () => {
    const service = new ProductJourneyService({ productJourneyEvent: {
      createMany: async () => { throw new Error('storage unavailable'); },
    } } as unknown as PrismaClient);
    await assert.rejects(service.ingest(context,
      journeyBatchSchema.parse({ companyId: 'company-a', events: [event] })), /storage unavailable/);
  });

  it('uses parameterized report filters and exposes honest metric semantics', async () => {
    const injected = "1.0.0' OR true --";
    let queryValues: unknown[] = [];
    const service = new ProductJourneyService({
      $queryRaw: async (query: { values: unknown[]; strings: string[] }) => {
        queryValues = query.values;
        assert.equal(query.strings.join('').includes(injected), false);
        return [];
      },
    } as unknown as PrismaClient);
    const report = await service.report(journeyReportQuerySchema.parse({ appVersion: injected }));
    assert.ok(queryValues.includes(injected));
    assert.equal(report.source, 'client_reported');
    assert.equal(report.timeBasis, 'receivedAt');
  });
});
