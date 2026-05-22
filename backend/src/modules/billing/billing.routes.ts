import { Router } from "express";

import { requireAppContext } from "../../shared/http/auth-middleware";
import { asyncHandler } from "../../shared/http/async-handler";
import { buildPaginatedResponse } from "../../shared/http/api-response";
import { createRateLimit } from "../../shared/http/rate-limit";
import { validateBody, validateQuery } from "../../shared/http/validate";
import {
  billingCancelSchema,
  billingChangePlanSchema,
  billingInvoicesQuerySchema,
  billingSubscribeSchema,
} from "./billing.schemas";
import { BillingService } from "./billing.service";
import { BillingWebhookService } from "./billing-webhook.service";

const billingService = new BillingService();
const webhookService = new BillingWebhookService();

export const billingRouter = Router();
export const mercadoPagoWebhookRouter = Router();

billingRouter.get(
  "/plans",
  asyncHandler(async (_request, response) => {
    response.json({ items: billingService.listPlans() });
  }),
);

billingRouter.get(
  "/return",
  asyncHandler(async (_request, response) => {
    response.status(200).type("html").send(renderBillingReturnPage());
  }),
);

billingRouter.get(
  "/status",
  requireAppContext,
  asyncHandler(async (request, response) => {
    const status = await billingService.getStatusForContext(
      request.appContext!,
    );
    response.json(status);
  }),
);

billingRouter.post(
  "/subscribe",
  requireAppContext,
  validateBody(billingSubscribeSchema),
  asyncHandler(async (request, response) => {
    const result = await billingService.subscribe(
      request.appContext!,
      request.body,
      { requestId: request.requestId },
    );
    response.status(result.checkoutUrl == null ? 200 : 201).json(result);
  }),
);

billingRouter.post(
  "/refresh",
  requireAppContext,
  createRateLimit({
    name: "billing_refresh",
    windowMs: 60_000,
    max: 4,
    message:
      "Muitas atualizacoes de assinatura em pouco tempo. Aguarde um instante e tente novamente.",
    code: "BILLING_REFRESH_RATE_LIMITED",
    keyGenerator(request) {
      const auth = request.auth;
      return auth == null
        ? (request.ip ?? "unknown-billing-refresh")
        : `${auth.companyId}:${auth.userId}`;
    },
  }),
  asyncHandler(async (request, response) => {
    const status = await billingService.refresh(request.appContext!);
    response.json(status);
  }),
);

billingRouter.get(
  "/invoices",
  requireAppContext,
  validateQuery(billingInvoicesQuerySchema),
  asyncHandler(async (request, response) => {
    const result = await billingService.listInvoices(
      request.appContext!,
      request.query as unknown as Parameters<
        typeof billingService.listInvoices
      >[1],
    );
    response.json(buildPaginatedResponse(result));
  }),
);

billingRouter.get(
  "/invoices/:id",
  requireAppContext,
  asyncHandler(async (request, response) => {
    const invoice = await billingService.getInvoice(
      request.appContext!,
      readParam(request.params.id),
    );
    response.json(invoice);
  }),
);

billingRouter.get(
  "/payment-method",
  requireAppContext,
  asyncHandler(async (request, response) => {
    const paymentMethod = await billingService.getPaymentMethod(
      request.appContext!,
    );
    response.json(paymentMethod);
  }),
);

billingRouter.post(
  "/cancel",
  requireAppContext,
  validateBody(billingCancelSchema),
  asyncHandler(async (request, response) => {
    const result = await billingService.cancelSubscription(
      request.appContext!,
      request.body,
    );
    response.json(result);
  }),
);

billingRouter.post(
  "/resume",
  requireAppContext,
  asyncHandler(async (request, response) => {
    const result = await billingService.resumeSubscription(request.appContext!);
    response.json(result);
  }),
);

billingRouter.post(
  "/change-plan",
  requireAppContext,
  validateBody(billingChangePlanSchema),
  asyncHandler(async (request, response) => {
    const result = await billingService.changePlan(
      request.appContext!,
      request.body,
    );
    response.json(result);
  }),
);

mercadoPagoWebhookRouter.post(
  "/mercadopago",
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
  if (value == null || typeof value !== "object" || Array.isArray(value)) {
    return {};
  }
  return value as Record<string, unknown>;
}

function readParam(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : (value ?? "");
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

function renderBillingReturnPage() {
  return `<!doctype html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Assinatura recebida - Tatuzin</title>
  <style>
    :root {
      color-scheme: light dark;
      --bg: #0f172a;
      --card: #111827;
      --text: #f8fafc;
      --muted: #cbd5e1;
      --accent: #38bdf8;
    }
    @media (prefers-color-scheme: light) {
      :root {
        --bg: #f8fafc;
        --card: #ffffff;
        --text: #0f172a;
        --muted: #475569;
        --accent: #0284c7;
      }
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      display: grid;
      place-items: center;
      padding: 24px;
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: var(--bg);
      color: var(--text);
    }
    main {
      width: min(100%, 520px);
      padding: 28px;
      border-radius: 16px;
      background: var(--card);
      box-shadow: 0 18px 50px rgba(15, 23, 42, 0.22);
    }
    h1 {
      margin: 0 0 12px;
      font-size: clamp(1.8rem, 5vw, 2.4rem);
      line-height: 1.1;
    }
    p {
      margin: 0 0 12px;
      color: var(--muted);
      font-size: 1rem;
      line-height: 1.55;
    }
    .brand {
      margin-top: 22px;
      color: var(--accent);
      font-weight: 700;
    }
  </style>
</head>
<body>
  <main>
    <h1>Assinatura recebida</h1>
    <p>Volte para o app Tatuzin e toque em Atualizar status.</p>
    <p>Se o pagamento ainda não aparecer, aguarde alguns instantes.</p>
    <p class="brand">Tatuzin ERP</p>
  </main>
</body>
</html>`;
}
