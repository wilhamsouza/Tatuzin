import { Router } from 'express';

import { requireCloudLicense } from '../../shared/http/auth-middleware';
import { asyncHandler } from '../../shared/http/async-handler';
import { validateBody } from '../../shared/http/validate';
import { CashEventsService } from './cash-events.service';
import { cashEventCreateSchema } from './cash-events.schemas';

const cashEventsService = new CashEventsService();

export const cashEventsRouter = Router();

cashEventsRouter.use(requireCloudLicense);

cashEventsRouter.post(
  '/events',
  validateBody(cashEventCreateSchema),
  asyncHandler(async (request, response) => {
    const event = await cashEventsService.create(
      request.auth!.companyId,
      request.body,
    );
    response.status(201).json({ event });
  }),
);
