import crypto from 'node:crypto';

import { Prisma, type EmployeeProfile } from '@prisma/client';

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

  private toDto(employee: EmployeeProfile) {
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
      createdAt: employee.createdAt.toISOString(),
      updatedAt: employee.updatedAt.toISOString(),
    };
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
