import { Router } from 'express';

import { requireCloudLicense } from '../../shared/http/auth-middleware';
import { asyncHandler } from '../../shared/http/async-handler';
import { validateBody } from '../../shared/http/validate';
import { purchaseUpsertSchema } from './purchases.schemas';
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
  asyncHandler(async (request, response) => {
    const items = await purchasesService.listForCompany(request.auth!.companyId);
    response.json({
      items,
      count: items.length,
    });
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
