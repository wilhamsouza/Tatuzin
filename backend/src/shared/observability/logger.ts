type LogLevel = "info" | "warn" | "error";

type LogContext = Record<string, unknown>;

type SerializableError = {
  name: string;
  message: string;
  stack?: string;
  cause?: unknown;
  [key: string]: unknown;
};

const REDACTED = "[redacted]";
const CIRCULAR = "[circular]";
const TRUNCATED = "[truncated]";
const MAX_DEPTH = 8;
const MAX_COLLECTION_ITEMS = 100;
const MAX_STRING_LENGTH = 8000;
const MAX_STACK_LENGTH = 16000;

const sensitiveKeys = new Set(
  [
    "password",
    "passwordHash",
    "token",
    "accessToken",
    "refreshToken",
    "resetToken",
    "verificationToken",
    "secret",
    "clientSecret",
    "apiKey",
    "authorization",
    "proxy-authorization",
    "cookie",
    "set-cookie",
    "credential",
    "credentials",
    "privateKey",
    "session",
    "sessionId",
  ].map(normalizeSensitiveKey),
);

function normalizeContext(context: LogContext | undefined) {
  if (context == null) {
    return undefined;
  }

  const normalized = serializeObjectEntries(context, 0, new WeakSet<object>());
  if (Object.keys(normalized).length === 0) {
    return undefined;
  }

  return normalized;
}

function serializeValue(
  value: unknown,
  depth: number,
  ancestors: WeakSet<object>,
): unknown {
  if (depth > MAX_DEPTH) {
    return TRUNCATED;
  }

  if (
    value == null ||
    typeof value === "number" ||
    typeof value === "boolean"
  ) {
    return value;
  }

  if (typeof value === "string") {
    return sanitizeString(value, MAX_STRING_LENGTH);
  }

  if (typeof value === "bigint") {
    return value.toString();
  }

  if (typeof value === "symbol" || typeof value === "function") {
    return String(value);
  }

  if (value instanceof Date) {
    return value.toISOString();
  }

  if (value instanceof Error) {
    return serializeError(value, depth, ancestors);
  }

  if (Array.isArray(value)) {
    return serializeArray(value, depth, ancestors);
  }

  if (value instanceof Map) {
    return serializeArray(Array.from(value.entries()), depth, ancestors);
  }

  if (value instanceof Set) {
    return serializeArray(Array.from(value.values()), depth, ancestors);
  }

  if (isHeadersLike(value)) {
    return serializeHeaders(value, depth, ancestors);
  }

  if (typeof value === "object") {
    return serializeObject(value as Record<string, unknown>, depth, ancestors);
  }

  return value;
}

function serializeArray(
  value: unknown[],
  depth: number,
  ancestors: WeakSet<object>,
) {
  if (ancestors.has(value)) {
    return CIRCULAR;
  }

  ancestors.add(value);
  const serialized = value
    .slice(0, MAX_COLLECTION_ITEMS)
    .map((item) => serializeValue(item, depth + 1, ancestors));
  ancestors.delete(value);

  if (value.length > MAX_COLLECTION_ITEMS) {
    serialized.push(`...${value.length - MAX_COLLECTION_ITEMS} more items`);
  }

  return serialized;
}

function serializeObject(
  value: Record<string, unknown>,
  depth: number,
  ancestors: WeakSet<object>,
) {
  if (ancestors.has(value)) {
    return CIRCULAR;
  }

  ancestors.add(value);
  const serialized = serializeObjectEntries(value, depth + 1, ancestors);
  ancestors.delete(value);
  return serialized;
}

function serializeObjectEntries(
  value: Record<string, unknown>,
  depth: number,
  ancestors: WeakSet<object>,
) {
  const entries = Object.entries(value)
    .filter(([, nestedValue]) => nestedValue !== undefined)
    .slice(0, MAX_COLLECTION_ITEMS)
    .map(([key, nestedValue]) => [
      key,
      isSensitiveKey(key)
        ? REDACTED
        : serializeValue(nestedValue, depth, ancestors),
    ]);

  if (Object.keys(value).length > MAX_COLLECTION_ITEMS) {
    entries.push(["_truncated", TRUNCATED]);
  }

  return Object.fromEntries(entries);
}

function serializeHeaders(
  value: object,
  depth: number,
  ancestors: WeakSet<object>,
) {
  const headers: Record<string, unknown> = {};
  const headerLike = value as {
    forEach?: (callback: (value: string, key: string) => void) => void;
    entries?: () => IterableIterator<[string, string]>;
  };

  if (typeof headerLike.forEach === "function") {
    headerLike.forEach((headerValue, key) => {
      headers[key] = headerValue;
    });
  } else if (typeof headerLike.entries === "function") {
    for (const [key, headerValue] of headerLike.entries()) {
      headers[key] = headerValue;
    }
  }

  return serializeObject(headers, depth, ancestors);
}

function serializeError(
  error: Error,
  depth: number,
  ancestors: WeakSet<object>,
): SerializableError {
  if (ancestors.has(error)) {
    return {
      name: error.name,
      message: CIRCULAR,
    };
  }

  ancestors.add(error);
  const serialized: SerializableError = {
    name: error.name,
    message: sanitizeString(error.message, MAX_STRING_LENGTH),
    ...(error.stack == null
      ? {}
      : { stack: sanitizeString(error.stack, MAX_STACK_LENGTH) }),
  };

  const cause = (error as { cause?: unknown }).cause;
  if (cause !== undefined) {
    serialized.cause = serializeValue(cause, depth + 1, ancestors);
  }

  for (const [key, value] of Object.entries(error)) {
    if (key === "cause") {
      continue;
    }
    serialized[key] = isSensitiveKey(key)
      ? REDACTED
      : serializeValue(value, depth + 1, ancestors);
  }

  ancestors.delete(error);
  return serialized;
}

function isHeadersLike(value: unknown) {
  if (value == null || typeof value !== "object") {
    return false;
  }

  const candidate = value as {
    constructor?: { name?: string };
    entries?: unknown;
  };
  return (
    candidate.constructor?.name === "Headers" ||
    typeof candidate.entries === "function"
  );
}

function isSensitiveKey(key: string) {
  return sensitiveKeys.has(normalizeSensitiveKey(key));
}

function normalizeSensitiveKey(key: string) {
  return key.toLowerCase().replace(/[^a-z0-9]/g, "");
}

function sanitizeString(value: string, maxLength: number) {
  const sanitized = sanitizeUrlCredentials(value);
  if (sanitized.length <= maxLength) {
    return sanitized;
  }

  return `${sanitized.slice(0, maxLength)}...${TRUNCATED}`;
}

function sanitizeUrlCredentials(value: string) {
  const trimmed = value.trim();
  if (/^https?:\/\//i.test(trimmed)) {
    try {
      const url = new URL(trimmed);
      if (url.username.length > 0) {
        url.username = REDACTED;
      }
      if (url.password.length > 0) {
        url.password = REDACTED;
      }
      redactSearchParams(url.searchParams);
      return url.toString();
    } catch {
      return sanitizeUrlQuery(value);
    }
  }

  return sanitizeUrlQuery(value);
}

function sanitizeUrlQuery(value: string) {
  return value.replace(
    /([?&])([^=&#\s]+)=([^&#\s]*)/g,
    (match, separator: string, key: string) =>
      isSensitiveKey(key) ? `${separator}${key}=${REDACTED}` : match,
  );
}

function redactSearchParams(params: URLSearchParams) {
  for (const key of Array.from(params.keys())) {
    if (isSensitiveKey(key)) {
      params.set(key, REDACTED);
    }
  }
}

function writeLog(level: LogLevel, message: string, context?: LogContext) {
  const normalizedContext = normalizeContext(context);
  const payload = {
    timestamp: new Date().toISOString(),
    level,
    message,
    ...(normalizedContext == null ? {} : { context: normalizedContext }),
  };

  const line = JSON.stringify(payload);
  if (level === "error") {
    console.error(line);
    return;
  }

  console.log(line);
}

export const logger = {
  info(message: string, context?: LogContext) {
    writeLog("info", message, context);
  },
  warn(message: string, context?: LogContext) {
    writeLog("warn", message, context);
  },
  error(message: string, context?: LogContext) {
    writeLog("error", message, context);
  },
};
