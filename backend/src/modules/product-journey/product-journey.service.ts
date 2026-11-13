import { Prisma, type PrismaClient } from '@prisma/client';
import { prisma } from '../../database/prisma';
import { AppError } from '../../shared/http/app-error';
import type { AppContext } from '../app/app-context.types';
import type { JourneyBatch, JourneyReportQuery } from './product-journey.schemas';

export function purgeExpiredJourneyEvents(
  db: Pick<PrismaClient, 'productJourneyEvent'> = prisma,
  now = new Date(),
) {
  return db.productJourneyEvent.deleteMany({
    where: { receivedAt: { lt: new Date(now.getTime() - 90 * 86400000) } },
  });
}

export class ProductJourneyService {
  constructor(private readonly db = prisma) {}

  async ingest(context: AppContext, input: JourneyBatch) {
    if (input.companyId !== context.company.id) {
      throw new AppError('Empresa divergente.', 403, 'JOURNEY_COMPANY_MISMATCH');
    }
    await this.db.productJourneyEvent.createMany({
      data: input.events.map((event) => ({
        ...event,
        occurredAt: new Date(event.occurredAt),
        companyId: context.company.id,
        deviceId: context.device.id,
      })),
      skipDuplicates: true,
    });
    // Duplicate events are acknowledged too, making retries after a lost response safe.
    return { acknowledgedEventIds: input.events.map((event) => event.eventId) };
  }

  async report(query: JourneyReportQuery) {
    const since = new Date(Date.now() - query.days * 86400000);
    const filters = [Prisma.sql`"receivedAt" >= ${since}`];
    if (query.companyId) filters.push(Prisma.sql`"companyId" = ${query.companyId}`);
    if (query.appVersion) filters.push(Prisma.sql`"appVersion" = ${query.appVersion}`);
    if (query.plan) filters.push(Prisma.sql`"plan" = ${query.plan}`);
    if (query.experienceProfile) filters.push(Prisma.sql`"experienceProfile" = ${query.experienceProfile}`);
    const steps = await this.db.$queryRaw<Array<{
      name: string; events: number; companies: number; attempts: number;
      medianDurationMs: number | null;
    }>>(Prisma.sql`
      SELECT name, COUNT(*)::int AS events,
        COUNT(DISTINCT "companyId")::int AS companies,
        COUNT(DISTINCT ("companyId", "deviceId", "attemptId"))
          FILTER (WHERE "attemptId" IS NOT NULL)::int AS attempts,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY "durationMs")
          FILTER (WHERE name = 'checkout_completed') AS "medianDurationMs"
      FROM "ProductJourneyEvent"
      WHERE ${Prisma.join(filters, ' AND ')}
      GROUP BY name ORDER BY name
    `);
    return {
      since: since.toISOString(),
      timeBasis: 'receivedAt',
      source: 'client_reported',
      note: 'Etapas alcancadas no periodo; nao representam uma coorte sequencial. Saidas do checkout nao provam abandono definitivo. Assinatura iniciada nao significa plano ativado.',
      steps,
    };
  }
}
