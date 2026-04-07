import type { NextFunction, Request, Response } from 'express';
import { ZodError } from 'zod';

import { logger } from '../observability/logger';
import { AppError } from './app-error';

export function errorHandler(
  error: unknown,
  request: Request,
  response: Response,
  _next: NextFunction,
): void {
  const requestId = request.requestId;

  if (error instanceof ZodError) {
    const details = error.flatten();
    logger.warn('http.request.validation_failed', {
      requestId,
      method: request.method,
      path: request.originalUrl,
      details,
    });

    response.status(422).json({
      ok: false,
      message: 'Dados invalidos enviados para a API.',
      code: 'VALIDATION_ERROR',
      details,
      requestId,
      error: {
        message: 'Dados invalidos enviados para a API.',
        code: 'VALIDATION_ERROR',
        details,
        requestId,
      },
    });
    return;
  }

  if (error instanceof AppError) {
    if (error.headers != null) {
      for (const [headerName, headerValue] of Object.entries(error.headers)) {
        response.setHeader(headerName, headerValue);
      }
    }

    const log = error.statusCode >= 500 ? logger.error : logger.warn;
    log('http.request.failed', {
      requestId,
      method: request.method,
      path: request.originalUrl,
      statusCode: error.statusCode,
      code: error.code,
      details: error.details,
      userId: request.auth?.userId,
      companyId: request.auth?.companyId,
    });

    response.status(error.statusCode).json({
      ok: false,
      message: error.message,
      code: error.code,
      details: error.details,
      requestId,
      error: {
        message: error.message,
        code: error.code,
        details: error.details,
        requestId,
      },
    });
    return;
  }

  logger.error('http.request.unhandled_error', {
    requestId,
    method: request.method,
    path: request.originalUrl,
    userId: request.auth?.userId,
    companyId: request.auth?.companyId,
    error,
  });

  response.status(500).json({
    ok: false,
    message: 'Erro interno inesperado no backend.',
    code: 'INTERNAL_SERVER_ERROR',
    requestId,
    error: {
      message: 'Erro interno inesperado no backend.',
      code: 'INTERNAL_SERVER_ERROR',
      requestId,
    },
  });
}
