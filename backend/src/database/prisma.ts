import { PrismaClient } from '@prisma/client';

import { logger } from '../shared/observability/logger';

declare global {
  // eslint-disable-next-line no-var
  var __simplesPrisma__: PrismaClient | undefined;
}

export const prisma =
  globalThis.__simplesPrisma__ ??
  new PrismaClient({
    log: [
      { emit: 'event', level: 'warn' },
      { emit: 'event', level: 'error' },
    ],
  });

const prismaWithEvents = prisma as PrismaClient & {
  $on(
    eventType: 'warn' | 'error',
    callback: (event: { target?: string; message: string }) => void,
  ): void;
};

prismaWithEvents.$on('warn', (event) => {
  logger.warn('prisma.warn', {
    target: event.target,
    message: event.message,
  });
});

prismaWithEvents.$on('error', (event) => {
  logger.error('prisma.error', {
    target: event.target,
    message: event.message,
  });
});

if (process.env.NODE_ENV != 'production') {
  globalThis.__simplesPrisma__ = prisma;
}
