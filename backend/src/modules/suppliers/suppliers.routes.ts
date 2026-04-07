import { Router } from 'express';

import { requireCloudLicense } from '../../shared/http/auth-middleware';
import { asyncHandler } from '../../shared/http/async-handler';
import { validateBody } from '../../shared/http/validate';
import { supplierUpsertSchema } from './suppliers.schemas';
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

suppliersRouter.use(requireCloudLicense);

suppliersRouter.get(
  '/',
  asyncHandler(async (request, response) => {
    const includeDeleted = request.query.includeDeleted === 'true';
    const items = await suppliersService.listForCompany(
      request.auth!.companyId,
      includeDeleted,
    );
    response.json({
      items,
      count: items.length,
    });
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
