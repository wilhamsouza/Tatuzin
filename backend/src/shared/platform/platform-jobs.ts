import { LicenseStatus } from '@prisma/client';

import { env } from '../../config/env';
import { prisma } from '../../database/prisma';
import { logger } from '../observability/logger';

type JobRunStatus = 'idle' | 'running' | 'ok' | 'error';

type MaintenanceJobSummary = {
  expiredLicensesUpdated: number;
  deletedSessions: number;
  deletedRateLimitBuckets: number;
};

type PlatformJobsSnapshot = {
  enabled: boolean;
  intervalMs: number;
  status: JobRunStatus;
  lastRunStartedAt: string | null;
  lastRunFinishedAt: string | null;
  lastRunDurationMs: number | null;
  lastRunReason: string | null;
  lastSummary: MaintenanceJobSummary | null;
  lastError: string | null;
};

export class PlatformJobsService {
  private timer: NodeJS.Timeout | null = null;
  private running = false;
  private lastRunStartedAt: Date | null = null;
  private lastRunFinishedAt: Date | null = null;
  private lastRunDurationMs: number | null = null;
  private lastRunReason: string | null = null;
  private lastSummary: MaintenanceJobSummary | null = null;
  private lastError: string | null = null;
  private status: JobRunStatus = 'idle';

  start() {
    if (this.timer != null) {
      return;
    }

    this.timer = setInterval(() => {
      void this.runMaintenanceSweep('interval');
    }, env.PLATFORM_JOB_SWEEP_INTERVAL_MS);
    this.timer.unref();

    void this.runMaintenanceSweep('startup');

    logger.info('platform.jobs.started', {
      intervalMs: env.PLATFORM_JOB_SWEEP_INTERVAL_MS,
    });
  }

  stop() {
    if (this.timer == null) {
      return;
    }

    clearInterval(this.timer);
    this.timer = null;
    logger.info('platform.jobs.stopped');
  }

  async runMaintenanceSweep(reason: string) {
    if (this.running) {
      return this.getSnapshot();
    }

    const startedAt = new Date();
    this.running = true;
    this.status = 'running';
    this.lastRunStartedAt = startedAt;
    this.lastRunReason = reason;

    try {
      const now = new Date();
      const sessionRetentionCutoff = new Date(
        now.getTime() -
          env.SESSION_CLEANUP_RETENTION_DAYS * 24 * 60 * 60 * 1000,
      );
      const rateLimitRetentionCutoff = new Date(
        now.getTime() -
          env.RATE_LIMIT_BUCKET_RETENTION_MINUTES * 60 * 1000,
      );

      const [expiredLicenses, deletedSessions, deletedRateLimitBuckets] =
        await Promise.all([
        prisma.license.updateMany({
          where: {
            status: {
              in: [LicenseStatus.ACTIVE, LicenseStatus.TRIAL],
            },
            expiresAt: {
              not: null,
              lt: now,
            },
          },
          data: {
            status: LicenseStatus.EXPIRED,
          },
        }),
        prisma.deviceSession.deleteMany({
          where: {
            OR: [
              {
                revokedAt: {
                  not: null,
                  lt: sessionRetentionCutoff,
                },
              },
              {
                refreshTokenExpiresAt: {
                  lt: sessionRetentionCutoff,
                },
              },
            ],
          },
        }),
        prisma.rateLimitBucket.deleteMany({
          where: {
            resetAt: {
              lt: rateLimitRetentionCutoff,
            },
          },
        }),
      ]);

      const finishedAt = new Date();
      this.lastRunFinishedAt = finishedAt;
      this.lastRunDurationMs = finishedAt.getTime() - startedAt.getTime();
      this.lastSummary = {
        expiredLicensesUpdated: expiredLicenses.count,
        deletedSessions: deletedSessions.count,
        deletedRateLimitBuckets: deletedRateLimitBuckets.count,
      };
      this.lastError = null;
      this.status = 'ok';

      logger.info('platform.jobs.maintenance.completed', {
        reason,
        durationMs: this.lastRunDurationMs,
        summary: this.lastSummary,
      });

      return this.getSnapshot();
    } catch (error) {
      const finishedAt = new Date();
      this.lastRunFinishedAt = finishedAt;
      this.lastRunDurationMs = finishedAt.getTime() - startedAt.getTime();
      this.lastError =
        error instanceof Error ? error.message : 'unexpected_platform_job_error';
      this.status = 'error';

      logger.error('platform.jobs.maintenance.failed', {
        reason,
        durationMs: this.lastRunDurationMs,
        error,
      });

      return this.getSnapshot();
    } finally {
      this.running = false;
    }
  }

  getSnapshot(): PlatformJobsSnapshot {
    return {
      enabled: true,
      intervalMs: env.PLATFORM_JOB_SWEEP_INTERVAL_MS,
      status: this.status,
      lastRunStartedAt: this.lastRunStartedAt?.toISOString() ?? null,
      lastRunFinishedAt: this.lastRunFinishedAt?.toISOString() ?? null,
      lastRunDurationMs: this.lastRunDurationMs,
      lastRunReason: this.lastRunReason,
      lastSummary: this.lastSummary,
      lastError: this.lastError,
    };
  }
}

export const platformJobsService = new PlatformJobsService();
