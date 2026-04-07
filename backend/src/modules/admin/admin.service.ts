import type {
  License,
  LicenseStatus,
  Prisma,
  SessionAuditLog,
} from '@prisma/client';

import { prisma } from '../../database/prisma';
import {
  buildPaginatedResponse,
  buildPaginationMeta,
} from '../../shared/http/api-response';
import { toPaginationParams } from '../../shared/http/pagination';
import { logger } from '../../shared/observability/logger';
import { AppError } from '../../shared/http/app-error';
import { AuthSessionService } from '../auth/auth-session.service';
import type {
  AdminAuditQueryInput,
  AdminCompaniesQueryInput,
  AdminLicensePatchInput,
  AdminLicensesQueryInput,
  AdminSyncQueryInput,
} from './admin.schemas';

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
  source: 'admin' | 'session';
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

export class AdminService {
  constructor(private readonly sessionService = new AuthSessionService()) {}

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

    return {
      ...buildPaginatedResponse({
        items: companies.map((company) => this.toCompanySummary(company)),
        page: query.page,
        pageSize: query.pageSize,
        total,
      }),
      filters: {
        search: query.search ?? null,
        isActive: query.isActive ?? null,
        licenseStatus: query.licenseStatus ?? null,
        syncEnabled: query.syncEnabled ?? null,
      },
      sortBy: query.sortBy,
      sortDirection: query.sortDirection,
    };
  }

  async getCompany(companyId: string) {
    const company = await prisma.company.findUnique({
      where: { id: companyId },
      include: {
        license: true,
        memberships: {
          orderBy: [{ isDefault: 'desc' }, { createdAt: 'asc' }],
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
        'Empresa nao encontrada.',
        404,
        'ADMIN_COMPANY_NOT_FOUND',
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

  async revokeSession(input: { sessionId: string; actorUserId: string }) {
    await this.sessionService.revokeSessionAsPlatformAdmin(input);
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

    return {
      ...buildPaginatedResponse({
        items: licenses.map((license) =>
          this.toLicenseDto(license, license.company),
        ),
        page: query.page,
        pageSize: query.pageSize,
        total,
      }),
      filters: {
        search: query.search ?? null,
        status: query.status ?? null,
        syncEnabled: query.syncEnabled ?? null,
      },
      sortBy: query.sortBy,
      sortDirection: query.sortDirection,
    };
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
        'Licenca nao encontrada para esta empresa.',
        404,
        'LICENSE_NOT_FOUND',
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
        'Empresa nao encontrada.',
        404,
        'ADMIN_COMPANY_NOT_FOUND',
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
        action: 'license.updated',
        details: {
          before: current == null ? null : this.serializeLicense(current),
          after: this.serializeLicense(license),
        },
      },
    });

    logger.info('admin.license.updated', {
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
        by: ['action'],
        orderBy: {
          action: 'asc',
        },
        _count: {
          _all: true,
        },
      }),
      prisma.adminAuditLog.findMany({
        where: adminWhere,
        orderBy: { createdAt: 'desc' },
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
        by: ['action'],
        orderBy: {
          action: 'asc',
        },
        _count: {
          _all: true,
        },
      }),
      prisma.sessionAuditLog.findMany({
        where: sessionWhere,
        orderBy: { createdAt: 'desc' },
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
          new Date(right.createdAt).getTime() - new Date(left.createdAt).getTime()
        );
      })
      .slice((query.page - 1) * query.pageSize, query.page * query.pageSize);

    return {
      totalEvents,
      countsByAction: [...countsByAction.entries()]
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([action, count]) => ({ action, count })),
      recentEvents: mergedEvents,
      pagination: buildPaginationMeta({
        items: mergedEvents,
        page: query.page,
        pageSize: query.pageSize,
        total: totalEvents,
      }),
      filters: {
        action: query.action ?? null,
        actorUserId: query.actorUserId ?? null,
        companyId: query.companyId ?? null,
      },
    };
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
        license == null ? 'without_license' : license.status.toLowerCase();
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

    return {
      overview: {
        totalCompanies: companies.length,
        syncEnabledCompanies,
        licenseStatusCounts: statusCounts,
      },
      companies: pagedCompanies,
      pagination: buildPaginationMeta({
        items: pagedCompanies,
        page: query.page,
        pageSize: query.pageSize,
        total: companies.length,
      }),
      filters: {
        search: query.search ?? null,
        licenseStatus: query.licenseStatus ?? null,
        syncEnabled: query.syncEnabled ?? null,
      },
      sortBy: query.sortBy,
      sortDirection: query.sortDirection,
    };
  }

  private buildCompanyWhere(
    query: Pick<
      AdminCompaniesQueryInput,
      'search' | 'isActive' | 'licenseStatus' | 'syncEnabled'
    >,
  ): Prisma.CompanyWhereInput {
    const filters: Prisma.CompanyWhereInput[] = [];

    if (query.search != null) {
      filters.push({
        OR: [
          {
            name: {
              contains: query.search,
              mode: 'insensitive',
            },
          },
          {
            legalName: {
              contains: query.search,
              mode: 'insensitive',
            },
          },
          {
            slug: {
              contains: query.search,
              mode: 'insensitive',
            },
          },
          {
            documentNumber: {
              contains: query.search,
              mode: 'insensitive',
            },
          },
        ],
      });
    }

    if (query.isActive !== undefined) {
      filters.push({ isActive: query.isActive });
    }

    if (query.licenseStatus != null) {
      if (query.licenseStatus === 'without_license') {
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
    query: Pick<AdminLicensesQueryInput, 'search' | 'status' | 'syncEnabled'>,
  ): Prisma.LicenseWhereInput {
    const filters: Prisma.LicenseWhereInput[] = [];

    if (query.search != null) {
      filters.push({
        company: {
          OR: [
            {
              name: {
                contains: query.search,
                mode: 'insensitive',
              },
            },
            {
              legalName: {
                contains: query.search,
                mode: 'insensitive',
              },
            },
            {
              slug: {
                contains: query.search,
                mode: 'insensitive',
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
    query: Pick<AdminCompaniesQueryInput, 'sortBy' | 'sortDirection'>,
  ): Prisma.CompanyOrderByWithRelationInput[] {
    switch (query.sortBy) {
      case 'name':
        return [{ name: query.sortDirection }, { createdAt: 'desc' }];
      case 'updatedAt':
        return [{ updatedAt: query.sortDirection }, { name: 'asc' }];
      default:
        return [{ createdAt: query.sortDirection }, { name: 'asc' }];
    }
  }

  private resolveLicenseOrderBy(
    query: Pick<AdminLicensesQueryInput, 'sortBy' | 'sortDirection'>,
  ): Prisma.LicenseOrderByWithRelationInput[] {
    switch (query.sortBy) {
      case 'companyName':
        return [{ company: { name: query.sortDirection } }, { updatedAt: 'desc' }];
      case 'expiresAt':
        return [{ expiresAt: query.sortDirection }, { updatedAt: 'desc' }];
      case 'status':
        return [{ status: query.sortDirection }, { updatedAt: 'desc' }];
      default:
        return [{ updatedAt: query.sortDirection }, { createdAt: 'desc' }];
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
    query: Pick<AdminSyncQueryInput, 'sortBy' | 'sortDirection'>,
  ) {
    const factor = query.sortDirection === 'asc' ? 1 : -1;

    switch (query.sortBy) {
      case 'remoteRecordCount':
        return (left.remoteRecordCount - right.remoteRecordCount) * factor;
      case 'licenseStatus':
        return (
          (left.licenseStatus ?? '').localeCompare(right.licenseStatus ?? '') *
          factor
        );
      default:
        return left.companyName.localeCompare(right.companyName) * factor;
    }
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
      source: 'admin',
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
      source: 'session',
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
      createdAt: license.createdAt.toISOString(),
      updatedAt: license.updatedAt.toISOString(),
    };
  }

  private buildDefaultLicense(companyId: string): License {
    const now = new Date();
    return {
      id: `license_${companyId}`,
      companyId,
      plan: 'trial',
      status: 'TRIAL',
      startsAt: now,
      expiresAt: null,
      maxDevices: null,
      syncEnabled: true,
      createdAt: now,
      updatedAt: now,
    };
  }
}
