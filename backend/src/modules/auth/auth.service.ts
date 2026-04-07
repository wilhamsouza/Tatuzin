import { MembershipRole, type Membership } from '@prisma/client';
import bcrypt from 'bcryptjs';

import { env } from '../../config/env';
import { prisma } from '../../database/prisma';
import { AppError } from '../../shared/http/app-error';
import { logger } from '../../shared/observability/logger';
import {
  AuthSessionService,
  type SessionTokenBundle,
} from './auth-session.service';
import type {
  LoginInput,
  RefreshInput,
  RegisterInitialInput,
  SessionClientInput,
} from './auth.schemas';

type MembershipWithRelations = Membership & {
  user: {
    id: string;
    email: string;
    name: string;
    passwordHash: string;
    isActive: boolean;
    isPlatformAdmin: boolean;
    createdAt: Date;
    updatedAt: Date;
  };
  company: {
    id: string;
    name: string;
    legalName: string;
    documentNumber: string | null;
    slug: string;
    isActive: boolean;
    createdAt: Date;
    updatedAt: Date;
    license: {
      id: string;
      plan: string;
      status: string;
      startsAt: Date;
      expiresAt: Date | null;
      maxDevices: number | null;
      syncEnabled: boolean;
      createdAt: Date;
      updatedAt: Date;
    } | null;
  };
};

export class AuthService {
  constructor(private readonly sessionService = new AuthSessionService()) {}

  async login(input: LoginInput) {
    const membership = await this.findDefaultMembershipByEmail(input.email);

    const passwordMatches = await bcrypt.compare(
      input.password,
      membership.user.passwordHash,
    );

    if (!passwordMatches) {
      throw new AppError('E-mail ou senha invalidos.', 401, 'INVALID_CREDENTIALS');
    }

    const sessionTokens = await this.sessionService.createSession({
      userId: membership.user.id,
      userEmail: membership.user.email,
      userIsPlatformAdmin: membership.user.isPlatformAdmin,
      companyId: membership.company.id,
      membershipId: membership.id,
      membershipRole: membership.role,
      licenseMaxDevices: membership.company.license?.maxDevices ?? null,
      clientInput: this.toSessionClientInput(input),
    });

    logger.info('auth.login.succeeded', {
      userId: membership.user.id,
      companyId: membership.company.id,
      clientType: sessionTokens.session.clientType,
    });

    return this.buildAuthPayload(membership, sessionTokens);
  }

  async refresh(input: RefreshInput) {
    const sessionTokens = await this.sessionService.refreshSession({
      refreshToken: input.refreshToken,
      clientInput: this.toSessionClientInput(input),
    });

    const membership = await this.findMembershipById(sessionTokens.membershipId);
    logger.info('auth.refresh.succeeded', {
      userId: membership.user.id,
      companyId: membership.company.id,
      sessionId: sessionTokens.session.id,
    });
    return this.buildAuthPayload(membership, sessionTokens);
  }

  async me(membershipId: string, sessionId?: string | null, userId?: string | null) {
    if (sessionId != null && sessionId.trim().length > 0) {
      await this.sessionService.recordSessionRestored(sessionId, userId);
    }

    const membership = await this.findMembershipById(membershipId);
    return this.buildIdentityPayload(membership);
  }

  async logout(input: {
    sessionId?: string | null;
    userId: string;
    companyId: string;
  }) {
    await this.sessionService.logoutCurrentSession({
      sessionId: input.sessionId,
      actorUserId: input.userId,
      companyId: input.companyId,
    });
    logger.info('auth.logout.completed', {
      userId: input.userId,
      companyId: input.companyId,
      sessionId: input.sessionId,
    });
  }

  async listMySessions(userId: string, companyId: string) {
    return this.sessionService.listUserSessions(userId, companyId);
  }

  async revokeMySession(input: {
    sessionId: string;
    actorUserId: string;
    companyId: string;
  }) {
    await this.sessionService.revokeOwnSession(input);
  }

  async registerInitial(input: RegisterInitialInput) {
    if (!env.ALLOW_INITIAL_BOOTSTRAP) {
      throw new AppError(
        'Bootstrap inicial desativado neste ambiente.',
        403,
        'BOOTSTRAP_DISABLED',
      );
    }

    const existingUsers = await prisma.user.count();

    if (existingUsers > 0) {
      throw new AppError(
        'Bootstrap inicial disponivel apenas antes do primeiro usuario.',
        409,
        'BOOTSTRAP_ALREADY_COMPLETED',
      );
    }

    const passwordHash = await bcrypt.hash(input.password, 10);

    const result = await prisma.$transaction(async (transaction) => {
      const company = await transaction.company.create({
        data: {
          name: input.companyName.trim(),
          legalName: input.companyName.trim(),
          slug: input.companySlug.trim(),
        },
      });

      const user = await transaction.user.create({
        data: {
          email: input.email.toLowerCase().trim(),
          name: input.userName.trim(),
          passwordHash,
          isPlatformAdmin: true,
        },
      });

      await transaction.license.create({
        data: {
          companyId: company.id,
          plan: 'trial',
          status: 'TRIAL',
          startsAt: new Date(),
          syncEnabled: true,
        },
      });

      const membership = await transaction.membership.create({
        data: {
          userId: user.id,
          companyId: company.id,
          role: MembershipRole.OWNER,
          isDefault: true,
        },
        include: {
          user: true,
          company: {
            include: {
              license: true,
            },
          },
        },
      });

      return membership;
    });

    const sessionTokens = await this.sessionService.createSession({
      userId: result.user.id,
      userEmail: result.user.email,
      userIsPlatformAdmin: result.user.isPlatformAdmin,
      companyId: result.company.id,
      membershipId: result.id,
      membershipRole: result.role,
      licenseMaxDevices: result.company.license?.maxDevices ?? null,
      clientInput: this.toSessionClientInput(input),
    });

    logger.info('auth.bootstrap.completed', {
      userId: result.user.id,
      companyId: result.company.id,
      sessionId: sessionTokens.session.id,
    });

    return this.buildAuthPayload(result, sessionTokens);
  }

  private async findDefaultMembershipByEmail(
    email: string,
  ): Promise<MembershipWithRelations> {
    const membership = await prisma.membership.findFirst({
      where: {
        user: {
          email: email.toLowerCase().trim(),
          isActive: true,
        },
        company: {
          isActive: true,
        },
      },
      orderBy: [{ isDefault: 'desc' }, { createdAt: 'asc' }],
      include: {
        user: true,
        company: {
          include: {
            license: true,
          },
        },
      },
    });

    if (!membership) {
      throw new AppError('E-mail ou senha invalidos.', 401, 'INVALID_CREDENTIALS');
    }

    return membership;
  }

  private async findMembershipById(
    membershipId: string,
  ): Promise<MembershipWithRelations> {
    const membership = await prisma.membership.findUnique({
      where: { id: membershipId },
      include: {
        user: true,
        company: {
          include: {
            license: true,
          },
        },
      },
    });

    if (!membership || !membership.user.isActive || !membership.company.isActive) {
      throw new AppError('Sessao nao encontrada.', 401, 'SESSION_NOT_FOUND');
    }

    return membership;
  }

  private buildAuthPayload(
    membership: MembershipWithRelations,
    sessionTokens: SessionTokenBundle,
  ) {
    return {
      accessToken: sessionTokens.accessToken,
      refreshToken: sessionTokens.refreshToken,
      tokenType: sessionTokens.tokenType,
      expiresIn: sessionTokens.expiresIn,
      refreshTokenExpiresAt: sessionTokens.refreshTokenExpiresAt,
      session: sessionTokens.session,
      ...this.buildIdentityPayload(membership),
    };
  }

  private buildIdentityPayload(membership: MembershipWithRelations) {
    return {
      user: {
        id: membership.user.id,
        email: membership.user.email,
        name: membership.user.name,
        isPlatformAdmin: membership.user.isPlatformAdmin,
      },
      company: {
        id: membership.company.id,
        name: membership.company.name,
        legalName: membership.company.legalName,
        documentNumber: membership.company.documentNumber,
        slug: membership.company.slug,
        license:
          membership.company.license == null
            ? null
            : {
                id: membership.company.license.id,
                plan: membership.company.license.plan,
                status: membership.company.license.status,
                startsAt: membership.company.license.startsAt.toISOString(),
                expiresAt:
                  membership.company.license.expiresAt?.toISOString() ?? null,
                maxDevices: membership.company.license.maxDevices,
                syncEnabled: membership.company.license.syncEnabled,
              },
      },
      membership: {
        id: membership.id,
        role: membership.role,
        isDefault: membership.isDefault,
      },
    };
  }

  private toSessionClientInput(
    input:
      | LoginInput
      | RefreshInput
      | RegisterInitialInput,
  ): SessionClientInput {
    return {
      clientType: input.clientType,
      clientInstanceId: input.clientInstanceId,
      deviceLabel: input.deviceLabel,
      platform: input.platform,
      appVersion: input.appVersion,
    };
  }
}
