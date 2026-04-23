import { createHash, randomBytes } from 'crypto';

import { MembershipRole, Prisma, type Membership } from '@prisma/client';
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
  ForgotPasswordInput,
  LoginInput,
  RefreshInput,
  RegisterInput,
  RegisterInitialInput,
  ResetPasswordInput,
  SessionClientInput,
} from './auth.schemas';
import {
  ResendPasswordResetDeliveryService,
  type PasswordResetDeliveryService,
} from './password-reset-delivery.service';

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

const INITIAL_TRIAL_DURATION_DAYS = 15;
const FORGOT_PASSWORD_NEUTRAL_MESSAGE =
  'Se existir uma conta com este e-mail, enviaremos as instrucoes para redefinir sua senha.';

export class AuthService {
  constructor(
    private readonly sessionService = new AuthSessionService(),
    private readonly passwordResetDelivery: PasswordResetDeliveryService =
      new ResendPasswordResetDeliveryService(),
  ) {}

  async register(input: RegisterInput) {
    await this.ensureRegistrationAvailable({
      email: input.email,
      companySlug: input.companySlug,
    });

    const passwordHash = await bcrypt.hash(input.password, 10);
    const result = await this.createOwnerAccount({
      companyName: input.companyName,
      companySlug: input.companySlug,
      userName: input.userName,
      email: input.email,
      passwordHash,
      isPlatformAdmin: false,
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

    logger.info('auth.register.completed', {
      userId: result.user.id,
      companyId: result.company.id,
      sessionId: sessionTokens.session.id,
    });

    return this.buildAuthPayload(result, sessionTokens);
  }

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

  async forgotPassword(input: ForgotPasswordInput) {
    const normalizedEmail = input.email.toLowerCase().trim();
    const emailFingerprint = this.fingerprintEmail(normalizedEmail);
    const user = await prisma.user.findUnique({
      where: { email: normalizedEmail },
      select: {
        id: true,
        email: true,
        name: true,
        isActive: true,
      },
    });

    if (user == null || !user.isActive) {
      logger.info('auth.password_reset.request_accepted', {
        emailFingerprint,
        matchedUser: false,
      });
      return {
        message: FORGOT_PASSWORD_NEUTRAL_MESSAGE,
      };
    }

    const resetToken = this.generateOpaqueToken();
    const expiresAt = this.buildPasswordResetExpiry();

    await prisma.$transaction(async (transaction) => {
      await transaction.passwordResetToken.deleteMany({
        where: {
          userId: user.id,
        },
      });

      await transaction.passwordResetToken.create({
        data: {
          userId: user.id,
          tokenHash: this.hashOpaqueToken(resetToken),
          expiresAt,
        },
      });
    });

    try {
      await this.passwordResetDelivery.sendResetToken({
        userId: user.id,
        userEmail: user.email,
        userName: user.name,
        resetToken,
        expiresAt,
      });
    } catch (error) {
      logger.error('auth.password_reset.delivery_failed', {
        userId: user.id,
        emailFingerprint,
        error,
      });
    }

    logger.info('auth.password_reset.request_accepted', {
      userId: user.id,
      emailFingerprint,
      matchedUser: true,
      expiresAt,
    });

    return {
      message: FORGOT_PASSWORD_NEUTRAL_MESSAGE,
    };
  }

  async resetPassword(input: ResetPasswordInput) {
    const normalizedToken = input.token.trim();
    const tokenHash = this.hashOpaqueToken(normalizedToken);
    const now = new Date();

    const existingToken = await prisma.passwordResetToken.findUnique({
      where: { tokenHash },
      include: {
        user: {
          select: {
            id: true,
            isActive: true,
          },
        },
      },
    });

    if (existingToken == null) {
      logger.warn('auth.password_reset.failed', {
        reason: 'token_not_found',
      });
      throw new AppError(
        'O token de redefinicao de senha e invalido.',
        400,
        'PASSWORD_RESET_TOKEN_INVALID',
      );
    }

    if (existingToken.consumedAt != null) {
      logger.warn('auth.password_reset.failed', {
        userId: existingToken.userId,
        reason: 'token_already_consumed',
      });
      throw new AppError(
        'Este token de redefinicao de senha ja foi utilizado.',
        400,
        'PASSWORD_RESET_TOKEN_ALREADY_USED',
      );
    }

    if (existingToken.expiresAt.getTime() <= now.getTime()) {
      logger.warn('auth.password_reset.failed', {
        userId: existingToken.userId,
        reason: 'token_expired',
      });
      throw new AppError(
        'Este token de redefinicao de senha expirou.',
        400,
        'PASSWORD_RESET_TOKEN_EXPIRED',
      );
    }

    if (!existingToken.user.isActive) {
      logger.warn('auth.password_reset.failed', {
        userId: existingToken.userId,
        reason: 'user_inactive',
      });
      throw new AppError(
        'Nao foi possivel redefinir a senha desta conta.',
        400,
        'PASSWORD_RESET_NOT_ALLOWED',
      );
    }

    const passwordHash = await bcrypt.hash(input.newPassword, 10);

    await prisma.$transaction(async (transaction) => {
      const consumedTokens = await transaction.passwordResetToken.updateMany({
        where: {
          id: existingToken.id,
          consumedAt: null,
          expiresAt: {
            gt: now,
          },
        },
        data: {
          consumedAt: now,
        },
      });

      if (consumedTokens.count !== 1) {
        throw new AppError(
          'O token de redefinicao de senha e invalido.',
          400,
          'PASSWORD_RESET_TOKEN_INVALID',
        );
      }

      await transaction.user.update({
        where: { id: existingToken.userId },
        data: {
          passwordHash,
        },
      });

      await transaction.passwordResetToken.deleteMany({
        where: {
          userId: existingToken.userId,
          id: {
            not: existingToken.id,
          },
        },
      });
    });

    const revokedSessionsCount = await this.sessionService.revokeAllUserSessions({
      userId: existingToken.userId,
      actorUserId: existingToken.userId,
      auditAction: 'session_revoked',
      revokedReason: 'password_reset',
    });

    logger.info('auth.password_reset.completed', {
      userId: existingToken.userId,
      revokedSessionsCount,
    });

    return {
      message:
        'Sua senha foi redefinida com sucesso. Entre novamente para continuar.',
    };
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
    const result = await this.createOwnerAccount({
      companyName: input.companyName,
      companySlug: input.companySlug,
      userName: input.userName,
      email: input.email,
      passwordHash,
      isPlatformAdmin: true,
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
      | RegisterInput
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

  private async ensureRegistrationAvailable(input: {
    email: string;
    companySlug: string;
  }) {
    const normalizedEmail = input.email.toLowerCase().trim();
    const normalizedCompanySlug = input.companySlug.toLowerCase().trim();

    const [existingUser, existingCompany] = await prisma.$transaction([
      prisma.user.findUnique({
        where: { email: normalizedEmail },
        select: { id: true },
      }),
      prisma.company.findUnique({
        where: { slug: normalizedCompanySlug },
        select: { id: true },
      }),
    ]);

    if (existingUser) {
      throw new AppError(
        'Ja existe uma conta cadastrada com este e-mail.',
        409,
        'EMAIL_ALREADY_IN_USE',
      );
    }

    if (existingCompany) {
      throw new AppError(
        'Este identificador de empresa ja esta em uso.',
        409,
        'COMPANY_SLUG_ALREADY_IN_USE',
      );
    }
  }

  private async createOwnerAccount(input: {
    companyName: string;
    companySlug: string;
    userName: string;
    email: string;
    passwordHash: string;
    isPlatformAdmin: boolean;
  }): Promise<MembershipWithRelations> {
    try {
      return await prisma.$transaction(async (transaction) => {
        const trialWindow = this.buildInitialTrialWindow();
        const company = await transaction.company.create({
          data: {
            name: input.companyName.trim(),
            legalName: input.companyName.trim(),
            slug: input.companySlug.toLowerCase().trim(),
          },
        });

        const user = await transaction.user.create({
          data: {
            email: input.email.toLowerCase().trim(),
            name: input.userName.trim(),
            passwordHash: input.passwordHash,
            isPlatformAdmin: input.isPlatformAdmin,
          },
        });

        await transaction.license.create({
          data: {
            companyId: company.id,
            plan: 'trial',
            status: 'TRIAL',
            startsAt: trialWindow.startsAt,
            expiresAt: trialWindow.expiresAt,
            syncEnabled: true,
          },
        });

        return transaction.membership.create({
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
      });
    } catch (error) {
      this.rethrowRegistrationConstraintError(error);
      throw error;
    }
  }

  private rethrowRegistrationConstraintError(error: unknown): never | void {
    if (
      error instanceof Prisma.PrismaClientKnownRequestError &&
      error.code === 'P2002'
    ) {
      const target = Array.isArray(error.meta?.target)
        ? error.meta.target.join(',')
        : `${error.meta?.target ?? ''}`;

      if (target.includes('email')) {
        throw new AppError(
          'Ja existe uma conta cadastrada com este e-mail.',
          409,
          'EMAIL_ALREADY_IN_USE',
        );
      }

      if (target.includes('slug')) {
        throw new AppError(
          'Este identificador de empresa ja esta em uso.',
          409,
          'COMPANY_SLUG_ALREADY_IN_USE',
        );
      }

      throw new AppError(
        'Nao foi possivel concluir o cadastro porque os dados informados ja estao em uso.',
        409,
        'REGISTRATION_CONFLICT',
      );
    }
  }

  private buildInitialTrialWindow() {
    const startsAt = new Date();
    const expiresAt = new Date(
      startsAt.getTime() +
        INITIAL_TRIAL_DURATION_DAYS * 24 * 60 * 60 * 1000,
    );

    return {
      startsAt,
      expiresAt,
    };
  }

  private buildPasswordResetExpiry() {
    return new Date(
      Date.now() + env.PASSWORD_RESET_TOKEN_TTL_MINUTES * 60 * 1000,
    );
  }

  private generateOpaqueToken() {
    return randomBytes(48).toString('base64url');
  }

  private hashOpaqueToken(token: string) {
    return createHash('sha256').update(token).digest('hex');
  }

  private fingerprintEmail(email: string) {
    return createHash('sha256').update(email).digest('hex');
  }
}
