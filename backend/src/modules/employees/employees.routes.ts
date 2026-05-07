import { Router } from 'express';

import { requireAppContext } from '../../shared/http/auth-middleware';
import { asyncHandler } from '../../shared/http/async-handler';
import { requireFeature } from '../../shared/http/feature-middleware';

export const employeesRouter = Router();

employeesRouter.get(
  '/',
  requireAppContext,
  requireFeature('employees'),
  asyncHandler(async (request, response) => {
    const companyId = request.appContext!.company.id;
    void companyId;
    response.json({
      items: [],
      count: 0,
    });
  }),
);
