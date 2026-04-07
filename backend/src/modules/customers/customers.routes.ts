import { Router } from 'express';

import { requireCloudLicense } from '../../shared/http/auth-middleware';
import { asyncHandler } from '../../shared/http/async-handler';
import { validateBody } from '../../shared/http/validate';
import { customerUpsertSchema } from './customers.schemas';
import { CustomersService } from './customers.service';

const customersService = new CustomersService();

export const customersRouter = Router();

customersRouter.get('/health', (_request, response) => {
  response.json({
    ok: true,
    feature: 'customers',
    timestamp: new Date().toISOString(),
  });
});

customersRouter.use(requireCloudLicense);

customersRouter.get(
  '/',
  asyncHandler(async (request, response) => {
    const includeDeleted = request.query.includeDeleted === 'true';
    const items = await customersService.listForCompany(
      request.auth!.companyId,
      includeDeleted,
    );
    response.json({
      items,
      count: items.length,
    });
  }),
);

customersRouter.get(
  '/:id',
  asyncHandler(async (request, response) => {
    const customerId = Array.isArray(request.params.id)
      ? request.params.id[0]
      : request.params.id;
    const customer = await customersService.getById(
      request.auth!.companyId,
      customerId,
    );
    response.json({ customer });
  }),
);

customersRouter.post(
  '/',
  validateBody(customerUpsertSchema),
  asyncHandler(async (request, response) => {
    const customer = await customersService.create(
      request.auth!.companyId,
      request.body,
    );
    response.status(201).json({ customer });
  }),
);

customersRouter.put(
  '/:id',
  validateBody(customerUpsertSchema),
  asyncHandler(async (request, response) => {
    const customerId = Array.isArray(request.params.id)
      ? request.params.id[0]
      : request.params.id;
    const customer = await customersService.update(
      request.auth!.companyId,
      customerId,
      request.body,
    );
    response.json({ customer });
  }),
);

customersRouter.delete(
  '/:id',
  asyncHandler(async (request, response) => {
    const customerId = Array.isArray(request.params.id)
      ? request.params.id[0]
      : request.params.id;
    const customer = await customersService.softDelete(
      request.auth!.companyId,
      customerId,
    );
    response.json({ customer });
  }),
);
