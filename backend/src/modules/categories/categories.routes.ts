import { Router } from 'express';

import { requireCloudLicense } from '../../shared/http/auth-middleware';
import { buildPaginatedResponse } from '../../shared/http/api-response';
import { asyncHandler } from '../../shared/http/async-handler';
import { validateBody, validateQuery } from '../../shared/http/validate';
import {
  categoryListQuerySchema,
  type CategoryListQueryInput,
  categoryUpsertSchema,
} from './categories.schemas';
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
  validateQuery(categoryListQuerySchema),
  asyncHandler(async (request, response) => {
    const query = request.query as CategoryListQueryInput;
    const result = await categoriesService.listForCompany(
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
