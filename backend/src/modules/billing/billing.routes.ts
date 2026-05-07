import { Router } from 'express';

import { requireAppContext } from '../../shared/http/auth-middleware';
import { asyncHandler } from '../../shared/http/async-handler';
import { createRateLimit } from '../../shared/http/rate-limit';
import { validateBody } from '../../shared/http/validate';
import { billingSubscribeSchema } from './billing.schemas';
import { BillingService } from './billing.service';
import { BillingWebhookService } from './billing-webhook.service';

const billingService = new BillingService();
const webhookService = new BillingWebhookService();

export const billingRouter = Router();
export const mercadoPagoWebhookRouter = Router();

billingRouter.get(
  '/plans',
  asyncHandler(async (_request, response) => {
    response.json({ items: billingService.listPlans() });
  }),
);

billingRouter.get(
  '/status',
  requireAppContext,
  asyncHandler(async (request, response) => {
    const status = await billingService.getStatusForContext(request.appContext!);
    response.json(status);
  }),
);

billingRouter.post(
  '/subscribe',
  requireAppContext,
  validateBody(billingSubscribeSchema),
  asyncHandler(async (request, response) => {
    const result = await billingService.subscribe(
      request.appContext!,
      request.body,
    );
    response.status(result.checkoutUrl == null ? 200 : 201).json(result);
  }),
);

billingRouter.post(
  '/refresh',
  requireAppContext,
  createRateLimit({
    name: 'billing_refresh',
    windowMs: 60_000,
    max: 4,
    message:
      'Muitas atualizacoes de assinatura em pouco tempo. Aguarde um instante e tente novamente.',
    code: 'BILLING_REFRESH_RATE_LIMITED',
    keyGenerator(request) {
      const auth = request.auth;
      return auth == null
        ? request.ip ?? 'unknown-billing-refresh'
        : `${auth.companyId}:${auth.userId}`;
    },
  }),
  asyncHandler(async (request, response) => {
    const status = await billingService.refresh(request.appContext!);
    response.json(status);
  }),
);

mercadoPagoWebhookRouter.post(
  '/mercadopago',
  asyncHandler(async (request, response) => {
    const result = await webhookService.handleMercadoPagoWebhook({
      body: normalizeRecord(request.body),
      query: normalizeRecord(request.query),
      headers: normalizeHeaders(request.headers),
    });
    response.status(200).json(result);
  }),
);

function normalizeRecord(value: unknown): Record<string, unknown> {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) {
    return {};
  }
  return value as Record<string, unknown>;
}

function normalizeHeaders(
  headers: Record<string, string | string[] | undefined>,
) {
  const normalized: Record<string, string | undefined> = {};
  for (const [key, value] of Object.entries(headers)) {
    normalized[key.toLowerCase()] = Array.isArray(value) ? value[0] : value;
  }
  return normalized;
}
