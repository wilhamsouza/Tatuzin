import { env } from '../../config/env';
import { AppError } from '../../shared/http/app-error';
import type {
  MercadoPagoAuthorizedPaymentDetails,
  MercadoPagoPreapprovalCreateInput,
  MercadoPagoPreapprovalResult,
  MercadoPagoSubscriptionDetails,
} from './billing.types';

type FetchLike = (
  url: string,
  init: {
    method: string;
    headers: Record<string, string>;
    body?: string;
  },
) => Promise<{
  ok: boolean;
  status: number;
  text(): Promise<string>;
}>;

const MERCADO_PAGO_API_BASE_URL = 'https://api.mercadopago.com';

export class MercadoPagoService {
  constructor(
    private readonly accessToken: string | null = null,
    private readonly fetchImpl: FetchLike | null = null,
  ) {}

  async createPreapproval(
    input: MercadoPagoPreapprovalCreateInput,
  ): Promise<MercadoPagoPreapprovalResult> {
    const body = {
      reason: `Tatuzin ${input.plan}`,
      external_reference: input.checkoutSessionId,
      payer_email: input.payerEmail,
      back_url: input.backUrl,
      // Redirect checkout sem card_token_id deve nascer pendente no Mercado Pago.
      status: 'pending',
      ...(input.notificationUrl == null
        ? {}
        : { notification_url: input.notificationUrl }),
      auto_recurring: {
        frequency: 1,
        frequency_type: 'months',
        transaction_amount: input.priceCents / 100,
        currency_id: 'BRL',
      },
    };

    const payload = await this.requestJson('/preapproval', {
      method: 'POST',
      body,
    });

    return {
      id: readString(payload, 'id') ?? input.checkoutSessionId,
      initPoint: readString(payload, 'init_point'),
      sandboxInitPoint: readString(payload, 'sandbox_init_point'),
      status: readString(payload, 'status'),
    };
  }

  async getSubscription(
    providerReference: string,
  ): Promise<MercadoPagoSubscriptionDetails> {
    const payload = await this.requestJson(
      `/preapproval/${encodeURIComponent(providerReference)}`,
      { method: 'GET' },
    );

    return this.toSubscriptionDetails(providerReference, payload);
  }

  async getPayment(paymentId: string): Promise<MercadoPagoSubscriptionDetails> {
    const payload = await this.requestJson(
      `/v1/payments/${encodeURIComponent(paymentId)}`,
      { method: 'GET' },
    );

    const preapprovalId =
      readString(payload, 'preapproval_id') ??
      readNestedString(payload, 'metadata', 'preapproval_id') ??
      paymentId;

    return {
      providerReference: preapprovalId,
      status: readString(payload, 'status'),
      externalReference:
        readString(payload, 'external_reference') ??
        readNestedString(payload, 'metadata', 'external_reference') ??
        readNestedString(payload, 'metadata', 'checkout_session_id'),
      currentPeriodStart: parseDate(readString(payload, 'date_created')),
      currentPeriodEnd: null,
      nextPaymentDate: null,
    };
  }

  async getAuthorizedPayment(
    id: string,
  ): Promise<MercadoPagoAuthorizedPaymentDetails> {
    const authorizedPaymentId = normalizeRequiredId(
      id,
      'MERCADO_PAGO_AUTHORIZED_PAYMENT_ID_REQUIRED',
    );
    const payload = await this.requestJson(
      `/authorized_payments/${encodeURIComponent(authorizedPaymentId)}`,
      { method: 'GET' },
    );

    return this.toAuthorizedPaymentDetails(authorizedPaymentId, payload);
  }

  async searchAuthorizedPaymentsByPreapproval(
    preapprovalId: string,
    options: { limit?: number; offset?: number } = {},
  ): Promise<MercadoPagoAuthorizedPaymentDetails[]> {
    const normalizedPreapprovalId = normalizeRequiredId(
      preapprovalId,
      'MERCADO_PAGO_PREAPPROVAL_ID_REQUIRED',
    );
    const params = new URLSearchParams({
      preapproval_id: normalizedPreapprovalId,
      limit: String(clampInteger(options.limit, 1, 100, 20)),
      offset: String(clampInteger(options.offset, 0, 10000, 0)),
    });
    const payload = await this.requestJson(
      `/authorized_payments/search?${params.toString()}`,
      { method: 'GET' },
    );
    const results = payload.results;
    if (!Array.isArray(results)) {
      return [];
    }
    return results.flatMap((item) => {
      if (item == null || typeof item !== 'object' || Array.isArray(item)) {
        return [];
      }
      const record = item as Record<string, unknown>;
      const authorizedPaymentId =
        readString(record, 'id') ?? readString(record, 'authorized_payment_id');
      if (authorizedPaymentId == null) {
        return [];
      }
      return [this.toAuthorizedPaymentDetails(authorizedPaymentId, record)];
    });
  }

  private toSubscriptionDetails(
    fallbackProviderReference: string,
    payload: Record<string, unknown>,
  ): MercadoPagoSubscriptionDetails {
    return {
      providerReference: readString(payload, 'id') ?? fallbackProviderReference,
      status: readString(payload, 'status'),
      externalReference: readString(payload, 'external_reference'),
      currentPeriodStart: parseDate(
        readString(payload, 'date_created') ??
          readString(payload, 'summarized_start_date'),
      ),
      currentPeriodEnd: parseDate(
        readString(payload, 'end_date') ?? readString(payload, 'next_payment_date'),
      ),
      nextPaymentDate: parseDate(readString(payload, 'next_payment_date')),
    };
  }

  private toAuthorizedPaymentDetails(
    fallbackAuthorizedPaymentId: string,
    payload: Record<string, unknown>,
  ): MercadoPagoAuthorizedPaymentDetails {
    const status = readString(payload, 'status');
    return {
      authorizedPaymentId:
        readString(payload, 'id') ??
        readString(payload, 'authorized_payment_id') ??
        fallbackAuthorizedPaymentId,
      providerSubscriptionId:
        readString(payload, 'preapproval_id') ??
        readNestedString(payload, 'preapproval', 'id') ??
        readNestedString(payload, 'subscription', 'id'),
      status,
      amountCents: readAmountCents(payload),
      currency:
        readString(payload, 'currency_id') ??
        readString(payload, 'currency') ??
        'BRL',
      dueAt: parseDate(
        readString(payload, 'debit_date') ??
          readString(payload, 'scheduled_date') ??
          readString(payload, 'due_date'),
      ),
      paidAt: isPaidAuthorizedPaymentStatus(status)
        ? parseDate(
            readString(payload, 'date_last_updated') ??
              readString(payload, 'date_created'),
          )
        : null,
      failedAt: isFailedAuthorizedPaymentStatus(status)
        ? parseDate(
            readString(payload, 'date_last_updated') ??
              readString(payload, 'date_created'),
          )
        : null,
      periodStart: parseDate(
        readString(payload, 'period_start') ??
          readNestedString(payload, 'period', 'start'),
      ),
      periodEnd: parseDate(
        readString(payload, 'period_end') ??
          readNestedString(payload, 'period', 'end'),
      ),
      invoiceUrl:
        readString(payload, 'invoice_url') ??
        readNestedString(payload, 'transaction_details', 'external_resource_url'),
      payload: sanitizeProviderPayload(payload) as Record<string, unknown>,
    };
  }

  private async requestJson(
    path: string,
    input: { method: 'GET' | 'POST'; body?: Record<string, unknown> },
  ) {
    const accessToken = this.accessToken ?? env.MERCADO_PAGO_ACCESS_TOKEN;
    if (accessToken == null || accessToken.trim().length === 0) {
      throw new AppError(
        'Mercado Pago nao configurado para billing.',
        503,
        'MERCADO_PAGO_NOT_CONFIGURED',
      );
    }

    const fetchImpl = this.fetchImpl ?? (globalThis.fetch as unknown as FetchLike);
    const response = await fetchImpl(`${MERCADO_PAGO_API_BASE_URL}${path}`, {
      method: input.method,
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
        Authorization: `Bearer ${accessToken.trim()}`,
      },
      ...(input.body == null ? {} : { body: JSON.stringify(input.body) }),
    });
    const text = await response.text();
    const payload = text.trim().length === 0 ? {} : JSON.parse(text);

    if (!response.ok) {
      throw new AppError(
        'Mercado Pago nao confirmou a operacao de billing.',
        502,
        'MERCADO_PAGO_REQUEST_FAILED',
        {
          statusCode: response.status,
          payload: sanitizeProviderPayload(payload),
        },
      );
    }

    if (payload == null || typeof payload !== 'object' || Array.isArray(payload)) {
      throw new AppError(
        'Mercado Pago respondeu em formato inesperado.',
        502,
        'MERCADO_PAGO_INVALID_RESPONSE',
      );
    }

    return payload as Record<string, unknown>;
  }
}

function normalizeRequiredId(value: unknown, code: string) {
  const normalized = typeof value === 'string' ? value.trim() : '';
  if (normalized.length === 0) {
    throw new AppError('Identificador Mercado Pago obrigatorio.', 400, code);
  }
  return normalized;
}

function clampInteger(
  value: number | undefined,
  min: number,
  max: number,
  fallback: number,
) {
  if (value == null || !Number.isFinite(value)) {
    return fallback;
  }
  return Math.min(max, Math.max(min, Math.trunc(value)));
}

function readString(source: Record<string, unknown>, key: string) {
  const value = source[key];
  if (typeof value !== 'string') {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length === 0 ? null : trimmed;
}

function readNestedString(
  source: Record<string, unknown>,
  parentKey: string,
  childKey: string,
) {
  const parent = source[parentKey];
  if (parent == null || typeof parent !== 'object' || Array.isArray(parent)) {
    return null;
  }
  return readString(parent as Record<string, unknown>, childKey);
}

function readNumber(source: Record<string, unknown>, key: string) {
  const value = source[key];
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === 'string' && value.trim().length > 0) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function readNestedNumber(
  source: Record<string, unknown>,
  parentKey: string,
  childKey: string,
) {
  const parent = source[parentKey];
  if (parent == null || typeof parent !== 'object' || Array.isArray(parent)) {
    return null;
  }
  return readNumber(parent as Record<string, unknown>, childKey);
}

function readAmountCents(payload: Record<string, unknown>) {
  const amount =
    readNumber(payload, 'transaction_amount') ??
    readNumber(payload, 'amount') ??
    readNestedNumber(payload, 'payment', 'transaction_amount') ??
    readNestedNumber(payload, 'payment', 'amount');
  if (amount == null || amount <= 0) {
    return 0;
  }
  return Math.round(amount * 100);
}

function parseDate(value: string | null) {
  if (value == null) {
    return null;
  }
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function isPaidAuthorizedPaymentStatus(status: string | null) {
  const normalized = status?.trim().toLowerCase();
  return (
    normalized === 'processed' ||
    normalized === 'approved' ||
    normalized === 'authorized' ||
    normalized === 'accredited' ||
    normalized === 'paid'
  );
}

function isFailedAuthorizedPaymentStatus(status: string | null) {
  const normalized = status?.trim().toLowerCase();
  return (
    normalized === 'rejected' ||
    normalized === 'cancelled' ||
    normalized === 'canceled' ||
    normalized === 'failed'
  );
}

function sanitizeProviderPayload(payload: unknown): unknown {
  if (payload == null || typeof payload !== 'object') {
    return payload;
  }
  if (Array.isArray(payload)) {
    return payload.map((item): unknown => sanitizeProviderPayload(item));
  }
  const record: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(payload as Record<string, unknown>)) {
    if (isSensitiveProviderKey(key)) {
      record[key] = '[redacted]';
      continue;
    }
    record[key] = sanitizeProviderPayload(value);
  }
  return record;
}

function isSensitiveProviderKey(key: string) {
  const normalized = key.trim().toLowerCase().replace(/[-\s]/g, '_');
  return (
    normalized === 'access_token' ||
    normalized === 'refresh_token' ||
    normalized === 'authorization' ||
    normalized === 'token' ||
    normalized === 'webhook_secret' ||
    normalized === 'secret' ||
    normalized === 'card' ||
    normalized === 'card_number' ||
    normalized === 'cvv' ||
    normalized === 'security_code' ||
    normalized === 'init_point' ||
    normalized === 'sandbox_init_point'
  );
}
