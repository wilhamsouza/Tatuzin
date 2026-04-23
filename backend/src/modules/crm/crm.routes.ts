import { Router } from 'express';

import { requirePlatformAdmin } from '../../shared/http/auth-middleware';
import { asyncHandler } from '../../shared/http/async-handler';
import { validateBody, validateQuery } from '../../shared/http/validate';
import {
  crmCustomerContextQuerySchema,
  crmCustomerNoteCreateSchema,
  crmCustomerTagsApplySchema,
  crmCustomerTaskCreateSchema,
  crmCustomerTimelineQuerySchema,
  crmCustomersListQuerySchema,
  type CrmCustomerContextQueryInput,
  type CrmCustomerTimelineQueryInput,
  type CrmCustomersListQueryInput,
} from './crm.schemas';
import { CrmService } from './crm.service';

const crmService = new CrmService();

export const crmRouter = Router();

crmRouter.use(requirePlatformAdmin);

crmRouter.get(
  '/customers',
  validateQuery(crmCustomersListQuerySchema),
  asyncHandler(async (request, response) => {
    const payload = await crmService.listCustomersWithCommercialContext(
      request.query as unknown as CrmCustomersListQueryInput,
    );
    response.json(payload);
  }),
);

crmRouter.get(
  '/customers/:id',
  validateQuery(crmCustomerContextQuerySchema),
  asyncHandler(async (request, response) => {
    const customerId = Array.isArray(request.params.id)
      ? request.params.id[0]
      : request.params.id;
    const payload = await crmService.getCustomerDetail(
      customerId,
      request.query as unknown as CrmCustomerContextQueryInput,
    );
    response.json(payload);
  }),
);

crmRouter.get(
  '/customers/:id/timeline',
  validateQuery(crmCustomerTimelineQuerySchema),
  asyncHandler(async (request, response) => {
    const customerId = Array.isArray(request.params.id)
      ? request.params.id[0]
      : request.params.id;
    const payload = await crmService.getCustomerTimeline(
      customerId,
      request.query as unknown as CrmCustomerTimelineQueryInput,
    );
    response.json(payload);
  }),
);

crmRouter.post(
  '/customers/:id/notes',
  validateBody(crmCustomerNoteCreateSchema),
  asyncHandler(async (request, response) => {
    const customerId = Array.isArray(request.params.id)
      ? request.params.id[0]
      : request.params.id;
    const payload = await crmService.createCustomerNote(
      customerId,
      request.body,
      request.auth!.userId,
    );
    response.status(201).json(payload);
  }),
);

crmRouter.post(
  '/customers/:id/tasks',
  validateBody(crmCustomerTaskCreateSchema),
  asyncHandler(async (request, response) => {
    const customerId = Array.isArray(request.params.id)
      ? request.params.id[0]
      : request.params.id;
    const payload = await crmService.createCustomerTask(
      customerId,
      request.body,
      request.auth!.userId,
    );
    response.status(201).json(payload);
  }),
);

crmRouter.post(
  '/customers/:id/tags',
  validateBody(crmCustomerTagsApplySchema),
  asyncHandler(async (request, response) => {
    const customerId = Array.isArray(request.params.id)
      ? request.params.id[0]
      : request.params.id;
    const payload = await crmService.applyCustomerTags(
      customerId,
      request.body,
      request.auth!.userId,
    );
    response.json(payload);
  }),
);
