import packageJson from '../../../package.json';
import { env } from '../../config/env';
import { prisma } from '../../database/prisma';
import { platformJobsService } from './platform-jobs';

export async function buildReadinessSnapshot() {
  const startedAt = Date.now();

  try {
    await prisma.$queryRaw`SELECT 1`;

    return {
      ok: true,
      ready: true,
      service: packageJson.name,
      version: packageJson.version,
      environment: env.APP_ENV,
      timestamp: new Date().toISOString(),
      checks: {
        database: 'ok',
        jobs: platformJobsService.getSnapshot(),
      },
      durationMs: Date.now() - startedAt,
    };
  } catch (error) {
    return {
      ok: false,
      ready: false,
      service: packageJson.name,
      version: packageJson.version,
      environment: env.APP_ENV,
      timestamp: new Date().toISOString(),
      checks: {
        database: 'error',
        jobs: platformJobsService.getSnapshot(),
      },
      durationMs: Date.now() - startedAt,
      error: error instanceof Error ? error.message : 'database_unavailable',
    };
  }
}

export function buildLivenessSnapshot() {
  return {
    ok: true,
    live: true,
    service: packageJson.name,
    version: packageJson.version,
    environment: env.APP_ENV,
    uptimeSeconds: Math.round(process.uptime()),
    timestamp: new Date().toISOString(),
    jobs: platformJobsService.getSnapshot(),
  };
}
