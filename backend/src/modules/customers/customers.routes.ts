import { Router } from 'express';

import { requireCloudLicense } from '../../shared/http/auth-middleware';
import { buildPaginatedResponse } from '../../shared/http/api-response';
import { asyncHandler } from '../../shared/http/async-handler';
import { validateBody, validateQuery } from '../../shared/http/validate';
import {
  customerListQuerySchema,
  type CustomerListQueryInput,
  customerUpsertSchema,
} from './customers.schemas';
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
  validateQuery(customerListQuerySchema),
  asyncHandler(async (request, response) => {
    const query = request.query as CustomerListQueryInput;
    const result = await customersService.listForCompany(
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
