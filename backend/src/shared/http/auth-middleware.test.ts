import assert from 'node:assert/strict';
import { afterEach, before, describe, it } from 'node:test';
import { MembershipRole, SessionClientType } from '@prisma/client';
import type { NextFunction, Request, Response } from 'express';
import jwt from 'jsonwebtoken';

import type { env as Env } from '../../config/env';
import type { AuthSessionService as AuthSessionServiceClass } from '../../modules/auth/auth-session.service';
import type { AppError as AppErrorClass } from './app-error';
import type { requireAuth as RequireAuth } from './auth-middleware';

let env: typeof Env;
let AuthSessionService: typeof AuthSessionServiceClass;
let AppError: typeof AppErrorClass;
let requireAuth: typeof RequireAuth;
let originalRequireJwtSessionId: boolean;
let originalValidateAccessSession: typeof AuthSessionServiceClass.prototype.validateAccessSession;

describe('auth middleware JWT session hardening', () => {
  before(async () => {
    process.env.DATABASE_URL ??=
      'postgresql://user:pass@localhost:5432/tatuzin_auth_middleware_test';
    process.env.JWT_SECRET ??= 'auth-middleware-test-secret';
    process.env.APP_ENV ??= 'test';
    process.env.CORS_ORIGINS ??= 'http://127.0.0.1';

    const envModule = await import('../../config/env');
    const authSessionModule = await import(
      '../../modules/auth/auth-session.service'
    );
    const appErrorModule = await import('./app-error');
    const authMiddlewareModule = await import('./auth-middleware');

    env = envModule.env;
    AuthSessionService = authSessionModule.AuthSessionService;
    AppError = appErrorModule.AppError;
    requireAuth = authMiddlewareModule.requireAuth;
    originalRequireJwtSessionId = env.REQUIRE_JWT_SESSION_ID;
    originalValidateAccessSession =
      AuthSessionService.prototype.validateAccessSession;
  });

  afterEach(() => {
    env.REQUIRE_JWT_SESSION_ID = originalRequireJwtSessionId;
    AuthSessionService.prototype.validateAccessSession =
      originalValidateAccessSession;
  });

  it('accepts a token with a valid sessionId', async () => {
    AuthSessionService.prototype.validateAccessSession = async () => ({
      sessionId: 'session-1',
      sessionClientType: SessionClientType.ADMIN_WEB,
      membershipRole: MembershipRole.OWNER,
      clientInstanceId: 'client-1',
    });

    const request = buildRequest({
      token: signToken({ sessionId: 'session-1' }),
    });
    const error = await runRequireAuth(request);

    assert.equal(error, undefined);
    assert.equal(request.auth?.sessionId, 'session-1');
    assert.equal(request.auth?.membershipRole, 'OWNER');
    assert.equal(request.auth?.clientInstanceId, 'client-1');
  });

  it('keeps accepting a token without sessionId when the flag is disabled', async () => {
    env.REQUIRE_JWT_SESSION_ID = false;
    const logs = captureConsoleLog();

    try {
      const request = buildRequest({
        path: '/api/sync/pull',
        originalUrl:
          '/api/sync/pull?token=query-token&signature=query-signature&email=client@example.com&document=123',
        token: signToken(),
      });
      const error = await runRequireAuth(request);

      assert.equal(error, undefined);
      assert.equal(request.auth?.sessionId, undefined);
      assert.equal(request.auth?.userId, 'user-1');
      assert.equal(logs.lines.length, 1);
      assert.match(logs.lines[0]!, /auth\.legacy_token_without_session_id/);
    } finally {
      logs.restore();
    }
  });

  it('logs sanitized telemetry for a token without sessionId', async () => {
    env.REQUIRE_JWT_SESSION_ID = false;
    const token = signToken();
    const logs = captureConsoleLog();

    try {
      const request = buildRequest({
        method: 'POST',
        path: '/api/billing/refresh',
        originalUrl:
          '/api/billing/refresh?token=query-token&signature=query-signature&code=reset-code&email=client@example.com&document=123',
        token,
      });

      await runRequireAuth(request);

      assert.equal(logs.lines.length, 1);
      const logged = JSON.parse(logs.lines[0]!);
      assert.equal(logged.message, 'auth.legacy_token_without_session_id');
      assert.equal(logged.context.userId, 'user-1');
      assert.equal(logged.context.companyId, 'company-1');
      assert.equal(logged.context.membershipId, 'membership-1');
      assert.equal(logged.context.clientInstanceId, 'client-1');
      assert.equal(logged.context.method, 'POST');
      assert.equal(logged.context.path, '/api/billing/refresh');
      assert.equal(logged.context.routeType, 'billing');

      for (const forbidden of [
        token,
        'Authorization',
        'Bearer',
        'query-token',
        'query-signature',
        'reset-code',
        'client@example.com',
        'document',
        'signature',
        'code',
        'email',
        '?',
      ]) {
        assert.equal(logs.lines[0]!.includes(forbidden), false);
      }
    } finally {
      logs.restore();
    }
  });

  it('rejects a token without sessionId when the flag is enabled', async () => {
    env.REQUIRE_JWT_SESSION_ID = true;
    const logs = captureConsoleLog();

    try {
      const request = buildRequest({
        token: signToken(),
      });
      const error = await runRequireAuth(request);

      assert.ok(error instanceof AppError);
      assert.equal(error.statusCode, 401);
      assert.equal(error.code, 'JWT_SESSION_ID_REQUIRED');
      assert.equal(request.auth, undefined);
      assert.equal(logs.lines.length, 1);
    } finally {
      logs.restore();
    }
  });

  it('keeps rejecting a token with an invalid or revoked sessionId', async () => {
    AuthSessionService.prototype.validateAccessSession = async () => {
      throw new AppError(
        'Esta sessao foi revogada. Faca login novamente.',
        401,
        'SESSION_REVOKED',
      );
    };

    const request = buildRequest({
      token: signToken({ sessionId: 'revoked-session' }),
    });
    const error = await runRequireAuth(request);

    assert.ok(error instanceof AppError);
    assert.equal(error.statusCode, 401);
    assert.equal(error.code, 'SESSION_REVOKED');
    assert.equal(request.auth, undefined);
  });
});

function signToken(input: { sessionId?: string } = {}) {
  return jwt.sign(
    {
      companyId: 'company-1',
      membershipId: 'membership-1',
      membershipRole: 'OPERATOR',
      email: 'user@example.com',
      isPlatformAdmin: false,
      clientInstanceId: 'client-1',
      ...(input.sessionId == null ? {} : { sessionId: input.sessionId }),
    },
    env.JWT_SECRET,
    {
      subject: 'user-1',
      expiresIn: '15m',
    },
  );
}

function buildRequest(input: {
  token: string;
  method?: string;
  path?: string;
  originalUrl?: string;
}) {
  const path = input.path ?? '/api/test';
  return {
    headers: {
      authorization: `Bearer ${input.token}`,
    },
    method: input.method ?? 'GET',
    path,
    originalUrl: input.originalUrl ?? path,
    url: input.originalUrl ?? path,
  } as unknown as Request;
}

async function runRequireAuth(request: Request) {
  let capturedError: unknown;
  const next: NextFunction = (error?: unknown) => {
    capturedError = error;
  };

  await requireAuth(request, {} as Response, next);
  return capturedError;
}

function captureConsoleLog() {
  const lines: string[] = [];
  const originalLog = console.log;
  console.log = (line?: unknown) => {
    lines.push(String(line));
  };

  return {
    lines,
    restore() {
      console.log = originalLog;
    },
  };
}

