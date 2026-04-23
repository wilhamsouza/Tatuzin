import { Router } from 'express';

import { requireCloudLicense } from '../../shared/http/auth-middleware';
import { buildPaginatedResponse } from '../../shared/http/api-response';
import { asyncHandler } from '../../shared/http/async-handler';
import { validateBody, validateQuery } from '../../shared/http/validate';
import {
  financialEventListQuerySchema,
  type FinancialEventListQueryInput,
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
  validateQuery(financialEventListQuerySchema),
  asyncHandler(async (request, response) => {
    const query = request.query as FinancialEventListQueryInput;
    const result = await financialEventsService.listForCompany(
      request.auth!.companyId,
      query,
    );
    response.json(
      buildPaginatedResponse({
        items: result.items,
        page: query.page,
        pageSize: query.pageSize,
        total: result.total,
      }),
    );
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
