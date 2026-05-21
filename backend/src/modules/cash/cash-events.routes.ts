import { Router } from 'express';

import { requireAppContext } from '../../shared/http/auth-middleware';
import { asyncHandler } from '../../shared/http/async-handler';
import { blockMobilePdvLegacyWrite } from '../../shared/http/pdv-legacy-write-guard';
import { validateBody } from '../../shared/http/validate';
import { requireEmployeePermission } from '../employees/employee-permission-middleware';
import { CashEventsService } from './cash-events.service';
import { cashEventCreateSchema } from './cash-events.schemas';

const cashEventsService = new CashEventsService();

export const cashEventsRouter = Router();

cashEventsRouter.use(requireAppContext);

cashEventsRouter.post(
  '/events',
  blockMobilePdvLegacyWrite,
  requireEmployeePermission('cash.withdraw'),
  validateBody(cashEventCreateSchema),
  asyncHandler(async (request, response) => {
    const event = await cashEventsService.create(
      request.auth!.companyId,
      request.body,
    );
    response.status(201).json({ event });
  }),
);
