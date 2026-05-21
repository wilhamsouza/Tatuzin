import { Router } from 'express';

import { requireAppContext } from '../../shared/http/auth-middleware';
import { asyncHandler } from '../../shared/http/async-handler';
import { requireFeature } from '../../shared/http/feature-middleware';
import { blockMobilePdvLegacyWrite } from '../../shared/http/pdv-legacy-write-guard';
import { validateBody } from '../../shared/http/validate';
import { requireEmployeePermission } from '../employees/employee-permission-middleware';
import { fiadoPaymentCreateSchema } from './fiado-payments.schemas';
import { FiadoPaymentsService } from './fiado-payments.service';

const fiadoPaymentsService = new FiadoPaymentsService();

export const fiadoPaymentsRouter = Router();

fiadoPaymentsRouter.use(requireAppContext);

fiadoPaymentsRouter.post(
  '/payments',
  requireFeature('fiadoManagement'),
  requireEmployeePermission('fiado.receive'),
  blockMobilePdvLegacyWrite,
  validateBody(fiadoPaymentCreateSchema),
  asyncHandler(async (request, response) => {
    const payment = await fiadoPaymentsService.create(
      request.auth!.companyId,
      request.body,
    );
    response.status(201).json({ payment });
  }),
);
