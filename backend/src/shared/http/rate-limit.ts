import { createHash } from 'crypto';

import { Prisma } from '@prisma/client';
import type { NextFunction, Request, RequestHandler, Response } from 'express';

import { prisma } from '../../database/prisma';
import { AppError } from './app-error';

type RateLimitOptions = {
  name: string;
  windowMs: number;
  max: number;
  message: string;
  code?: string;
  keyGenerator?: (request: Request) => string;
  skip?: (request: Request) => boolean;
};

function getClientIp(request: Request) {
  return request.ip ?? 'unknown';
}

function defaultKeyGenerator(request: Request) {
  return getClientIp(request);
}

function hashBucketKey(scope: string, key: string) {
  return createHash('sha256').update(`${scope}:${key}`).digest('hex');
}

async function consumeRateLimitBucket(input: {
  bucketHash: string;
  scope: string;
  windowMs: number;
}) {
  const resetAt = new Date(Date.now() + input.windowMs);
  const [bucket] = await prisma.$queryRaw<
    Array<{
      requestCount: number;
      resetAt: Date;
    }>
  >(Prisma.sql`
    INSERT INTO "RateLimitBucket" (
      "bucketHash",
      "scope",
      "requestCount",
      "resetAt",
      "createdAt",
      "updatedAt"
    )
    VALUES (
      ${input.bucketHash},
      ${input.scope},
      1,
      ${resetAt},
      NOW(),
      NOW()
    )
    ON CONFLICT ("bucketHash")
    DO UPDATE SET
      "scope" = EXCLUDED."scope",
      "requestCount" = CASE
        WHEN "RateLimitBucket"."resetAt" <= NOW() THEN 1
        ELSE "RateLimitBucket"."requestCount" + 1
      END,
      "resetAt" = CASE
        WHEN "RateLimitBucket"."resetAt" <= NOW() THEN ${resetAt}
        ELSE "RateLimitBucket"."resetAt"
      END,
      "updatedAt" = NOW()
    RETURNING "requestCount", "resetAt"
  `);

  if (bucket == null) {
    throw new AppError(
      'Nao foi possivel aplicar o controle de taxa para esta requisicao.',
      500,
      'RATE_LIMIT_STORE_UNAVAILABLE',
    );
  }

  return bucket;
}

export function createRateLimit(options: RateLimitOptions): RequestHandler {
  return (request: Request, response: Response, next: NextFunction) => {
    if (options.skip?.(request) === true) {
      next();
      return;
    }

    void (async () => {
      const bucketKey = (options.keyGenerator ?? defaultKeyGenerator)(request);
      const bucket = await consumeRateLimitBucket({
        bucketHash: hashBucketKey(options.name, bucketKey),
        scope: options.name,
        windowMs: options.windowMs,
      });

      const remaining = Math.max(options.max - bucket.requestCount, 0);
      response.setHeader('X-RateLimit-Limit', String(options.max));
      response.setHeader('X-RateLimit-Remaining', String(remaining));
      response.setHeader(
        'X-RateLimit-Reset',
        String(Math.ceil(bucket.resetAt.getTime() / 1000)),
      );

      if (bucket.requestCount <= options.max) {
        next();
        return;
      }

      const retryAfterSeconds = Math.max(
        1,
        Math.ceil((bucket.resetAt.getTime() - Date.now()) / 1000),
      );
      response.setHeader('Retry-After', String(retryAfterSeconds));

      next(
        new AppError(
          options.message,
          429,
          options.code ?? 'RATE_LIMIT_EXCEEDED',
          {
            limitName: options.name,
            retryAfterSeconds,
          },
          {
            'Retry-After': String(retryAfterSeconds),
          },
        ),
      );
    })().catch(next);
  };
}

export async function resetRateLimitStore() {
  await prisma.rateLimitBucket.deleteMany();
}
