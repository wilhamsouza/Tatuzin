import type { Request } from 'express';

const REDACTED = '[redacted]';

const SENSITIVE_QUERY_KEYS = new Set([
  'token',
  'access_token',
  'refresh_token',
  'authorization',
  'signature',
  'secret',
  'password',
  'code',
  'data.id',
  'payment_id',
  'external_reference',
  'email',
  'phone',
  'document',
  'cpf',
  'cnpj',
]);

type RequestUrlFields = Pick<Request, 'path' | 'originalUrl' | 'url'>;

export function safeRequestPath(request: RequestUrlFields) {
  const path = normalizePath(request.path);
  if (path != null) {
    return path;
  }

  return pathOnly(request.originalUrl ?? request.url ?? '/');
}

export function sanitizeUrlForLogging(rawUrl: string) {
  const [path = '/', query = ''] = rawUrl.split('?', 2);
  const normalizedPath = normalizePath(path) ?? '/';
  if (query.length === 0) {
    return normalizedPath;
  }

  const params = new URLSearchParams(query);
  for (const key of [...params.keys()]) {
    if (isSensitiveQueryKey(key)) {
      params.set(key, REDACTED);
    }
  }

  const sanitizedQuery = params.toString();
  return sanitizedQuery.length === 0
    ? normalizedPath
    : `${normalizedPath}?${sanitizedQuery}`;
}

function pathOnly(rawUrl: string) {
  return sanitizeUrlForLogging(rawUrl).split('?', 1)[0] ?? '/';
}

function normalizePath(value: string | undefined) {
  if (value == null) {
    return null;
  }

  const trimmed = value.trim();
  if (trimmed.length === 0) {
    return null;
  }

  const [path = '/'] = trimmed.split('?', 1);
  return path.length === 0 ? '/' : path;
}

function isSensitiveQueryKey(key: string) {
  const normalized = key.trim().toLowerCase();
  return (
    SENSITIVE_QUERY_KEYS.has(normalized) ||
    normalized.includes('token') ||
    normalized.includes('authorization') ||
    normalized.includes('signature') ||
    normalized.includes('secret') ||
    normalized.includes('password')
  );
}
