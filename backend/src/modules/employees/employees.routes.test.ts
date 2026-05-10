import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';
import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';

import jwt from 'jsonwebtoken';

import { createApp } from '../../app';
import { env } from '../../config/env';
import { prisma } from '../../database/prisma';

const runId = `employees-${Date.now()}`;

let server: Server;
let apiBaseUrl = '';

describe('employees PRO module', () => {
  before(async () => {
    await prisma.$connect();
    server = createApp().listen(0);
    const address = server.address() as AddressInfo;
    apiBaseUrl = `http://127.0.0.1:${address.port}/api`;
  });

  beforeEach(async () => {
    await cleanupFixtures();
  });

  after(async () => {
    await cleanupFixtures();
    await new Promise<void>((resolve, reject) => {
      server.close((error) => (error == null ? resolve() : reject(error)));
    });
    await prisma.$disconnect();
  });

  it('blocks FREE and BASIC by entitlement, even with OWNER membership', async () => {
    for (const plan of ['free', 'basic']) {
      const fixture = await createFixture({ plan });
      const response = await requestJson('GET', '/employees', {
        token: fixture.token,
      });

      assert.equal(response.status, 403);
      const payload = response.data as {
        code?: string;
        details?: { feature?: string };
      };
      assert.equal(payload.code, 'FEATURE_NOT_AVAILABLE');
      assert.equal(payload.details?.feature, 'employees');
    }
  });

  it('upserts OWNER profile, lists it and exposes effective permissions in bootstrap', async () => {
    const fixture = await createFixture({ plan: 'pro' });

    const bootstrap = await requestJson('GET', '/app/bootstrap', {
      token: fixture.token,
    });
    assert.equal(bootstrap.status, 200);
    const bootstrapPayload = bootstrap.data as {
      membership: { permissions: string[] };
      employee: { role: string; status: string; permissions: string[] };
      features: { employees?: boolean };
    };
    assert.equal(bootstrapPayload.features.employees, true);
    assert.equal(bootstrapPayload.employee.role, 'OWNER');
    assert.equal(bootstrapPayload.employee.status, 'ACTIVE');
    assert.ok(
      bootstrapPayload.membership.permissions.includes('employees.manage'),
    );
    assert.ok(bootstrapPayload.employee.permissions.includes('employees.manage'));

    const list = await requestJson('GET', '/employees', {
      token: fixture.token,
    });
    assert.equal(list.status, 200);
    const listPayload = list.data as {
      items: Array<{ role: string; status: string; permissions: string[] }>;
      total: number;
    };
    assert.equal(listPayload.total, 1);
    assert.equal(listPayload.items[0]?.role, 'OWNER');
    assert.equal(listPayload.items[0]?.status, 'ACTIVE');
    assert.ok(listPayload.items[0]?.permissions.includes('employees.manage'));
  });

  it('keeps pendingPlan PRO from unlocking employees before license.plan is PRO', async () => {
    const fixture = await createFixture({ plan: 'basic', pendingPlan: 'PRO' });

    const response = await requestJson('GET', '/employees', {
      token: fixture.token,
    });

    assert.equal(response.status, 403);
    assert.equal((response.data as { code?: string }).code, 'FEATURE_NOT_AVAILABLE');
  });

  it('requires employees.manage for reading and writing', async () => {
    const fixture = await createFixture({ plan: 'pro', role: 'OPERATOR' });

    const response = await requestJson('GET', '/employees', {
      token: fixture.token,
    });

    assert.equal(response.status, 403);
    assert.equal(
      (response.data as { code?: string }).code,
      'EMPLOYEE_PERMISSION_REQUIRED',
    );
  });

  it('removes effective permissions from DISABLED employee profiles', async () => {
    const fixture = await createFixture({ plan: 'pro', role: 'ADMIN' });
    await prisma.employeeProfile.create({
      data: {
        companyId: fixture.companyId,
        userId: fixture.userId,
        membershipId: fixture.membershipId,
        name: 'Disabled Manager',
        email: fixture.email,
        emailNormalized: fixture.email.toLowerCase(),
        role: 'MANAGER',
        status: 'DISABLED',
        permissions: ['employees.manage'],
        disabledAt: new Date(),
      },
    });

    const bootstrap = await requestJson('GET', '/app/bootstrap', {
      token: fixture.token,
    });
    assert.equal(bootstrap.status, 200);
    const bootstrapPayload = bootstrap.data as {
      membership: { permissions: string[] };
      employee: { status: string; permissions: string[] };
    };
    assert.equal(bootstrapPayload.employee.status, 'DISABLED');
    assert.deepEqual(bootstrapPayload.employee.permissions, []);
    assert.deepEqual(bootstrapPayload.membership.permissions, []);

    const response = await requestJson('GET', '/employees', {
      token: fixture.token,
    });
    assert.equal(response.status, 403);
    assert.equal(
      (response.data as { code?: string }).code,
      'EMPLOYEE_PERMISSION_REQUIRED',
    );
  });

  it('does not grant OWNER permissions from an inconsistent non-owner employee profile', async () => {
    const fixture = await createFixture({ plan: 'pro', role: 'OPERATOR' });
    await prisma.employeeProfile.create({
      data: {
        companyId: fixture.companyId,
        userId: fixture.userId,
        membershipId: fixture.membershipId,
        name: 'Corrupted Owner',
        email: fixture.email,
        emailNormalized: fixture.email.toLowerCase(),
        role: 'OWNER',
        status: 'ACTIVE',
      },
    });

    const bootstrap = await requestJson('GET', '/app/bootstrap', {
      token: fixture.token,
    });
    assert.equal(bootstrap.status, 200);
    const bootstrapPayload = bootstrap.data as {
      employee: { role: string; permissions: string[] };
    };
    assert.equal(bootstrapPayload.employee.role, 'CASHIER');
    assert.equal(
      bootstrapPayload.employee.permissions.includes('employees.manage'),
      false,
    );

    const response = await requestJson('GET', '/employees', {
      token: fixture.token,
    });
    assert.equal(response.status, 403);
    assert.equal(
      (response.data as { code?: string }).code,
      'EMPLOYEE_PERMISSION_REQUIRED',
    );
  });

  it('creates, lists, updates, invites, disables and enables employees safely', async () => {
    const fixture = await createFixture({ plan: 'pro' });

    const create = await requestJson('POST', '/employees', {
      token: fixture.token,
      body: {
        name: 'Caixa Principal',
        email: ' Caixa@Tatuzin.Test ',
        phone: '11999990000',
        role: 'CASHIER',
        permissions: ['sales.create', 'cash.open'],
      },
    });
    assert.equal(create.status, 201);
    const created = (create.data as { employee: EmployeeDto }).employee;
    assert.equal(created.email, 'Caixa@Tatuzin.Test');
    assert.deepEqual(created.permissions, ['sales.create', 'cash.open']);

    const stored = await prisma.employeeProfile.findUniqueOrThrow({
      where: { id: created.id },
    });
    assert.equal(stored.emailNormalized, 'caixa@tatuzin.test');

    const list = await requestJson('GET', '/employees?search=caixa', {
      token: fixture.token,
    });
    assert.equal(list.status, 200);
    assert.equal((list.data as { total: number }).total, 1);

    const detail = await requestJson('GET', `/employees/${created.id}`, {
      token: fixture.token,
    });
    assert.equal(detail.status, 200);

    const patch = await requestJson('PATCH', `/employees/${created.id}`, {
      token: fixture.token,
      body: {
        name: 'Vendedor Principal',
        role: 'SELLER',
        permissions: null,
      },
    });
    assert.equal(patch.status, 200);
    const patched = (patch.data as { employee: EmployeeDto }).employee;
    assert.equal(patched.role, 'SELLER');
    assert.deepEqual(patched.permissions, [
      'sales.create',
      'customers.read',
      'customers.write',
    ]);

    const invite = await requestJson('POST', `/employees/${created.id}/invite`, {
      token: fixture.token,
    });
    assert.equal(invite.status, 200);
    const invitePayload = invite.data as {
      employee: EmployeeDto;
      message: string;
      inviteTokenHash?: string;
      token?: string;
    };
    assert.equal(invitePayload.employee.status, 'INVITED');
    assert.ok(invitePayload.message.includes('Convite gerado'));
    assert.equal(invitePayload.inviteTokenHash, undefined);
    assert.equal(invitePayload.token, undefined);

    const invited = await prisma.employeeProfile.findUniqueOrThrow({
      where: { id: created.id },
    });
    assert.ok(invited.inviteTokenHash);

    const clearInvitedEmail = await requestJson(
      'PATCH',
      `/employees/${created.id}`,
      {
        token: fixture.token,
        body: { email: null },
      },
    );
    assert.equal(clearInvitedEmail.status, 422);
    assert.equal(
      (clearInvitedEmail.data as { code?: string }).code,
      'EMPLOYEE_EMAIL_REQUIRED',
    );

    const disable = await requestJson(
      'POST',
      `/employees/${created.id}/disable`,
      { token: fixture.token },
    );
    assert.equal(disable.status, 200);
    assert.equal(
      (disable.data as { employee: EmployeeDto }).employee.status,
      'DISABLED',
    );

    const removeAgain = await requestJson('DELETE', `/employees/${created.id}`, {
      token: fixture.token,
    });
    assert.equal(removeAgain.status, 200);
    assert.equal(
      (removeAgain.data as { employee: EmployeeDto }).employee.status,
      'DISABLED',
    );

    const enable = await requestJson('POST', `/employees/${created.id}/enable`, {
      token: fixture.token,
    });
    assert.equal(enable.status, 200);
    assert.equal(
      (enable.data as { employee: EmployeeDto }).employee.status,
      'ACTIVE',
    );
  });

  it('rejects invalid role, invalid permissions and duplicate normalized email', async () => {
    const fixture = await createFixture({ plan: 'pro' });

    const invalidRole = await requestJson('POST', '/employees', {
      token: fixture.token,
      body: {
        name: 'Owner Manual',
        email: 'owner-manual@tatuzin.test',
        role: 'OWNER',
      },
    });
    assert.equal(invalidRole.status, 422);

    const invalidPermission = await requestJson('POST', '/employees', {
      token: fixture.token,
      body: {
        name: 'Permissao Invalida',
        role: 'SELLER',
        permissions: ['employees.delete'],
      },
    });
    assert.equal(invalidPermission.status, 422);

    const first = await requestJson('POST', '/employees', {
      token: fixture.token,
      body: {
        name: 'Duplicado A',
        email: 'DUP@tatuzin.test',
        role: 'SELLER',
      },
    });
    assert.equal(first.status, 201);

    const duplicate = await requestJson('POST', '/employees', {
      token: fixture.token,
      body: {
        name: 'Duplicado B',
        email: 'dup@tatuzin.test',
        role: 'SELLER',
      },
    });
    assert.equal(duplicate.status, 409);
    assert.equal(
      (duplicate.data as { code?: string }).code,
      'EMPLOYEE_EMAIL_CONFLICT',
    );
  });

  it('protects OWNER from manual changes', async () => {
    const fixture = await createFixture({ plan: 'pro' });
    const list = await requestJson('GET', '/employees', { token: fixture.token });
    const owner = (list.data as { items: EmployeeDto[] }).items[0]!;

    const patch = await requestJson('PATCH', `/employees/${owner.id}`, {
      token: fixture.token,
      body: { name: 'Outro Nome' },
    });
    assert.equal(patch.status, 403);

    const disable = await requestJson('POST', `/employees/${owner.id}/disable`, {
      token: fixture.token,
    });
    assert.equal(disable.status, 403);

    const remove = await requestJson('DELETE', `/employees/${owner.id}`, {
      token: fixture.token,
    });
    assert.equal(remove.status, 403);

    const stored = await prisma.employeeProfile.findUniqueOrThrow({
      where: { id: owner.id },
    });
    assert.equal(stored.role, 'OWNER');
    assert.equal(stored.status, 'ACTIVE');
  });

  it('isolates employees by company', async () => {
    const first = await createFixture({ plan: 'pro' });
    const second = await createFixture({ plan: 'pro' });

    const create = await requestJson('POST', '/employees', {
      token: first.token,
      body: {
        name: 'Empresa A',
        email: 'empresa-a@tatuzin.test',
        role: 'SELLER',
      },
    });
    assert.equal(create.status, 201);
    const employeeId = (create.data as { employee: EmployeeDto }).employee.id;

    const crossCompany = await requestJson('GET', `/employees/${employeeId}`, {
      token: second.token,
    });
    assert.equal(crossCompany.status, 404);
  });

  it('respects maxEmployees and keeps disabled employees out of the count', async () => {
    const fixture = await createFixture({ plan: 'pro' });
    await prisma.employeeProfile.createMany({
      data: Array.from({ length: 100 }, (_, index) => ({
        companyId: fixture.companyId,
        name: `Funcionario ${index}`,
        email: `limit-${index}@tatuzin.test`,
        emailNormalized: `limit-${index}@tatuzin.test`,
        role: 'SELLER',
        status: 'ACTIVE',
      })),
    });

    const blocked = await requestJson('POST', '/employees', {
      token: fixture.token,
      body: {
        name: 'Funcionario Excedente',
        email: 'excedente@tatuzin.test',
        role: 'SELLER',
      },
    });
    assert.equal(blocked.status, 409);
    assert.equal(
      (blocked.data as { code?: string }).code,
      'EMPLOYEE_LIMIT_REACHED',
    );

    const firstEmployee = await prisma.employeeProfile.findFirstOrThrow({
      where: { companyId: fixture.companyId, role: 'SELLER' },
      select: { id: true },
    });
    const disable = await requestJson(
      'POST',
      `/employees/${firstEmployee.id}/disable`,
      { token: fixture.token },
    );
    assert.equal(disable.status, 200);

    const allowed = await requestJson('POST', '/employees', {
      token: fixture.token,
      body: {
        name: 'Funcionario Novo',
        email: 'novo@tatuzin.test',
        role: 'SELLER',
      },
    });
    assert.equal(allowed.status, 201);
  });

  it('preserves employees after downgrade while blocking the endpoint', async () => {
    const fixture = await createFixture({ plan: 'pro' });
    const create = await requestJson('POST', '/employees', {
      token: fixture.token,
      body: {
        name: 'Preservado',
        email: 'preservado@tatuzin.test',
        role: 'SELLER',
      },
    });
    assert.equal(create.status, 201);

    await prisma.license.update({
      where: { companyId: fixture.companyId },
      data: { plan: 'free' },
    });

    const blocked = await requestJson('GET', '/employees', {
      token: fixture.token,
    });
    assert.equal(blocked.status, 403);
    assert.equal((blocked.data as { code?: string }).code, 'FEATURE_NOT_AVAILABLE');

    const employeesCount = await prisma.employeeProfile.count({
      where: { companyId: fixture.companyId },
    });
    assert.equal(employeesCount, 2);
  });

  it('requires email to invite employees', async () => {
    const fixture = await createFixture({ plan: 'pro' });
    const create = await requestJson('POST', '/employees', {
      token: fixture.token,
      body: {
        name: 'Sem Email',
        role: 'SELLER',
      },
    });
    assert.equal(create.status, 201);
    const employeeId = (create.data as { employee: EmployeeDto }).employee.id;

    const invite = await requestJson('POST', `/employees/${employeeId}/invite`, {
      token: fixture.token,
    });
    assert.equal(invite.status, 422);
    assert.equal(
      (invite.data as { code?: string }).code,
      'EMPLOYEE_EMAIL_REQUIRED',
    );
  });
});

type EmployeeDto = {
  id: string;
  email: string | null;
  role: string;
  status: string;
  permissions: string[];
};

async function createFixture(options: {
  plan: string;
  role?: 'OWNER' | 'ADMIN' | 'OPERATOR';
  pendingPlan?: string | null;
}) {
  const unique = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
  const company = await prisma.company.create({
    data: {
      name: 'Employees Company',
      legalName: 'Employees Company LTDA',
      slug: `${runId}-company-${unique}`,
    },
  });
  const user = await prisma.user.create({
    data: {
      email: `${runId}-${unique}@tatuzin.test`,
      name: 'Employees User',
      passwordHash: 'not-used',
    },
  });
  const membership = await prisma.membership.create({
    data: {
      userId: user.id,
      companyId: company.id,
      role: options.role ?? 'OWNER',
      isDefault: true,
    },
  });
  await prisma.license.create({
    data: {
      companyId: company.id,
      plan: options.plan,
      pendingPlan: options.pendingPlan,
      status: 'ACTIVE',
      startsAt: new Date(),
      syncEnabled: true,
    },
  });
  const clientInstanceId = `${runId}-device-${unique}`;
  await prisma.companyDevice.create({
    data: {
      companyId: company.id,
      userId: user.id,
      clientInstanceId,
      deviceLabel: 'Employees Test Device',
      platform: 'node-test',
      appVersion: 'employees-test',
      status: 'ACTIVE',
      approvedAt: new Date(),
      approvedByUserId: user.id,
      lastSeenAt: new Date(),
    },
  });

  return {
    userId: user.id,
    companyId: company.id,
    membershipId: membership.id,
    email: user.email,
    clientInstanceId,
    token: signToken({
      userId: user.id,
      companyId: company.id,
      membershipId: membership.id,
      membershipRole: membership.role,
      email: user.email,
      clientInstanceId,
    }),
  };
}

function signToken(input: {
  userId: string;
  companyId: string;
  membershipId: string;
  membershipRole: string;
  email: string;
  clientInstanceId: string;
}) {
  return jwt.sign(
    {
      sub: input.userId,
      companyId: input.companyId,
      membershipId: input.membershipId,
      membershipRole: input.membershipRole,
      email: input.email,
      isPlatformAdmin: false,
      clientInstanceId: input.clientInstanceId,
    },
    env.JWT_SECRET,
    { expiresIn: '15m' },
  );
}

async function requestJson(
  method: string,
  path: string,
  options?: { token?: string; body?: Record<string, unknown> },
) {
  const response = await fetch(`${apiBaseUrl}${path}`, {
    method,
    headers: {
      ...(options?.token == null
        ? {}
        : { Authorization: `Bearer ${options.token}` }),
      ...(options?.body == null ? {} : { 'Content-Type': 'application/json' }),
    },
    body: options?.body == null ? undefined : JSON.stringify(options.body),
  });
  const rawBody = await response.text();
  return {
    status: response.status,
    data: rawBody.trim().length === 0 ? null : JSON.parse(rawBody),
  };
}

async function cleanupFixtures() {
  await prisma.company.deleteMany({
    where: { slug: { startsWith: `${runId}-` } },
  });
  await prisma.user.deleteMany({
    where: { email: { startsWith: `${runId}-` } },
  });
}
