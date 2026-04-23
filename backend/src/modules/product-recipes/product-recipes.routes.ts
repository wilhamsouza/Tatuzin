import { Router } from 'express';

import { requireCloudLicense } from '../../shared/http/auth-middleware';
import { buildPaginatedResponse } from '../../shared/http/api-response';
import { asyncHandler } from '../../shared/http/async-handler';
import { validateBody, validateQuery } from '../../shared/http/validate';
import {
  productRecipeListQuerySchema,
  type ProductRecipeListQueryInput,
  productRecipeUpsertSchema,
} from './product-recipes.schemas';
import { ProductRecipesService } from './product-recipes.service';

const productRecipesService = new ProductRecipesService();

export const productRecipesRouter = Router();

productRecipesRouter.get('/health', (_request, response) => {
  response.json({
    ok: true,
    feature: 'product_recipes',
    timestamp: new Date().toISOString(),
  });
});

productRecipesRouter.use(requireCloudLicense);

productRecipesRouter.get(
  '/',
  validateQuery(productRecipeListQuerySchema),
  asyncHandler(async (request, response) => {
    const query = request.query as ProductRecipeListQueryInput;
    const result = await productRecipesService.listForCompany(
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

productRecipesRouter.get(
  '/:productId',
  asyncHandler(async (request, response) => {
    const productId = Array.isArray(request.params.productId)
      ? request.params.productId[0]
      : request.params.productId;
    const recipe = await productRecipesService.getByProductId(
      request.auth!.companyId,
      productId,
    );
    response.json({ recipe });
  }),
);

productRecipesRouter.put(
  '/:productId',
  validateBody(productRecipeUpsertSchema),
  asyncHandler(async (request, response) => {
    const productId = Array.isArray(request.params.productId)
      ? request.params.productId[0]
      : request.params.productId;
    const recipe = await productRecipesService.upsertForProduct(
      request.auth!.companyId,
      productId,
      request.body,
    );
    response.json({ recipe });
  }),
);

productRecipesRouter.delete(
  '/:productId',
  asyncHandler(async (request, response) => {
    const productId = Array.isArray(request.params.productId)
      ? request.params.productId[0]
      : request.params.productId;
    const recipe = await productRecipesService.deleteForProduct(
      request.auth!.companyId,
      productId,
    );
    response.json({ recipe });
  }),
);
