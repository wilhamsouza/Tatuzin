import {
  CompanyDeviceStatus,
  LicenseStatus,
  MembershipRole,
  Prisma,
  type CompanyDevice,
} from '@prisma/client';

import { prisma } from '../../database/prisma';
import { AppError } from '../../shared/http/app-error';
import { logger } from '../../shared/observability/logger';
import { getPlanEntitlements } from '../plans/plan-catalog.service';

type DeviceIdentityInput = {
  companyId: string;
  userId: string;
  membershipRole: string;
  licensePlan: string | null;
  clientInstanceId: string;
  deviceLabel?: string | null;
  platform?: string | null;
  appVersion?: string | null;
};

export type CompanyDeviceDto = {
  id: string;
  companyId: string;
  userId: string;
  clientInstanceId: string;
  status: CompanyDeviceStatus;
  deviceLabel: string | null;
  platform: string | null;
  appVersion: string | null;
  lastSeenAt: string | null;
};

export class CompanyDeviceService {
  async registerOrResolve(input: DeviceIdentityInput): Promise<CompanyDeviceDto> {
    const clientInstanceId = this.normalizeRequiredClientInstanceId(
      input.clientInstanceId,
    );
    const now = new Date();

    const existingDevice = await prisma.companyDevice.findUnique({
      where: {
        companyId_clientInstanceId: {
          companyId: input.companyId,
          clientInstanceId,
        },
      },
    });

    if (existingDevice != null) {
      const device = await this.updateExistingDevice(existingDevice, input, now);
      this.throwIfDeviceCannotOperate(device);
      return this.toDto(device);
    }

    const maxDevices = getPlanEntitlements(input.licensePlan).limits.maxDevices;
    const activeDevicesCount = await prisma.companyDevice.count({
      where: {
        companyId: input.companyId,
        status: CompanyDeviceStatus.ACTIVE,
      },
    });
    const isFirstOwnerDevice =
      activeDevicesCount === 0 && input.membershipRole === MembershipRole.OWNER;
    const canActivate = isFirstOwnerDevice || activeDevicesCount < maxDevices;

    const device = await prisma.companyDevice.create({
      data: {
        companyId: input.companyId,
        userId: input.userId,
        clientInstanceId,
        deviceLabel: this.normalizeOptionalString(input.deviceLabel),
        platform: this.normalizeOptionalString(input.platform),
        appVersion: this.normalizeOptionalString(input.appVersion),
        status: canActivate
          ? CompanyDeviceStatus.ACTIVE
          : CompanyDeviceStatus.BLOCKED,
        approvedAt: canActivate ? now : undefined,
        approvedByUserId: canActivate ? input.userId : undefined,
        lastSeenAt: now,
        revokedReason: canActivate ? undefined : 'device_limit_reached',
      },
    });

    logger.info('app.device.registered', {
      companyId: input.companyId,
      userId: input.userId,
      deviceId: device.id,
      clientInstanceId,
      status: device.status,
      maxDevices,
      activeDevicesCount,
      autoApproved: canActivate,
    });

    this.throwIfDeviceCannotOperate(device, {
      activeDevices: activeDevicesCount,
      maxDevices,
    });

    return this.toDto(device);
  }

  async resolveForAuthenticatedUser(input: {
    userId: string;
    companyId: string;
    membershipId: string;
    membershipRole: string;
    clientInstanceId: string;
    deviceLabel?: string | null;
    platform?: string | null;
    appVersion?: string | null;
  }) {
    const membership = await prisma.membership.findUnique({
      where: { id: input.membershipId },
      include: {
        company: {
          include: {
            license: true,
          },
        },
        user: {
          select: {
            id: true,
            isActive: true,
          },
        },
      },
    });

    if (
      membership == null ||
      membership.userId !== input.userId ||
      membership.companyId !== input.companyId ||
      !membership.user.isActive ||
      !membership.company.isActive
    ) {
      throw new AppError(
        'Nao foi possivel resolver a empresa desta sessao.',
        403,
        'APP_CONTEXT_REQUIRED',
      );
    }

    if (membership.company.license == null) {
      throw new AppError(
        'A empresa precisa de uma licenca valida para registrar aparelhos.',
        403,
        'LICENSE_REQUIRED',
      );
    }
    this.assertLicenseCanRegisterDevice(membership.company.license);

    return this.registerOrResolve({
      userId: input.userId,
      companyId: input.companyId,
      membershipRole: input.membershipRole,
      licensePlan: membership.company.license.plan,
      clientInstanceId: input.clientInstanceId,
      deviceLabel: input.deviceLabel,
      platform: input.platform,
      appVersion: input.appVersion,
    });
  }

  throwIfDeviceCannotOperate(
    device: CompanyDevice | CompanyDeviceDto,
    limitDetails?: { activeDevices: number; maxDevices: number },
  ) {
    switch (device.status) {
      case CompanyDeviceStatus.ACTIVE:
        return;
      case CompanyDeviceStatus.PENDING:
        throw new AppError(
          'Este aparelho ainda aguarda aprovacao para operar nesta empresa.',
          403,
          'DEVICE_PENDING',
        );
      case CompanyDeviceStatus.BLOCKED:
        throw new AppError(
          'Este aparelho esta bloqueado para operar nesta empresa.',
          limitDetails == null ? 403 : 409,
          limitDetails == null ? 'DEVICE_BLOCKED' : 'DEVICE_LIMIT_REACHED',
          limitDetails,
        );
      case CompanyDeviceStatus.REVOKED:
        throw new AppError(
          'Este aparelho foi revogado para esta empresa.',
          403,
          'DEVICE_REVOKED',
        );
    }
  }

  toDto(device: CompanyDevice): CompanyDeviceDto {
    return {
      id: device.id,
      companyId: device.companyId,
      userId: device.userId,
      clientInstanceId: device.clientInstanceId,
      status: device.status,
      deviceLabel: device.deviceLabel,
      platform: device.platform,
      appVersion: device.appVersion,
      lastSeenAt: device.lastSeenAt?.toISOString() ?? null,
    };
  }

  private async updateExistingDevice(
    existingDevice: CompanyDevice,
    input: DeviceIdentityInput,
    now: Date,
  ) {
    if (existingDevice.status !== CompanyDeviceStatus.ACTIVE) {
      return prisma.companyDevice.update({
        where: { id: existingDevice.id },
        data: {
          lastSeenAt: now,
          deviceLabel:
            this.normalizeOptionalString(input.deviceLabel) ??
            existingDevice.deviceLabel,
          platform:
            this.normalizeOptionalString(input.platform) ??
            existingDevice.platform,
          appVersion:
            this.normalizeOptionalString(input.appVersion) ??
            existingDevice.appVersion,
        },
      });
    }

    return prisma.companyDevice.update({
      where: { id: existingDevice.id },
      data: {
        userId: input.userId,
        lastSeenAt: now,
        deviceLabel:
          this.normalizeOptionalString(input.deviceLabel) ??
          existingDevice.deviceLabel,
        platform:
          this.normalizeOptionalString(input.platform) ??
          existingDevice.platform,
        appVersion:
          this.normalizeOptionalString(input.appVersion) ??
          existingDevice.appVersion,
      },
    });
  }

  private normalizeRequiredClientInstanceId(rawValue: string) {
    const normalized = rawValue.trim();
    if (normalized.length === 0) {
      throw new AppError(
        'Identificador do aparelho ausente.',
        400,
        'DEVICE_REQUIRED',
      );
    }
    return normalized;
  }

  private normalizeOptionalString(rawValue: string | null | undefined) {
    if (rawValue == null) {
      return null;
    }

    const normalized = rawValue.trim();
    return normalized.length === 0 ? null : normalized;
  }

  private assertLicenseCanRegisterDevice(license: {
    status: string;
    expiresAt: Date | null;
  }) {
    const expiredByDate =
      license.expiresAt != null && license.expiresAt.getTime() < Date.now();
    if (license.status === LicenseStatus.EXPIRED || expiredByDate) {
      throw new AppError(
        'Licenca expirada para registrar aparelhos.',
        403,
        'LICENSE_EXPIRED',
      );
    }

    if (
      license.status !== LicenseStatus.ACTIVE &&
      license.status !== LicenseStatus.TRIAL
    ) {
      throw new AppError(
        'Licenca ativa obrigatoria para registrar aparelhos.',
        403,
        'LICENSE_REQUIRED',
      );
    }
  }
}

export function rethrowCompanyDeviceConstraintError(error: unknown): never | void {
  if (
    error instanceof Prisma.PrismaClientKnownRequestError &&
    error.code === 'P2002'
  ) {
    throw new AppError(
      'Este aparelho ja esta vinculado a esta empresa. Tente novamente.',
      409,
      'DEVICE_REQUIRED',
    );
  }
}
