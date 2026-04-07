import type { NextFunction, Request, Response } from 'express';
import jwt from 'jsonwebtoken';

import { prisma } from '../../database/prisma';
import { AuthSessionService } from '../../modules/auth/auth-session.service';
import { env } from '../../config/env';
import { AppError } from './app-error';

interface JwtPayload {
  sub: string;
  companyId: string;
  membershipId: string;
  membershipRole: string;
  email: string;
  isPlatformAdmin: boolean;
  sessionId?: string;
}

const authSessionService = new AuthSessionService();

export async function requireAuth(
  request: Request,
  _response: Response,
  next: NextFunction,
): Promise<void> {
  const authorization = request.headers.authorization;

  if (!authorization?.startsWith('Bearer ')) {
    next(new AppError('Token de acesso ausente.', 401, 'AUTH_REQUIRED'));
    return;
  }

  const token = authorization.replace('Bearer ', '').trim();

  try {
    const payload = jwt.verify(token, env.JWT_SECRET) as JwtPayload;

    let validatedSession:
      | {
          sessionId: string;
          sessionClientType: string;
          membershipRole: string;
        }
      | undefined;

    if (
      typeof payload.sessionId === 'string' &&
      payload.sessionId.trim().length > 0
    ) {
      validatedSession = await authSessionService.validateAccessSession({
        sessionId: payload.sessionId.trim(),
        userId: payload.sub,
        companyId: payload.companyId,
        membershipId: payload.membershipId,
      });
    }

    request.auth = {
      userId: payload.sub,
      companyId: payload.companyId,
      membershipId: payload.membershipId,
      membershipRole:
        validatedSession?.membershipRole ??
        (typeof payload.membershipRole === 'string'
          ? payload.membershipRole
          : 'OPERATOR'),
      email: payload.email,
      isPlatformAdmin: payload.isPlatformAdmin === true,
      accessToken: token,
      sessionId: validatedSession?.sessionId,
      sessionClientType: validatedSession?.sessionClientType,
    };

    next();
  } catch (error) {
    next(
      error instanceof AppError
        ? error
        : new AppError(
            'Sessao invalida ou expirada. Faca login novamente.',
            401,
            'INVALID_ACCESS_TOKEN',
            error,
          ),
    );
  }
}

export async function requirePlatformAdmin(
  request: Request,
  response: Response,
  next: NextFunction,
): Promise<void> {
  try {
    await new Promise<void>((resolve, reject) => {
      void requireAuth(request, response, (error?: unknown) => {
        if (error != null) {
          reject(error);
          return;
        }
        resolve();
      });
    });

    const auth = request.auth;
    if (auth == null) {
      throw new AppError('Sessao administrativa invalida.', 401, 'AUTH_REQUIRED');
    }

    const user = await prisma.user.findUnique({
      where: { id: auth.userId },
      select: {
        id: true,
        isActive: true,
        isPlatformAdmin: true,
      },
    });

    if (!user?.isActive || !user.isPlatformAdmin) {
      throw new AppError(
        'Acesso administrativo restrito ao time interno autorizado.',
        403,
        'PLATFORM_ADMIN_REQUIRED',
      );
    }

    request.auth = {
      ...auth,
      isPlatformAdmin: true,
    };

    next();
  } catch (error) {
    next(error);
  }
}

export async function requireCloudLicense(
  request: Request,
  response: Response,
  next: NextFunction,
): Promise<void> {
  try {
    await new Promise<void>((resolve, reject) => {
      void requireAuth(request, response, (error?: unknown) => {
        if (error != null) {
          reject(error);
          return;
        }
        resolve();
      });
    });

    const auth = request.auth;
    if (auth == null) {
      throw new AppError('Sessao cloud invalida.', 401, 'AUTH_REQUIRED');
    }

    const license = await prisma.license.findUnique({
      where: { companyId: auth.companyId },
      select: {
        status: true,
        syncEnabled: true,
        expiresAt: true,
      },
    });

    if (license == null) {
      throw new AppError(
        'A empresa ainda nao possui licenca cloud configurada.',
        403,
        'LICENSE_NOT_CONFIGURED',
      );
    }

    if (!license.syncEnabled) {
      throw new AppError(
        'A sincronizacao cloud esta desabilitada para esta empresa.',
        403,
        'CLOUD_SYNC_DISABLED',
      );
    }

    const isExpiredByDate =
      license.expiresAt != null && license.expiresAt.getTime() < Date.now();
    if (license.status === 'SUSPENDED') {
      throw new AppError(
        'A licenca desta empresa esta suspensa para uso cloud.',
        403,
        'LICENSE_SUSPENDED',
      );
    }

    if (license.status === 'EXPIRED' || isExpiredByDate) {
      throw new AppError(
        'A licenca desta empresa expirou para uso cloud.',
        403,
        'LICENSE_EXPIRED',
      );
    }

    if (license.status !== 'ACTIVE' && license.status !== 'TRIAL') {
      throw new AppError(
        'A licenca atual nao permite operacao cloud para esta empresa.',
        403,
        'LICENSE_CLOUD_BLOCKED',
      );
    }

    next();
  } catch (error) {
    next(error);
  }
}
