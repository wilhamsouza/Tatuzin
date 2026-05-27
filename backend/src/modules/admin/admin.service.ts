import type {
  License,
  LicenseStatus,
  Prisma,
  SessionAuditLog,
} from "@prisma/client";

import { prisma } from "../../database/prisma";
import { buildAdminListResponse } from "../../shared/http/api-response";
import { toPaginationParams } from "../../shared/http/pagination";
import { logger } from "../../shared/observability/logger";
import { AppError } from "../../shared/http/app-error";
import { AuthSessionService } from "../auth/auth-session.service";
import {
  classifySyncOperationalStatus,
  observedSyncFeatureCatalog,
  telemetryGapFeatures,
  unavailableOperationalSignals,
} from "./admin-sync-operational";
import {
  EMPLOYEE_PERMISSIONS,
  defaultPermissionsForRole,
  effectivePermissionsForEmployee,
  parseStoredPermissions,
  roleFromMembershipRole,
} from "../employees/employee-permissions";
import { BillingService } from "../billing/billing.service";
import { maskProviderSubscriptionId } from "../billing/billing-sanitizer";
import {
  FEATURE_KEYS,
  PLAN_KEYS,
  getPlanEntitlements,
  requiredPlanForFeature,
  type PlanKey,
} from "../plans/plan-catalog.service";
import type {
  AdminAuditQueryInput,
  AdminCompaniesQueryInput,
  AdminLicensePatchInput,
  AdminLicensesQueryInput,
  AdminSyncOperationalQueryInput,
  AdminSyncQueryInput,
} from "./admin.schemas";

type CompanyWithCounts = Prisma.CompanyGetPayload<{
  include: {
    license: true;
    _count: {
      select: {
        memberships: true;
        categories: true;
        products: true;
        customers: true;
        suppliers: true;
        purchases: true;
        sales: true;
        financialEvents: true;
        cashEvents: true;
      };
    };
  };
}>;

type CompanyIdentity = {
  id: string;
  name: string;
  legalName: string;
  slug: string;
  isActive: boolean;
};

type AdminAuditEventDto = {
  id: string;
  source: "admin" | "session";
  action: string;
  createdAt: string;
  actorUser: {
    id: string;
    name: string;
    email: string;
  } | null;
  targetCompany: {
    id: string;
    name: string;
    slug: string;
  } | null;
  details: Prisma.JsonValue | null;
};

type SessionAuditEventWithRelations = Prisma.SessionAuditLogGetPayload<{
  include: {
    actorUser: {
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
        slug: true;
      };
    };
  };
}>;

type SyncObservedFeatureAggregate = {
  featureKey: string;
  displayName: string;
  remoteRecordCount: number;
  lastObservedRemoteChangeAt: string | null;
};

type SyncObservedFeatureSnapshot = SyncObservedFeatureAggregate & {
  observationKind: "remote_mirror";
};

type AdminAccessTargetType = "USER" | "MEMBERSHIP" | "EMPLOYEE";

type AdminAccessActionParams = {
  companyId: string;
  targetId: string;
  targetType: AdminAccessTargetType;
  reason: string;
  note?: string | null;
  actorUserId?: string | null;
  ipAddress?: string | null;
  userAgent?: string | null;
};

type AdminAccessApplyParams = AdminAccessActionParams & {
  confirmationText: string;
};

type AdminAccessEmployeeTarget = Prisma.EmployeeProfileGetPayload<{
  include: {
    user: {
      select: {
        id: true;
        name: true;
        email: true;
        isActive: true;
        isPlatformAdmin: true;
        mustChangePassword: true;
        temporaryPasswordExpiresAt: true;
      };
    };
    membership: {
      select: {
        id: true;
        role: true;
        isDefault: true;
        createdAt: true;
        updatedAt: true;
      };
    };
  };
}>;

export class AdminService {
  private readonly accessEmployeeInclude = {
    user: {
      select: {
        id: true,
        name: true,
        email: true,
        isActive: true,
        isPlatformAdmin: true,
        mustChangePassword: true,
        temporaryPasswordExpiresAt: true,
      },
    },
    membership: {
      select: {
        id: true,
        role: true,
        isDefault: true,
        createdAt: true,
        updatedAt: true,
      },
    },
  } satisfies Prisma.EmployeeProfileInclude;

  constructor(
    private readonly sessionService = new AuthSessionService(),
    private readonly billingService = new BillingService(),
  ) {}

  async listCompanies(query: AdminCompaniesQueryInput) {
    const where = this.buildCompanyWhere(query);
    const { skip, take } = toPaginationParams(query);

    const [total, companies] = await prisma.$transaction([
      prisma.company.count({ where }),
      prisma.company.findMany({
        where,
        skip,
        take,
        orderBy: this.resolveCompanyOrderBy(query),
        include: {
          license: true,
          _count: {
            select: {
              memberships: true,
              categories: true,
              products: true,
              customers: true,
              suppliers: true,
              purchases: true,
              sales: true,
              financialEvents: true,
              cashEvents: true,
            },
          },
        },
      }),
    ]);

    const items = companies.map((company) => this.toCompanySummary(company));
    return buildAdminListResponse({
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      filters: {
        search: query.search ?? null,
        isActive: query.isActive ?? null,
        licenseStatus: query.licenseStatus ?? null,
        syncEnabled: query.syncEnabled ?? null,
      },
      sort: {
        by: query.sortBy,
        direction: query.sortDirection,
      },
    });
  }

  async getCompany(companyId: string) {
    const company = await prisma.company.findUnique({
      where: { id: companyId },
      include: {
        license: true,
        memberships: {
          orderBy: [{ isDefault: "desc" }, { createdAt: "asc" }],
          include: {
            user: {
              select: {
                id: true,
                name: true,
                email: true,
                isActive: true,
                isPlatformAdmin: true,
              },
            },
          },
        },
        _count: {
          select: {
            memberships: true,
            categories: true,
            products: true,
            customers: true,
            suppliers: true,
            purchases: true,
            sales: true,
            financialEvents: true,
            cashEvents: true,
          },
        },
      },
    });

    if (!company) {
      throw new AppError(
        "Empresa nao encontrada.",
        404,
        "ADMIN_COMPANY_NOT_FOUND",
      );
    }

    const sessions = await this.sessionService.listCompanySessions(companyId);

    return {
      company: this.toCompanySummary(company),
      memberships: company.memberships.map((membership) => ({
        id: membership.id,
        role: membership.role,
        isDefault: membership.isDefault,
        createdAt: membership.createdAt.toISOString(),
        updatedAt: membership.updatedAt.toISOString(),
        user: {
          id: membership.user.id,
          name: membership.user.name,
          email: membership.user.email,
          isActive: membership.user.isActive,
          isPlatformAdmin: membership.user.isPlatformAdmin,
        },
      })),
      sessions,
    };
  }

  async listDevices(query: AdminDevicesQueryInput) {
    const { skip, take } = toPaginationParams(query);
    const search = query.search?.trim();
    const status =
      query.status === "all" ? undefined : query.status.toUpperCase();

    if (query.companyId != null) {
      await this.requireCompany(query.companyId);
    }

    const devices = await prisma.companyDevice.findMany({
      where: {
        ...(query.companyId == null ? {} : { companyId: query.companyId }),
        ...(status == null ? {} : { status: status as never }),
        ...(search == null
          ? {}
          : {
              OR: [
                { id: { contains: search, mode: "insensitive" } },
                { clientInstanceId: { contains: search, mode: "insensitive" } },
                { deviceLabel: { contains: search, mode: "insensitive" } },
                { platform: { contains: search, mode: "insensitive" } },
                { appVersion: { contains: search, mode: "insensitive" } },
                {
                  company: {
                    name: { contains: search, mode: "insensitive" },
                  },
                },
                { user: { name: { contains: search, mode: "insensitive" } } },
                { user: { email: { contains: search, mode: "insensitive" } } },
              ],
            }),
      },
      orderBy: [{ lastSeenAt: "desc" }, { createdAt: "desc" }],
      take: 500,
      include: {
        company: {
          select: {
            id: true,
            name: true,
            slug: true,
          },
        },
        user: {
          select: {
            id: true,
            name: true,
            email: true,
          },
        },
        syncDiagnostic: true,
      },
    });

    const sessions = await this.findSessionsForDevices(devices);
    const sessionByDeviceKey = new Map<string, AdminDeviceInventorySession>();
    for (const session of sessions) {
      const key = `${session.companyId}:${session.clientInstanceId}`;
      if (!sessionByDeviceKey.has(key)) {
        sessionByDeviceKey.set(key, session);
      }
    }

    const items = devices
      .map((device) =>
        this.toDeviceInventoryDto(
          device,
          sessionByDeviceKey.get(
            `${device.companyId}:${device.clientInstanceId}`,
          ) ?? null,
        ),
      )
      .filter((device) =>
        query.clientType === "all"
          ? true
          : device.clientType === query.clientType,
      )
      .filter((device) =>
        query.attention === true
          ? device.diagnostic != null &&
            (device.diagnostic.pendingCount > 0 ||
              device.diagnostic.failedCount > 0 ||
              device.diagnostic.openConflictCount > 0)
          : true,
      );

    return buildAdminListResponse({
      items: items.slice(skip, skip + take),
      page: query.page,
      pageSize: query.pageSize,
      total: items.length,
      filters: {
        companyId: query.companyId ?? null,
        search: query.search ?? null,
        clientType: query.clientType,
        status: query.status,
        attention: query.attention ?? null,
      },
      sort: { by: "lastSeenAt", direction: "desc" },
    });
  }

  async listCompanySessions(companyId: string) {
    await this.requireCompany(companyId);
    const sessions = (await this.sessionService.listCompanySessions(companyId))
      .map((session) => this.toAdminSessionDto(session));

    return {
      items: sessions,
      count: sessions.length,
    };
  }

  async getCompanyAccessSummary(companyId: string) {
    const company = await prisma.company.findUnique({
      where: { id: companyId },
      include: { license: true },
    });

    if (!company) {
      throw new AppError(
        "Empresa nao encontrada.",
        404,
        "ADMIN_COMPANY_NOT_FOUND",
      );
    }

    const [memberships, employeeProfiles, sessions, adminAuditLogs] =
      await prisma.$transaction([
        prisma.membership.findMany({
          where: { companyId },
          orderBy: [{ role: "asc" }, { createdAt: "asc" }],
          include: {
            user: {
              select: {
                id: true,
                name: true,
                email: true,
                isActive: true,
                isPlatformAdmin: true,
                mustChangePassword: true,
                temporaryPasswordExpiresAt: true,
                createdAt: true,
                updatedAt: true,
              },
            },
            employeeProfiles: true,
          },
        }),
        prisma.employeeProfile.findMany({
          where: { companyId },
          orderBy: [{ role: "asc" }, { name: "asc" }],
          include: {
            user: {
              select: {
                id: true,
                name: true,
                email: true,
                isActive: true,
                isPlatformAdmin: true,
                mustChangePassword: true,
                temporaryPasswordExpiresAt: true,
                createdAt: true,
                updatedAt: true,
              },
            },
            membership: {
              select: {
                id: true,
                role: true,
                isDefault: true,
                createdAt: true,
                updatedAt: true,
              },
            },
          },
        }),
        prisma.deviceSession.findMany({
          where: { companyId },
          orderBy: { lastSeenAt: "desc" },
          take: 100,
          include: {
            user: {
              select: {
                id: true,
                name: true,
                email: true,
              },
            },
            membership: {
              select: {
                id: true,
                role: true,
              },
            },
          },
        }),
        prisma.adminAuditLog.findMany({
          where: {
            targetCompanyId: companyId,
            action: {
              in: [
                "access.block",
                "access.reactivate",
                "admin.access.block",
                "admin.access.reactivate",
              ],
            },
          },
          orderBy: { createdAt: "desc" },
          take: 20,
          include: {
            actorUser: {
              select: {
                id: true,
                name: true,
                email: true,
              },
            },
          },
        }),
      ]);

    const employeeByMembershipId = new Map(
      employeeProfiles
        .filter((employee) => employee.membershipId != null)
        .map((employee) => [employee.membershipId!, employee]),
    );
    const employeeByUserId = new Map(
      employeeProfiles
        .filter((employee) => employee.userId != null)
        .map((employee) => [employee.userId!, employee]),
    );

    const deviceDtos = sessions.map((session) => ({
      id: session.id,
      userId: session.userId,
      membershipId: session.membershipId,
      userName: session.user.name,
      userEmail: session.user.email,
      membershipRole: session.membership.role,
      clientType: session.clientType,
      clientInstanceId: session.clientInstanceId,
      deviceLabel: session.deviceLabel,
      platform: session.platform,
      appVersion: session.appVersion,
      status: session.revokedAt == null ? "ACTIVE" : "REVOKED",
      lastSeenAt: session.lastSeenAt.toISOString(),
      lastRefreshedAt: session.lastRefreshedAt?.toISOString() ?? null,
      createdAt: session.createdAt.toISOString(),
      updatedAt: session.updatedAt.toISOString(),
    }));

    const users = memberships.map((membership) => {
      const employee =
        employeeByMembershipId.get(membership.id) ??
        employeeByUserId.get(membership.userId) ??
        null;
      const role = employee?.role ?? roleFromMembershipRole(membership.role);
      const status =
        employee?.status ?? (membership.user.isActive ? "ACTIVE" : "DISABLED");
      const effectivePermissions =
        employee == null
          ? membership.user.isActive
            ? defaultPermissionsForRole(roleFromMembershipRole(membership.role))
            : []
          : effectivePermissionsForEmployee(employee);
      const userDevices = deviceDtos.filter(
        (device) => device.userId === membership.userId,
      );

      return {
        userId: membership.user.id,
        membershipId: membership.id,
        employeeProfileId: employee?.id ?? null,
        name: membership.user.name,
        email: membership.user.email,
        membershipRole: membership.role,
        employeeRole: role,
        status,
        accountStatus: membership.user.isActive ? "ACTIVE" : "DISABLED",
        effectivePermissions,
        isOwner: membership.role === "OWNER" || role === "OWNER",
        isProtectedOwner: membership.role === "OWNER" || role === "OWNER",
        hasUserAccount: true,
        hasEmployeeProfile: employee != null,
        invitationStatus: employee?.status === "INVITED" ? "PENDING" : null,
        invitationSentAt: employee?.invitedAt?.toISOString() ?? null,
        lastSeenAt: userDevices[0]?.lastSeenAt ?? null,
        createdAt: membership.createdAt.toISOString(),
        updatedAt: membership.updatedAt.toISOString(),
        devices: userDevices,
      };
    });

    const employees = employeeProfiles.map((employee) => {
      const role = employee.role;
      const status = employee.status;
      const effectivePermissions = effectivePermissionsForEmployee(employee);
      return {
        employeeProfileId: employee.id,
        userId: employee.userId,
        membershipId: employee.membershipId,
        name: employee.name,
        email: employee.email,
        phone: employee.phone,
        employeeRole: role,
        membershipRole: employee.membership?.role ?? null,
        status,
        savedPermissions: parseStoredPermissions(employee.permissions) ?? [],
        effectivePermissions,
        isOwner: role === "OWNER" || employee.membership?.role === "OWNER",
        isProtectedOwner:
          role === "OWNER" || employee.membership?.role === "OWNER",
        hasUserAccount: employee.userId != null,
        hasEmployeeProfile: true,
        invitationStatus: status === "INVITED" ? "PENDING" : null,
        invitationSentAt: employee.invitedAt?.toISOString() ?? null,
        inviteExpiresAt: employee.inviteExpiresAt?.toISOString() ?? null,
        acceptedAt: employee.acceptedAt?.toISOString() ?? null,
        disabledAt: employee.disabledAt?.toISOString() ?? null,
        createdAt: employee.createdAt.toISOString(),
        updatedAt: employee.updatedAt.toISOString(),
      };
    });

    const summary = {
      totalUsers: users.length,
      totalEmployees: employees.length,
      activeEmployees: employees.filter(
        (employee) => employee.status === "ACTIVE",
      ).length,
      invitedEmployees: employees.filter(
        (employee) => employee.status === "INVITED",
      ).length,
      disabledEmployees: employees.filter(
        (employee) => employee.status === "DISABLED",
      ).length,
      owners: users.filter((user) => user.isOwner).length,
      admins: users.filter(
        (user) =>
          user.membershipRole === "ADMIN" || user.employeeRole === "MANAGER",
      ).length,
      operators: users.filter(
        (user) =>
          user.membershipRole === "OPERATOR" && user.employeeRole !== "MANAGER",
      ).length,
      usersWithoutEmployeeProfile: users.filter(
        (user) => !user.hasEmployeeProfile,
      ).length,
      employeeProfilesWithoutUser: employees.filter(
        (employee) => !employee.hasUserAccount,
      ).length,
      lastSeenAt: deviceDtos[0]?.lastSeenAt ?? null,
      lastPermissionChangeAt:
        employees
          .map((employee) => employee.updatedAt)
          .sort()
          .reverse()[0] ?? null,
    };

    return {
      company: {
        id: company.id,
        name: company.name,
        slug: company.slug,
        license:
          company.license == null
            ? null
            : {
                plan: company.license.plan,
                status: company.license.status,
                pendingPlan: company.license.pendingPlan,
              },
      },
      summary,
      users,
      employees,
      permissionsCatalog: EMPLOYEE_PERMISSIONS.map((permission) => ({
        key: permission,
        description: this.describeEmployeePermission(permission),
        owner: true,
        admin: defaultPermissionsForRole("MANAGER").includes(permission),
        operator: defaultPermissionsForRole("CASHIER").includes(permission),
      })),
      devices: deviceDtos,
      audit: adminAuditLogs.map((event) =>
        this.serializeAccessAuditLog(event, company.name),
      ),
    };
  }

  async dryRunAccessBlock(input: AdminAccessActionParams) {
    return this.buildAccessActionDryRun(input, "block");
  }

  async dryRunAccessReactivate(input: AdminAccessActionParams) {
    return this.buildAccessActionDryRun(input, "reactivate");
  }

  async applyAccessBlock(input: AdminAccessApplyParams) {
    if (input.confirmationText.trim() !== "BLOQUEAR") {
      throw new AppError(
        "Digite BLOQUEAR para liberar a confirmacao.",
        422,
        "ADMIN_CONFIRMATION_INVALID",
      );
    }
    const validation = await this.buildAccessActionDryRun(input, "block");
    if (!validation.allowed) {
      throw new AppError(
        "Bloqueio de acesso operacional nao permitido para este alvo.",
        409,
        "ADMIN_ACCESS_ACTION_BLOCKED",
        { blockers: validation.blockers },
      );
    }
    const employeeProfileId = validation.currentAccess?.employeeProfileId;
    if (
      typeof employeeProfileId !== "string" ||
      employeeProfileId.length === 0
    ) {
      throw new AppError(
        "Alvo de acesso nao encontrado nesta empresa.",
        404,
        "ADMIN_ACCESS_TARGET_NOT_FOUND",
      );
    }
    const actorUserId = this.requireAdminActor(input.actorUserId);

    const now = new Date();
    const result = await prisma.$transaction(async (transaction) => {
      const current = await transaction.employeeProfile.findUniqueOrThrow({
        where: { id: employeeProfileId },
        include: this.accessEmployeeInclude,
      });
      const before = this.serializeAccessEmployee(current);
      const updated = await transaction.employeeProfile.update({
        where: { id: current.id },
        data: {
          status: "DISABLED",
          disabledAt: current.disabledAt ?? now,
          updatedByUserId: actorUserId,
        },
        include: this.accessEmployeeInclude,
      });
      const after = this.serializeAccessEmployee(updated);
      const audit = await transaction.adminAuditLog.create({
        data: {
          actorUserId,
          targetCompanyId: input.companyId,
          action: "access.block",
          details: this.buildAccessAuditDetails({
            input,
            before,
            after,
            confirmationTextExpected: "BLOQUEAR",
          }),
        },
      });
      return { updated, audit };
    });

    return {
      success: true,
      message: "Acesso operacional bloqueado com seguranca.",
      updatedAccess: this.serializeAccessEmployee(result.updated),
      auditId: result.audit.id,
    };
  }

  async applyAccessReactivate(input: AdminAccessApplyParams) {
    if (input.confirmationText.trim() !== "REATIVAR") {
      throw new AppError(
        "Digite REATIVAR para liberar a confirmacao.",
        422,
        "ADMIN_CONFIRMATION_INVALID",
      );
    }
    const validation = await this.buildAccessActionDryRun(input, "reactivate");
    if (!validation.allowed) {
      throw new AppError(
        "Reativacao de acesso operacional nao permitida para este alvo.",
        409,
        "ADMIN_ACCESS_ACTION_BLOCKED",
        { blockers: validation.blockers },
      );
    }
    const employeeProfileId = validation.currentAccess?.employeeProfileId;
    if (
      typeof employeeProfileId !== "string" ||
      employeeProfileId.length === 0
    ) {
      throw new AppError(
        "Alvo de acesso nao encontrado nesta empresa.",
        404,
        "ADMIN_ACCESS_TARGET_NOT_FOUND",
      );
    }
    const actorUserId = this.requireAdminActor(input.actorUserId);

    const result = await prisma.$transaction(async (transaction) => {
      const current = await transaction.employeeProfile.findUniqueOrThrow({
        where: { id: employeeProfileId },
        include: this.accessEmployeeInclude,
      });
      const before = this.serializeAccessEmployee(current);
      const updated = await transaction.employeeProfile.update({
        where: { id: current.id },
        data: {
          status: "ACTIVE",
          disabledAt: null,
          updatedByUserId: actorUserId,
        },
        include: this.accessEmployeeInclude,
      });
      const after = this.serializeAccessEmployee(updated);
      const audit = await transaction.adminAuditLog.create({
        data: {
          actorUserId,
          targetCompanyId: input.companyId,
          action: "access.reactivate",
          details: this.buildAccessAuditDetails({
            input,
            before,
            after,
            confirmationTextExpected: "REATIVAR",
          }),
        },
      });
      return { updated, audit };
    });

    return {
      success: true,
      message: "Acesso operacional reativado com seguranca.",
      updatedAccess: this.serializeAccessEmployee(result.updated),
      auditId: result.audit.id,
    };
  }

  async revokeSession(input: { sessionId: string; actorUserId: string }) {
    await this.sessionService.revokeSessionAsPlatformAdmin(input);
  }

  async getPlansOverview() {
    const countResults = await prisma.$transaction([
      ...PLAN_KEYS.map((plan) => prisma.license.count({ where: { plan } })),
      ...PLAN_KEYS.map((plan) =>
        prisma.license.count({ where: { plan, status: "ACTIVE" } }),
      ),
      ...PLAN_KEYS.map((plan) =>
        prisma.license.count({ where: { pendingPlan: plan } }),
      ),
    ]);
    const companiesByPlan = planCountRecordFromValues(countResults.slice(0, 3));
    const activeCompaniesByPlan = planCountRecordFromValues(
      countResults.slice(3, 6),
    );
    const pendingCompaniesByPlan = planCountRecordFromValues(
      countResults.slice(6, 9),
    );
    const publicPlans = new Map(
      this.billingService.listPlans().map((plan) => [plan.key, plan]),
    );

    const items = PLAN_KEYS.map((plan) => {
      const publicPlan = publicPlans.get(plan);
      return {
        key: plan,
        name: publicPlan?.name ?? plan,
        description: publicPlan?.description ?? null,
        priceCents: publicPlan?.priceCents ?? null,
        currency: publicPlan?.currency ?? null,
        billingCycle: publicPlan?.billingCycle ?? null,
        featuresSummary: publicPlan?.featuresSummary ?? [],
        entitlements: getPlanEntitlements(plan),
        usage: {
          companiesCount: companiesByPlan[plan] ?? 0,
          activeCompaniesCount: activeCompaniesByPlan[plan] ?? 0,
          pendingPlanCount: pendingCompaniesByPlan[plan] ?? 0,
        },
        status: "ACTIVE",
        isPublic: true,
        observations: planObservations(plan),
      };
    });

    return {
      items,
      features: FEATURE_KEYS.map((feature) => ({
        key: feature,
        requiredPlan: requiredPlanForFeature(feature),
      })),
      usageSummary: {
        totalPlans: PLAN_KEYS.length,
        companiesByPlan,
        activeCompaniesByPlan,
        pendingCompaniesByPlan,
        pendingPlanCount: Object.values(pendingCompaniesByPlan).reduce(
          (sum, value) => sum + value,
          0,
        ),
        plansWithActiveCompanies: PLAN_KEYS.filter(
          (plan) => (activeCompaniesByPlan[plan] ?? 0) > 0,
        ).length,
      },
      rules: {
        entitlementSource: "license.plan",
        pendingPlanReleasesFeatures: false,
      },
    };
  }

  private describeEmployeePermission(permission: string) {
    const descriptions: Record<string, string> = {
      "sales.create": "Criar vendas e pedidos operacionais.",
      "sales.cancel": "Cancelar vendas quando autorizado.",
      "sales.discount": "Aplicar descontos em vendas.",
      "cash.open": "Abrir caixa.",
      "cash.close": "Fechar caixa.",
      "cash.withdraw": "Registrar retiradas de caixa.",
      "products.read": "Consultar produtos.",
      "products.write": "Criar e alterar produtos.",
      "stock.adjust": "Ajustar estoque.",
      "customers.read": "Consultar clientes.",
      "customers.write": "Criar e alterar clientes.",
      "fiado.read": "Consultar fiado.",
      "fiado.receive": "Receber pagamentos de fiado.",
      "reports.basic": "Acessar relatorios basicos.",
      "reports.advanced": "Acessar relatorios avancados.",
      "employees.manage": "Gerenciar funcionarios.",
      "devices.manage": "Gerenciar dispositivos.",
      "subscription.manage": "Gerenciar assinatura.",
    };
    return descriptions[permission] ?? "Permissao nao reconhecida.";
  }

  private sanitizeAuditDetails(value: Prisma.JsonValue | null) {
    if (value == null) {
      return null;
    }
    return sanitizeAdminAccessValue(value);
  }

  private serializeAccessAuditLog(
    event: Prisma.AdminAuditLogGetPayload<{
      include: {
        actorUser: {
          select: {
            id: true;
            name: true;
            email: true;
          };
        };
      };
    }>,
    fallbackTarget: string,
  ) {
    const details = this.sanitizeAuditDetails(event.details);
    const detailsObject =
      details != null && typeof details === "object" && !Array.isArray(details)
        ? (details as Record<string, unknown>)
        : {};
    const before = this.readAuditObject(detailsObject.before);
    const after = this.readAuditObject(detailsObject.after);
    const metadata = this.readAuditObject(detailsObject.metadata);
    const target = after ?? before ?? {};

    return {
      id: event.id,
      source: "admin",
      action: event.action,
      actorUserId: event.actorUser.id,
      actorName: event.actorUser.name,
      actorEmail: event.actorUser.email,
      target: this.readAuditString(target.name) ?? fallbackTarget,
      targetEmail: this.readAuditString(target.email),
      targetUserId: this.readAuditString(target.userId),
      targetEmployeeId: this.readAuditString(target.employeeProfileId),
      membershipId: this.readAuditString(target.membershipId),
      reason: this.readAuditString(detailsObject.reason),
      before,
      after,
      metadata,
      createdAt: event.createdAt.toISOString(),
    };
  }

  private readAuditObject(value: unknown) {
    return value != null && typeof value === "object" && !Array.isArray(value)
      ? (value as Record<string, unknown>)
      : null;
  }

  private readAuditString(value: unknown) {
    return typeof value === "string" && value.trim().length > 0 ? value : null;
  }

  private async buildAccessActionDryRun(
    input: AdminAccessActionParams,
    action: "block" | "reactivate",
  ) {
    const resolved = await this.resolveAccessActionTarget(input);
    const blockers = [
      ...resolved.blockers,
      ...(action === "block"
        ? await this.validateAccessBlock(resolved.target)
        : this.validateAccessReactivate(resolved.company, resolved.target)),
    ];
    const currentAccess =
      resolved.target == null
        ? null
        : this.serializeAccessEmployee(resolved.target);
    const expectedConfirmationText =
      action === "block" ? "BLOQUEAR" : "REATIVAR";
    const proposedStatus = action === "block" ? "DISABLED" : "ACTIVE";

    return {
      allowed: blockers.length === 0,
      expectedConfirmationText,
      summary:
        action === "block"
          ? "Bloquear acesso operacional desativa o perfil de funcionario nesta empresa."
          : "Reativar acesso operacional habilita novamente o perfil nesta empresa.",
      risks:
        action === "block"
          ? [
              "O usuario perde acesso operacional nas rotas protegidas pelo contexto da empresa.",
              "Esta acao nao revoga sessoes ou JWT nesta fase.",
              "Esta acao nao apaga vendas, pedidos, estoque ou historico.",
              "Esta acao nao remove o usuario da empresa.",
              "Esta acao nao altera senha, papel ou permissoes.",
            ]
          : [
              "O usuario voltara a ter acesso operacional conforme papel e permissoes existentes.",
              "Esta acao nao cria nova sessao e nao altera credenciais.",
              "Esta acao nao altera papel.",
              "Esta acao nao altera permissoes.",
              "Esta acao nao altera senha.",
            ],
      blockers,
      currentAccess,
      proposedChange:
        currentAccess == null
          ? null
          : {
              field: "EmployeeProfile.status",
              statusBefore: currentAccess.status,
              statusAfter: proposedStatus,
              disabledAtAfter: action === "block" ? "now" : null,
            },
    };
  }

  private async resolveAccessActionTarget(input: AdminAccessActionParams) {
    const company = await prisma.company.findUnique({
      where: { id: input.companyId },
      include: { license: true },
    });
    if (company == null) {
      throw new AppError(
        "Empresa nao encontrada.",
        404,
        "ADMIN_COMPANY_NOT_FOUND",
      );
    }

    let target: AdminAccessEmployeeTarget | null = null;
    if (input.targetType === "EMPLOYEE") {
      target = await prisma.employeeProfile.findUnique({
        where: { id: input.targetId },
        include: this.accessEmployeeInclude,
      });
      if (target != null && target.companyId !== input.companyId) {
        return {
          company,
          target: null,
          blockers: ["Alvo de acesso nao pertence a esta empresa."],
        };
      }
    } else if (input.targetType === "MEMBERSHIP") {
      target = await prisma.employeeProfile.findFirst({
        where: {
          companyId: input.companyId,
          membershipId: input.targetId,
        },
        include: this.accessEmployeeInclude,
      });
    } else {
      target = await prisma.employeeProfile.findFirst({
        where: {
          companyId: input.companyId,
          userId: input.targetId,
        },
        include: this.accessEmployeeInclude,
      });
    }

    return {
      company,
      target,
      blockers:
        target == null
          ? [
              "Alvo de acesso nao encontrado nesta empresa ou sem EmployeeProfile vinculado.",
            ]
          : [],
    };
  }

  private async validateAccessBlock(target: AdminAccessEmployeeTarget | null) {
    const blockers: string[] = [];
    if (target == null) {
      return blockers;
    }
    if (this.isProtectedOwner(target)) {
      blockers.push("OWNER protegido nao pode ser bloqueado por esta acao.");
      const activeOwners = await prisma.membership.count({
        where: {
          companyId: target.companyId,
          role: "OWNER",
          user: { isActive: true },
        },
      });
      if (activeOwners <= 1) {
        blockers.push("Nao e permitido bloquear o ultimo OWNER ativo.");
      }
    }
    if (target.status === "DISABLED") {
      blockers.push("Acesso ja esta bloqueado/desativado.");
    }
    return blockers;
  }

  private validateAccessReactivate(
    company: { license: { plan: string } | null },
    target: AdminAccessEmployeeTarget | null,
  ) {
    const blockers: string[] = [];
    if (target == null) {
      return blockers;
    }
    if (target.status !== "DISABLED") {
      blockers.push("Acesso ja esta ativo ou nao esta bloqueado.");
    }
    if (target.userId == null || target.membershipId == null) {
      blockers.push(
        "Perfil sem User/Membership vinculado nao pode ser reativado.",
      );
    }
    if (target.user != null && !target.user.isActive) {
      blockers.push("Conta de usuario esta inativa globalmente.");
    }
    if (!this.isProtectedOwner(target)) {
      const plan = company.license?.plan ?? "FREE";
      if (!getPlanEntitlements(plan).features.employees) {
        blockers.push(
          "Plano ativo license.plan nao libera modulo Funcionarios para reativacao.",
        );
      }
    }
    return blockers;
  }

  private isProtectedOwner(target: AdminAccessEmployeeTarget) {
    return target.role === "OWNER" || target.membership?.role === "OWNER";
  }

  private serializeAccessEmployee(target: AdminAccessEmployeeTarget) {
    return {
      employeeProfileId: target.id,
      userId: target.userId,
      membershipId: target.membershipId,
      name: target.name,
      email: target.email,
      phone: target.phone,
      employeeRole: target.role,
      membershipRole: target.membership?.role ?? null,
      status: target.status,
      effectivePermissions: effectivePermissionsForEmployee(target),
      isOwner: this.isProtectedOwner(target),
      isProtectedOwner: this.isProtectedOwner(target),
      hasUserAccount: target.userId != null,
      userIsActive: target.user?.isActive ?? null,
      disabledAt: target.disabledAt?.toISOString() ?? null,
      createdAt: target.createdAt.toISOString(),
      updatedAt: target.updatedAt.toISOString(),
    };
  }

  private buildAccessAuditDetails(input: {
    input: AdminAccessActionParams;
    before: Record<string, unknown>;
    after: Record<string, unknown>;
    confirmationTextExpected: string;
  }) {
    return sanitizeAdminAccessValue({
      reason: input.input.reason,
      before: input.before,
      after: input.after,
      metadata: {
        source: "admin_web",
        note: input.input.note ?? null,
        targetType: input.input.targetType,
        targetId: input.input.targetId,
        confirmationTextExpected: input.confirmationTextExpected,
        ipAddress: input.input.ipAddress ?? null,
        userAgent: input.input.userAgent ?? null,
      },
    }) as Prisma.InputJsonValue;
  }

  private async requireCompany(companyId: string) {
    const company = await prisma.company.findUnique({
      where: { id: companyId },
      select: { id: true },
    });
    if (company == null) {
      throw new AppError(
        "Empresa nao encontrada.",
        404,
        "ADMIN_COMPANY_NOT_FOUND",
      );
    }
    return company;
  }

  private async findSessionsForDevices(devices: AdminDeviceInventoryDevice[]) {
    if (devices.length === 0) {
      return [];
    }
    const companyIds = [...new Set(devices.map((device) => device.companyId))];
    const clientInstanceIds = [
      ...new Set(devices.map((device) => device.clientInstanceId)),
    ];
    return prisma.deviceSession.findMany({
      where: {
        companyId: { in: companyIds },
        clientInstanceId: { in: clientInstanceIds },
      },
      orderBy: [{ lastSeenAt: "desc" }, { createdAt: "desc" }],
      include: {
        user: {
          select: {
            id: true,
            name: true,
            email: true,
          },
        },
        membership: {
          select: {
            id: true,
            role: true,
          },
        },
      },
    });
  }

  private toDeviceInventoryDto(
    device: AdminDeviceInventoryDevice,
    latestSession: AdminDeviceInventorySession | null,
  ) {
    const diagnostic = device.syncDiagnostic;
    return {
      id: device.id,
      maskedDeviceId: this.maskAuditId(device.id),
      companyId: device.companyId,
      companyName: device.company.name,
      companySlug: device.company.slug,
      userId: device.userId,
      userName: device.user.name,
      userEmail: device.user.email,
      membershipId: latestSession?.membershipId ?? null,
      membershipRole: latestSession?.membership.role ?? null,
      deviceLabel: device.deviceLabel,
      clientType: latestSession?.clientType ?? "UNKNOWN",
      clientInstanceId: this.maskAuditId(device.clientInstanceId),
      platform: device.platform ?? latestSession?.platform ?? null,
      appVersion: device.appVersion ?? latestSession?.appVersion ?? null,
      status: device.status.toLowerCase(),
      lastSeenAt: device.lastSeenAt?.toISOString() ?? null,
      createdAt: device.createdAt.toISOString(),
      updatedAt: device.updatedAt.toISOString(),
      approvedAt: device.approvedAt?.toISOString() ?? null,
      revokedAt: device.revokedAt?.toISOString() ?? null,
      revokedReason: device.revokedReason,
      session:
        latestSession == null
          ? null
          : {
              id: this.maskAuditId(latestSession.id),
              status: this.resolveDeviceSessionStatus(latestSession),
              createdAt: latestSession.createdAt.toISOString(),
              lastSeenAt: latestSession.lastSeenAt.toISOString(),
              lastRefreshedAt:
                latestSession.lastRefreshedAt?.toISOString() ?? null,
              expiresAt: latestSession.refreshTokenExpiresAt.toISOString(),
              revokedAt: latestSession.revokedAt?.toISOString() ?? null,
              revokedReason: latestSession.revokedReason,
            },
      diagnostic:
        diagnostic == null
          ? null
          : {
              pendingCount: diagnostic.pendingCount,
              failedCount: diagnostic.failedCount,
              openConflictCount: diagnostic.openConflictCount,
              resolvedConflictCount: diagnostic.resolvedConflictCount,
              ignoredConflictCount: diagnostic.ignoredConflictCount,
              lastLocalError: this.sanitizeNullableText(
                diagnostic.lastLocalError,
              ),
              lastLocalErrorCode: this.sanitizeNullableText(
                diagnostic.lastLocalErrorCode,
              ),
              lastLocalErrorEntity: this.sanitizeNullableText(
                diagnostic.lastLocalErrorEntity,
              ),
              reportedAt: diagnostic.reportedAt.toISOString(),
            },
    };
  }

  private sanitizeNullableText(value: string | null) {
    if (value == null) {
      return null;
    }
    const sanitized = sanitizeAdminAccessValue(value);
    return typeof sanitized === "string" ? sanitized : "[redacted]";
  }

  private resolveDeviceSessionStatus(session: {
    revokedAt: Date | null;
    refreshTokenExpiresAt: Date;
  }) {
    if (session.revokedAt != null) {
      return "revoked";
    }
    if (session.refreshTokenExpiresAt.getTime() <= Date.now()) {
      return "expired";
    }
    return "active";
  }

  private toAdminSessionDto<T extends { id: string; clientInstanceId: string }>(
    session: T,
  ): T {
    return {
      ...session,
      id: this.maskAuditId(session.id),
      clientInstanceId: this.maskAuditId(session.clientInstanceId),
    };
  }

  private requireAdminActor(actorUserId: string | null | undefined) {
    const normalized = actorUserId?.trim();
    if (normalized == null || normalized.length === 0) {
      throw new AppError(
        "Sessao administrativa invalida.",
        401,
        "AUTH_REQUIRED",
      );
    }
    return normalized;
  }

  async listLicenses(query: AdminLicensesQueryInput) {
    const where = this.buildLicenseWhere(query);
    const { skip, take } = toPaginationParams(query);

    const [total, licenses] = await prisma.$transaction([
      prisma.license.count({ where }),
      prisma.license.findMany({
        where,
        skip,
        take,
        orderBy: this.resolveLicenseOrderBy(query),
        include: {
          company: {
            select: {
              id: true,
              name: true,
              legalName: true,
              slug: true,
              isActive: true,
            },
          },
        },
      }),
    ]);

    const items = licenses.map((license) =>
      this.toLicenseDto(license, license.company),
    );
    return buildAdminListResponse({
      items,
      page: query.page,
      pageSize: query.pageSize,
      total,
      filters: {
        search: query.search ?? null,
        status: query.status ?? null,
        syncEnabled: query.syncEnabled ?? null,
      },
      sort: {
        by: query.sortBy,
        direction: query.sortDirection,
      },
    });
  }

  async getLicense(companyId: string) {
    const license = await prisma.license.findUnique({
      where: { companyId },
      include: {
        company: {
          select: {
            id: true,
            name: true,
            legalName: true,
            slug: true,
            isActive: true,
          },
        },
      },
    });

    if (!license) {
      throw new AppError(
        "Licenca nao encontrada para esta empresa.",
        404,
        "LICENSE_NOT_FOUND",
      );
    }

    return this.toLicenseDto(license, license.company);
  }

  async updateLicense(
    companyId: string,
    input: AdminLicensePatchInput,
    actorUserId: string,
  ) {
    const company = await prisma.company.findUnique({
      where: { id: companyId },
      select: {
        id: true,
        name: true,
        legalName: true,
        slug: true,
        isActive: true,
      },
    });

    if (!company) {
      throw new AppError(
        "Empresa nao encontrada.",
        404,
        "ADMIN_COMPANY_NOT_FOUND",
      );
    }

    const current = await prisma.license.findUnique({
      where: { companyId },
    });

    const baseline = current ?? this.buildDefaultLicense(companyId);
    const nextData = {
      plan: input.plan ?? baseline.plan,
      status: (input.status as LicenseStatus | undefined) ?? baseline.status,
      startsAt: input.startsAt ?? baseline.startsAt,
      expiresAt:
        input.expiresAt === undefined ? baseline.expiresAt : input.expiresAt,
      maxDevices:
        input.maxDevices === undefined ? baseline.maxDevices : input.maxDevices,
      syncEnabled: input.syncEnabled ?? baseline.syncEnabled,
    };

    const license =
      current == null
        ? await prisma.license.create({
            data: {
              id: baseline.id,
              companyId,
              ...nextData,
            },
          })
        : await prisma.license.update({
            where: { companyId },
            data: nextData,
          });

    await prisma.adminAuditLog.create({
      data: {
        actorUserId,
        targetCompanyId: companyId,
        action: "license.updated",
        details: {
          before: current == null ? null : this.serializeLicense(current),
          after: this.serializeLicense(license),
        },
      },
    });

    logger.info("admin.license.updated", {
      actorUserId,
      companyId,
      status: license.status,
      syncEnabled: license.syncEnabled,
      maxDevices: license.maxDevices,
    });

    return this.toLicenseDto(license, company);
  }

  async getAuditSummary(query: AdminAuditQueryInput) {
    const adminWhere: Prisma.AdminAuditLogWhereInput = {
      ...(query.action == null ? {} : { action: query.action }),
      ...(query.actorUserId == null ? {} : { actorUserId: query.actorUserId }),
      ...(query.companyId == null ? {} : { targetCompanyId: query.companyId }),
    };
    const sessionWhere: Prisma.SessionAuditLogWhereInput = {
      ...(query.action == null ? {} : { action: query.action }),
      ...(query.actorUserId == null ? {} : { actorUserId: query.actorUserId }),
      ...(query.companyId == null ? {} : { companyId: query.companyId }),
    };

    const fetchTake = query.page * query.pageSize;
    const [
      adminCount,
      adminCountsByAction,
      adminEvents,
      sessionCount,
      sessionCountsByAction,
      sessionEvents,
    ] = await prisma.$transaction([
      prisma.adminAuditLog.count({ where: adminWhere }),
      prisma.adminAuditLog.groupBy({
        where: adminWhere,
        by: ["action"],
        orderBy: {
          action: "asc",
        },
        _count: {
          _all: true,
        },
      }),
      prisma.adminAuditLog.findMany({
        where: adminWhere,
        orderBy: { createdAt: "desc" },
        take: fetchTake,
        include: {
          actorUser: {
            select: {
              id: true,
              name: true,
              email: true,
            },
          },
          targetCompany: {
            select: {
              id: true,
              name: true,
              slug: true,
            },
          },
        },
      }),
      prisma.sessionAuditLog.count({ where: sessionWhere }),
      prisma.sessionAuditLog.groupBy({
        where: sessionWhere,
        by: ["action"],
        orderBy: {
          action: "asc",
        },
        _count: {
          _all: true,
        },
      }),
      prisma.sessionAuditLog.findMany({
        where: sessionWhere,
        orderBy: { createdAt: "desc" },
        take: fetchTake,
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

    const countsByAction = new Map<string, number>();
    for (const item of [...adminCountsByAction, ...sessionCountsByAction]) {
      countsByAction.set(
        item.action,
        (countsByAction.get(item.action) ?? 0) +
          ((item._count as { _all?: number })._all ?? 0),
      );
    }

    const totalEvents = adminCount + sessionCount;
    const mergedEvents = [
      ...adminEvents.map((event) => this.toAdminAuditEventDto(event)),
      ...sessionEvents.map((event) => this.toSessionAuditEventDto(event)),
    ]
      .sort((left, right) => {
        return (
          new Date(right.createdAt).getTime() -
          new Date(left.createdAt).getTime()
        );
      })
      .slice((query.page - 1) * query.pageSize, query.page * query.pageSize);

    const countsByActionItems = [...countsByAction.entries()]
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([action, count]) => ({ action, count }));

    return buildAdminListResponse({
      items: mergedEvents,
      page: query.page,
      pageSize: query.pageSize,
      total: totalEvents,
      filters: {
        action: query.action ?? null,
        actorUserId: query.actorUserId ?? null,
        companyId: query.companyId ?? null,
      },
      sort: null,
      overview: {
        totalEvents,
        countsByAction: countsByActionItems,
      },
    });
  }

  async getSyncSummary(query: AdminSyncQueryInput) {
    const where = this.buildCompanyWhere({
      search: query.search,
      isActive: undefined,
      licenseStatus: query.licenseStatus,
      syncEnabled: query.syncEnabled,
    });

    const companies = await prisma.company.findMany({
      where,
      include: {
        license: true,
        _count: {
          select: {
            memberships: true,
            categories: true,
            products: true,
            customers: true,
            suppliers: true,
            purchases: true,
            sales: true,
            financialEvents: true,
            cashEvents: true,
          },
        },
      },
    });

    const statusCounts: Record<string, number> = {
      trial: 0,
      active: 0,
      suspended: 0,
      expired: 0,
      without_license: 0,
    };

    let syncEnabledCompanies = 0;

    const companySummaries = companies.map((company) => {
      const license = company.license;
      const statusKey =
        license == null ? "without_license" : license.status.toLowerCase();
      statusCounts[statusKey] = (statusCounts[statusKey] ?? 0) + 1;
      if (license?.syncEnabled === true) {
        syncEnabledCompanies += 1;
      }

      const remoteRecordCount =
        company._count.categories +
        company._count.products +
        company._count.customers +
        company._count.suppliers +
        company._count.purchases +
        company._count.sales +
        company._count.financialEvents +
        company._count.cashEvents;

      return {
        companyId: company.id,
        companyName: company.name,
        companySlug: company.slug,
        licenseStatus: license?.status.toLowerCase() ?? null,
        licensePlan: license?.plan ?? null,
        syncEnabled: license?.syncEnabled ?? false,
        remoteRecordCount,
        entityCounts: {
          memberships: company._count.memberships,
          categories: company._count.categories,
          products: company._count.products,
          customers: company._count.customers,
          suppliers: company._count.suppliers,
          purchases: company._count.purchases,
          sales: company._count.sales,
          financialEvents: company._count.financialEvents,
          cashEvents: company._count.cashEvents,
        },
      };
    });

    const sortedCompanies = companySummaries.sort((left, right) =>
      this.compareSyncCompanySummaries(left, right, query),
    );
    const pagedCompanies = sortedCompanies.slice(
      (query.page - 1) * query.pageSize,
      query.page * query.pageSize,
    );

    const overview = {
      totalCompanies: companies.length,
      syncEnabledCompanies,
      licenseStatusCounts: statusCounts,
    };

    return buildAdminListResponse({
      items: pagedCompanies,
      page: query.page,
      pageSize: query.pageSize,
      total: companies.length,
      filters: {
        search: query.search ?? null,
        licenseStatus: query.licenseStatus ?? null,
        syncEnabled: query.syncEnabled ?? null,
      },
      sort: {
        by: query.sortBy,
        direction: query.sortDirection,
      },
      overview,
    });
  }

  async getSyncOperationalSummary(query: AdminSyncOperationalQueryInput) {
    const where = this.buildCompanyWhere({
      search: query.search,
      isActive: undefined,
      licenseStatus: query.licenseStatus,
      syncEnabled: query.syncEnabled,
    });

    const companies = await prisma.company.findMany({
      where,
      include: {
        license: true,
      },
    });

    const companyIds = companies.map((company) => company.id);
    const [sessionSignals, featureSignals] = await Promise.all([
      this.collectActiveSessionSignals(companyIds),
      this.collectObservedFeatureSignals(companyIds),
    ]);

    const companySummaries = companies.map((company) => {
      const licenseStatus =
        company.license == null
          ? "without_license"
          : company.license.status.toLowerCase();
      const companySessionSignals = sessionSignals.get(company.id) ?? {
        activeSessionsCount: 0,
        activeMobileSessionsCount: 0,
        lastSessionSeenAt: null,
      };
      const observedFeatures = this.buildObservedFeatureSnapshots(
        company.id,
        featureSignals,
      );
      const observedRemoteRecordCount = observedFeatures.reduce(
        (total, feature) => total + feature.remoteRecordCount,
        0,
      );
      const featuresWithRemoteRecords = observedFeatures.filter(
        (feature) => feature.remoteRecordCount > 0,
      ).length;
      const lastObservedRemoteChangeAt = observedFeatures.reduce<string | null>(
        (latest, feature) => {
          if (feature.lastObservedRemoteChangeAt == null) {
            return latest;
          }
          if (latest == null) {
            return feature.lastObservedRemoteChangeAt;
          }
          return new Date(feature.lastObservedRemoteChangeAt) > new Date(latest)
            ? feature.lastObservedRemoteChangeAt
            : latest;
        },
        null,
      );

      const classification = classifySyncOperationalStatus({
        companyIsActive: company.isActive,
        hasLicense: company.license != null,
        licenseStatus,
        syncEnabled: company.license?.syncEnabled ?? false,
        activeMobileSessionsCount:
          companySessionSignals.activeMobileSessionsCount,
        observedRemoteRecordCount,
      });

      return {
        companyId: company.id,
        companyName: company.name,
        companySlug: company.slug,
        companyIsActive: company.isActive,
        licenseStatus,
        syncEnabled: company.license?.syncEnabled ?? false,
        activeSessionsCount: companySessionSignals.activeSessionsCount,
        activeMobileSessionsCount:
          companySessionSignals.activeMobileSessionsCount,
        lastSessionSeenAt: companySessionSignals.lastSessionSeenAt,
        observedRemoteRecordCount,
        lastObservedRemoteChangeAt,
        remoteCoverage: {
          observedFeatureCount: observedFeatures.length,
          featuresWithRemoteRecords,
          telemetryScope: "partial_remote_mirror",
        },
        status: classification.status,
        statusSource: classification.statusSource,
        statusReason: classification.statusReason,
        telemetryAvailability: {
          level: classification.telemetryLevel,
          hasDeviceSessionSignals: true,
          hasRemoteMirrorSignals: true,
          hasLocalQueueSignals: false,
          hasConflictSignals: false,
          hasRetrySignals: false,
          hasClientRepairSignals: false,
        },
        observedFeatures,
      };
    });

    const sortedCompanies = companySummaries.sort((left, right) =>
      this.compareSyncOperationalCompanies(left, right, query),
    );
    const pagedCompanies = sortedCompanies.slice(
      (query.page - 1) * query.pageSize,
      query.page * query.pageSize,
    );

    const statusCounts = {
      healthy: 0,
      attention: 0,
      sync_disabled: 0,
      license_inactive: 0,
      telemetry_limited: 0,
    };
    const telemetryLevelCounts = {
      blocked: 0,
      partial: 0,
      limited: 0,
    };

    for (const company of companySummaries) {
      statusCounts[company.status] += 1;
      telemetryLevelCounts[company.telemetryAvailability.level] += 1;
    }

    const overview = {
      totalCompanies: companySummaries.length,
      statusCounts,
      telemetryLevelCounts,
    };
    const capabilities = {
      observedSignals: [
        "company_status",
        "license_status",
        "license_sync_enabled",
        "device_sessions",
        "remote_entity_counts",
        "remote_entity_timestamps",
      ],
      unavailableSignals: [...unavailableOperationalSignals],
      observedFeatureKeys: observedSyncFeatureCatalog.map(
        (feature) => feature.featureKey,
      ),
      telemetryGaps: telemetryGapFeatures,
      notes: [
        "lastObservedRemoteChangeAt vem do maior updatedAt observado nas entidades remotas conhecidas pelo backend.",
        "status=healthy e uma inferencia limitada: o backend nao enxerga fila local, conflito, retry ou repair do app.",
        "status=telemetry_limited indica ausencia de telemetria suficiente, nao ausencia de problema.",
      ],
    };

    return buildAdminListResponse({
      items: pagedCompanies,
      page: query.page,
      pageSize: query.pageSize,
      total: companySummaries.length,
      filters: {
        search: query.search ?? null,
        licenseStatus: query.licenseStatus ?? null,
        syncEnabled: query.syncEnabled ?? null,
      },
      sort: {
        by: query.sortBy,
        direction: query.sortDirection,
      },
      overview,
      capabilities,
    });
  }

  private buildCompanyWhere(
    query: Pick<
      AdminCompaniesQueryInput,
      "search" | "isActive" | "licenseStatus" | "syncEnabled"
    >,
  ): Prisma.CompanyWhereInput {
    const filters: Prisma.CompanyWhereInput[] = [];

    if (query.search != null) {
      filters.push({
        OR: [
          {
            name: {
              contains: query.search,
              mode: "insensitive",
            },
          },
          {
            legalName: {
              contains: query.search,
              mode: "insensitive",
            },
          },
          {
            slug: {
              contains: query.search,
              mode: "insensitive",
            },
          },
          {
            documentNumber: {
              contains: query.search,
              mode: "insensitive",
            },
          },
        ],
      });
    }

    if (query.isActive !== undefined) {
      filters.push({ isActive: query.isActive });
    }

    if (query.licenseStatus != null) {
      if (query.licenseStatus === "without_license") {
        filters.push({ license: { is: null } });
      } else {
        filters.push({
          license: {
            is: {
              status: query.licenseStatus.toUpperCase() as LicenseStatus,
            },
          },
        });
      }
    }

    if (query.syncEnabled !== undefined) {
      if (query.syncEnabled) {
        filters.push({
          license: {
            is: {
              syncEnabled: true,
            },
          },
        });
      } else {
        filters.push({
          OR: [
            { license: { is: null } },
            {
              license: {
                is: {
                  syncEnabled: false,
                },
              },
            },
          ],
        });
      }
    }

    if (filters.length === 0) {
      return {};
    }

    return { AND: filters };
  }

  private buildLicenseWhere(
    query: Pick<AdminLicensesQueryInput, "search" | "status" | "syncEnabled">,
  ): Prisma.LicenseWhereInput {
    const filters: Prisma.LicenseWhereInput[] = [];

    if (query.search != null) {
      filters.push({
        company: {
          OR: [
            {
              name: {
                contains: query.search,
                mode: "insensitive",
              },
            },
            {
              legalName: {
                contains: query.search,
                mode: "insensitive",
              },
            },
            {
              slug: {
                contains: query.search,
                mode: "insensitive",
              },
            },
          ],
        },
      });
    }

    if (query.status != null) {
      filters.push({
        status: query.status.toUpperCase() as LicenseStatus,
      });
    }

    if (query.syncEnabled !== undefined) {
      filters.push({
        syncEnabled: query.syncEnabled,
      });
    }

    if (filters.length === 0) {
      return {};
    }

    return { AND: filters };
  }

  private resolveCompanyOrderBy(
    query: Pick<AdminCompaniesQueryInput, "sortBy" | "sortDirection">,
  ): Prisma.CompanyOrderByWithRelationInput[] {
    switch (query.sortBy) {
      case "name":
        return [{ name: query.sortDirection }, { createdAt: "desc" }];
      case "updatedAt":
        return [{ updatedAt: query.sortDirection }, { name: "asc" }];
      default:
        return [{ createdAt: query.sortDirection }, { name: "asc" }];
    }
  }

  private resolveLicenseOrderBy(
    query: Pick<AdminLicensesQueryInput, "sortBy" | "sortDirection">,
  ): Prisma.LicenseOrderByWithRelationInput[] {
    switch (query.sortBy) {
      case "companyName":
        return [
          { company: { name: query.sortDirection } },
          { updatedAt: "desc" },
        ];
      case "expiresAt":
        return [{ expiresAt: query.sortDirection }, { updatedAt: "desc" }];
      case "status":
        return [{ status: query.sortDirection }, { updatedAt: "desc" }];
      default:
        return [{ updatedAt: query.sortDirection }, { createdAt: "desc" }];
    }
  }

  private compareSyncCompanySummaries(
    left: {
      companyName: string;
      remoteRecordCount: number;
      licenseStatus: string | null;
    },
    right: {
      companyName: string;
      remoteRecordCount: number;
      licenseStatus: string | null;
    },
    query: Pick<AdminSyncQueryInput, "sortBy" | "sortDirection">,
  ) {
    const factor = query.sortDirection === "asc" ? 1 : -1;

    switch (query.sortBy) {
      case "remoteRecordCount":
        return (left.remoteRecordCount - right.remoteRecordCount) * factor;
      case "licenseStatus":
        return (
          (left.licenseStatus ?? "").localeCompare(right.licenseStatus ?? "") *
          factor
        );
      default:
        return left.companyName.localeCompare(right.companyName) * factor;
    }
  }

  private compareSyncOperationalCompanies(
    left: {
      companyName: string;
      observedRemoteRecordCount: number;
      licenseStatus: string;
    },
    right: {
      companyName: string;
      observedRemoteRecordCount: number;
      licenseStatus: string;
    },
    query: Pick<AdminSyncOperationalQueryInput, "sortBy" | "sortDirection">,
  ) {
    const factor = query.sortDirection === "asc" ? 1 : -1;

    switch (query.sortBy) {
      case "remoteRecordCount":
        return (
          (left.observedRemoteRecordCount - right.observedRemoteRecordCount) *
          factor
        );
      case "licenseStatus":
        return left.licenseStatus.localeCompare(right.licenseStatus) * factor;
      default:
        return left.companyName.localeCompare(right.companyName) * factor;
    }
  }

  private async collectActiveSessionSignals(companyIds: string[]) {
    if (companyIds.length === 0) {
      return new Map<
        string,
        {
          activeSessionsCount: number;
          activeMobileSessionsCount: number;
          lastSessionSeenAt: string | null;
        }
      >();
    }

    const activeSessions = await prisma.deviceSession.findMany({
      where: {
        companyId: {
          in: companyIds,
        },
        revokedAt: null,
        refreshTokenExpiresAt: {
          gt: new Date(),
        },
      },
      select: {
        companyId: true,
        clientType: true,
        lastSeenAt: true,
      },
    });

    const map = new Map<
      string,
      {
        activeSessionsCount: number;
        activeMobileSessionsCount: number;
        lastSessionSeenAt: string | null;
      }
    >();

    for (const session of activeSessions) {
      const current = map.get(session.companyId) ?? {
        activeSessionsCount: 0,
        activeMobileSessionsCount: 0,
        lastSessionSeenAt: null,
      };

      current.activeSessionsCount += 1;
      if (session.clientType === "MOBILE_APP") {
        current.activeMobileSessionsCount += 1;
      }

      const lastSeenIso = session.lastSeenAt.toISOString();
      if (
        current.lastSessionSeenAt == null ||
        new Date(lastSeenIso) > new Date(current.lastSessionSeenAt)
      ) {
        current.lastSessionSeenAt = lastSeenIso;
      }

      map.set(session.companyId, current);
    }

    return map;
  }

  private async collectObservedFeatureSignals(companyIds: string[]) {
    if (companyIds.length === 0) {
      return new Map<string, Map<string, SyncObservedFeatureAggregate>>();
    }

    const [
      categories,
      products,
      customers,
      suppliers,
      purchases,
      sales,
      financialEvents,
      cashEvents,
      fiadoPayments,
    ] = await Promise.all([
      prisma.category.groupBy({
        by: ["companyId"],
        where: { companyId: { in: companyIds } },
        _count: { _all: true },
        _max: { updatedAt: true },
      }),
      prisma.product.groupBy({
        by: ["companyId"],
        where: { companyId: { in: companyIds } },
        _count: { _all: true },
        _max: { updatedAt: true },
      }),
      prisma.customer.groupBy({
        by: ["companyId"],
        where: { companyId: { in: companyIds } },
        _count: { _all: true },
        _max: { updatedAt: true },
      }),
      prisma.supplier.groupBy({
        by: ["companyId"],
        where: { companyId: { in: companyIds } },
        _count: { _all: true },
        _max: { updatedAt: true },
      }),
      prisma.purchase.groupBy({
        by: ["companyId"],
        where: { companyId: { in: companyIds } },
        _count: { _all: true },
        _max: { updatedAt: true },
      }),
      prisma.sale.groupBy({
        by: ["companyId"],
        where: { companyId: { in: companyIds } },
        _count: { _all: true },
        _max: { updatedAt: true },
      }),
      prisma.financialEvent.groupBy({
        by: ["companyId"],
        where: { companyId: { in: companyIds } },
        _count: { _all: true },
        _max: { updatedAt: true },
      }),
      prisma.cashEvent.groupBy({
        by: ["companyId"],
        where: { companyId: { in: companyIds } },
        _count: { _all: true },
        _max: { updatedAt: true },
      }),
      prisma.fiadoPayment.groupBy({
        by: ["companyId"],
        where: { companyId: { in: companyIds } },
        _count: { _all: true },
        _max: { updatedAt: true },
      }),
    ]);

    const byCompany = new Map<
      string,
      Map<string, SyncObservedFeatureAggregate>
    >();

    const registerFeature = (
      featureKey: string,
      displayName: string,
      rows: Array<{
        companyId: string;
        _count: { _all: number };
        _max: { updatedAt: Date | null };
      }>,
    ) => {
      for (const row of rows) {
        const current = byCompany.get(row.companyId) ?? new Map();
        current.set(featureKey, {
          featureKey,
          displayName,
          remoteRecordCount: row._count._all,
          lastObservedRemoteChangeAt: row._max.updatedAt?.toISOString() ?? null,
        });
        byCompany.set(row.companyId, current);
      }
    };

    registerFeature("categories", "Categorias", categories);
    registerFeature("products", "Produtos", products);
    registerFeature("customers", "Clientes", customers);
    registerFeature("suppliers", "Fornecedores", suppliers);
    registerFeature("purchases", "Compras", purchases);
    registerFeature("sales", "Vendas", sales);
    registerFeature("financial_events", "Eventos financeiros", financialEvents);
    registerFeature("cash_events", "Eventos de caixa", cashEvents);
    registerFeature("fiado_payments", "Pagamentos de fiado", fiadoPayments);

    return byCompany;
  }

  private buildObservedFeatureSnapshots(
    companyId: string,
    byCompany: Map<string, Map<string, SyncObservedFeatureAggregate>>,
  ): SyncObservedFeatureSnapshot[] {
    const aggregates = byCompany.get(companyId) ?? new Map();
    return observedSyncFeatureCatalog.map((feature) => {
      const aggregate = aggregates.get(feature.featureKey);
      return {
        featureKey: feature.featureKey,
        displayName: feature.displayName,
        remoteRecordCount: aggregate?.remoteRecordCount ?? 0,
        lastObservedRemoteChangeAt:
          aggregate?.lastObservedRemoteChangeAt ?? null,
        observationKind: "remote_mirror" as const,
      };
    });
  }

  private toAdminAuditEventDto(
    event: Prisma.AdminAuditLogGetPayload<{
      include: {
        actorUser: {
          select: {
            id: true;
            name: true;
            email: true;
          };
        };
        targetCompany: {
          select: {
            id: true;
            name: true;
            slug: true;
          };
        };
      };
    }>,
  ): AdminAuditEventDto {
    return {
      id: event.id,
      source: "admin",
      action: event.action,
      createdAt: event.createdAt.toISOString(),
      actorUser: event.actorUser,
      targetCompany: event.targetCompany,
      details: event.details,
    };
  }

  private toSessionAuditEventDto(
    event: SessionAuditEventWithRelations,
  ): AdminAuditEventDto {
    return {
      id: event.id,
      source: "session",
      action: event.action,
      createdAt: event.createdAt.toISOString(),
      actorUser: event.actorUser,
      targetCompany: event.company,
      details: event.details,
    };
  }

  private toCompanySummary(company: CompanyWithCounts) {
    return {
      id: company.id,
      name: company.name,
      legalName: company.legalName,
      documentNumber: company.documentNumber,
      slug: company.slug,
      isActive: company.isActive,
      createdAt: company.createdAt.toISOString(),
      updatedAt: company.updatedAt.toISOString(),
      license:
        company.license == null
          ? null
          : this.toLicenseDto(company.license, company),
      counts: {
        memberships: company._count.memberships,
        categories: company._count.categories,
        products: company._count.products,
        customers: company._count.customers,
        suppliers: company._count.suppliers,
        purchases: company._count.purchases,
        sales: company._count.sales,
        financialEvents: company._count.financialEvents,
        cashEvents: company._count.cashEvents,
      },
    };
  }

  private toLicenseDto(license: License, company: CompanyIdentity) {
    return {
      id: license.id,
      companyId: company.id,
      companyName: company.name,
      companyLegalName: company.legalName,
      companySlug: company.slug,
      companyIsActive: company.isActive,
      plan: license.plan,
      status: license.status.toLowerCase(),
      startsAt: license.startsAt.toISOString(),
      expiresAt: license.expiresAt?.toISOString() ?? null,
      maxDevices: license.maxDevices,
      syncEnabled: license.syncEnabled,
      billingProvider: license.billingProvider,
      maskedProviderSubscriptionId: maskProviderSubscriptionId(
        license.providerSubscriptionId,
      ),
      currentPeriodStart: license.currentPeriodStart?.toISOString() ?? null,
      currentPeriodEnd: license.currentPeriodEnd?.toISOString() ?? null,
      nextPaymentDate: license.nextPaymentDate?.toISOString() ?? null,
      cancelAtPeriodEnd: license.cancelAtPeriodEnd,
      cancelRequestedAt: license.cancelRequestedAt?.toISOString() ?? null,
      canceledAt: license.canceledAt?.toISOString() ?? null,
      pendingPlan: license.pendingPlan,
      pendingPlanRequestedAt:
        license.pendingPlanRequestedAt?.toISOString() ?? null,
      billingSubscriptionStatus: license.billingSubscriptionStatus,
      createdAt: license.createdAt.toISOString(),
      updatedAt: license.updatedAt.toISOString(),
    };
  }

  private serializeLicense(license: License) {
    return {
      id: license.id,
      companyId: license.companyId,
      plan: license.plan,
      status: license.status.toLowerCase(),
      startsAt: license.startsAt.toISOString(),
      expiresAt: license.expiresAt?.toISOString() ?? null,
      maxDevices: license.maxDevices,
      syncEnabled: license.syncEnabled,
      billingProvider: license.billingProvider,
      maskedProviderSubscriptionId: maskProviderSubscriptionId(
        license.providerSubscriptionId,
      ),
      currentPeriodStart: license.currentPeriodStart?.toISOString() ?? null,
      currentPeriodEnd: license.currentPeriodEnd?.toISOString() ?? null,
      nextPaymentDate: license.nextPaymentDate?.toISOString() ?? null,
      createdAt: license.createdAt.toISOString(),
      updatedAt: license.updatedAt.toISOString(),
    };
  }

  private buildDefaultLicense(companyId: string): License {
    const now = new Date();
    return {
      id: `license_${companyId}`,
      companyId,
      plan: "trial",
      status: "TRIAL",
      startsAt: now,
      expiresAt: null,
      maxDevices: null,
      syncEnabled: true,
      billingProvider: null,
      providerSubscriptionId: null,
      currentPeriodStart: null,
      currentPeriodEnd: null,
      nextPaymentDate: null,
      cancelAtPeriodEnd: false,
      cancelRequestedAt: null,
      canceledAt: null,
      pendingPlan: null,
      pendingPlanRequestedAt: null,
      billingSubscriptionStatus: null,
      createdAt: now,
      updatedAt: now,
    };
  }
}

function sanitizeAdminAccessValue(value: unknown): unknown {
  if (
    value == null ||
    typeof value === "number" ||
    typeof value === "boolean"
  ) {
    return value;
  }
  if (typeof value === "string") {
    const lower = value.toLowerCase();
    if (
      lower.startsWith("bearer ") ||
      lower.includes("token=") ||
      lower.includes("authorization") ||
      lower.includes("secret") ||
      lower.includes("password")
    ) {
      return "[redacted]";
    }
    return value;
  }
  if (Array.isArray(value)) {
    return value.map(sanitizeAdminAccessValue);
  }
  if (typeof value === "object") {
    const result: Record<string, unknown> = {};
    for (const [key, rawValue] of Object.entries(value)) {
      const normalized = key.toLowerCase().replace(/[\s_-]/g, "");
      if (
        normalized.includes("token") ||
        normalized.includes("secret") ||
        normalized.includes("authorization") ||
        normalized.includes("password") ||
        normalized.includes("hash") ||
        normalized.includes("header")
      ) {
        result.campo_sensivel_removido = "[redacted]";
        continue;
      }
      result[key] = sanitizeAdminAccessValue(rawValue);
    }
    return result;
  }
  return String(value);
}

function planCountRecordFromValues(values: number[]): Record<PlanKey, number> {
  const result: Record<PlanKey, number> = {
    FREE: 0,
    BASIC: 0,
    PRO: 0,
  };
  for (let index = 0; index < PLAN_KEYS.length; index += 1) {
    result[PLAN_KEYS[index]] = values[index] ?? 0;
  }
  return result;
}

function planObservations(plan: PlanKey) {
  switch (plan) {
    case "PRO":
      return [
        "Libera Funcionarios PRO, permissoes, multi-dispositivo, owner_web e relatorios avancados.",
        "license.plan=PRO e necessario para liberar estes recursos; pendingPlan nao libera acesso.",
      ];
    case "BASIC":
      return [
        "Recursos comerciais basicos para operacao individual.",
        "Nao libera Funcionarios PRO nem owner_web.",
      ];
    case "FREE":
    default:
      return [
        "Plano gratuito/base para PDV com um dispositivo.",
        "Trial e planos desconhecidos caem no mesmo fallback de entitlement FREE.",
      ];
  }
}
