import { Router } from 'express';

import { requireCloudLicense } from '../../shared/http/auth-middleware';
import { asyncHandler } from '../../shared/http/async-handler';
import { validateBody } from '../../shared/http/validate';
import {
  financialEventCreateSchema,
} from './financial-events.schemas';
import { FinancialEventsService } from './financial-events.service';

const financialEventsService = new FinancialEventsService();

export const financialEventsRouter = Router();

financialEventsRouter.get('/health', (_request, response) => {
  response.json({
    ok: true,
    feature: 'financial-events',
    timestamp: new Date().toISOString(),
  });
});

financialEventsRouter.use(requireCloudLicense);

financialEventsRouter.get(
  '/',
  asyncHandler(async (request, response) => {
    const items = await financialEventsService.listForCompany(
      request.auth!.companyId,
    );
    response.json({
      items,
      count: items.length,
    });
  }),
);

financialEventsRouter.post(
  '/',
  validateBody(financialEventCreateSchema),
  asyncHandler(async (request, response) => {
    const event = await financialEventsService.create(
      request.auth!.companyId,
      request.body,
    );
    response.status(201).json({ event });
  }),
);
