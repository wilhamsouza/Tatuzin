import crypto from 'node:crypto';

import { MembershipRole, Prisma, type EmployeeProfile } from '@prisma/client';
import bcrypt from 'bcryptjs';

import { prisma } from '../../database/prisma';
import type { AppContext } from '../app/app-context.types';
import { AppError } from '../../shared/http/app-error';
import { toPaginationParams } from '../../shared/http/pagination';
import { EmployeeContextService } from './employee-context.service';
import {
  effectivePermissionsForEmployee,
  normalizeEmployeeRole,
  normalizeEmployeeStatus,
  type EmployeeStatus,
} from './employee-permissions';
import type {
  EmployeeCreateInput,
  EmployeeListQueryInput,
  EmployeeUpdateInput,
} from './employees.schemas';

const INVITE_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const TEMPORARY_PASSWORD_TTL_MS = 7 * 24 * 60 * 60 * 1000;

type EmployeeWithAccess = EmployeeProfile & {
  user?: {
    id: string;
    mustChangePassword: boolean;
    temporaryPasswordExpiresAt: Date | null;
    isActive: boolean;
  } | null;
};

export class EmployeesService {
  private readonly employeeContextService = new EmployeeContextService();

  async list(context: AppContext, query: EmployeeListQueryInput) {
    await this.employeeContextService.ensureOwnerProfilesForCompany(
      context.company.id,
    );

    const where = this.listWhere(context.company.id, query);
    const { skip, take } = toPaginationParams(query);
    const [total, employees] = await prisma.$transaction([
      prisma.employeeProfile.count({ where }),
      prisma.employeeProfile.findMany({
        where,
        skip,
        take,
        orderBy: [{ role: 'asc' }, { name: 'asc' }, { createdAt: 'asc' }],
        include: {
          user: {
            select: {
              id: true,
              mustChangePassword: true,
              temporaryPasswordExpiresAt: true,
              isActive: true,
            },
          },
        },
      }),
    ]);

    return {
      items: employees.map((employee) => this.toDto(employee)),
      total,
    };
  }

  async get(context: AppContext, employeeId: string) {
    await this.employeeContextService.ensureOwnerProfilesForCompany(
      context.company.id,
    );
    const employee = await this.findEmployeeOrThrow(
      context.company.id,
      employeeId,
    );
    return this.toDto(employee);
  }

  async create(context: AppContext, input: EmployeeCreateInput) {
    this.assertNotOwnerRole(input.role);
    const email = normalizeEmail(input.email);
    if (input.status === 'INVITED' && email == null) {
      throw new AppError(
        'E-mail obrigatorio para convidar funcionario.',
        422,
        'EMPLOYEE_EMAIL_REQUIRED',
      );
    }

    await this.ensureEmailAvailable(context.company.id, email?.normalized);
    if (this.countsTowardLimit(input.role, input.status)) {
      await this.ensureEmployeeLimitAvailable(context);
    }

    const employee = await prisma.employeeProfile.create({
      data: {
        companyId: context.company.id,
        name: input.name,
        email: email?.display ?? null,
        emailNormalized: email?.normalized ?? null,
        phone: input.phone ?? null,
        role: input.role,
        status: input.status,
        permissions: this.toPermissionsJson(input.permissions),
        disabledAt: input.status === 'DISABLED' ? new Date() : null,
        createdByUserId: context.user.id,
        updatedByUserId: context.user.id,
      },
    });

    return this.toDto(employee);
  }

  async update(
    context: AppContext,
    employeeId: string,
    input: EmployeeUpdateInput,
  ) {
    const existing = await this.findEmployeeOrThrow(
      context.company.id,
      employeeId,
    );
    this.assertMutableEmployee(existing);
    if (input.role != null) {
      this.assertNotOwnerRole(input.role);
    }

    const email = input.email === undefined ? undefined : normalizeEmail(input.email);
    const nextEmailNormalized =
      email === undefined ? existing.emailNormalized : email?.normalized ?? null;
    const nextRole = input.role ?? existing.role;
    const nextStatus = input.status ?? existing.status;
    if (email !== undefined) {
      await this.ensureEmailAvailable(
        context.company.id,
        email?.normalized,
        employeeId,
      );
      if (
        existing.userId != null &&
        email?.normalized !== existing.emailNormalized
      ) {
        throw new AppError(
          'Nao altere o e-mail de um funcionario com acesso ativo. Redefina o acesso com outro cadastro.',
          409,
          'EMPLOYEE_ACCESS_EMAIL_LOCKED',
        );
      }
    }

    if (nextStatus === 'INVITED' && nextEmailNormalized == null) {
      throw new AppError(
        'E-mail obrigatorio para convidar funcionario.',
        422,
        'EMPLOYEE_EMAIL_REQUIRED',
      );
    }

    if (
      !this.countsTowardLimit(existing.role, existing.status) &&
      this.countsTowardLimit(nextRole, nextStatus)
    ) {
      await this.ensureEmployeeLimitAvailable(context);
    }

    const employee = await prisma.employeeProfile.update({
      where: { id: existing.id },
      data: {
        ...(input.name === undefined ? {} : { name: input.name }),
        ...(email === undefined
          ? {}
          : {
              email: email?.display ?? null,
              emailNormalized: email?.normalized ?? null,
            }),
        ...(input.phone === undefined ? {} : { phone: input.phone }),
        ...(input.role === undefined ? {} : { role: input.role }),
        ...(input.status === undefined
          ? {}
          : {
              status: input.status,
              disabledAt:
                input.status === 'DISABLED'
                  ? existing.disabledAt ?? new Date()
                  : null,
            }),
        ...(input.permissions === undefined
          ? {}
          : { permissions: this.toPermissionsJson(input.permissions) }),
        updatedByUserId: context.user.id,
      },
    });

    return this.toDto(employee);
  }

  async softDelete(context: AppContext, employeeId: string) {
    const existing = await this.findEmployeeOrThrow(
      context.company.id,
      employeeId,
    );
    this.assertMutableEmployee(existing);

    if (existing.status === 'DISABLED') {
      return this.toDto(existing);
    }

    const employee = await prisma.employeeProfile.update({
      where: { id: existing.id },
      data: {
        status: 'DISABLED',
        disabledAt: new Date(),
        updatedByUserId: context.user.id,
      },
    });

    return this.toDto(employee);
  }

  async invite(context: AppContext, employeeId: string) {
    const existing = await this.findEmployeeOrThrow(
      context.company.id,
      employeeId,
    );
    this.assertMutableEmployee(existing);
    if (existing.emailNormalized == null) {
      throw new AppError(
        'E-mail obrigatorio para convidar funcionario.',
        422,
        'EMPLOYEE_EMAIL_REQUIRED',
      );
    }

    if (!this.countsTowardLimit(existing.role, existing.status)) {
      await this.ensureEmployeeLimitAvailable(context);
    }

    const rawToken = crypto.randomBytes(32).toString('hex');
    const inviteTokenHash = crypto
      .createHash('sha256')
      .update(rawToken)
      .digest('hex');

    const employee = await prisma.employeeProfile.update({
      where: { id: existing.id },
      data: {
        status: 'INVITED',
        invitedAt: new Date(),
        inviteTokenHash,
        inviteExpiresAt: new Date(Date.now() + INVITE_TTL_MS),
        disabledAt: null,
        updatedByUserId: context.user.id,
      },
    });

    return {
      employee: this.toDto(employee),
      message:
        'Convite gerado. O envio automatico de e-mail sera implementado em etapa futura.',
    };
  }

  async generateTemporaryPassword(context: AppContext, employeeId: string) {
    const existing = await this.findEmployeeOrThrow(
      context.company.id,
      employeeId,
    );
    this.assertMutableEmployee(existing);

    if (existing.status === 'DISABLED') {
      throw new AppError(
        'Reative o funcionario antes de redefinir a senha.',
        409,
        'EMPLOYEE_DISABLED',
      );
    }

    if (existing.emailNormalized == null) {
      throw new AppError(
        'Informe um e-mail para gerar acesso. Login por telefone ficara para uma melhoria futura.',
        422,
        'EMPLOYEE_EMAIL_REQUIRED_FOR_ACCESS',
      );
    }

    const temporaryPassword = this.generateTemporaryPasswordValue();
    const passwordHash = await bcrypt.hash(temporaryPassword, 10);
    const expiresAt = new Date(Date.now() + TEMPORARY_PASSWORD_TTL_MS);

    const employee = await prisma.$transaction(async (transaction) => {
      let userId = existing.userId;
      let membershipId = existing.membershipId;

      if (userId == null) {
        const existingUser = await transaction.user.findUnique({
          where: { email: existing.emailNormalized! },
          select: { id: true },
        });

        if (existingUser != null) {
          throw new AppError(
            'Ja existe uma conta com este e-mail. Use outro e-mail para evitar mistura de acesso.',
            409,
            'EMPLOYEE_ACCESS_EMAIL_CONFLICT',
          );
        }

        const user = await transaction.user.create({
          data: {
            email: existing.emailNormalized!,
            name: existing.name,
            passwordHash,
            mustChangePassword: true,
            temporaryPasswordExpiresAt: expiresAt,
          },
          select: { id: true },
        });
        userId = user.id;
      } else {
        const user = await transaction.user.findUnique({
          where: { id: userId },
          select: {
            id: true,
            email: true,
            isPlatformAdmin: true,
          },
        });

        if (user == null) {
          throw new AppError(
            'Conta vinculada ao funcionario nao foi encontrada.',
            409,
            'EMPLOYEE_ACCESS_USER_NOT_FOUND',
          );
        }

        if (user.email.toLowerCase().trim() !== existing.emailNormalized) {
          throw new AppError(
            'O e-mail do funcionario nao confere com a conta vinculada.',
            409,
            'EMPLOYEE_ACCESS_EMAIL_CONFLICT',
          );
        }

        if (user.isPlatformAdmin) {
          throw new AppError(
            'Esta conta nao pode receber senha de funcionario.',
            403,
            'EMPLOYEE_ACCESS_PROTECTED_USER',
          );
        }

        await transaction.user.update({
          where: { id: userId },
          data: {
            name: existing.name,
            passwordHash,
            isActive: true,
            mustChangePassword: true,
            temporaryPasswordExpiresAt: expiresAt,
          },
        });
      }

      if (membershipId == null) {
        const membership = await transaction.membership.findUnique({
          where: {
            userId_companyId: {
              userId,
              companyId: context.company.id,
            },
          },
          select: { id: true, role: true },
        });

        if (membership?.role === MembershipRole.OWNER) {
          throw new AppError(
            'OWNER nao pode ser alterado por este fluxo.',
            403,
            'EMPLOYEE_OWNER_PROTECTED',
          );
        }

        if (membership != null) {
          membershipId = membership.id;
        } else {
          const createdMembership = await transaction.membership.create({
            data: {
              userId,
              companyId: context.company.id,
              role: this.membershipRoleForEmployee(existing.role),
              isDefault: false,
            },
            select: { id: true },
          });
          membershipId = createdMembership.id;
        }
      } else {
        const membership = await transaction.membership.findUnique({
          where: { id: membershipId },
          select: { id: true, userId: true, companyId: true, role: true },
        });

        if (
          membership == null ||
          membership.userId !== userId ||
          membership.companyId !== context.company.id
        ) {
          throw new AppError(
            'Vinculo de acesso do funcionario esta inconsistente.',
            409,
            'EMPLOYEE_ACCESS_MEMBERSHIP_CONFLICT',
          );
        }

        if (membership.role === MembershipRole.OWNER) {
          throw new AppError(
            'OWNER nao pode ser alterado por este fluxo.',
            403,
            'EMPLOYEE_OWNER_PROTECTED',
          );
        }
      }

      return transaction.employeeProfile.update({
        where: { id: existing.id },
        data: {
          userId,
          membershipId,
          status: 'ACTIVE',
          invitedAt: null,
          inviteTokenHash: null,
          inviteExpiresAt: null,
          acceptedAt: null,
          disabledAt: null,
          updatedByUserId: context.user.id,
        },
        include: {
          user: {
            select: {
              id: true,
              mustChangePassword: true,
              temporaryPasswordExpiresAt: true,
              isActive: true,
            },
          },
        },
      });
    });

    return {
      employee: this.toDto(employee),
      login: employee.email,
      temporaryPassword,
      temporaryPasswordExpiresAt: expiresAt.toISOString(),
      message: 'Senha temporaria gerada.',
    };
  }

  async disable(context: AppContext, employeeId: string) {
    return this.softDelete(context, employeeId);
  }

  async enable(context: AppContext, employeeId: string) {
    const existing = await this.findEmployeeOrThrow(
      context.company.id,
      employeeId,
    );
    this.assertMutableEmployee(existing);

    if (!this.countsTowardLimit(existing.role, existing.status)) {
      await this.ensureEmployeeLimitAvailable(context);
    }

    const employee = await prisma.employeeProfile.update({
      where: { id: existing.id },
      data: {
        status: 'ACTIVE',
        disabledAt: null,
        updatedByUserId: context.user.id,
      },
    });

    return this.toDto(employee);
  }

  private listWhere(companyId: string, query: EmployeeListQueryInput) {
    return {
      companyId,
      ...(query.status == null ? {} : { status: query.status }),
      ...(query.role == null ? {} : { role: query.role }),
      ...(query.search == null
        ? {}
        : {
            OR: [
              { name: { contains: query.search, mode: 'insensitive' as const } },
              { email: { contains: query.search, mode: 'insensitive' as const } },
              { phone: { contains: query.search, mode: 'insensitive' as const } },
            ],
          }),
    };
  }

  private async findEmployeeOrThrow(companyId: string, employeeId: string) {
    const employee = await prisma.employeeProfile.findFirst({
      where: {
        id: employeeId,
        companyId,
      },
      include: {
        user: {
          select: {
            id: true,
            mustChangePassword: true,
            temporaryPasswordExpiresAt: true,
            isActive: true,
          },
        },
      },
    });

    if (employee == null) {
      throw new AppError(
        'Funcionario nao encontrado.',
        404,
        'EMPLOYEE_NOT_FOUND',
      );
    }

    return employee;
  }

  private assertNotOwnerRole(role: string) {
    if (role === 'OWNER') {
      throw new AppError(
        'OWNER nao pode ser criado ou promovido manualmente.',
        422,
        'EMPLOYEE_OWNER_PROTECTED',
      );
    }
  }

  private assertMutableEmployee(employee: EmployeeProfile) {
    if (employee.role === 'OWNER') {
      throw new AppError(
        'OWNER nao pode ser alterado por este endpoint.',
        403,
        'EMPLOYEE_OWNER_PROTECTED',
      );
    }
  }

  private async ensureEmailAvailable(
    companyId: string,
    emailNormalized: string | null | undefined,
    currentEmployeeId?: string,
  ) {
    if (emailNormalized == null) {
      return;
    }

    const existing = await prisma.employeeProfile.findFirst({
      where: {
        companyId,
        emailNormalized,
        ...(currentEmployeeId == null ? {} : { id: { not: currentEmployeeId } }),
      },
      select: { id: true },
    });

    if (existing != null) {
      throw new AppError(
        'Ja existe funcionario com este e-mail nesta empresa.',
        409,
        'EMPLOYEE_EMAIL_CONFLICT',
      );
    }
  }

  private async ensureEmployeeLimitAvailable(context: AppContext) {
    const maxEmployees = context.limits.maxEmployees;
    const total = await prisma.employeeProfile.count({
      where: {
        companyId: context.company.id,
        role: { not: 'OWNER' },
        status: { in: ['ACTIVE', 'INVITED'] },
      },
    });

    if (total >= maxEmployees) {
      throw new AppError(
        'Limite de funcionarios atingido para o plano atual.',
        409,
        'EMPLOYEE_LIMIT_REACHED',
        { maxEmployees },
      );
    }
  }

  private countsTowardLimit(role: string, status: string) {
    return role !== 'OWNER' && (status === 'ACTIVE' || status === 'INVITED');
  }

  private toPermissionsJson(
    permissions: string[] | null | undefined,
  ): Prisma.InputJsonValue | typeof Prisma.JsonNull | undefined {
    if (permissions === undefined) {
      return undefined;
    }
    if (permissions === null) {
      return Prisma.JsonNull;
    }
    return permissions as Prisma.InputJsonValue;
  }

  private toDto(employee: EmployeeWithAccess) {
    const role = normalizeEmployeeRole(employee.role) ?? 'READ_ONLY';
    const status = normalizeEmployeeStatus(employee.status) ?? 'DISABLED';
    return {
      id: employee.id,
      name: employee.name,
      email: employee.email,
      phone: employee.phone,
      role,
      status,
      permissions: effectivePermissionsForEmployee(employee),
      invitedAt: employee.invitedAt?.toISOString() ?? null,
      inviteExpiresAt: employee.inviteExpiresAt?.toISOString() ?? null,
      acceptedAt: employee.acceptedAt?.toISOString() ?? null,
      disabledAt: employee.disabledAt?.toISOString() ?? null,
      accessStatus: this.resolveAccessStatus(employee),
      temporaryPasswordExpiresAt:
        employee.user?.temporaryPasswordExpiresAt?.toISOString() ?? null,
      createdAt: employee.createdAt.toISOString(),
      updatedAt: employee.updatedAt.toISOString(),
    };
  }

  private resolveAccessStatus(employee: EmployeeWithAccess) {
    if (employee.status === 'DISABLED') {
      return 'DISABLED';
    }
    if (employee.userId == null || employee.membershipId == null) {
      return 'NO_ACCESS';
    }
    if (employee.user == null || !employee.user.isActive) {
      return 'DISABLED';
    }
    if (employee.user.mustChangePassword) {
      return 'TEMPORARY_PASSWORD_PENDING';
    }
    return 'ACTIVE';
  }

  private membershipRoleForEmployee(role: string) {
    return role === 'MANAGER' ? MembershipRole.ADMIN : MembershipRole.OPERATOR;
  }

  private generateTemporaryPasswordValue() {
    return crypto.randomBytes(9).toString('base64url');
  }
}

type NormalizedEmail = {
  display: string;
  normalized: string;
};

function normalizeEmail(rawEmail: string | null | undefined): NormalizedEmail | null {
  const display = rawEmail?.trim();
  if (display == null || display.length === 0) {
    return null;
  }
  return {
    display,
    normalized: display.toLowerCase(),
  };
}
