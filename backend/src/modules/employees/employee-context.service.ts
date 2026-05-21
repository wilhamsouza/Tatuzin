import { Prisma, type MembershipRole } from '@prisma/client';

import { prisma } from '../../database/prisma';
import {
  effectivePermissionsForEmployee,
  membershipRoleFromEmployeeRole,
  roleFromMembershipRole,
} from './employee-permissions';

export type EmployeeContextSnapshot = {
  id: string;
  role: string;
  status: string;
  permissions: string[];
};

type MembershipInput = {
  companyId: string;
  userId: string;
  membershipId: string;
  membershipRole: MembershipRole | string;
  userName: string;
  userEmail: string;
};

export class EmployeeContextService {
  async resolveForMembership(
    input: MembershipInput,
  ): Promise<{
    employee: EmployeeContextSnapshot | null;
    permissions: string[];
    membershipRole: string;
  }> {
    const fallbackRole = roleFromMembershipRole(input.membershipRole);
    const profile =
      fallbackRole === 'OWNER'
        ? await this.ensureOwnerProfile(input)
        : await this.findProfile(input.companyId, input.membershipId, input.userId);

    if (profile == null) {
      const permissions = effectivePermissionsForEmployee({
        role: fallbackRole,
        status: 'ACTIVE',
        permissions: null,
      });
      return {
        employee: null,
        permissions,
        membershipRole: input.membershipRole,
      };
    }

    const effectiveRole =
      fallbackRole === 'OWNER' || profile.role !== 'OWNER'
        ? profile.role
        : fallbackRole;
    const permissions = effectivePermissionsForEmployee({
      role: effectiveRole,
      status: profile.status,
      permissions: profile.permissions,
    });
    return {
      employee: {
        id: profile.id,
        role: effectiveRole,
        status: profile.status,
        permissions,
      },
      permissions,
      membershipRole: membershipRoleFromEmployeeRole(effectiveRole),
    };
  }

  async ensureOwnerProfilesForCompany(companyId: string) {
    const owners = await prisma.membership.findMany({
      where: { companyId, role: 'OWNER' },
      include: {
        user: {
          select: {
            id: true,
            name: true,
            email: true,
          },
        },
      },
    });

    for (const owner of owners) {
      await this.ensureOwnerProfile({
        companyId,
        userId: owner.userId,
        membershipId: owner.id,
        membershipRole: owner.role,
        userName: owner.user.name,
        userEmail: owner.user.email,
      });
    }
  }

  async ensureOwnerProfile(input: MembershipInput) {
    const email = normalizeEmail(input.userEmail);
    const existing = await this.findProfile(
      input.companyId,
      input.membershipId,
      input.userId,
      email,
    );
    const data: Prisma.EmployeeProfileUncheckedCreateInput = {
      companyId: input.companyId,
      userId: input.userId,
      membershipId: input.membershipId,
      name: input.userName,
      email: email?.display ?? input.userEmail.trim(),
      emailNormalized: email?.normalized ?? null,
      role: 'OWNER',
      status: 'ACTIVE',
      permissions: Prisma.JsonNull,
      disabledAt: null,
    };

    if (existing != null) {
      if (this.isOwnerProfileConsistent(existing, data)) {
        return existing;
      }

      return prisma.employeeProfile.update({
        where: { id: existing.id },
        data,
      });
    }

    return prisma.employeeProfile.create({ data });
  }

  private async findProfile(
    companyId: string,
    membershipId: string,
    userId: string,
    email?: NormalizedEmail | null,
  ) {
    return prisma.employeeProfile.findFirst({
      where: {
        companyId,
        OR: [
          { membershipId },
          { userId },
          ...(email?.normalized == null
            ? []
            : [{ emailNormalized: email.normalized }]),
        ],
      },
    });
  }

  private isOwnerProfileConsistent(
    existing: {
      companyId: string;
      userId: string | null;
      membershipId: string | null;
      name: string;
      email: string | null;
      emailNormalized: string | null;
      role: string;
      status: string;
      disabledAt: Date | null;
    },
    expected: Prisma.EmployeeProfileUncheckedCreateInput,
  ) {
    return (
      existing.companyId === expected.companyId &&
      existing.userId === expected.userId &&
      existing.membershipId === expected.membershipId &&
      existing.name === expected.name &&
      existing.email === expected.email &&
      existing.emailNormalized === expected.emailNormalized &&
      existing.role === 'OWNER' &&
      existing.status === 'ACTIVE' &&
      existing.disabledAt == null
    );
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
