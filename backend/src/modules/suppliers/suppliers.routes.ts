import { Router } from 'express';

import { requireAppContext } from '../../shared/http/auth-middleware';
import { buildPaginatedResponse } from '../../shared/http/api-response';
import { asyncHandler } from '../../shared/http/async-handler';
import { requireFeature } from '../../shared/http/feature-middleware';
import { validateBody, validateQuery } from '../../shared/http/validate';
import { requireEmployeePermission } from '../employees/employee-permission-middleware';
import {
  supplierListQuerySchema,
  type SupplierListQueryInput,
  supplierUpsertSchema,
} from './suppliers.schemas';
import { SuppliersService } from './suppliers.service';

const suppliersService = new SuppliersService();

export const suppliersRouter = Router();

suppliersRouter.get('/health', (_request, response) => {
  response.json({
    ok: true,
    feature: 'suppliers',
    timestamp: new Date().toISOString(),
  });
});

suppliersRouter.use(
  requireAppContext,
  requireFeature('suppliers'),
  requireEmployeePermission('reports.advanced'),
);

suppliersRouter.get(
  '/',
  validateQuery(supplierListQuerySchema),
  asyncHandler(async (request, response) => {
    const query = request.query as SupplierListQueryInput;
    const result = await suppliersService.listForCompany(
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

suppliersRouter.get(
  '/:id',
  asyncHandler(async (request, response) => {
    const supplierId = Array.isArray(request.params.id)
      ? request.params.id[0]
      : request.params.id;
    const supplier = await suppliersService.getById(
      request.auth!.companyId,
      supplierId,
    );
    response.json({ supplier });
  }),
);

suppliersRouter.post(
  '/',
  validateBody(supplierUpsertSchema),
  asyncHandler(async (request, response) => {
    const supplier = await suppliersService.create(
      request.auth!.companyId,
      request.body,
    );
    response.status(201).json({ supplier });
  }),
);

suppliersRouter.put(
  '/:id',
  validateBody(supplierUpsertSchema),
  asyncHandler(async (request, response) => {
    const supplierId = Array.isArray(request.params.id)
      ? request.params.id[0]
      : request.params.id;
    const supplier = await suppliersService.update(
      request.auth!.companyId,
      supplierId,
      request.body,
    );
    response.json({ supplier });
  }),
);

suppliersRouter.delete(
  '/:id',
  asyncHandler(async (request, response) => {
    const supplierId = Array.isArray(request.params.id)
      ? request.params.id[0]
      : request.params.id;
    const supplier = await suppliersService.softDelete(
      request.auth!.companyId,
      supplierId,
    );
    response.json({ supplier });
  }),
);
