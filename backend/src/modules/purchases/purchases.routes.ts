import { Router } from 'express';

import { requireCloudLicense } from '../../shared/http/auth-middleware';
import { buildPaginatedResponse } from '../../shared/http/api-response';
import { asyncHandler } from '../../shared/http/async-handler';
import { validateBody, validateQuery } from '../../shared/http/validate';
import {
  purchaseListQuerySchema,
  type PurchaseListQueryInput,
  purchaseUpsertSchema,
} from './purchases.schemas';
import { PurchasesService } from './purchases.service';

const purchasesService = new PurchasesService();

export const purchasesRouter = Router();

purchasesRouter.get('/health', (_request, response) => {
  response.json({
    ok: true,
    feature: 'purchases',
    timestamp: new Date().toISOString(),
  });
});

purchasesRouter.use(requireCloudLicense);

purchasesRouter.get(
  '/',
  validateQuery(purchaseListQuerySchema),
  asyncHandler(async (request, response) => {
    const query = request.query as PurchaseListQueryInput;
    const result = await purchasesService.listForCompany(
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

purchasesRouter.get(
  '/:id',
  asyncHandler(async (request, response) => {
    const purchaseId = Array.isArray(request.params.id)
      ? request.params.id[0]
      : request.params.id;
    const purchase = await purchasesService.getById(
      request.auth!.companyId,
      purchaseId,
    );
    response.json({ purchase });
  }),
);

purchasesRouter.post(
  '/',
  validateBody(purchaseUpsertSchema),
  asyncHandler(async (request, response) => {
    const purchase = await purchasesService.create(
      request.auth!.companyId,
      request.body,
    );
    response.status(201).json({ purchase });
  }),
);

purchasesRouter.put(
  '/:id',
  validateBody(purchaseUpsertSchema),
  asyncHandler(async (request, response) => {
    const purchaseId = Array.isArray(request.params.id)
      ? request.params.id[0]
      : request.params.id;
    const purchase = await purchasesService.update(
      request.auth!.companyId,
      purchaseId,
      request.body,
    );
    response.json({ purchase });
  }),
);
