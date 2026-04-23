import { Router } from 'express';

import { requireCloudLicense } from '../../shared/http/auth-middleware';
import { buildPaginatedResponse } from '../../shared/http/api-response';
import { asyncHandler } from '../../shared/http/async-handler';
import { validateBody, validateQuery } from '../../shared/http/validate';
import {
  supplyListQuerySchema,
  type SupplyListQueryInput,
  supplyUpsertSchema,
} from './supplies.schemas';
import { SuppliesService } from './supplies.service';

const suppliesService = new SuppliesService();

export const suppliesRouter = Router();

suppliesRouter.get('/health', (_request, response) => {
  response.json({
    ok: true,
    feature: 'supplies',
    timestamp: new Date().toISOString(),
  });
});

suppliesRouter.use(requireCloudLicense);

suppliesRouter.get(
  '/',
  validateQuery(supplyListQuerySchema),
  asyncHandler(async (request, response) => {
    const query = request.query as SupplyListQueryInput;
    const result = await suppliesService.listForCompany(
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

suppliesRouter.get(
  '/:id',
  asyncHandler(async (request, response) => {
    const supplyId = Array.isArray(request.params.id)
      ? request.params.id[0]
      : request.params.id;
    const supply = await suppliesService.getById(
      request.auth!.companyId,
      supplyId,
    );
    response.json({ supply });
  }),
);

suppliesRouter.post(
  '/',
  validateBody(supplyUpsertSchema),
  asyncHandler(async (request, response) => {
    const supply = await suppliesService.create(
      request.auth!.companyId,
      request.body,
    );
    response.status(201).json({ supply });
  }),
);

suppliesRouter.put(
  '/:id',
  validateBody(supplyUpsertSchema),
  asyncHandler(async (request, response) => {
    const supplyId = Array.isArray(request.params.id)
      ? request.params.id[0]
      : request.params.id;
    const supply = await suppliesService.update(
      request.auth!.companyId,
      supplyId,
      request.body,
    );
    response.json({ supply });
  }),
);

suppliesRouter.delete(
  '/:id',
  asyncHandler(async (request, response) => {
    const supplyId = Array.isArray(request.params.id)
      ? request.params.id[0]
      : request.params.id;
    const supply = await suppliesService.softDelete(
      request.auth!.companyId,
      supplyId,
    );
    response.json({ supply });
  }),
);
