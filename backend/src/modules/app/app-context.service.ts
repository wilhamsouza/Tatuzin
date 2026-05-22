import type { Request } from "express";
import { CompanyDeviceStatus, LicenseStatus } from "@prisma/client";

import { prisma } from "../../database/prisma";
import { AppError } from "../../shared/http/app-error";
import { logger } from "../../shared/observability/logger";
import { EmployeeContextService } from "../employees/employee-context.service";
import { getPlanEntitlements } from "../plans/plan-catalog.service";
import type { AppContext } from "./app-context.types";

export class AppContextService {
  private readonly employeeContextService = new EmployeeContextService();

  async resolveFromRequest(request: Request): Promise<AppContext> {
    const auth = request.auth;
    if (auth == null) {
      throw new AppError(
        "Contexto de aplicativo ausente.",
        401,
        "APP_CONTEXT_REQUIRED",
      );
    }

    if (
      this.isBlank(auth.userId) ||
      this.isBlank(auth.companyId) ||
      this.isBlank(auth.membershipId)
    ) {
      throw new AppError(
        "Sessao sem empresa, usuario ou membership valido.",
        403,
        "APP_CONTEXT_REQUIRED",
      );
    }

    const clientInstanceId = this.resolveClientInstanceId(request);
    const membership = await prisma.membership.findUnique({
      where: { id: auth.membershipId },
      include: {
        user: {
          select: {
            id: true,
            name: true,
            email: true,
            isActive: true,
            mustChangePassword: true,
          },
        },
        company: {
          include: {
            license: true,
          },
        },
      },
    });

    if (
      membership == null ||
      membership.userId !== auth.userId ||
      membership.companyId !== auth.companyId ||
      !membership.user.isActive
    ) {
      throw new AppError(
        "Membership ativo obrigatorio para operar no app.",
        403,
        "MEMBERSHIP_REQUIRED",
      );
    }

    if (membership.user.mustChangePassword) {
      throw new AppError(
        "Voce precisa criar uma nova senha para continuar.",
        403,
        "INITIAL_PASSWORD_CHANGE_REQUIRED",
      );
    }

    if (!membership.company.isActive) {
      throw new AppError(
        "Empresa ativa obrigatoria para operar no app.",
        403,
        "COMPANY_REQUIRED",
      );
    }

    const license = membership.company.license;
    if (license == null) {
      throw new AppError(
        "Licenca valida obrigatoria para operar no app.",
        403,
        "LICENSE_REQUIRED",
      );
    }

    this.assertLicenseCanOperate(license);
    const entitlements = getPlanEntitlements(license.plan);
    const employeeContext =
      await this.employeeContextService.resolveForMembership({
        companyId: membership.companyId,
        userId: membership.userId,
        membershipId: membership.id,
        membershipRole: membership.role,
        userName: membership.user.name,
        userEmail: membership.user.email,
      });

    if (
      employeeContext.employee != null &&
      !["ACTIVE", "INVITED"].includes(employeeContext.employee.status)
    ) {
      throw new AppError(
        "Funcionario desativado nao pode acessar o app.",
        403,
        "EMPLOYEE_DISABLED",
      );
    }

    const device = await prisma.companyDevice.findUnique({
      where: {
        companyId_clientInstanceId: {
          companyId: auth.companyId,
          clientInstanceId,
        },
      },
    });

    if (device == null) {
      throw new AppError(
        "Aparelho autorizado obrigatorio para operar no app.",
        403,
        "DEVICE_REQUIRED",
      );
    }

    switch (device.status) {
      case CompanyDeviceStatus.ACTIVE:
        break;
      case CompanyDeviceStatus.PENDING:
        throw new AppError(
          "Este aparelho ainda aguarda aprovacao para operar nesta empresa.",
          403,
          "DEVICE_PENDING",
        );
      case CompanyDeviceStatus.BLOCKED:
        throw new AppError(
          "Este aparelho esta bloqueado para operar nesta empresa.",
          403,
          "DEVICE_BLOCKED",
        );
      case CompanyDeviceStatus.REVOKED:
        throw new AppError(
          "Este aparelho foi revogado para esta empresa.",
          403,
          "DEVICE_REVOKED",
        );
    }

    await this.touchDeviceIfNeeded(device.id, device.lastSeenAt);

    return {
      user: {
        id: membership.user.id,
        name: membership.user.name,
        email: membership.user.email,
      },
      company: {
        id: membership.company.id,
        name: membership.company.name,
        legalName: membership.company.legalName,
        documentNumber: membership.company.documentNumber,
        receiptDisplayName: membership.company.receiptDisplayName,
        receiptDocument: membership.company.receiptDocument,
        receiptPhone: membership.company.receiptPhone,
        receiptAddress: membership.company.receiptAddress,
        receiptFooterMessage: membership.company.receiptFooterMessage,
        showDocumentOnReceipt: membership.company.showDocumentOnReceipt,
        showPhoneOnReceipt: membership.company.showPhoneOnReceipt,
        showAddressOnReceipt: membership.company.showAddressOnReceipt,
        showFooterMessageOnReceipt:
          membership.company.showFooterMessageOnReceipt,
        setupCompleted: true,
      },
      membership: {
        id: membership.id,
        role: employeeContext.membershipRole,
        permissions: employeeContext.permissions,
      },
      employee: employeeContext.employee,
      license: {
        id: license.id,
        plan: license.plan,
        status: license.status,
        syncEnabled: license.syncEnabled,
        maxDevices: license.maxDevices,
        expiresAt: license.expiresAt?.toISOString() ?? null,
        pendingPlan: license.pendingPlan,
        pendingPlanRequestedAt:
          license.pendingPlanRequestedAt?.toISOString() ?? null,
      },
      device: {
        id: device.id,
        clientInstanceId: device.clientInstanceId,
        status: device.status,
        deviceLabel: device.deviceLabel,
        platform: device.platform,
        appVersion: device.appVersion,
        lastSeenAt: device.lastSeenAt?.toISOString() ?? null,
      },
      plan: entitlements.plan,
      features: entitlements.features,
      limits: entitlements.limits,
      clientInstanceId,
      tenantReady: true,
    };
  }

  logBootstrapOutcome(input: {
    appContext?: AppContext;
    blockedReason?: string;
    syncEnabled?: boolean;
  }) {
    const context = input.appContext;
    logger.info("app.bootstrap.context", {
      sessionState: context == null ? "blocked" : "authenticated",
      companyId: context?.company.id,
      userId: context?.user.id,
      deviceId: context?.device.id,
      clientInstanceId: context?.clientInstanceId,
      dbName: "remote_postgres",
      plan: context?.plan,
      tenantReady: context?.tenantReady ?? false,
      syncEnabled: context?.license.syncEnabled ?? input.syncEnabled ?? false,
      offlineAllowed: false,
      blockedReason: input.blockedReason,
    });
  }

  private resolveClientInstanceId(request: Request) {
    const clientFromSession = request.auth?.clientInstanceId;
    const clientFromHeader =
      this.headerValue(request, "x-client-instance-id") ??
      this.headerValue(request, "x-device-id");

    if (
      clientFromSession != null &&
      clientFromHeader != null &&
      clientFromSession !== clientFromHeader
    ) {
      throw new AppError(
        "O identificador do aparelho nao confere com a sessao.",
        401,
        "DEVICE_REQUIRED",
      );
    }

    const clientInstanceId = clientFromHeader ?? clientFromSession;
    if (clientInstanceId == null || clientInstanceId.trim().length === 0) {
      throw new AppError(
        "Identificador do aparelho obrigatorio para operar no app.",
        400,
        "DEVICE_REQUIRED",
      );
    }

    return clientInstanceId.trim();
  }

  private assertLicenseCanOperate(license: {
    status: LicenseStatus;
    expiresAt: Date | null;
  }) {
    const expiredByDate =
      license.expiresAt != null && license.expiresAt.getTime() < Date.now();

    if (license.status === LicenseStatus.EXPIRED || expiredByDate) {
      throw new AppError(
        "Licenca expirada para operar no app.",
        403,
        "LICENSE_EXPIRED",
      );
    }

    if (
      license.status !== LicenseStatus.ACTIVE &&
      license.status !== LicenseStatus.TRIAL
    ) {
      throw new AppError(
        "Licenca ativa obrigatoria para operar no app.",
        403,
        "LICENSE_REQUIRED",
      );
    }
  }

  private async touchDeviceIfNeeded(deviceId: string, lastSeenAt: Date | null) {
    if (
      lastSeenAt != null &&
      Date.now() - lastSeenAt.getTime() < 5 * 60 * 1000
    ) {
      return;
    }

    await prisma.companyDevice.update({
      where: { id: deviceId },
      data: { lastSeenAt: new Date() },
    });
  }

  private headerValue(request: Request, headerName: string) {
    const rawValue = request.headers[headerName];
    const value = Array.isArray(rawValue) ? rawValue[0] : rawValue;
    if (value == null) {
      return null;
    }

    const normalized = value.trim();
    return normalized.length === 0 ? null : normalized;
  }

  private isBlank(value: string | null | undefined) {
    return value == null || value.trim().length === 0;
  }
}
