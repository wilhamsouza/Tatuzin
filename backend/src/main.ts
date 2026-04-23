import { env } from './config/env';
import { prisma } from './database/prisma';
import { createApp } from './app';
import { logger } from './shared/observability/logger';
import { platformJobsService } from './shared/platform/platform-jobs';

async function bootstrap() {
  await prisma.$connect();

  const app = createApp();
  const listenHost = env.HOST;

  const server = app.listen(env.PORT, listenHost, () => {
    platformJobsService.start();
    logger.info('backend.started', {
      host: listenHost,
      port: env.PORT,
      environment: env.APP_ENV,
      trustProxy: env.TRUST_PROXY ?? 'false',
      healthPath: '/api/health',
      readinessPath: '/api/readiness',
    });
  });

  server.on('error', (error) => {
    void (async () => {
      logger.error('backend.server.error', {
        error,
        host: listenHost,
        port: env.PORT,
      });
      platformJobsService.stop();
      await prisma.$disconnect().catch(() => undefined);
      process.exit(1);
    })();
  });

  const shutdown = async (signal: string) => {
    logger.info('backend.shutdown.requested', { signal });
    platformJobsService.stop();
    await new Promise<void>((resolve, reject) => {
      server.close((error) => {
        if (error != null) {
          reject(error);
          return;
        }
        resolve();
      });
    });
    await prisma.$disconnect();
    logger.info('backend.shutdown.completed', { signal });
    process.exit(0);
  };

  process.on('SIGINT', () => {
    void shutdown('SIGINT');
  });
  process.on('SIGTERM', () => {
    void shutdown('SIGTERM');
  });
}

bootstrap().catch(async (error) => {
  logger.error('backend.startup.failed', { error });
  platformJobsService.stop();
  await prisma.$disconnect();
  process.exit(1);
});
