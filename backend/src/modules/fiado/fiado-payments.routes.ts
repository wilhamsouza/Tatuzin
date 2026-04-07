import { Router } from 'express';

import { requireCloudLicense } from '../../shared/http/auth-middleware';
import { asyncHandler } from '../../shared/http/async-handler';
import { validateBody } from '../../shared/http/validate';
import { fiadoPaymentCreateSchema } from './fiado-payments.schemas';
import { FiadoPaymentsService } from './fiado-payments.service';

const fiadoPaymentsService = new FiadoPaymentsService();

export const fiadoPaymentsRouter = Router();

fiadoPaymentsRouter.use(requireCloudLicense);

fiadoPaymentsRouter.post(
  '/payments',
  validateBody(fiadoPaymentCreateSchema),
  asyncHandler(async (request, response) => {
    const payment = await fiadoPaymentsService.create(
      request.auth!.companyId,
      request.body,
    );
    response.status(201).json({ payment });
  }),
);
