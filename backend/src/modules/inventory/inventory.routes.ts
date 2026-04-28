import { Router } from 'express';

import { requireCloudLicense } from '../../shared/http/auth-middleware';
import { asyncHandler } from '../../shared/http/async-handler';
import { validateQuery } from '../../shared/http/validate';
import {
  inventoryListQuerySchema,
  inventorySummaryQuerySchema,
  type InventoryListQueryInput,
} from './inventory.schemas';
import { InventoryService } from './inventory.service';

const inventoryService = new InventoryService();

export const inventoryRouter = Router();

inventoryRouter.get('/health', (_request, response) => {
  response.json({
    ok: true,
    feature: 'inventory',
    timestamp: new Date().toISOString(),
  });
});

inventoryRouter.use(requireCloudLicense);

inventoryRouter.get(
  '/summary',
  validateQuery(inventorySummaryQuerySchema),
  asyncHandler(async (request, response) => {
    const summary = await inventoryService.summaryForCompany(
      request.auth!.companyId,
    );
    response.json({ summary });
  }),
);

inventoryRouter.get(
  '/',
  validateQuery(inventoryListQuerySchema),
  asyncHandler(async (request, response) => {
    const query = request.query as unknown as InventoryListQueryInput;
    const result = await inventoryService.listForCompany(
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
