import { Router } from 'express';

import { requireCloudLicense } from '../../shared/http/auth-middleware';
import { asyncHandler } from '../../shared/http/async-handler';
import { validateBody } from '../../shared/http/validate';
import { saleCancelSchema, saleCreateSchema } from './sales.schemas';
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
  asyncHandler(async (request, response) => {
    const items = await salesService.listForCompany(request.auth!.companyId);
    response.json({
      items,
      count: items.length,
    });
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
