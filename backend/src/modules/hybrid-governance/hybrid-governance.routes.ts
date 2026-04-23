import { Router } from 'express';

import { requirePlatformAdmin } from '../../shared/http/auth-middleware';
import { asyncHandler } from '../../shared/http/async-handler';
import { validateBody, validateQuery } from '../../shared/http/validate';
import {
  hybridGovernanceProfileUpdateSchema,
  hybridGovernanceQuerySchema,
  type HybridGovernanceProfileUpdateInput,
  type HybridGovernanceQueryInput,
} from './hybrid-governance.schemas';
import { HybridGovernanceService } from './hybrid-governance.service';

const hybridGovernanceService = new HybridGovernanceService();

export const hybridGovernanceRouter = Router();

hybridGovernanceRouter.use(requirePlatformAdmin);

hybridGovernanceRouter.get(
  '/overview',
  validateQuery(hybridGovernanceQuerySchema),
  asyncHandler(async (request, response) => {
    const payload = await hybridGovernanceService.getOverview(
      request.query as unknown as HybridGovernanceQueryInput,
    );
    response.json(payload);
  }),
);

hybridGovernanceRouter.patch(
  '/profile',
  validateBody(hybridGovernanceProfileUpdateSchema),
  asyncHandler(async (request, response) => {
    const payload = await hybridGovernanceService.updateProfile(
      request.body as HybridGovernanceProfileUpdateInput,
    );
    response.json(payload);
  }),
);
