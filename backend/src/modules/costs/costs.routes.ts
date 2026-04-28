import { Router } from 'express';

import { requireCloudLicense } from '../../shared/http/auth-middleware';
import { asyncHandler } from '../../shared/http/async-handler';
import { validateBody, validateQuery } from '../../shared/http/validate';
import {
  costCancelSchema,
  costCreateSchema,
  costListQuerySchema,
  costPaySchema,
  costSummaryQuerySchema,
  costUpdateSchema,
  type CostListQueryInput,
  type CostSummaryQueryInput,
} from './costs.schemas';
import { CostsService } from './costs.service';

const costsService = new CostsService();

export const costsRouter = Router();

function routeParam(value: string | string[]) {
  return Array.isArray(value) ? value[0] : value;
}

costsRouter.get('/health', (_request, response) => {
  response.json({
    ok: true,
    feature: 'costs',
    timestamp: new Date().toISOString(),
  });
});

costsRouter.use(requireCloudLicense);

costsRouter.get(
  '/summary',
  validateQuery(costSummaryQuerySchema),
  asyncHandler(async (request, response) => {
    const summary = await costsService.summaryForCompany(
      request.auth!.companyId,
      request.query as CostSummaryQueryInput,
    );
    response.json({ summary });
  }),
);

costsRouter.get(
  '/',
  validateQuery(costListQuerySchema),
  asyncHandler(async (request, response) => {
    const query = request.query as unknown as CostListQueryInput;
    const result = await costsService.listForCompany(
      request.auth!.companyId,
      query,
    );
    response.json({
      items: result.items,
      pagination: {
        page: query.page,
        pageSize: query.pageSize,
        total: result.total,
        totalPages: Math.ceil(result.total / query.pageSize),
      },
    });
  }),
);

costsRouter.post(
  '/',
  validateBody(costCreateSchema),
  asyncHandler(async (request, response) => {
    const cost = await costsService.create(
      request.auth!.companyId,
      request.body,
    );
    response.status(201).json({ cost });
  }),
);

costsRouter.put(
  '/:id',
  validateBody(costUpdateSchema),
  asyncHandler(async (request, response) => {
    const cost = await costsService.update(
      request.auth!.companyId,
      routeParam(request.params.id),
      request.body,
    );
    response.json({ cost });
  }),
);

costsRouter.delete(
  '/:id',
  validateBody(costCancelSchema),
  asyncHandler(async (request, response) => {
    const cost = await costsService.cancel(
      request.auth!.companyId,
      routeParam(request.params.id),
      request.body,
    );
    response.json({ cost });
  }),
);

costsRouter.post(
  '/:id/cancel',
  validateBody(costCancelSchema),
  asyncHandler(async (request, response) => {
    const cost = await costsService.cancel(
      request.auth!.companyId,
      routeParam(request.params.id),
      request.body,
    );
    response.json({ cost });
  }),
);

costsRouter.post(
  '/:id/pay',
  validateBody(costPaySchema),
  asyncHandler(async (request, response) => {
    const cost = await costsService.pay(
      request.auth!.companyId,
      routeParam(request.params.id),
      request.body,
    );
    response.json({ cost });
  }),
);
