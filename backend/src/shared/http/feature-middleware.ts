import type { NextFunction, Request, RequestHandler, Response } from 'express';

import type { FeatureKey } from '../../modules/plans/plan-catalog.service';
import { requiredPlanForFeature } from '../../modules/plans/plan-catalog.service';
import { AppError } from './app-error';

const FEATURE_NOT_AVAILABLE_MESSAGE =
  'Este recurso não está disponível no seu plano atual.';

export function requireFeature(feature: FeatureKey): RequestHandler {
  return (request: Request, _response: Response, next: NextFunction) => {
    const appContext = request.appContext;
    if (appContext == null) {
      next(
        new AppError(
          'Contexto de aplicativo ausente.',
          401,
          'APP_CONTEXT_REQUIRED',
        ),
      );
      return;
    }

    if (appContext.features[feature] === true) {
      next();
      return;
    }

    next(
      new AppError(
        FEATURE_NOT_AVAILABLE_MESSAGE,
        403,
        'FEATURE_NOT_AVAILABLE',
        {
          feature,
          requiredPlan: requiredPlanForFeature(feature),
        },
      ),
    );
  };
}
