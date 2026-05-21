import { Router } from 'express';

import { requireAppContext } from '../../shared/http/auth-middleware';
import { buildPaginatedResponse } from '../../shared/http/api-response';
import { asyncHandler } from '../../shared/http/async-handler';
import { validateQuery } from '../../shared/http/validate';
import { requireAnyEmployeePermission } from '../employees/employee-permission-middleware';
import {
  operationalOrderIdParamSchema,
  operationalOrderListQuerySchema,
  operationalOrderLocalUuidParamSchema,
  type OperationalOrderListQueryInput,
} from './operational-orders.schemas';
import { OperationalOrdersService } from './operational-orders.service';

const operationalOrdersService = new OperationalOrdersService();

export const operationalOrdersRouter = Router();

operationalOrdersRouter.use(
  requireAppContext,
  requireAnyEmployeePermission([
    'sales.create',
    'reports.basic',
    'reports.advanced',
  ]),
);

operationalOrdersRouter.get(
  '/',
  validateQuery(operationalOrderListQuerySchema),
  asyncHandler(async (request, response) => {
    const query = request.query as unknown as OperationalOrderListQueryInput;
    const companyId = request.appContext!.company.id;
    const result = await operationalOrdersService.listForCompany(
      companyId,
      query,
    );

    response.json(
      buildPaginatedResponse({
        items: result.items,
        page: query.page,
        pageSize: query.limit,
        total: result.total,
      }),
    );
  }),
);

operationalOrdersRouter.get(
  '/by-local/:localUuid',
  asyncHandler(async (request, response) => {
    const { localUuid } = operationalOrderLocalUuidParamSchema.parse(
      request.params,
    );
    const order = await operationalOrdersService.getByLocalUuid(
      request.appContext!.company.id,
      localUuid,
    );
    response.json({ order });
  }),
);

operationalOrdersRouter.get(
  '/:id/items',
  asyncHandler(async (request, response) => {
    const { id } = operationalOrderIdParamSchema.parse(request.params);
    const items = await operationalOrdersService.listItems(
      request.appContext!.company.id,
      id,
    );
    response.json({ items, count: items.length });
  }),
);

operationalOrdersRouter.get(
  '/:id',
  asyncHandler(async (request, response) => {
    const { id } = operationalOrderIdParamSchema.parse(request.params);
    const order = await operationalOrdersService.getById(
      request.appContext!.company.id,
      id,
    );
    response.json({ order });
  }),
);
