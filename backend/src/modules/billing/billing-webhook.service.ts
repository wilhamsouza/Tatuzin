import { createHash, createHmac, timingSafeEqual } from 'crypto';

import { Prisma } from '@prisma/client';

import { env } from '../../config/env';
import { prisma } from '../../database/prisma';
import { AppError } from '../../shared/http/app-error';
import { logger } from '../../shared/observability/logger';
import { BillingService } from './billing.service';
import type { MercadoPagoWebhookContext } from './billing.types';
import { MercadoPagoService } from './mercado-pago.service';

const PROVIDER = 'mercadopago';

export class BillingWebhookService {
  constructor(
    private readonly billingService = new BillingService(),
    private readonly mercadoPagoService = new MercadoPagoService(),
  ) {}

  async handleMercadoPagoWebhook(context: MercadoPagoWebhookContext) {
    this.assertValidSignature(context);

    const eventType = readEventType(context);
    const dataId = readDataId(context);
    const providerEventId = readProviderEventId(context, eventType, dataId);
    const dedupeKey = buildDedupeKey(context, {
      eventType,
      dataId,
      providerEventId,
    });
    const payload = buildStoredPayload(context);

    const event = await prisma.billingProviderEvent.upsert({
      where: {
        provider_dedupeKey: {
          provider: PROVIDER,
          dedupeKey,
        },
      },
      create: {
        provider: PROVIDER,
        eventType,
        providerEventId,
        dedupeKey,
        payload,
        status: 'RECEIVED',
      },
      update: {
        eventType,
        providerEventId,
        payload,
      },
    });

    if (
      event.status === 'PROCESSED' ||
      event.status === 'IGNORED' ||
      event.status === 'IGNORED_UNKNOWN'
    ) {
      return { ok: true, duplicate: true, status: event.status };
    }

    if (dataId == null) {
      await this.markEvent(event.id, 'IGNORED', 'missing_data_id');
      return { ok: true, status: 'IGNORED' };
    }

    try {
      const result = isSubscriptionAuthorizedPaymentEvent(eventType)
        ? await this.billingService.applyMercadoPagoAuthorizedPayment(
            await this.mercadoPagoService.getAuthorizedPayment(dataId),
          )
        : await this.billingService.applyMercadoPagoDetails(
            isPaymentEvent(eventType)
              ? await this.mercadoPagoService.getPayment(dataId)
              : await this.mercadoPagoService.getSubscription(dataId),
          );

      const nextStatus =
        result.action === 'ignored_unknown'
          ? 'IGNORED_UNKNOWN'
          : result.action === 'ignored_missing_session'
            ? 'IGNORED'
            : 'PROCESSED';
      const errorMessage =
        nextStatus === 'PROCESSED'
          ? null
          : `${result.action}:${result.providerStatus}`;

      await this.markEvent(event.id, nextStatus, errorMessage, true, result.companyId);

      return {
        ok: true,
        status: nextStatus,
        action: result.action,
        providerStatus: result.providerStatus,
      };
    } catch (error) {
      await this.markEvent(
        event.id,
        'FAILED_RETRYABLE',
        error instanceof Error ? error.message : String(error),
        false,
      );
      logger.warn('billing.webhook.mercadopago.retryable_failure', {
        eventType,
        providerEventId,
        dedupeKey,
        error: error instanceof Error ? error.message : String(error),
      });
      return { ok: true, status: 'FAILED_RETRYABLE' };
    }
  }

  private assertValidSignature(context: MercadoPagoWebhookContext) {
    const secret = env.MERCADO_PAGO_WEBHOOK_SECRET;
    if (secret == null || secret.trim().length === 0) {
      if (env.isProduction) {
        throw new AppError(
          'Assinatura do webhook Mercado Pago nao configurada.',
          401,
          'MERCADO_PAGO_WEBHOOK_SIGNATURE_REQUIRED',
        );
      }
      logger.warn('billing.webhook.mercadopago.signature_skipped_non_production');
      return;
    }

    const signature = context.headers['x-signature'];
    const requestId = context.headers['x-request-id'];
    const dataId = readDataId(context);
    const parsedSignature = parseMercadoPagoSignature(signature);

    if (
      requestId == null ||
      requestId.trim().length === 0 ||
      dataId == null ||
      parsedSignature == null
    ) {
      throw new AppError(
        'Assinatura do webhook Mercado Pago invalida.',
        401,
        'MERCADO_PAGO_WEBHOOK_SIGNATURE_INVALID',
      );
    }

    // Mercado Pago signs id:{data.id};request-id:{x-request-id};ts:{ts};.
    // Keep data.id as received; only lowercase it if official docs confirm that rule.
    const manifest = `id:${dataId};request-id:${requestId.trim()};ts:${parsedSignature.ts};`;
    const expected = createHmac('sha256', secret.trim())
      .update(manifest)
      .digest('hex');

    if (!safeEquals(expected, parsedSignature.v1)) {
      throw new AppError(
        'Assinatura do webhook Mercado Pago invalida.',
        401,
        'MERCADO_PAGO_WEBHOOK_SIGNATURE_INVALID',
      );
    }
  }

  private async markEvent(
    eventId: string,
    status: string,
    errorMessage: string | null,
    processed = true,
    companyId: string | null = null,
  ) {
    await prisma.billingProviderEvent.update({
      where: { id: eventId },
      data: {
        ...(companyId == null ? {} : { companyId }),
        status,
        errorMessage,
        processedAt: processed ? new Date() : null,
      },
    });
  }
}

function readEventType(context: MercadoPagoWebhookContext) {
  return (
    readString(context.body, 'type') ??
    readString(context.body, 'action') ??
    readString(context.query, 'type') ??
    'unknown'
  );
}

function readDataId(context: MercadoPagoWebhookContext) {
  return (
    readNestedString(context.query, 'data', 'id') ??
    readNestedString(context.body, 'data', 'id') ??
    readString(context.query, 'data.id') ??
    readString(context.body, 'id')
  );
}

function readProviderEventId(
  context: MercadoPagoWebhookContext,
  eventType: string,
  dataId: string | null,
) {
  return (
    readString(context.body, 'id') ??
    readString(context.query, 'id') ??
    (dataId == null
      ? null
      : `${eventType}:${dataId}:${context.headers['x-request-id'] ?? 'no-request-id'}`)
  );
}

function buildDedupeKey(
  context: MercadoPagoWebhookContext,
  input: {
    eventType: string;
    dataId: string | null;
    providerEventId: string | null;
  },
) {
  const parts = [
    input.providerEventId,
    input.eventType,
    input.dataId,
    context.headers['x-request-id'] ?? null,
  ].filter((value): value is string => value != null && value.length > 0);

  const source =
    parts.length > 0
      ? parts.join('|')
      : JSON.stringify(buildStoredPayload(context));
  return createHash('sha256').update(source).digest('hex');
}

function buildStoredPayload(context: MercadoPagoWebhookContext) {
  const payload = {
    body: context.body,
    query: context.query,
    headers: {
      'x-request-id': context.headers['x-request-id'] ?? null,
      'x-signature': context.headers['x-signature'] == null ? null : '[present]',
    },
  };
  return JSON.parse(JSON.stringify(payload)) as Prisma.InputJsonObject;
}

function isPaymentEvent(eventType: string) {
  const normalized = eventType.trim().toLowerCase();
  return normalized === 'payment' || normalized.startsWith('payment.');
}

function isSubscriptionAuthorizedPaymentEvent(eventType: string) {
  const normalized = eventType.trim().toLowerCase();
  return (
    normalized === 'subscription_authorized_payment' ||
    normalized.startsWith('subscription_authorized_payment.')
  );
}

function parseMercadoPagoSignature(signature: string | undefined) {
  if (signature == null) {
    return null;
  }
  const parts = new Map(
    signature
      .split(',')
      .map((part) => part.trim().split('='))
      .filter((part): part is [string, string] => part.length === 2),
  );
  const ts = parts.get('ts')?.trim();
  const v1 = parts.get('v1')?.trim();
  if (ts == null || ts.length === 0 || v1 == null || v1.length === 0) {
    return null;
  }
  return { ts, v1 };
}

function safeEquals(left: string, right: string) {
  const leftBuffer = Buffer.from(left, 'utf8');
  const rightBuffer = Buffer.from(right, 'utf8');
  return (
    leftBuffer.length === rightBuffer.length &&
    timingSafeEqual(leftBuffer, rightBuffer)
  );
}

function readString(source: Record<string, unknown>, key: string) {
  const value = source[key];
  if (Array.isArray(value)) {
    return typeof value[0] === 'string' && value[0].trim().length > 0
      ? value[0].trim()
      : null;
  }
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
