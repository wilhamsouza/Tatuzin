import type { PrismaClient } from "@prisma/client";

import { prisma } from "../../database/prisma";
import { AppError } from "../../shared/http/app-error";

export const tenantPendingDeletionStatus = "FUTURE_PENDING_DELETION" as const;

type TenantLifecycleClient = Pick<PrismaClient, "tenantDeletionRequest">;

export class TenantLifecycleService {
  constructor(
    private readonly client: TenantLifecycleClient = prisma as TenantLifecycleClient,
  ) {}

  async findPendingDeletion(companyId: string) {
    const normalizedCompanyId = companyId.trim();
    if (normalizedCompanyId.length === 0) {
      return null;
    }

    return this.client.tenantDeletionRequest.findFirst({
      where: {
        companyId: normalizedCompanyId,
        status: tenantPendingDeletionStatus,
        activeCompanyGuard: normalizedCompanyId,
      },
      select: {
        id: true,
        companyId: true,
        status: true,
        updatedAt: true,
      },
    });
  }

  async assertTenantOperational(companyId: string) {
    const request = await this.findPendingDeletion(companyId);
    if (request == null) {
      return;
    }

    throw new AppError(
      "Empresa em quarentena por solicitacao de exclusao. Acesso operacional e sincronizacao estao bloqueados.",
      423,
      "TENANT_PENDING_DELETION",
    );
  }
}
