import type { NextFunction, Request, RequestHandler, Response } from 'express';

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

type RateLimitEntry = {
  count: number;
  resetAt: number;
};

const rateLimitStore = new Map<string, RateLimitEntry>();

function getClientIp(request: Request) {
  const forwarded = request.headers['x-forwarded-for'];
  if (typeof forwarded === 'string' && forwarded.trim().length > 0) {
    const first = forwarded.split(',')[0]?.trim();
    if (first != null && first.length > 0) {
      return first;
    }
  }

  return request.ip ?? 'unknown';
}

function cleanupExpiredEntries(now: number) {
  for (const [key, entry] of rateLimitStore.entries()) {
    if (entry.resetAt <= now) {
      rateLimitStore.delete(key);
    }
  }
}

function defaultKeyGenerator(request: Request) {
  return getClientIp(request);
}

export function createRateLimit(options: RateLimitOptions): RequestHandler {
  return (request: Request, response: Response, next: NextFunction) => {
    if (options.skip?.(request) === true) {
      next();
      return;
    }

    const now = Date.now();
    cleanupExpiredEntries(now);

    const key = `${options.name}:${(options.keyGenerator ?? defaultKeyGenerator)(
      request,
    )}`;
    const existing = rateLimitStore.get(key);

    if (existing == null || existing.resetAt <= now) {
      rateLimitStore.set(key, {
        count: 1,
        resetAt: now + options.windowMs,
      });
      response.setHeader('X-RateLimit-Limit', String(options.max));
      response.setHeader('X-RateLimit-Remaining', String(options.max - 1));
      response.setHeader(
        'X-RateLimit-Reset',
        String(Math.ceil((now + options.windowMs) / 1000)),
      );
      next();
      return;
    }

    existing.count += 1;
    rateLimitStore.set(key, existing);

    const remaining = Math.max(options.max - existing.count, 0);
    response.setHeader('X-RateLimit-Limit', String(options.max));
    response.setHeader('X-RateLimit-Remaining', String(remaining));
    response.setHeader(
      'X-RateLimit-Reset',
      String(Math.ceil(existing.resetAt / 1000)),
    );

    if (existing.count <= options.max) {
      next();
      return;
    }

    const retryAfterSeconds = Math.max(
      1,
      Math.ceil((existing.resetAt - now) / 1000),
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
  };
}

export function resetRateLimitStore() {
  rateLimitStore.clear();
}
