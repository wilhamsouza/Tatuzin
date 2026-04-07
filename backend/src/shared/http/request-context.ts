import { randomUUID } from 'crypto';

import type { NextFunction, Request, Response } from 'express';

import { logger } from '../observability/logger';

function normalizeRequestId(rawValue: string | undefined) {
  if (rawValue == null) {
    return randomUUID();
  }

  const normalized = rawValue.trim();
  return normalized.length === 0 ? randomUUID() : normalized.slice(0, 120);
}

function readClientIp(request: Request) {
  const forwarded = request.headers['x-forwarded-for'];
  if (typeof forwarded === 'string' && forwarded.trim().length > 0) {
    const first = forwarded.split(',')[0]?.trim();
    if (first != null && first.length > 0) {
      return first;
    }
  }

  return request.ip;
}

export function requestContextMiddleware(
  request: Request,
  response: Response,
  next: NextFunction,
) {
  const startedAt = Date.now();
  const requestId = normalizeRequestId(
    Array.isArray(request.headers['x-request-id'])
      ? request.headers['x-request-id'][0]
      : request.headers['x-request-id'],
  );

  request.requestId = requestId;
  response.locals.requestStartedAt = startedAt;
  response.setHeader('X-Request-Id', requestId);

  response.on('finish', () => {
    const isHealthRequest =
      request.path === '/api/health' || request.path === '/api/readiness';
    if (isHealthRequest && response.statusCode < 500) {
      return;
    }

    logger.info('http.request.completed', {
      requestId,
      method: request.method,
      path: request.originalUrl,
      statusCode: response.statusCode,
      durationMs: Date.now() - startedAt,
      ip: readClientIp(request),
      userAgent: request.headers['user-agent'],
      userId: request.auth?.userId,
      companyId: request.auth?.companyId,
    });
  });

  next();
}
