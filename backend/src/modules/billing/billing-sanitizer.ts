import { createHash } from 'crypto';

const REDACTED = '[redacted]';

const SENSITIVE_KEYS = new Set([
  'authorization',
  'access_token',
  'token',
  'mercado_pago_access_token',
  'mercado_pago_webhook_secret',
  'x-signature',
  'card',
  'card_number',
  'security_code',
  'cvv',
]);

const URL_KEYS = new Set([
  'checkouturl',
  'sandboxcheckouturl',
  'checkout_url',
  'sandbox_checkout_url',
  'init_point',
  'sandbox_init_point',
]);

export function sanitizeForAdmin<T>(value: T): T {
  return sanitizeValue(value, null) as T;
}

export function maskProviderSubscriptionId(value: string | null | undefined) {
  if (value == null || value.trim().length === 0) {
    return null;
  }
  const trimmed = value.trim();
  if (trimmed.length <= 8) {
    return '****';
  }
  return `${trimmed.slice(0, 4)}...${trimmed.slice(-4)}`;
}

export function maskUrl(value: string | null | undefined) {
  if (value == null || value.trim().length === 0) {
    return null;
  }
  const trimmed = value.trim();
  const hash = createHash('sha256').update(trimmed).digest('hex').slice(0, 12);
  try {
    const parsed = new URL(trimmed);
    return `${parsed.origin}/...#${hash}`;
  } catch {
    return `masked-url#${hash}`;
  }
}

function sanitizeValue(value: unknown, key: string | null): unknown {
  if (value == null) {
    return value;
  }
  if (value instanceof Date) {
    return value;
  }
  if (Array.isArray(value)) {
    return value.map((item) => sanitizeValue(item, null));
  }
  if (typeof value !== 'object') {
    if (typeof value === 'string' && key != null && isUrlKey(key)) {
      return maskUrl(value);
    }
    return value;
  }

  const output: Record<string, unknown> = {};
  for (const [entryKey, entryValue] of Object.entries(
    value as Record<string, unknown>,
  )) {
    if (isSensitiveKey(entryKey)) {
      output[entryKey] = REDACTED;
      continue;
    }
    if (isUrlKey(entryKey) && typeof entryValue === 'string') {
      output[entryKey] = maskUrl(entryValue);
      continue;
    }
    output[entryKey] = sanitizeValue(entryValue, entryKey);
  }
  return output;
}

function isSensitiveKey(key: string) {
  const normalized = normalizeKey(key);
  return (
    SENSITIVE_KEYS.has(normalized) ||
    normalized.includes('authorization') ||
    normalized.includes('access_token') ||
    normalized.includes('token') ||
    normalized.includes('webhook_secret') ||
    normalized.includes('security_code') ||
    normalized.includes('card_number')
  );
}

function isUrlKey(key: string) {
  return URL_KEYS.has(normalizeKey(key));
}

function normalizeKey(key: string) {
  return key.trim().toLowerCase();
}
