import { z } from 'zod';

const sessionClientTypeSchema = z
  .enum(['mobile_app', 'admin_web', 'unknown'])
  .default('mobile_app');

const optionalClientString = (maxLength: number) =>
  z
    .string()
    .trim()
    .min(1)
    .max(maxLength)
    .optional();

export const sessionClientSchema = z.object({
  clientType: sessionClientTypeSchema.optional(),
  clientInstanceId: optionalClientString(120),
  deviceLabel: optionalClientString(120),
  platform: optionalClientString(60),
  appVersion: optionalClientString(40),
});

export const loginSchema = z.object({
  email: z
    .string()
    .email('Informe um e-mail valido.')
    .transform((value) => value.trim()),
  password: z
    .string()
    .min(6, 'A senha precisa ter pelo menos 6 caracteres.')
    .max(72),
  clientType: sessionClientTypeSchema,
  clientInstanceId: optionalClientString(120),
  deviceLabel: optionalClientString(120),
  platform: optionalClientString(60),
  appVersion: optionalClientString(40),
});

const normalizedNameSchema = z
  .string()
  .trim()
  .min(3, 'Informe pelo menos 3 caracteres.')
  .max(120);

const normalizedRegisterSlugSchema = z
  .string()
  .trim()
  .toLowerCase()
  .min(3, 'Informe pelo menos 3 caracteres.')
  .max(60)
  .regex(/^[a-z0-9-]+$/, 'Use apenas letras minusculas, numeros e hifens.');

const normalizedRegisterEmailSchema = z
  .string()
  .trim()
  .toLowerCase()
  .email('Informe um e-mail valido.');

export const registerSchema = z.object({
  companyName: normalizedNameSchema,
  companySlug: normalizedRegisterSlugSchema,
  userName: normalizedNameSchema,
  email: normalizedRegisterEmailSchema,
  password: z
    .string()
    .min(8, 'A senha precisa ter pelo menos 8 caracteres.')
    .max(72),
  clientType: sessionClientTypeSchema,
  clientInstanceId: optionalClientString(120),
  deviceLabel: optionalClientString(120),
  platform: optionalClientString(60),
  appVersion: optionalClientString(40),
});

export const registerInitialSchema = z.object({
  companyName: z.string().min(3).max(120),
  companySlug: z
    .string()
    .min(3)
    .max(60)
    .regex(/^[a-z0-9-]+$/, 'Use apenas letras minusculas, numeros e hifens.'),
  userName: z.string().min(3).max(120),
  email: z
    .string()
    .email('Informe um e-mail valido.')
    .transform((value) => value.trim()),
  password: z
    .string()
    .min(6, 'A senha precisa ter pelo menos 6 caracteres.')
    .max(72),
  clientType: sessionClientTypeSchema,
  clientInstanceId: optionalClientString(120),
  deviceLabel: optionalClientString(120),
  platform: optionalClientString(60),
  appVersion: optionalClientString(40),
});

export const refreshSchema = z.object({
  refreshToken: z.string().trim().min(24).max(512),
  clientType: sessionClientTypeSchema.optional(),
  clientInstanceId: optionalClientString(120),
  deviceLabel: optionalClientString(120),
  platform: optionalClientString(60),
  appVersion: optionalClientString(40),
});

export type LoginInput = z.infer<typeof loginSchema>;
export type RegisterInput = z.infer<typeof registerSchema>;
export type RefreshInput = z.infer<typeof refreshSchema>;
export type RegisterInitialInput = z.infer<typeof registerInitialSchema>;
export type SessionClientInput = z.infer<typeof sessionClientSchema>;
