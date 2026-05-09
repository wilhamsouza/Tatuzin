import { env } from '../../config/env';
import { AppError } from '../../shared/http/app-error';
import { sanitizeForAdmin } from './billing-sanitizer';
import type {
  MercadoPagoAuthorizedPaymentDetails,
  MercadoPagoPreapprovalCreateInput,
  MercadoPagoPreapprovalResult,
  MercadoPagoPreapprovalUpdateInput,
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
    const safeProviderReference = assertNonEmptyProviderId(
      providerReference,
      'preapprovalId',
    );
    const payload = await this.requestJson(
      `/preapproval/${encodeURIComponent(safeProviderReference)}`,
      { method: 'GET' },
    );

    return this.toSubscriptionDetails(safeProviderReference, payload);
  }

  async getPreapproval(
    preapprovalId: string,
  ): Promise<MercadoPagoSubscriptionDetails> {
    return this.getSubscription(preapprovalId);
  }

  async updatePreapproval(
    preapprovalId: string,
    body: MercadoPagoPreapprovalUpdateInput,
  ): Promise<MercadoPagoSubscriptionDetails> {
    const safePreapprovalId = assertNonEmptyProviderId(
      preapprovalId,
      'preapprovalId',
    );
    const payload = await this.requestJson(
      `/preapproval/${encodeURIComponent(safePreapprovalId)}`,
      { method: 'PUT', body },
    );

    return this.toSubscriptionDetails(safePreapprovalId, payload);
  }

  async getAuthorizedPayment(
    paymentId: unknown,
  ): Promise<MercadoPagoAuthorizedPaymentDetails> {
    const safePaymentId = assertNonEmptyProviderId(paymentId, 'paymentId');
    const payload = await this.requestJson(
      `/authorized_payments/${encodeURIComponent(safePaymentId)}`,
      { method: 'GET' },
    );

    return this.toAuthorizedPaymentDetails(payload, safePaymentId);
  }

  async searchAuthorizedPaymentsByPreapproval(
    preapprovalId: unknown,
    options: { limit?: number; offset?: number } = {},
  ): Promise<MercadoPagoAuthorizedPaymentDetails[]> {
    const safePreapprovalId = assertNonEmptyProviderId(
      preapprovalId,
      'preapprovalId',
    );
    const params = new URLSearchParams({
      preapproval_id: safePreapprovalId,
      limit: String(clampInteger(options.limit, 50, 1, 100)),
      offset: String(clampInteger(options.offset, 0, 0, 10_000)),
    });
    const payload = await this.requestJson(
      `/authorized_payments/search?${params.toString()}`,
      { method: 'GET' },
    );
    const results =
      readArray(payload, 'results') ?? readArray(payload, 'items') ?? [];

    return results.flatMap((item) => {
      if (item == null || typeof item !== 'object' || Array.isArray(item)) {
        return [];
      }
      return [
        this.toAuthorizedPaymentDetails(item as Record<string, unknown>, null),
      ];
    });
  }

  async getPayment(paymentId: string): Promise<MercadoPagoSubscriptionDetails> {
    const safePaymentId = assertNonEmptyProviderId(paymentId, 'paymentId');
    const payload = await this.requestJson(
      `/v1/payments/${encodeURIComponent(safePaymentId)}`,
      { method: 'GET' },
    );

    const preapprovalId =
      readString(payload, 'preapproval_id') ??
      readNestedString(payload, 'metadata', 'preapproval_id') ??
      safePaymentId;

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
        readString(payload, 'end_date') ??
          readString(payload, 'next_payment_date'),
      ),
      nextPaymentDate: parseDate(readString(payload, 'next_payment_date')),
      amountCents: readAmountCents(payload),
      paymentMethodId:
        readString(payload, 'payment_method_id') ??
        readNestedString(payload, 'payment_method', 'id'),
      paymentMethodType:
        readNestedString(payload, 'payment_method', 'type') ??
        readString(payload, 'payment_method_type'),
      lastFour:
        readNestedString(payload, 'card', 'last_four_digits') ??
        readNestedString(payload, 'payment_method', 'last_four_digits'),
      rawPayload: sanitizeProviderPayload(payload) as Record<string, unknown>,
    };
  }

  private toAuthorizedPaymentDetails(
    payload: Record<string, unknown>,
    fallbackAuthorizedPaymentId: string | null,
  ): MercadoPagoAuthorizedPaymentDetails {
    const authorizedPaymentId =
      readString(payload, 'id') ??
      readString(payload, 'authorized_payment_id') ??
      fallbackAuthorizedPaymentId;
    const status = readString(payload, 'status');
    const lastProviderUpdate =
      readString(payload, 'date_last_updated') ??
      readString(payload, 'last_modified') ??
      readString(payload, 'date_created');

    return {
      authorizedPaymentId,
      providerInvoiceId:
        readString(payload, 'providerInvoiceId') ??
        readString(payload, 'provider_invoice_id') ??
        authorizedPaymentId,
      providerSubscriptionId:
        readString(payload, 'preapproval_id') ??
        readString(payload, 'subscription_id') ??
        readNestedString(payload, 'preapproval', 'id') ??
        readNestedString(payload, 'subscription', 'id'),
      status,
      amountCents: readAmountCents(payload) ?? 0,
      currency:
        readString(payload, 'currency_id') ??
        readString(payload, 'currency') ??
        'BRL',
      periodStart:
        parseDate(readString(payload, 'period_start')) ??
        parseDate(readNestedString(payload, 'period', 'start')) ??
        parseDate(readString(payload, 'date_created')),
      periodEnd:
        parseDate(readString(payload, 'period_end')) ??
        parseDate(readNestedString(payload, 'period', 'end')),
      dueAt: parseDate(
        readString(payload, 'debit_date') ??
          readString(payload, 'due_date') ??
          readString(payload, 'scheduled_date'),
      ),
      paidAt: isPaidAuthorizedPaymentStatus(status)
        ? parseDate(
            readString(payload, 'payment_date') ??
              readString(payload, 'date_approved') ??
              lastProviderUpdate,
          )
        : null,
      failedAt: isFailedAuthorizedPaymentStatus(status)
        ? parseDate(lastProviderUpdate)
        : null,
      invoiceUrl:
        readString(payload, 'invoice_url') ??
        readString(payload, 'payment_url') ??
        readString(payload, 'external_resource_url') ??
        readNestedString(payload, 'transaction_details', 'external_resource_url'),
      rawPayload: sanitizeProviderPayload(payload) as Record<string, unknown>,
    };
  }

  private async requestJson(
    path: string,
    input: { method: 'GET' | 'POST' | 'PUT'; body?: Record<string, unknown> },
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
    let payload: unknown;
    try {
      payload = text.trim().length === 0 ? {} : JSON.parse(text);
    } catch {
      throw new AppError(
        'Mercado Pago respondeu em formato inesperado.',
        502,
        'MERCADO_PAGO_INVALID_RESPONSE',
      );
    }

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

function assertNonEmptyProviderId(value: unknown, fieldName: string) {
  const trimmed = typeof value === 'string' ? value.trim() : '';
  if (trimmed.length === 0) {
    throw new AppError(
      'Identificador Mercado Pago invalido.',
      400,
      'MERCADO_PAGO_PROVIDER_ID_INVALID',
      { field: fieldName },
    );
  }
  return trimmed;
}

function clampInteger(
  value: number | undefined,
  defaultValue: number,
  min: number,
  max: number,
) {
  if (value == null || !Number.isFinite(value)) {
    return defaultValue;
  }
  return Math.min(max, Math.max(min, Math.trunc(value)));
}

function readArray(source: Record<string, unknown>, key: string) {
  const value = source[key];
  return Array.isArray(value) ? value : null;
}

function readString(source: Record<string, unknown>, key: string) {
  const value = source[key];
  if (typeof value !== 'string') {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length === 0 ? null : trimmed;
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

function readAmountCents(source: Record<string, unknown>) {
  const cents = readNumber(source, 'amount_cents');
  if (cents != null) {
    return Math.round(cents);
  }
  const transactionAmount =
    readNumber(source, 'transaction_amount') ??
    readNumber(source, 'amount') ??
    readNestedNumber(source, 'auto_recurring', 'transaction_amount') ??
    readNestedNumber(source, 'payment', 'transaction_amount') ??
    readNestedNumber(source, 'payment', 'amount');
  return transactionAmount == null ? null : Math.round(transactionAmount * 100);
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

function parseDate(value: string | null) {
  if (value == null) {
    return null;
  }
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function sanitizeProviderPayload(payload: unknown) {
  return sanitizeForAdmin(payload);
}

function isPaidAuthorizedPaymentStatus(status: string | null) {
  const normalized = status?.trim().toLowerCase();
  return (
    normalized === 'processed' ||
    normalized === 'approved' ||
    normalized === 'authorized' ||
    normalized === 'accredited' ||
    normalized === 'active' ||
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
