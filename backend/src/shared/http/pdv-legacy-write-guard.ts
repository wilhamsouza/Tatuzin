import type { NextFunction, Request, Response } from 'express';

import { logger } from '../observability/logger';
import { AppError } from './app-error';
import { safeRequestPath } from './request-url-sanitizer';

const MOBILE_APP_CLIENT_TYPE = 'MOBILE_APP';
const PDV_SYNC_MESSAGE =
  'Operações de PDV devem ser enviadas pela sincronização operacional.';

export function blockMobilePdvLegacyWrite(
  request: Request,
  _response: Response,
  next: NextFunction,
): void {
  const safePath = safeRequestPath(request);
  const context = {
    requestId: request.requestId,
    method: request.method,
    path: safePath,
    userId: request.auth?.userId,
    companyId: request.auth?.companyId,
    clientInstanceId: request.auth?.clientInstanceId,
    sessionClientType: request.auth?.sessionClientType,
  };

  if (request.auth?.sessionClientType === MOBILE_APP_CLIENT_TYPE) {
    logger.warn('pdv.legacy_write.blocked', context);
    next(
      new AppError(PDV_SYNC_MESSAGE, 403, 'PDV_WRITES_MUST_USE_SYNC', {
        entity: legacyEntityFromPath(safePath),
        operation: request.method,
      }),
    );
    return;
  }

  logger.warn('pdv.legacy_write.allowed', context);
  next();
}

function legacyEntityFromPath(path: string) {
  if (path.includes('/sales')) {
    return 'sale';
  }
  if (path.includes('/cash/events')) {
    return 'cashEvent';
  }
  if (path.includes('/financial-events')) {
    return 'financialEvent';
  }
  if (path.includes('/fiado/payments')) {
    return 'fiadoPayment';
  }
  return 'operationalLegacyWrite';
}
