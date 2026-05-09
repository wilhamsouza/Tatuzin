import type { NextFunction, Request, Response } from 'express';
import { Router } from 'express';

import { requireAppContext } from '../../shared/http/auth-middleware';
import { asyncHandler } from '../../shared/http/async-handler';
import { AppError } from '../../shared/http/app-error';
import { requireFeature } from '../../shared/http/feature-middleware';
import { validateQuery } from '../../shared/http/validate';
import {
  ownerInvoicesQuerySchema,
  type OwnerInvoicesQueryInput,
} from './owner.schemas';
import { OwnerService } from './owner.service';

const ownerService = new OwnerService();

export const ownerRouter = Router();

ownerRouter.use(
  requireAppContext,
  requireOwnerMembership,
  requireFeature('ownerWebPanel'),
);

ownerRouter.get(
  '/company',
  asyncHandler(async (request, response) => {
    response.json(await ownerService.getCompanySummary(request.appContext!));
  }),
);

ownerRouter.get(
  '/billing/status',
  asyncHandler(async (request, response) => {
    response.json(await ownerService.getBillingStatus(request.appContext!));
  }),
);

ownerRouter.get(
  '/billing/invoices',
  validateQuery(ownerInvoicesQuerySchema),
  asyncHandler(async (request, response) => {
    response.json(
      await ownerService.listBillingInvoices(
        request.appContext!,
        request.query as unknown as OwnerInvoicesQueryInput,
      ),
    );
  }),
);

ownerRouter.get(
  '/employees',
  asyncHandler(async (_request, response) => {
    response.json(ownerService.getEmployeesPlaceholder());
  }),
);

ownerRouter.get(
  '/devices',
  asyncHandler(async (request, response) => {
    response.json(await ownerService.listDevices(request.appContext!));
  }),
);

ownerRouter.get(
  '/dashboard',
  asyncHandler(async (request, response) => {
    response.json(await ownerService.getDashboard(request.appContext!));
  }),
);

function requireOwnerMembership(
  request: Request,
  _response: Response,
  next: NextFunction,
) {
  if (request.appContext?.membership.role === 'OWNER') {
    next();
    return;
  }

  next(
    new AppError(
      'Apenas o dono da empresa pode acessar o painel owner.',
      403,
      'OWNER_REQUIRED',
    ),
  );
}
