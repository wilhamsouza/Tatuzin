import 'dotenv/config';
import { z } from 'zod';

const optionalTrimmedString = z
  .string()
  .trim()
  .optional()
  .transform((value) =>
    value == null || value.length === 0 ? null : value,
  );

const optionalUrlString = z.preprocess(
  (value) => {
    if (typeof value !== 'string') {
      return value;
    }

    const normalized = value.trim();
    return normalized.length === 0 ? undefined : normalized;
  },
  z.string().url().optional(),
).transform((value) => value ?? null);

function parseTrustProxySetting(rawValue: string | null) {
  if (rawValue == null) {
    return false;
  }

  const normalized = rawValue.trim().toLowerCase();
  if (normalized === 'true') {
    return true;
  }
  if (normalized === 'false') {
    return false;
  }
  if (/^\d+$/.test(normalized)) {
    return Number.parseInt(normalized, 10);
  }

  const parts = rawValue
    .split(',')
    .map((value) => value.trim())
    .filter((value) => value.length > 0);
  if (parts.length > 1) {
    return parts;
  }

  return rawValue;
}

const envSchema = z.object({
  PORT: z.coerce.number().int().positive().default(4000),
  HOST: z.string().trim().min(1).default('127.0.0.1'),
  DATABASE_URL: z.string().min(1),
  JWT_SECRET: z.string().min(16),
  ACCESS_TOKEN_TTL: z.string().min(2).default('12h'),
  REFRESH_TOKEN_TTL_DAYS: z.coerce.number().int().min(1).default(30),
  PASSWORD_RESET_TOKEN_TTL_MINUTES: z.coerce
    .number()
    .int()
    .min(5)
    .max(120)
    .default(30),
  PASSWORD_RESET_DEBUG_LOG_TOKEN: z
    .enum(['true', 'false'])
    .default('false')
    .transform((value) => value == 'true'),
  PASSWORD_RESET_APP_BASE_URL: optionalUrlString,
  RESEND_API_KEY: optionalTrimmedString,
  MAIL_FROM_AUTH: optionalTrimmedString,
  MAIL_REPLY_TO_SUPPORT: optionalTrimmedString,
  CORS_ORIGINS: z.string().default('http://localhost:3000'),
  TRUST_PROXY: optionalTrimmedString,
  APP_ENV: z.string().trim().min(1).default('local-development'),
  PLATFORM_JOB_SWEEP_INTERVAL_MS: z.coerce
    .number()
    .int()
    .min(60_000)
    .default(300_000),
  SESSION_CLEANUP_RETENTION_DAYS: z.coerce
    .number()
    .int()
    .min(1)
    .default(30),
  RATE_LIMIT_BUCKET_RETENTION_MINUTES: z.coerce
    .number()
    .int()
    .min(60)
    .default(1_440),
  ALLOW_INITIAL_BOOTSTRAP: z
    .enum(['true', 'false'])
    .default('false')
    .transform((value) => value == 'true'),
});

const parsed = envSchema.safeParse(process.env);

if (!parsed.success) {
  console.error('Invalid backend environment configuration.');
  console.error(parsed.error.flatten().fieldErrors);
  process.exit(1);
}

const appEnvNormalized = parsed.data.APP_ENV.trim().toLowerCase();
const isProduction = appEnvNormalized === 'production';

if (isProduction) {
  const missingProductionEnv = [
    process.env.CORS_ORIGINS == null || process.env.CORS_ORIGINS.trim().length == 0
      ? 'CORS_ORIGINS'
      : null,
    process.env.TRUST_PROXY == null || process.env.TRUST_PROXY.trim().length == 0
      ? 'TRUST_PROXY'
      : null,
    parsed.data.RESEND_API_KEY == null ? 'RESEND_API_KEY' : null,
    parsed.data.MAIL_FROM_AUTH == null ? 'MAIL_FROM_AUTH' : null,
    parsed.data.PASSWORD_RESET_APP_BASE_URL == null
      ? 'PASSWORD_RESET_APP_BASE_URL'
      : null,
  ].filter((value): value is string => value != null);

  if (missingProductionEnv.length > 0) {
    console.error(
      'Missing required backend environment configuration for production.',
    );
    console.error({
      required: missingProductionEnv,
    });
    process.exit(1);
  }
}

if (isProduction && parsed.data.PASSWORD_RESET_DEBUG_LOG_TOKEN) {
  console.error(
    'PASSWORD_RESET_DEBUG_LOG_TOKEN must remain disabled in production.',
  );
  process.exit(1);
}

export const env = {
  ...parsed.data,
  appEnvNormalized,
  isProduction,
  isLocalDevelopment: appEnvNormalized === 'local-development',
  trustProxy: parseTrustProxySetting(parsed.data.TRUST_PROXY),
  corsOrigins: parsed.data.CORS_ORIGINS.split(',')
    .map((origin) => origin.trim())
    .filter((origin) => origin.length > 0),
};
