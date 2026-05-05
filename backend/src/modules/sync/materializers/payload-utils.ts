import type { Prisma } from '@prisma/client';

import type { SyncPushEventInput } from '../sync.schemas';

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function asRecord(value: unknown): Record<string, unknown> {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) {
    return {};
  }

  return value as Record<string, unknown>;
}

export function firstString(
  payload: Record<string, unknown>,
  keys: string[],
): string | null {
  for (const key of keys) {
    const value = payload[key];
    if (typeof value === 'string' && value.trim().length > 0) {
      return value.trim();
    }
  }

  return null;
}

export function firstIdentity(
  payload: Record<string, unknown>,
  keys: string[],
): string | null {
  for (const key of keys) {
    const value = payload[key];
    if (typeof value === 'string' && value.trim().length > 0) {
      return value.trim();
    }
    if (
      typeof value === 'number' &&
      Number.isFinite(value) &&
      Number.isInteger(value)
    ) {
      return value.toString();
    }
  }

  return null;
}

export function localIdentityFor(
  event: SyncPushEventInput,
  payload: Record<string, unknown>,
) {
  return (
    clean(event.entityLocalId) ??
    firstIdentity(payload, [
      'uuid',
      'localUuid',
      'localId',
      'id',
      'localMovementUuid',
      'receiptNumber',
      'number',
      'idempotencyKey',
    ])
  );
}

export function firstUuid(
  payload: Record<string, unknown>,
  keys: string[],
): string | null {
  const value = firstString(payload, keys);
  return value != null && uuidPattern.test(value) ? value : null;
}

export function isUuid(value: string | null | undefined) {
  return value != null && uuidPattern.test(value);
}

export function firstInt(
  payload: Record<string, unknown>,
  keys: string[],
): number | null {
  for (const key of keys) {
    const value = payload[key];
    if (typeof value === 'number' && Number.isFinite(value)) {
      return Math.trunc(value);
    }
    if (typeof value === 'string' && value.trim().length > 0) {
      const parsed = Number(value);
      if (Number.isFinite(parsed)) {
        return Math.trunc(parsed);
      }
    }
  }

  return null;
}

export function positiveInt(
  payload: Record<string, unknown>,
  keys: string[],
) {
  const value = firstInt(payload, keys);
  return value != null && value > 0 ? value : null;
}

export function nonNegativeInt(
  payload: Record<string, unknown>,
  keys: string[],
) {
  const value = firstInt(payload, keys);
  return value != null && value >= 0 ? value : null;
}

export function absPositiveInt(
  payload: Record<string, unknown>,
  keys: string[],
) {
  const value = firstInt(payload, keys);
  if (value == null || value === 0) {
    return null;
  }
  return Math.abs(value);
}

export function firstDate(
  payload: Record<string, unknown>,
  keys: string[],
  fallback: Date,
) {
  const value = firstString(payload, keys);
  if (value == null) {
    return fallback;
  }

  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? fallback : date;
}

export function normalizeCashSessionStatus(raw: string | null) {
  const status = raw?.trim().toLowerCase();
  if (status == null || status.length === 0) {
    return 'open';
  }
  if (['closed', 'finished', 'finalized', 'fechado', 'fechada'].includes(status)) {
    return 'closed';
  }
  if (['open', 'opened', 'active', 'aberto', 'aberta'].includes(status)) {
    return 'open';
  }
  return status;
}

export function isClosedStatus(raw: string | null) {
  return normalizeCashSessionStatus(raw) === 'closed';
}

export function isOpenStatus(raw: string | null) {
  return normalizeCashSessionStatus(raw) === 'open';
}

export function jsonPayload(
  payload: Record<string, unknown>,
): Prisma.InputJsonValue {
  return payload as Prisma.InputJsonValue;
}

function clean(value: string | null | undefined) {
  const trimmed = value?.trim();
  return trimmed == null || trimmed.length === 0 ? null : trimmed;
}
