import { env } from '../../config/env';
import { AppError } from '../../shared/http/app-error';
import type {
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

function parseDate(value: string | null) {
  if (value == null) {
    return null;
  }
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function sanitizeProviderPayload(payload: unknown) {
  if (payload == null || typeof payload !== 'object') {
    return payload;
  }
  const record = { ...(payload as Record<string, unknown>) };
  delete record.access_token;
  delete record.token;
  return record;
}
