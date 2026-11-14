import { Router } from 'express';
import { requireAppContext, requirePlatformAdmin } from '../../shared/http/auth-middleware';
import { asyncHandler } from '../../shared/http/async-handler';
import { createRateLimit } from '../../shared/http/rate-limit';
import { validateBody, validateQuery } from '../../shared/http/validate';
import { journeyBatchSchema, journeyReportQuerySchema, type JourneyReportQuery } from './product-journey.schemas';
import { ProductJourneyService } from './product-journey.service';

const service = new ProductJourneyService();
export const productJourneyRouter = Router();
productJourneyRouter.post('/events', requireAppContext, createRateLimit({
  name: 'product_journey', windowMs: 60000, max: 30,
  message: 'Aguarde antes de reenviar eventos.',
  keyGenerator: (request) => request.appContext!.device.id,
}), validateBody(journeyBatchSchema), asyncHandler(async (request, response) => {
  response.json(await service.ingest(request.appContext!, request.body));
}));

export const productJourneyAdminRouter = Router();
productJourneyAdminRouter.get('/report', requirePlatformAdmin,
  validateQuery(journeyReportQuerySchema), asyncHandler(async (request, response) => {
    response.json(await service.report(request.query as unknown as JourneyReportQuery));
  }));
