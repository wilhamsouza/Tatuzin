import { Router } from 'express';

import { requireAuth } from '../../shared/http/auth-middleware';
import { asyncHandler } from '../../shared/http/async-handler';
import { createRateLimit } from '../../shared/http/rate-limit';
import { validateBody } from '../../shared/http/validate';
import { CompaniesService } from '../companies/companies.service';
import { AuthService } from './auth.service';
import {
  loginSchema,
  refreshSchema,
  registerInitialSchema,
} from './auth.schemas';

const authService = new AuthService();
const companiesService = new CompaniesService();

export const authRouter = Router();

const loginRateLimit = createRateLimit({
  name: 'auth_login',
  windowMs: 60_000,
  max: 8,
  message:
    'Muitas tentativas de login em pouco tempo. Aguarde um instante e tente novamente.',
  code: 'AUTH_LOGIN_RATE_LIMITED',
  keyGenerator(request) {
    const email =
      request.body != null && typeof request.body.email === 'string'
        ? request.body.email.trim().toLowerCase()
        : 'unknown-email';
    return `${request.ip}:${email}`;
  },
});

const refreshRateLimit = createRateLimit({
  name: 'auth_refresh',
  windowMs: 60_000,
  max: 30,
  message:
    'Muitas tentativas de restaurar a sessao em pouco tempo. Tente novamente em instantes.',
  code: 'AUTH_REFRESH_RATE_LIMITED',
  keyGenerator(request) {
    const clientInstanceId =
      request.body != null && typeof request.body.clientInstanceId === 'string'
        ? request.body.clientInstanceId.trim()
        : 'unknown-client';
    return `${request.ip}:${clientInstanceId}`;
  },
});

authRouter.get('/health', (_request, response) => {
  response.json({
    ok: true,
    service: 'auth',
    timestamp: new Date().toISOString(),
  });
});

authRouter.post(
  '/register-initial',
  validateBody(registerInitialSchema),
  asyncHandler(async (request, response) => {
    const payload = await authService.registerInitial(request.body);
    response.status(201).json(payload);
  }),
);

authRouter.post(
  '/login',
  loginRateLimit,
  validateBody(loginSchema),
  asyncHandler(async (request, response) => {
    const payload = await authService.login(request.body);
    response.json(payload);
  }),
);

authRouter.post(
  '/refresh',
  refreshRateLimit,
  validateBody(refreshSchema),
  asyncHandler(async (request, response) => {
    const payload = await authService.refresh(request.body);
    response.json(payload);
  }),
);

authRouter.get(
  '/me',
  requireAuth,
  asyncHandler(async (request, response) => {
    const identity = await authService.me(
      request.auth!.membershipId,
      request.auth!.sessionId,
      request.auth!.userId,
    );
    response.json(identity);
  }),
);

authRouter.post(
  '/logout',
  requireAuth,
  asyncHandler(async (request, response) => {
    await authService.logout({
      sessionId: request.auth!.sessionId,
      userId: request.auth!.userId,
      companyId: request.auth!.companyId,
    });
    response.status(204).send();
  }),
);

authRouter.get(
  '/sessions',
  requireAuth,
  asyncHandler(async (request, response) => {
    const sessions = await authService.listMySessions(
      request.auth!.userId,
      request.auth!.companyId,
    );
    response.json({
      items: sessions,
      count: sessions.length,
    });
  }),
);

authRouter.post(
  '/sessions/:sessionId/revoke',
  requireAuth,
  asyncHandler(async (request, response) => {
    const sessionId = Array.isArray(request.params.sessionId)
      ? request.params.sessionId[0]
      : request.params.sessionId;

    await authService.revokeMySession({
      sessionId,
      actorUserId: request.auth!.userId,
      companyId: request.auth!.companyId,
    });

    response.status(204).send();
  }),
);

export const companyRouter = Router();

companyRouter.get(
  '/current',
  requireAuth,
  asyncHandler(async (request, response) => {
    const company = await companiesService.getCurrentCompanyForMembership(
      request.auth!.membershipId,
    );

    response.json({
      company: {
        id: company.id,
        name: company.name,
        legalName: company.legalName,
        documentNumber: company.documentNumber,
        slug: company.slug,
        license: company.license == null
          ? null
          : {
              id: company.license.id,
              plan: company.license.plan,
              status: company.license.status,
              startsAt: company.license.startsAt.toISOString(),
              expiresAt: company.license.expiresAt?.toISOString() ?? null,
              maxDevices: company.license.maxDevices,
              syncEnabled: company.license.syncEnabled,
            },
      },
    });
  }),
);
