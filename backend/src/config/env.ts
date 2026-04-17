import 'dotenv/config';
import { z } from 'zod';

const envSchema = z.object({
  PORT: z.coerce.number().int().positive().default(4000),
  DATABASE_URL: z.string().min(1),
  JWT_SECRET: z.string().min(16),
  ACCESS_TOKEN_TTL: z.string().min(2).default('12h'),
  REFRESH_TOKEN_TTL_DAYS: z.coerce.number().int().min(1).default(30),
  CORS_ORIGINS: z.string().default('http://localhost:3000'),
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

export const env = {
  ...parsed.data,
  corsOrigins: parsed.data.CORS_ORIGINS.split(',')
    .map((origin) => origin.trim())
    .filter((origin) => origin.length > 0),
};
