import { Router } from 'express';

import { requireCloudLicense } from '../../shared/http/auth-middleware';
import { asyncHandler } from '../../shared/http/async-handler';
import { validateBody } from '../../shared/http/validate';
import { categoryUpsertSchema } from './categories.schemas';
import { CategoriesService } from './categories.service';

const categoriesService = new CategoriesService();

export const categoriesRouter = Router();

categoriesRouter.get('/health', (_request, response) => {
  response.json({
    ok: true,
    feature: 'categories',
    timestamp: new Date().toISOString(),
  });
});

categoriesRouter.use(requireCloudLicense);

categoriesRouter.get(
  '/',
  asyncHandler(async (request, response) => {
    const includeDeleted = request.query.includeDeleted === 'true';
    const items = await categoriesService.listForCompany(
      request.auth!.companyId,
      includeDeleted,
    );
    response.json({
      items,
      count: items.length,
    });
  }),
);

categoriesRouter.get(
  '/:id',
  asyncHandler(async (request, response) => {
    const categoryId = Array.isArray(request.params.id)
      ? request.params.id[0]
      : request.params.id;
    const category = await categoriesService.getById(
      request.auth!.companyId,
      categoryId,
    );
    response.json({ category });
  }),
);

categoriesRouter.post(
  '/',
  validateBody(categoryUpsertSchema),
  asyncHandler(async (request, response) => {
    const category = await categoriesService.create(
      request.auth!.companyId,
      request.body,
    );
    response.status(201).json({ category });
  }),
);

categoriesRouter.put(
  '/:id',
  validateBody(categoryUpsertSchema),
  asyncHandler(async (request, response) => {
    const categoryId = Array.isArray(request.params.id)
      ? request.params.id[0]
      : request.params.id;
    const category = await categoriesService.update(
      request.auth!.companyId,
      categoryId,
      request.body,
    );
    response.json({ category });
  }),
);

categoriesRouter.delete(
  '/:id',
  asyncHandler(async (request, response) => {
    const categoryId = Array.isArray(request.params.id)
      ? request.params.id[0]
      : request.params.id;
    const category = await categoriesService.softDelete(
      request.auth!.companyId,
      categoryId,
    );
    response.json({ category });
  }),
);
