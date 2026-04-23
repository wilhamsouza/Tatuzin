import { Router } from 'express';

import { requireCloudLicense } from '../../shared/http/auth-middleware';
import { buildPaginatedResponse } from '../../shared/http/api-response';
import { asyncHandler } from '../../shared/http/async-handler';
import { validateBody, validateQuery } from '../../shared/http/validate';
import {
  productListQuerySchema,
  type ProductListQueryInput,
  productUpsertSchema,
} from './products.schemas';
import { ProductsService } from './products.service';

const productsService = new ProductsService();

export const productsRouter = Router();

productsRouter.get('/health', (_request, response) => {
  response.json({
    ok: true,
    feature: 'products',
    timestamp: new Date().toISOString(),
  });
});

productsRouter.use(requireCloudLicense);

productsRouter.get(
  '/',
  validateQuery(productListQuerySchema),
  asyncHandler(async (request, response) => {
    const query = request.query as ProductListQueryInput;
    const result = await productsService.listForCompany(
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

productsRouter.get(
  '/:id',
  asyncHandler(async (request, response) => {
    const productId = Array.isArray(request.params.id)
      ? request.params.id[0]
      : request.params.id;
    const product = await productsService.getById(
      request.auth!.companyId,
      productId,
    );
    response.json({ product });
  }),
);

productsRouter.post(
  '/',
  validateBody(productUpsertSchema),
  asyncHandler(async (request, response) => {
    const product = await productsService.create(
      request.auth!.companyId,
      request.body,
    );
    response.status(201).json({ product });
  }),
);

productsRouter.put(
  '/:id',
  validateBody(productUpsertSchema),
  asyncHandler(async (request, response) => {
    const productId = Array.isArray(request.params.id)
      ? request.params.id[0]
      : request.params.id;
    const product = await productsService.update(
      request.auth!.companyId,
      productId,
      request.body,
    );
    response.json({ product });
  }),
);

productsRouter.delete(
  '/:id',
  asyncHandler(async (request, response) => {
    const productId = Array.isArray(request.params.id)
      ? request.params.id[0]
      : request.params.id;
    const product = await productsService.softDelete(
      request.auth!.companyId,
      productId,
    );
    response.json({ product });
  }),
);
