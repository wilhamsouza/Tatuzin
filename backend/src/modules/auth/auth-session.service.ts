import { createHash, randomBytes } from 'crypto';

import {
  LicenseStatus,
  SessionClientType,
  type DeviceSession,
  type Prisma,
} from '@prisma/client';
import jwt, { type SignOptions } from 'jsonwebtoken';

import { env } from '../../config/env';
import { prisma } from '../../database/prisma';
import {
  CompanyDeviceService,
  type CompanyDeviceDto,
} from '../app/company-device.service';
import { AppError } from '../../shared/http/app-error';
import { logger } from '../../shared/observability/logger';
import { TenantLifecycleService } from '../tenant-deletion/tenant-lifecycle.service';

export type SessionClientInput = {
  clientType?: string | null;
  clientInstanceId?: string | null;
  deviceLabel?: string | null;
  platform?: string | null;
  appVersion?: string | null;
};

type SessionIssueInput = {
  userId: string;
  userEmail: string;
  userIsPlatformAdmin: boolean;
  companyId: string;
  membershipId: string;
  membershipRole: string;
  licensePlan: string | null;
  clientInput?: SessionClientInput;
};

type SessionRefreshInput = {
  refreshToken: string;
  clientInput?: SessionClientInput;
};

type AccessSessionValidationInput = {
  sessionId: string;
  userId: string;
  companyId: string;
  membershipId: string;
};

type AuditEventInput = {
  action: string;
  deviceSessionId?: string | null;
  actorUserId?: string | null;
  subjectUserId?: string | null;
  companyId?: string | null;
  details?: Prisma.InputJsonValue;
};

type DeviceSessionWithRelations = Prisma.DeviceSessionGetPayload<{
  include: {
    user: {
      select: {
        id: true;
        name: true;
        email: true;
      };
    };
    company: {
      select: {
        id: true;
        name: true;
      };
    };
    membership: {
      select: {
        id: true;
        role: true;
      };
    };
  };
}>;

export type SessionTokenBundle = {
  accessToken: string;
  refreshToken: string;
  tokenType: 'Bearer';
  expiresIn: string;
  refreshTokenExpiresAt: string;
  session: SessionSummaryDto;
  device: SessionDeviceDto;
};

export type RefreshedSessionBundle = SessionTokenBundle & {
  userId: string;
  userEmail: string;
  userIsPlatformAdmin: boolean;
  companyId: string;
  membershipId: string;
  membershipRole: string;
};

export type SessionSummaryDto = {
  id: string;
  userId: string;
  userName: string;
  userEmail: string;
  companyId: string;
  companyName: string;
  membershipId: string;
  membershipRole: string;
  clientType: 'mobile_app' | 'admin_web' | 'unknown';
  clientInstanceId: string;
  deviceLabel: string | null;
  platform: string | null;
  appVersion: string | null;
  status: 'active' | 'revoked' | 'expired';
  createdAt: string;
  lastSeenAt: string;
  lastRefreshedAt: string | null;
  refreshTokenExpiresAt: string;
  revokedAt: string | null;
  revokedReason: string | null;
};

export type SessionDeviceDto = {
  id: string;
  clientInstanceId: string;
  status: string;
  deviceLabel: string | null;
  platform: string | null;
  appVersion: string | null;
  lastSeenAt: string | null;
};

export class AuthSessionService {
  constructor(
    private readonly companyDeviceService = new CompanyDeviceService(),
    private readonly tenantLifecycleService = new TenantLifecycleService(),
  ) {}

  async createSession(input: SessionIssueInput): Promise<SessionTokenBundle> {
    const client = this.resolveClientInput(input.clientInput, input.userId);
    if (
      !this.isPlatformAdminSupportSession(
        input.userIsPlatformAdmin,
        client.clientType,
      )
    ) {
      await this.tenantLifecycleService.assertTenantOperational(
        input.companyId,
        {
          clientInstanceId: client.clientInstanceId,
          deviceLabel: client.deviceLabel,
          platform: client.platform,
          appVersion: client.appVersion,
        },
      );
    }

    const device = await this.companyDeviceService.registerOrResolve({
      companyId: input.companyId,
      userId: input.userId,
      membershipRole: input.membershipRole,
      licensePlan: input.licensePlan,
      clientInstanceId: client.clientInstanceId,
      deviceLabel: client.deviceLabel,
      platform: client.platform,
      appVersion: client.appVersion,
    });

    await this.revokeSessionsForClient({
      companyId: input.companyId,
      clientType: client.clientType,
      clientInstanceId: client.clientInstanceId,
      actorUserId: input.userId,
      subjectUserId: input.userId,
      auditAction: 'session_revoked',
      revokedReason: 'replaced_by_new_login',
    });

    const now = new Date();
    const refreshToken = this.generateOpaqueToken();
    const refreshTokenExpiresAt = this.buildRefreshTokenExpiry(now);

    const session = await prisma.deviceSession.create({
      data: {
        userId: input.userId,
        companyId: input.companyId,
        membershipId: input.membershipId,
        clientType: client.clientType,
        clientInstanceId: client.clientInstanceId,
        deviceLabel: client.deviceLabel,
        platform: client.platform,
        appVersion: client.appVersion,
        refreshTokenHash: this.hashToken(refreshToken),
        refreshTokenExpiresAt,
        lastSeenAt: now,
      },
      include: this.sessionInclude,
    });

    await this.recordAudit({
      action: 'login',
      deviceSessionId: session.id,
      actorUserId: input.userId,
      subjectUserId: input.userId,
      companyId: input.companyId,
      details: {
        clientType: this.toPublicClientType(session.clientType),
        clientInstanceId: session.clientInstanceId,
        deviceLabel: session.deviceLabel,
        platform: session.platform,
        appVersion: session.appVersion,
        deviceId: device.id,
        deviceStatus: device.status,
      },
    });

    return this.buildSessionTokenBundle({
      session,
      device,
      refreshToken,
      refreshTokenExpiresAt,
      userId: input.userId,
      userEmail: input.userEmail,
      userIsPlatformAdmin: input.userIsPlatformAdmin,
      companyId: input.companyId,
      membershipId: input.membershipId,
      membershipRole: input.membershipRole,
    });
  }

  async refreshSession(
    input: SessionRefreshInput,
  ): Promise<RefreshedSessionBundle> {
    const rawRefreshToken = input.refreshToken.trim();
    if (rawRefreshToken.length === 0) {
      await this.recordAudit({
        action: 'token_refresh_failed',
        details: { reason: 'missing_refresh_token' },
      });
      throw new AppError(
        'Sua sessao na nuvem expirou. Entre novamente para continuar conectado.',
        401,
        'REFRESH_TOKEN_REQUIRED',
      );
    }

    const existingSession = await prisma.deviceSession.findUnique({
      where: {
        refreshTokenHash: this.hashToken(rawRefreshToken),
      },
      include: {
        membership: {
          include: {
            user: true,
            company: {
              include: {
                license: true,
              },
            },
          },
        },
        user: {
          select: {
            id: true,
            name: true,
            email: true,
          },
        },
        company: {
          select: {
            id: true,
            name: true,
          },
        },
      },
    });

    if (!existingSession) {
      await this.recordAudit({
        action: 'token_refresh_failed',
        details: { reason: 'refresh_token_not_found' },
      });
      throw new AppError(
        'Sua sessao na nuvem expirou. Entre novamente para continuar conectado.',
        401,
        'REFRESH_TOKEN_INVALID',
      );
    }

    if (
      !this.isPlatformAdminSupportSession(
        existingSession.membership.user.isPlatformAdmin,
        existingSession.clientType,
      )
    ) {
      await this.tenantLifecycleService.assertTenantOperational(
        existingSession.companyId,
        {
          clientInstanceId: existingSession.clientInstanceId,
          deviceLabel: existingSession.deviceLabel,
          platform: existingSession.platform,
          appVersion: existingSession.appVersion,
        },
      );
    }

    if (existingSession.revokedAt != null) {
      await this.recordAudit({
        action: 'token_refresh_failed',
        deviceSessionId: existingSession.id,
        actorUserId: existingSession.userId,
        subjectUserId: existingSession.userId,
        companyId: existingSession.companyId,
        details: { reason: 'session_revoked' },
      });
      throw new AppError(
        'Esta sessao foi revogada. Entre novamente para continuar conectado.',
        401,
        'SESSION_REVOKED',
      );
    }

    if (existingSession.refreshTokenExpiresAt.getTime() <= Date.now()) {
      await this.recordAudit({
        action: 'token_refresh_failed',
        deviceSessionId: existingSession.id,
        actorUserId: existingSession.userId,
        subjectUserId: existingSession.userId,
        companyId: existingSession.companyId,
        details: { reason: 'refresh_token_expired' },
      });
      throw new AppError(
        'Sua sessao na nuvem expirou. Entre novamente para continuar conectado.',
        401,
        'REFRESH_TOKEN_EXPIRED',
      );
    }

    const membership = existingSession.membership;
    if (!membership.user.isActive || !membership.company.isActive) {
      await this.revokeSession({
        session: existingSession,
        actorUserId: existingSession.userId,
        auditAction: 'session_revoked',
        revokedReason: 'membership_inactive',
      });
      await this.recordAudit({
        action: 'token_refresh_failed',
        deviceSessionId: existingSession.id,
        actorUserId: existingSession.userId,
        subjectUserId: existingSession.userId,
        companyId: existingSession.companyId,
        details: { reason: 'membership_inactive' },
      });
      throw new AppError(
        'Esta conta nao esta mais ativa para acesso cloud.',
        401,
        'SESSION_MEMBERSHIP_INACTIVE',
      );
    }

    this.assertLicenseAllowsSessionRestore(membership.company.license);

    const client = this.resolveClientInput(
      input.clientInput,
      existingSession.userId,
    );
    if (
      input.clientInput?.clientInstanceId != null &&
      client.clientInstanceId != existingSession.clientInstanceId
    ) {
      await this.recordAudit({
        action: 'token_refresh_failed',
        deviceSessionId: existingSession.id,
        actorUserId: existingSession.userId,
        subjectUserId: existingSession.userId,
        companyId: existingSession.companyId,
        details: { reason: 'client_instance_mismatch' },
      });
      throw new AppError(
        'Esta sessao nao pode ser restaurada neste dispositivo.',
        401,
        'SESSION_DEVICE_MISMATCH',
      );
    }

    if (
      input.clientInput?.clientType != null &&
      client.clientType != SessionClientType.UNKNOWN &&
      client.clientType != existingSession.clientType
    ) {
      await this.recordAudit({
        action: 'token_refresh_failed',
        deviceSessionId: existingSession.id,
        actorUserId: existingSession.userId,
        subjectUserId: existingSession.userId,
        companyId: existingSession.companyId,
        details: { reason: 'client_type_mismatch' },
      });
      throw new AppError(
        'Esta sessao nao corresponde a este cliente.',
        401,
        'SESSION_CLIENT_MISMATCH',
      );
    }

    const device = await this.companyDeviceService.registerOrResolve({
      companyId: existingSession.companyId,
      userId: existingSession.userId,
      membershipRole: membership.role,
      licensePlan: membership.company.license?.plan ?? null,
      clientInstanceId: existingSession.clientInstanceId,
      deviceLabel: client.deviceLabel ?? existingSession.deviceLabel,
      platform: client.platform ?? existingSession.platform,
      appVersion: client.appVersion ?? existingSession.appVersion,
    });

    const refreshToken = this.generateOpaqueToken();
    const refreshTokenExpiresAt = this.buildRefreshTokenExpiry(new Date());

    const session = await prisma.deviceSession.update({
      where: { id: existingSession.id },
      data: {
        refreshTokenHash: this.hashToken(refreshToken),
        refreshTokenExpiresAt,
        lastSeenAt: new Date(),
        lastRefreshedAt: new Date(),
        deviceLabel: client.deviceLabel ?? existingSession.deviceLabel,
        platform: client.platform ?? existingSession.platform,
        appVersion: client.appVersion ?? existingSession.appVersion,
      },
      include: this.sessionInclude,
    });

    await this.recordAudit({
      action: 'refresh',
      deviceSessionId: session.id,
      actorUserId: session.userId,
      subjectUserId: session.userId,
      companyId: session.companyId,
      details: {
        clientType: this.toPublicClientType(session.clientType),
        clientInstanceId: session.clientInstanceId,
      },
    });

    return {
      ...this.buildSessionTokenBundle({
        session,
        device,
        refreshToken,
        refreshTokenExpiresAt,
        userId: membership.user.id,
        userEmail: membership.user.email,
        userIsPlatformAdmin: membership.user.isPlatformAdmin,
        companyId: membership.company.id,
        membershipId: membership.id,
        membershipRole: membership.role,
      }),
      userId: membership.user.id,
      userEmail: membership.user.email,
      userIsPlatformAdmin: membership.user.isPlatformAdmin,
      companyId: membership.company.id,
      membershipId: membership.id,
      membershipRole: membership.role,
    };
  }

  async validateAccessSession(input: AccessSessionValidationInput) {
    const session = await prisma.deviceSession.findUnique({
      where: { id: input.sessionId },
      select: {
        id: true,
        userId: true,
        companyId: true,
        membershipId: true,
        clientType: true,
        clientInstanceId: true,
        lastSeenAt: true,
        revokedAt: true,
        refreshTokenExpiresAt: true,
        membership: {
          select: {
            role: true,
            user: {
              select: {
                isActive: true,
                isPlatformAdmin: true,
              },
            },
            company: {
              select: {
                isActive: true,
              },
            },
          },
        },
      },
    });

    if (!session) {
      throw new AppError(
        'Sessao nao encontrada. Faca login novamente.',
        401,
        'SESSION_NOT_FOUND',
      );
    }

    if (
      session.userId != input.userId ||
      session.companyId != input.companyId ||
      session.membershipId != input.membershipId
    ) {
      throw new AppError(
        'Esta sessao nao corresponde ao contexto autenticado.',
        401,
        'SESSION_CONTEXT_MISMATCH',
      );
    }

    if (
      !this.isPlatformAdminSupportSession(
        session.membership.user.isPlatformAdmin,
        session.clientType,
      )
    ) {
      await this.tenantLifecycleService.assertTenantOperational(
        session.companyId,
        {
          clientInstanceId: session.clientInstanceId,
        },
      );
    }

    if (session.revokedAt != null) {
      throw new AppError(
        'Esta sessao foi revogada. Faca login novamente.',
        401,
        'SESSION_REVOKED',
      );
    }

    if (session.refreshTokenExpiresAt.getTime() <= Date.now()) {
      throw new AppError(
        'Sua sessao expirou. Faca login novamente.',
        401,
        'SESSION_EXPIRED',
      );
    }

    if (
      !session.membership.user.isActive ||
      !session.membership.company.isActive
    ) {
      throw new AppError(
        'Esta conta nao esta mais ativa para acesso cloud.',
        401,
        'SESSION_MEMBERSHIP_INACTIVE',
      );
    }

    this.touchSessionHeartbeat(session);

    return {
      sessionId: session.id,
      sessionClientType: session.clientType,
      membershipRole: session.membership.role,
      clientInstanceId: session.clientInstanceId,
    };
  }

  async recordSessionRestored(sessionId: string, actorUserId?: string | null) {
    const session = await prisma.deviceSession.findUnique({
      where: { id: sessionId },
      select: {
        id: true,
        userId: true,
        companyId: true,
        clientType: true,
        lastSeenAt: true,
        revokedAt: true,
        refreshTokenExpiresAt: true,
      },
    });

    if (!session || session.revokedAt != null) {
      return;
    }

    if (session.refreshTokenExpiresAt.getTime() <= Date.now()) {
      return;
    }

    if (!this.shouldRefreshHeartbeat(session.lastSeenAt)) {
      return;
    }

    const now = new Date();
    await prisma.deviceSession.update({
      where: { id: session.id },
      data: { lastSeenAt: now },
    });

    await this.recordAudit({
      action: 'session_restored',
      deviceSessionId: session.id,
      actorUserId: actorUserId ?? session.userId,
      subjectUserId: session.userId,
      companyId: session.companyId,
      details: {
        clientType: this.toPublicClientType(session.clientType),
      },
    });
  }

  async logoutCurrentSession(input: {
    sessionId?: string | null;
    actorUserId: string;
    companyId: string;
  }) {
    if (input.sessionId == null || input.sessionId.trim().length === 0) {
      return;
    }

    const session = await this.getSessionOrThrow(input.sessionId);
    if (
      session.userId != input.actorUserId ||
      session.companyId != input.companyId
    ) {
      throw new AppError(
        'Nao foi possivel encerrar esta sessao.',
        403,
        'SESSION_LOGOUT_FORBIDDEN',
      );
    }

    await this.revokeSession({
      session,
      actorUserId: input.actorUserId,
      auditAction: 'logout',
      revokedReason: 'user_logout',
    });
  }

  async listUserSessions(userId: string, companyId: string) {
    const sessions = await prisma.deviceSession.findMany({
      where: {
        userId,
        companyId,
      },
      orderBy: [{ lastSeenAt: 'desc' }, { createdAt: 'desc' }],
      include: this.sessionInclude,
    });

    return sessions.map((session) => this.toSessionSummaryDto(session));
  }

  async listCompanySessions(companyId: string) {
    const sessions = await prisma.deviceSession.findMany({
      where: {
        companyId,
      },
      orderBy: [{ lastSeenAt: 'desc' }, { createdAt: 'desc' }],
      include: this.sessionInclude,
    });

    return sessions.map((session) => this.toSessionSummaryDto(session));
  }

  async revokeOwnSession(input: {
    sessionId: string;
    actorUserId: string;
    companyId: string;
  }) {
    const session = await this.getSessionOrThrow(input.sessionId);
    if (
      session.userId != input.actorUserId ||
      session.companyId != input.companyId
    ) {
      throw new AppError(
        'Voce so pode revogar sessoes da sua propria conta nesta empresa.',
        403,
        'SESSION_REVOKE_FORBIDDEN',
      );
    }

    await this.revokeSession({
      session,
      actorUserId: input.actorUserId,
      auditAction: 'session_revoked',
      revokedReason: 'user_revoked_session',
    });
  }

  async revokeAllUserSessions(input: {
    userId: string;
    actorUserId: string;
    auditAction: string;
    revokedReason: string;
  }) {
    const sessions = await prisma.deviceSession.findMany({
      where: {
        userId: input.userId,
        revokedAt: null,
      },
    });

    for (const session of sessions) {
      await this.revokeSession({
        session,
        actorUserId: input.actorUserId,
        subjectUserId: input.userId,
        auditAction: input.auditAction,
        revokedReason: input.revokedReason,
      });
    }

    return sessions.length;
  }

  async revokeSessionAsPlatformAdmin(input: {
    sessionId: string;
    actorUserId: string;
  }) {
    const session = await this.getSessionOrThrow(input.sessionId);
    await this.revokeSession({
      session,
      actorUserId: input.actorUserId,
      auditAction: 'session_revoked',
      revokedReason: 'platform_admin_revoked_session',
    });
  }

  async revokeCompanySession(input: {
    companyId: string;
    sessionId: string;
    actorUserId: string;
  }) {
    const session = await this.getSessionOrThrow(input.sessionId);
    if (session.companyId != input.companyId) {
      throw new AppError(
        'Sessao nao encontrada para esta empresa.',
        404,
        'SESSION_NOT_FOUND',
      );
    }

    await this.revokeSession({
      session,
      actorUserId: input.actorUserId,
      auditAction: 'session_revoked',
      revokedReason: 'platform_admin_revoked_session',
    });
  }

  async getRecentAuditSummary() {
    const [countsByAction, recentEvents] = await prisma.$transaction([
      prisma.sessionAuditLog.groupBy({
        by: ['action'],
        orderBy: {
          action: 'asc',
        },
        _count: {
          _all: true,
        },
      }),
      prisma.sessionAuditLog.findMany({
        orderBy: { createdAt: 'desc' },
        take: 20,
        include: {
          actorUser: {
            select: {
              id: true,
              name: true,
              email: true,
            },
          },
          company: {
            select: {
              id: true,
              name: true,
              slug: true,
            },
          },
        },
      }),
    ]);

    return {
      totalEvents: countsByAction.reduce(
        (total, item) => total + ((item._count as { _all?: number })._all ?? 0),
        0,
      ),
      countsByAction: countsByAction.map((item) => ({
        action: item.action,
        count: (item._count as { _all?: number })._all ?? 0,
      })),
      recentEvents: recentEvents.map((event) => ({
        id: event.id,
        action: event.action,
        createdAt: event.createdAt.toISOString(),
        actorUser: event.actorUser,
        targetCompany: event.company,
        details: event.details,
      })),
    };
  }

  private async revokeSessionsForClient(input: {
    companyId: string;
    clientType: SessionClientType;
    clientInstanceId: string;
    actorUserId: string;
    subjectUserId: string;
    auditAction: string;
    revokedReason: string;
  }) {
    const activeSessions = await prisma.deviceSession.findMany({
      where: {
        companyId: input.companyId,
        clientType: input.clientType,
        clientInstanceId: input.clientInstanceId,
        revokedAt: null,
        refreshTokenExpiresAt: {
          gt: new Date(),
        },
      },
    });

    for (const finalSession of activeSessions) {
      await this.revokeSession({
        session: finalSession,
        actorUserId: input.actorUserId,
        subjectUserId: input.subjectUserId,
        auditAction: input.auditAction,
        revokedReason: input.revokedReason,
      });
    }
  }

  private async getSessionOrThrow(sessionId: string) {
    const session = await prisma.deviceSession.findUnique({
      where: { id: sessionId },
    });

    if (!session) {
      throw new AppError('Sessao nao encontrada.', 404, 'SESSION_NOT_FOUND');
    }

    return session;
  }

  private async revokeSession(input: {
    session: DeviceSession;
    actorUserId: string;
    subjectUserId?: string;
    auditAction: string;
    revokedReason: string;
  }) {
    const currentSession = input.session;
    const alreadyRevoked = currentSession.revokedAt != null;
    const session = alreadyRevoked
      ? currentSession
      : await prisma.deviceSession.update({
          where: { id: currentSession.id },
          data: {
            revokedAt: new Date(),
            revokedReason: input.revokedReason,
          },
        });

    await this.recordAudit({
      action: input.auditAction,
      deviceSessionId: session.id,
      actorUserId: input.actorUserId,
      subjectUserId: input.subjectUserId ?? session.userId,
      companyId: session.companyId,
      details: {
        revokedReason: session.revokedReason,
        clientType: this.toPublicClientType(session.clientType),
        clientInstanceId: session.clientInstanceId,
      },
    });
  }

  private buildSessionTokenBundle(input: {
    session: DeviceSessionWithRelations;
    device: CompanyDeviceDto;
    refreshToken: string;
    refreshTokenExpiresAt: Date;
    userId: string;
    userEmail: string;
    userIsPlatformAdmin: boolean;
    companyId: string;
    membershipId: string;
    membershipRole: string;
  }): SessionTokenBundle {
    return {
      accessToken: this.createAccessToken({
        userId: input.userId,
        userEmail: input.userEmail,
        userIsPlatformAdmin: input.userIsPlatformAdmin,
        companyId: input.companyId,
        membershipId: input.membershipId,
        membershipRole: input.membershipRole,
        sessionId: input.session.id,
        clientInstanceId: input.session.clientInstanceId,
      }),
      refreshToken: input.refreshToken,
      tokenType: 'Bearer',
      expiresIn: env.ACCESS_TOKEN_TTL,
      refreshTokenExpiresAt: input.refreshTokenExpiresAt.toISOString(),
      session: this.toSessionSummaryDto(input.session),
      device: this.toSessionDeviceDto(input.device),
    };
  }

  private createAccessToken(input: {
    userId: string;
    userEmail: string;
    userIsPlatformAdmin: boolean;
    companyId: string;
    membershipId: string;
    membershipRole: string;
    sessionId: string;
    clientInstanceId: string;
  }) {
    const signOptions: SignOptions = {
      subject: input.userId,
      expiresIn: env.ACCESS_TOKEN_TTL as SignOptions['expiresIn'],
    };

    return jwt.sign(
      {
        companyId: input.companyId,
        membershipId: input.membershipId,
        membershipRole: input.membershipRole,
        email: input.userEmail,
        isPlatformAdmin: input.userIsPlatformAdmin,
        sessionId: input.sessionId,
        clientInstanceId: input.clientInstanceId,
      },
      env.JWT_SECRET,
      signOptions,
    );
  }

  private resolveClientInput(
    rawInput: SessionClientInput | undefined,
    fallbackUserId: string,
  ) {
    const clientType = this.normalizeClientType(rawInput?.clientType);
    const clientInstanceId = this.normalizeOptionalString(
      rawInput?.clientInstanceId,
    );

    if (clientInstanceId == null) {
      throw new AppError(
        'Identificador do aparelho obrigatorio para abrir sessao.',
        400,
        'DEVICE_REQUIRED',
        {
          clientType: this.toPublicClientType(clientType),
          userId: fallbackUserId,
        },
      );
    }

    return {
      clientType,
      clientInstanceId,
      deviceLabel: this.normalizeOptionalString(rawInput?.deviceLabel),
      platform: this.normalizeOptionalString(rawInput?.platform),
      appVersion: this.normalizeOptionalString(rawInput?.appVersion),
    };
  }

  private normalizeClientType(rawValue: string | null | undefined) {
    switch ((rawValue ?? '').trim().toLowerCase()) {
      case 'mobile_app':
      case 'mobile':
      case 'app':
        return SessionClientType.MOBILE_APP;
      case 'admin_web':
      case 'admin':
      case 'web':
        return SessionClientType.ADMIN_WEB;
      default:
        return SessionClientType.UNKNOWN;
    }
  }

  private toPublicClientType(
    clientType: SessionClientType,
  ): 'mobile_app' | 'admin_web' | 'unknown' {
    switch (clientType) {
      case SessionClientType.MOBILE_APP:
        return 'mobile_app';
      case SessionClientType.ADMIN_WEB:
        return 'admin_web';
      default:
        return 'unknown';
    }
  }

  private isPlatformAdminSupportSession(
    isPlatformAdmin: boolean,
    clientType: SessionClientType,
  ) {
    return isPlatformAdmin && clientType === SessionClientType.ADMIN_WEB;
  }

  private normalizeOptionalString(rawValue: string | null | undefined) {
    if (rawValue == null) {
      return null;
    }

    const normalized = rawValue.trim();
    return normalized.length === 0 ? null : normalized;
  }

  private assertLicenseAllowsSessionRestore(
    license: {
      status: string;
      expiresAt: Date | null;
    } | null,
  ) {
    if (license == null) {
      throw new AppError(
        'Licenca valida obrigatoria para restaurar a sessao do app.',
        403,
        'LICENSE_REQUIRED',
      );
    }

    const expiredByDate =
      license.expiresAt != null && license.expiresAt.getTime() < Date.now();
    if (license.status === LicenseStatus.EXPIRED || expiredByDate) {
      throw new AppError(
        'Licenca expirada para restaurar a sessao do app.',
        403,
        'LICENSE_EXPIRED',
      );
    }

    if (
      license.status !== LicenseStatus.ACTIVE &&
      license.status !== LicenseStatus.TRIAL
    ) {
      throw new AppError(
        'Licenca ativa obrigatoria para restaurar a sessao do app.',
        403,
        'LICENSE_REQUIRED',
      );
    }
  }

  private buildRefreshTokenExpiry(now: Date) {
    return new Date(
      now.getTime() + env.REFRESH_TOKEN_TTL_DAYS * 24 * 60 * 60 * 1000,
    );
  }

  private generateOpaqueToken() {
    return randomBytes(48).toString('base64url');
  }

  private hashToken(token: string) {
    return createHash('sha256').update(token).digest('hex');
  }

  private toSessionSummaryDto(
    session: DeviceSessionWithRelations,
  ): SessionSummaryDto {
    return {
      id: session.id,
      userId: session.user.id,
      userName: session.user.name,
      userEmail: session.user.email,
      companyId: session.company.id,
      companyName: session.company.name,
      membershipId: session.membership.id,
      membershipRole: session.membership.role,
      clientType: this.toPublicClientType(session.clientType),
      clientInstanceId: session.clientInstanceId,
      deviceLabel: session.deviceLabel,
      platform: session.platform,
      appVersion: session.appVersion,
      status: this.resolveSessionStatus(session),
      createdAt: session.createdAt.toISOString(),
      lastSeenAt: session.lastSeenAt.toISOString(),
      lastRefreshedAt: session.lastRefreshedAt?.toISOString() ?? null,
      refreshTokenExpiresAt: session.refreshTokenExpiresAt.toISOString(),
      revokedAt: session.revokedAt?.toISOString() ?? null,
      revokedReason: session.revokedReason,
    };
  }

  private toSessionDeviceDto(device: CompanyDeviceDto): SessionDeviceDto {
    return {
      id: device.id,
      clientInstanceId: device.clientInstanceId,
      status: device.status,
      deviceLabel: device.deviceLabel,
      platform: device.platform,
      appVersion: device.appVersion,
      lastSeenAt: device.lastSeenAt,
    };
  }

  private resolveSessionStatus(session: {
    revokedAt: Date | null;
    refreshTokenExpiresAt: Date;
  }): 'active' | 'revoked' | 'expired' {
    if (session.revokedAt != null) {
      return 'revoked';
    }
    if (session.refreshTokenExpiresAt.getTime() <= Date.now()) {
      return 'expired';
    }
    return 'active';
  }

  private shouldRefreshHeartbeat(lastSeenAt: Date) {
    return Date.now() - lastSeenAt.getTime() >= 5 * 60 * 1000;
  }

  private touchSessionHeartbeat(session: { id: string; lastSeenAt: Date }) {
    if (!this.shouldRefreshHeartbeat(session.lastSeenAt)) {
      return;
    }

    void prisma.deviceSession
      .update({
        where: { id: session.id },
        data: { lastSeenAt: new Date() },
      })
      .catch(() => {});
  }

  private async recordAudit(input: AuditEventInput) {
    await prisma.sessionAuditLog.create({
      data: {
        action: input.action,
        deviceSessionId: input.deviceSessionId ?? undefined,
        actorUserId: input.actorUserId ?? undefined,
        subjectUserId: input.subjectUserId ?? undefined,
        companyId: input.companyId ?? undefined,
        details: input.details,
      },
    });

    logger.info('auth.session.audit', {
      action: input.action,
      deviceSessionId: input.deviceSessionId,
      actorUserId: input.actorUserId,
      subjectUserId: input.subjectUserId,
      companyId: input.companyId,
      details: input.details,
    });
  }

  private get sessionInclude() {
    return {
      user: {
        select: {
          id: true,
          name: true,
          email: true,
        },
      },
      company: {
        select: {
          id: true,
          name: true,
        },
      },
      membership: {
        select: {
          id: true,
          role: true,
        },
      },
    } satisfies Prisma.DeviceSessionInclude;
  }
}
