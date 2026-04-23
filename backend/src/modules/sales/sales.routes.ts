import { Router } from 'express';

import { requireCloudLicense } from '../../shared/http/auth-middleware';
import { buildPaginatedResponse } from '../../shared/http/api-response';
import { asyncHandler } from '../../shared/http/async-handler';
import { validateBody, validateQuery } from '../../shared/http/validate';
import {
  saleCancelSchema,
  saleCreateSchema,
  saleListQuerySchema,
  type SaleListQueryInput,
} from './sales.schemas';
import { SalesService } from './sales.service';

const salesService = new SalesService();

export const salesRouter = Router();

salesRouter.get('/health', (_request, response) => {
  response.json({
    ok: true,
    feature: 'sales',
    timestamp: new Date().toISOString(),
  });
});

salesRouter.use(requireCloudLicense);

salesRouter.get(
  '/',
  validateQuery(saleListQuerySchema),
  asyncHandler(async (request, response) => {
    const query = request.query as SaleListQueryInput;
    const result = await salesService.listForCompany(
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

salesRouter.get(
  '/:id',
  asyncHandler(async (request, response) => {
    const saleId = Array.isArray(request.params.id)
      ? request.params.id[0]
      : request.params.id;
    const sale = await salesService.getById(request.auth!.companyId, saleId);
    response.json({ sale });
  }),
);

salesRouter.post(
  '/',
  validateBody(saleCreateSchema),
  asyncHandler(async (request, response) => {
    const sale = await salesService.create(request.auth!.companyId, request.body);
    response.status(201).json({ sale });
  }),
);

salesRouter.put(
  '/:id/cancel',
  validateBody(saleCancelSchema),
  asyncHandler(async (request, response) => {
    const saleId = Array.isArray(request.params.id)
      ? request.params.id[0]
      : request.params.id;
    const sale = await salesService.cancel(
      request.auth!.companyId,
      saleId,
      request.body,
    );
    response.json({ sale });
  }),
);
