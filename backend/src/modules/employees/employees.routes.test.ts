import assert from "node:assert/strict";
import { after, before, beforeEach, describe, it } from "node:test";
import type { AddressInfo } from "node:net";
import type { Server } from "node:http";

import jwt from "jsonwebtoken";
import bcrypt from "bcryptjs";
import { SyncEventStatus } from "@prisma/client";

import { createApp } from "../../app";
import { env } from "../../config/env";
import { prisma } from "../../database/prisma";

const runId = `employees-${Date.now()}`;

let server: Server;
let apiBaseUrl = "";

describe("employees PRO module", () => {
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

  it("blocks FREE and BASIC by entitlement, even with OWNER membership", async () => {
    for (const plan of ["free", "basic"]) {
      const fixture = await createFixture({ plan });
      const response = await requestJson("GET", "/employees", {
        token: fixture.token,
      });

      assert.equal(response.status, 403);
      const payload = response.data as {
        code?: string;
        details?: { feature?: string };
      };
      assert.equal(payload.code, "FEATURE_NOT_AVAILABLE");
      assert.equal(payload.details?.feature, "employees");
    }
  });

  it("upserts OWNER profile, lists it and exposes effective permissions in bootstrap", async () => {
    const fixture = await createFixture({ plan: "pro" });

    const bootstrap = await requestJson("GET", "/app/bootstrap", {
      token: fixture.token,
    });
    assert.equal(bootstrap.status, 200);
    const bootstrapPayload = bootstrap.data as {
      membership: { permissions: string[] };
      employee: { role: string; status: string; permissions: string[] };
      features: { employees?: boolean };
    };
    assert.equal(bootstrapPayload.features.employees, true);
    assert.equal(bootstrapPayload.employee.role, "OWNER");
    assert.equal(bootstrapPayload.employee.status, "ACTIVE");
    assert.ok(
      bootstrapPayload.membership.permissions.includes("employees.manage"),
    );
    assert.ok(
      bootstrapPayload.employee.permissions.includes("employees.manage"),
    );

    const list = await requestJson("GET", "/employees", {
      token: fixture.token,
    });
    assert.equal(list.status, 200);
    const listPayload = list.data as {
      items: Array<{ role: string; status: string; permissions: string[] }>;
      total: number;
    };
    assert.equal(listPayload.total, 1);
    assert.equal(listPayload.items[0]?.role, "OWNER");
    assert.equal(listPayload.items[0]?.status, "ACTIVE");
    assert.ok(listPayload.items[0]?.permissions.includes("employees.manage"));
  });

  it("keeps pendingPlan PRO from unlocking employees before license.plan is PRO", async () => {
    const fixture = await createFixture({ plan: "basic", pendingPlan: "PRO" });

    const response = await requestJson("GET", "/employees", {
      token: fixture.token,
    });

    assert.equal(response.status, 403);
    assert.equal(
      (response.data as { code?: string }).code,
      "FEATURE_NOT_AVAILABLE",
    );

    const activity = await requestJson(
      "GET",
      "/employees/activity/summary?from=2026-05-20&to=2026-05-20",
      { token: fixture.token },
    );
    assert.equal(activity.status, 403);
    assert.equal(
      (activity.data as { code?: string }).code,
      "FEATURE_NOT_AVAILABLE",
    );
  });

  it("requires employees.manage for reading and writing", async () => {
    const fixture = await createFixture({ plan: "pro", role: "OPERATOR" });

    const response = await requestJson("GET", "/employees", {
      token: fixture.token,
    });

    assert.equal(response.status, 403);
    assert.equal(
      (response.data as { code?: string }).code,
      "EMPLOYEE_PERMISSION_REQUIRED",
    );
  });

  it("blocks app context for DISABLED employee profiles", async () => {
    const fixture = await createFixture({ plan: "pro", role: "ADMIN" });
    await prisma.employeeProfile.create({
      data: {
        companyId: fixture.companyId,
        userId: fixture.userId,
        membershipId: fixture.membershipId,
        name: "Disabled Manager",
        email: fixture.email,
        emailNormalized: fixture.email.toLowerCase(),
        role: "MANAGER",
        status: "DISABLED",
        permissions: ["employees.manage"],
        disabledAt: new Date(),
      },
    });

    const bootstrap = await requestJson("GET", "/app/bootstrap", {
      token: fixture.token,
    });
    assert.equal(bootstrap.status, 403);
    assert.equal((bootstrap.data as { code?: string }).code, "EMPLOYEE_DISABLED");

    const response = await requestJson("GET", "/employees", {
      token: fixture.token,
    });
    assert.equal(response.status, 403);
    assert.equal((response.data as { code?: string }).code, "EMPLOYEE_DISABLED");

    const activity = await requestJson(
      "GET",
      "/employees/activity/summary?from=2026-05-20&to=2026-05-20",
      { token: fixture.token },
    );
    assert.equal(activity.status, 403);
    assert.equal((activity.data as { code?: string }).code, "EMPLOYEE_DISABLED");
  });

  it("does not let a cashier profile inherit ADMIN membership permissions", async () => {
    const fixture = await createFixture({ plan: "pro", role: "ADMIN" });
    await prisma.employeeProfile.create({
      data: {
        companyId: fixture.companyId,
        userId: fixture.userId,
        membershipId: fixture.membershipId,
        name: "Cashier Effective",
        email: fixture.email,
        emailNormalized: fixture.email.toLowerCase(),
        role: "CASHIER",
        status: "ACTIVE",
        permissions: ["sales.create", "cash.open", "cash.close"],
      },
    });

    const bootstrap = await requestJson("GET", "/app/bootstrap", {
      token: fixture.token,
    });
    assert.equal(bootstrap.status, 200);
    const payload = bootstrap.data as {
      membership: { role: string; permissions: string[] };
      employee: { role: string; permissions: string[] };
    };
    assert.equal(payload.employee.role, "CASHIER");
    assert.equal(payload.membership.role, "OPERATOR");
    assert.deepEqual(payload.membership.permissions, [
      "sales.create",
      "cash.open",
      "cash.close",
    ]);
    assert.equal(payload.membership.permissions.includes("employees.manage"), false);

    const response = await requestJson("GET", "/employees", {
      token: fixture.token,
    });
    assert.equal(response.status, 403);
    assert.equal(
      (response.data as { code?: string }).code,
      "EMPLOYEE_PERMISSION_REQUIRED",
    );
  });

  it("does not grant OWNER permissions from an inconsistent non-owner employee profile", async () => {
    const fixture = await createFixture({ plan: "pro", role: "OPERATOR" });
    await prisma.employeeProfile.create({
      data: {
        companyId: fixture.companyId,
        userId: fixture.userId,
        membershipId: fixture.membershipId,
        name: "Corrupted Owner",
        email: fixture.email,
        emailNormalized: fixture.email.toLowerCase(),
        role: "OWNER",
        status: "ACTIVE",
      },
    });

    const bootstrap = await requestJson("GET", "/app/bootstrap", {
      token: fixture.token,
    });
    assert.equal(bootstrap.status, 200);
    const bootstrapPayload = bootstrap.data as {
      employee: { role: string; permissions: string[] };
    };
    assert.equal(bootstrapPayload.employee.role, "CASHIER");
    assert.equal(
      bootstrapPayload.employee.permissions.includes("employees.manage"),
      false,
    );

    const response = await requestJson("GET", "/employees", {
      token: fixture.token,
    });
    assert.equal(response.status, 403);
    assert.equal(
      (response.data as { code?: string }).code,
      "EMPLOYEE_PERMISSION_REQUIRED",
    );
  });

  it("creates, lists, updates, invites, disables and enables employees safely", async () => {
    const fixture = await createFixture({ plan: "pro" });

    const create = await requestJson("POST", "/employees", {
      token: fixture.token,
      body: {
        name: "Caixa Principal",
        email: " Caixa@Tatuzin.Test ",
        phone: "11999990000",
        role: "CASHIER",
        permissions: ["sales.create", "cash.open"],
      },
    });
    assert.equal(create.status, 201);
    const created = (create.data as { employee: EmployeeDto }).employee;
    assert.equal(created.email, "Caixa@Tatuzin.Test");
    assert.deepEqual(created.permissions, ["sales.create", "cash.open"]);

    const stored = await prisma.employeeProfile.findUniqueOrThrow({
      where: { id: created.id },
    });
    assert.equal(stored.emailNormalized, "caixa@tatuzin.test");

    const list = await requestJson("GET", "/employees?search=caixa", {
      token: fixture.token,
    });
    assert.equal(list.status, 200);
    assert.equal((list.data as { total: number }).total, 1);

    const detail = await requestJson("GET", `/employees/${created.id}`, {
      token: fixture.token,
    });
    assert.equal(detail.status, 200);

    const patch = await requestJson("PATCH", `/employees/${created.id}`, {
      token: fixture.token,
      body: {
        name: "Vendedor Principal",
        role: "SELLER",
        permissions: null,
      },
    });
    assert.equal(patch.status, 200);
    const patched = (patch.data as { employee: EmployeeDto }).employee;
    assert.equal(patched.role, "SELLER");
    assert.deepEqual(patched.permissions, [
      "sales.create",
      "customers.read",
      "customers.write",
    ]);

    const invite = await requestJson(
      "POST",
      `/employees/${created.id}/invite`,
      {
        token: fixture.token,
      },
    );
    assert.equal(invite.status, 200);
    const invitePayload = invite.data as {
      employee: EmployeeDto;
      message: string;
      inviteTokenHash?: string;
      token?: string;
    };
    assert.equal(invitePayload.employee.status, "INVITED");
    assert.ok(invitePayload.message.includes("Convite gerado"));
    assert.equal(invitePayload.inviteTokenHash, undefined);
    assert.equal(invitePayload.token, undefined);

    const invited = await prisma.employeeProfile.findUniqueOrThrow({
      where: { id: created.id },
    });
    assert.ok(invited.inviteTokenHash);

    const clearInvitedEmail = await requestJson(
      "PATCH",
      `/employees/${created.id}`,
      {
        token: fixture.token,
        body: { email: null },
      },
    );
    assert.equal(clearInvitedEmail.status, 422);
    assert.equal(
      (clearInvitedEmail.data as { code?: string }).code,
      "EMPLOYEE_EMAIL_REQUIRED",
    );

    const disable = await requestJson(
      "POST",
      `/employees/${created.id}/disable`,
      { token: fixture.token },
    );
    assert.equal(disable.status, 200);
    assert.equal(
      (disable.data as { employee: EmployeeDto }).employee.status,
      "DISABLED",
    );

    const removeAgain = await requestJson(
      "DELETE",
      `/employees/${created.id}`,
      {
        token: fixture.token,
      },
    );
    assert.equal(removeAgain.status, 200);
    assert.equal(
      (removeAgain.data as { employee: EmployeeDto }).employee.status,
      "DISABLED",
    );

    const enable = await requestJson(
      "POST",
      `/employees/${created.id}/enable`,
      {
        token: fixture.token,
      },
    );
    assert.equal(enable.status, 200);
    assert.equal(
      (enable.data as { employee: EmployeeDto }).employee.status,
      "ACTIVE",
    );
  });

  it("rejects invalid role, invalid permissions and duplicate normalized email", async () => {
    const fixture = await createFixture({ plan: "pro" });

    const invalidRole = await requestJson("POST", "/employees", {
      token: fixture.token,
      body: {
        name: "Owner Manual",
        email: "owner-manual@tatuzin.test",
        role: "OWNER",
      },
    });
    assert.equal(invalidRole.status, 422);

    const invalidPermission = await requestJson("POST", "/employees", {
      token: fixture.token,
      body: {
        name: "Permissao Invalida",
        role: "SELLER",
        permissions: ["employees.delete"],
      },
    });
    assert.equal(invalidPermission.status, 422);

    const first = await requestJson("POST", "/employees", {
      token: fixture.token,
      body: {
        name: "Duplicado A",
        email: "DUP@tatuzin.test",
        role: "SELLER",
      },
    });
    assert.equal(first.status, 201);

    const duplicate = await requestJson("POST", "/employees", {
      token: fixture.token,
      body: {
        name: "Duplicado B",
        email: "dup@tatuzin.test",
        role: "SELLER",
      },
    });
    assert.equal(duplicate.status, 409);
    assert.equal(
      (duplicate.data as { code?: string }).code,
      "EMPLOYEE_EMAIL_CONFLICT",
    );
  });

  it("protects OWNER from manual changes", async () => {
    const fixture = await createFixture({ plan: "pro" });
    const list = await requestJson("GET", "/employees", {
      token: fixture.token,
    });
    const owner = (list.data as { items: EmployeeDto[] }).items[0]!;

    const patch = await requestJson("PATCH", `/employees/${owner.id}`, {
      token: fixture.token,
      body: { name: "Outro Nome" },
    });
    assert.equal(patch.status, 403);

    const disable = await requestJson(
      "POST",
      `/employees/${owner.id}/disable`,
      {
        token: fixture.token,
      },
    );
    assert.equal(disable.status, 403);

    const remove = await requestJson("DELETE", `/employees/${owner.id}`, {
      token: fixture.token,
    });
    assert.equal(remove.status, 403);

    const stored = await prisma.employeeProfile.findUniqueOrThrow({
      where: { id: owner.id },
    });
    assert.equal(stored.role, "OWNER");
    assert.equal(stored.status, "ACTIVE");
  });

  it("isolates employees by company", async () => {
    const first = await createFixture({ plan: "pro" });
    const second = await createFixture({ plan: "pro" });

    const create = await requestJson("POST", "/employees", {
      token: first.token,
      body: {
        name: "Empresa A",
        email: "empresa-a@tatuzin.test",
        role: "SELLER",
      },
    });
    assert.equal(create.status, 201);
    const employeeId = (create.data as { employee: EmployeeDto }).employee.id;

    const crossCompany = await requestJson("GET", `/employees/${employeeId}`, {
      token: second.token,
    });
    assert.equal(crossCompany.status, 404);
  });

  it("respects maxEmployees and keeps disabled employees out of the count", async () => {
    const fixture = await createFixture({ plan: "pro" });
    await prisma.employeeProfile.createMany({
      data: Array.from({ length: 100 }, (_, index) => ({
        companyId: fixture.companyId,
        name: `Funcionario ${index}`,
        email: `limit-${index}@tatuzin.test`,
        emailNormalized: `limit-${index}@tatuzin.test`,
        role: "SELLER",
        status: "ACTIVE",
      })),
    });

    const blocked = await requestJson("POST", "/employees", {
      token: fixture.token,
      body: {
        name: "Funcionario Excedente",
        email: "excedente@tatuzin.test",
        role: "SELLER",
      },
    });
    assert.equal(blocked.status, 409);
    assert.equal(
      (blocked.data as { code?: string }).code,
      "EMPLOYEE_LIMIT_REACHED",
    );

    const firstEmployee = await prisma.employeeProfile.findFirstOrThrow({
      where: { companyId: fixture.companyId, role: "SELLER" },
      select: { id: true },
    });
    const disable = await requestJson(
      "POST",
      `/employees/${firstEmployee.id}/disable`,
      { token: fixture.token },
    );
    assert.equal(disable.status, 200);

    const allowed = await requestJson("POST", "/employees", {
      token: fixture.token,
      body: {
        name: "Funcionario Novo",
        email: "novo@tatuzin.test",
        role: "SELLER",
      },
    });
    assert.equal(allowed.status, 201);
  });

  it("preserves employees after downgrade while blocking the endpoint", async () => {
    const fixture = await createFixture({ plan: "pro" });
    const create = await requestJson("POST", "/employees", {
      token: fixture.token,
      body: {
        name: "Preservado",
        email: "preservado@tatuzin.test",
        role: "SELLER",
      },
    });
    assert.equal(create.status, 201);

    await prisma.license.update({
      where: { companyId: fixture.companyId },
      data: { plan: "free" },
    });

    const blocked = await requestJson("GET", "/employees", {
      token: fixture.token,
    });
    assert.equal(blocked.status, 403);
    assert.equal(
      (blocked.data as { code?: string }).code,
      "FEATURE_NOT_AVAILABLE",
    );

    const employeesCount = await prisma.employeeProfile.count({
      where: { companyId: fixture.companyId },
    });
    assert.equal(employeesCount, 2);
  });

  it("requires email to invite employees", async () => {
    const fixture = await createFixture({ plan: "pro" });
    const create = await requestJson("POST", "/employees", {
      token: fixture.token,
      body: {
        name: "Sem Email",
        role: "SELLER",
      },
    });
    assert.equal(create.status, 201);
    const employeeId = (create.data as { employee: EmployeeDto }).employee.id;

    const invite = await requestJson(
      "POST",
      `/employees/${employeeId}/invite`,
      {
        token: fixture.token,
      },
    );
    assert.equal(invite.status, 422);
    assert.equal(
      (invite.data as { code?: string }).code,
      "EMPLOYEE_EMAIL_REQUIRED",
    );
  });

  it("OWNER generates a temporary password without storing it in plain text", async () => {
    const fixture = await createFixture({ plan: "pro" });
    const employeeEmail = `${runId}-caixa-acesso@tatuzin.test`;
    const create = await requestJson("POST", "/employees", {
      token: fixture.token,
      body: {
        name: "Caixa Acesso",
        email: employeeEmail,
        role: "CASHIER",
      },
    });
    assert.equal(create.status, 201);
    const employeeId = (create.data as { employee: EmployeeDto }).employee.id;

    const access = await requestJson(
      "POST",
      `/employees/${employeeId}/access/temporary-password`,
      { token: fixture.token },
    );

    assert.equal(access.status, 200);
    const payload = access.data as {
      employee: EmployeeDto & {
        accessStatus: string;
        temporaryPasswordExpiresAt: string | null;
      };
      login: string;
      temporaryPassword: string;
      temporaryPasswordExpiresAt: string;
    };
    assert.equal(payload.login, employeeEmail);
    assert.ok(payload.temporaryPassword.length >= 10);
    assert.equal(payload.employee.accessStatus, "TEMPORARY_PASSWORD_PENDING");
    assert.equal(
      payload.employee.temporaryPasswordExpiresAt,
      payload.temporaryPasswordExpiresAt,
    );

    const stored = await prisma.employeeProfile.findUniqueOrThrow({
      where: { id: employeeId },
      include: { user: true, membership: true },
    });
    assert.ok(stored.userId);
    assert.ok(stored.membershipId);
    assert.equal(stored.membership?.role, "OPERATOR");
    assert.equal(stored.user?.mustChangePassword, true);
    assert.notEqual(stored.user?.passwordHash, payload.temporaryPassword);
    assert.equal(
      await bcrypt.compare(
        payload.temporaryPassword,
        stored.user?.passwordHash ?? "",
      ),
      true,
    );
  });

  it("does not allow employee access takeover with the OWNER email", async () => {
    const fixture = await createFixture({ plan: "pro" });
    const create = await requestJson("POST", "/employees", {
      token: fixture.token,
      body: {
        name: "Tentativa Owner",
        email: fixture.email.toUpperCase(),
        role: "SELLER",
      },
    });
    assert.equal(create.status, 409);
    assert.equal(
      (create.data as { code?: string }).code,
      "EMPLOYEE_EMAIL_CONFLICT",
    );
  });

  it("blocks a regular employee from generating another employee password", async () => {
    const fixture = await createFixture({ plan: "pro", role: "OPERATOR" });
    await prisma.employeeProfile.create({
      data: {
        companyId: fixture.companyId,
        userId: fixture.userId,
        membershipId: fixture.membershipId,
        name: "Funcionario comum",
        email: fixture.email,
        emailNormalized: fixture.email.toLowerCase(),
        role: "CASHIER",
        status: "ACTIVE",
        permissions: ["sales.create"],
      },
    });
    const target = await prisma.employeeProfile.create({
      data: {
        companyId: fixture.companyId,
        name: "Alvo",
        email: "alvo-sem-permissao@tatuzin.test",
        emailNormalized: "alvo-sem-permissao@tatuzin.test",
        role: "SELLER",
        status: "ACTIVE",
      },
    });

    const response = await requestJson(
      "POST",
      `/employees/${target.id}/access/temporary-password`,
      { token: fixture.token },
    );

    assert.equal(response.status, 403);
    assert.equal(
      (response.data as { code?: string }).code,
      "EMPLOYEE_PERMISSION_REQUIRED",
    );
  });

  it("temporary password login requires initial password change and then activates access", async () => {
    const fixture = await createFixture({ plan: "pro" });
    const employeeEmail = `${runId}-senha-inicial@tatuzin.test`;
    const create = await requestJson("POST", "/employees", {
      token: fixture.token,
      body: {
        name: "Senha Inicial",
        email: employeeEmail,
        role: "SELLER",
      },
    });
    const employeeId = (create.data as { employee: EmployeeDto }).employee.id;
    const access = await requestJson(
      "POST",
      `/employees/${employeeId}/access/temporary-password`,
      { token: fixture.token },
    );
    const temporaryPassword = (access.data as { temporaryPassword: string })
      .temporaryPassword;

    const login = await requestJson("POST", "/auth/login", {
      body: {
        email: employeeEmail,
        password: temporaryPassword,
        clientType: "mobile_app",
        clientInstanceId: `${fixture.clientInstanceId}-employee`,
      },
    });
    assert.equal(login.status, 200);
    const loginPayload = login.data as {
      accessToken: string;
      user: { mustChangePassword: boolean };
    };
    assert.equal(loginPayload.user.mustChangePassword, true);

    const bootstrapBlocked = await requestJson("GET", "/app/bootstrap", {
      token: loginPayload.accessToken,
    });
    assert.equal(bootstrapBlocked.status, 403);
    assert.equal(
      (bootstrapBlocked.data as { code?: string }).code,
      "INITIAL_PASSWORD_CHANGE_REQUIRED",
    );

    const change = await requestJson("POST", "/auth/change-initial-password", {
      token: loginPayload.accessToken,
      body: { newPassword: "NovaSenha123!" },
    });
    assert.equal(change.status, 200);

    const stored = await prisma.employeeProfile.findUniqueOrThrow({
      where: { id: employeeId },
      include: { user: true },
    });
    assert.equal(stored.acceptedAt != null, true);
    assert.equal(stored.user?.mustChangePassword, false);
    assert.equal(stored.user?.temporaryPasswordExpiresAt, null);
    assert.equal(
      await bcrypt.compare(temporaryPassword, stored.user?.passwordHash ?? ""),
      false,
    );
    assert.equal(
      await bcrypt.compare("NovaSenha123!", stored.user?.passwordHash ?? ""),
      true,
    );

    const oldPasswordLogin = await requestJson("POST", "/auth/login", {
      body: {
        email: employeeEmail,
        password: temporaryPassword,
        clientType: "mobile_app",
        clientInstanceId: `${fixture.clientInstanceId}-old-after-change`,
      },
    });
    assert.equal(oldPasswordLogin.status, 401);
    assert.equal(
      (oldPasswordLogin.data as { code?: string }).code,
      "INVALID_CREDENTIALS",
    );
  });

  it("expired and reset temporary passwords cannot be reused", async () => {
    const fixture = await createFixture({ plan: "pro" });
    const employeeEmail = `${runId}-expirada@tatuzin.test`;
    const create = await requestJson("POST", "/employees", {
      token: fixture.token,
      body: {
        name: "Expirada",
        email: employeeEmail,
        role: "SELLER",
      },
    });
    const employeeId = (create.data as { employee: EmployeeDto }).employee.id;
    const firstAccess = await requestJson(
      "POST",
      `/employees/${employeeId}/access/temporary-password`,
      { token: fixture.token },
    );
    const firstPassword = (firstAccess.data as { temporaryPassword: string })
      .temporaryPassword;

    const employee = await prisma.employeeProfile.findUniqueOrThrow({
      where: { id: employeeId },
      select: { userId: true },
    });
    await prisma.user.update({
      where: { id: employee.userId! },
      data: { temporaryPasswordExpiresAt: new Date(Date.now() - 60_000) },
    });

    const expiredLogin = await requestJson("POST", "/auth/login", {
      body: {
        email: employeeEmail,
        password: firstPassword,
        clientType: "mobile_app",
        clientInstanceId: `${fixture.clientInstanceId}-expired`,
      },
    });
    assert.equal(expiredLogin.status, 401);
    assert.equal(
      (expiredLogin.data as { code?: string }).code,
      "TEMPORARY_PASSWORD_EXPIRED",
    );

    const resetAccess = await requestJson(
      "POST",
      `/employees/${employeeId}/access/temporary-password`,
      { token: fixture.token },
    );
    const secondPassword = (resetAccess.data as { temporaryPassword: string })
      .temporaryPassword;

    const oldLogin = await requestJson("POST", "/auth/login", {
      body: {
        email: employeeEmail,
        password: firstPassword,
        clientType: "mobile_app",
        clientInstanceId: `${fixture.clientInstanceId}-old`,
      },
    });
    assert.equal(oldLogin.status, 401);
    assert.equal(
      (oldLogin.data as { code?: string }).code,
      "INVALID_CREDENTIALS",
    );

    const newLogin = await requestJson("POST", "/auth/login", {
      body: {
        email: employeeEmail,
        password: secondPassword,
        clientType: "mobile_app",
        clientInstanceId: `${fixture.clientInstanceId}-new`,
      },
    });
    assert.equal(newLogin.status, 200);
  });

  it("disabled employee with generated access cannot login", async () => {
    const fixture = await createFixture({ plan: "pro" });
    const employeeEmail = `${runId}-desativar-login@tatuzin.test`;
    const create = await requestJson("POST", "/employees", {
      token: fixture.token,
      body: {
        name: "Desativar Login",
        email: employeeEmail,
        role: "SELLER",
      },
    });
    const employeeId = (create.data as { employee: EmployeeDto }).employee.id;
    const access = await requestJson(
      "POST",
      `/employees/${employeeId}/access/temporary-password`,
      { token: fixture.token },
    );
    const temporaryPassword = (access.data as { temporaryPassword: string })
      .temporaryPassword;

    const disable = await requestJson(
      "POST",
      `/employees/${employeeId}/disable`,
      { token: fixture.token },
    );
    assert.equal(disable.status, 200);

    const login = await requestJson("POST", "/auth/login", {
      body: {
        email: employeeEmail,
        password: temporaryPassword,
        clientType: "mobile_app",
        clientInstanceId: `${fixture.clientInstanceId}-disabled`,
      },
    });
    assert.equal(login.status, 403);
    assert.equal((login.data as { code?: string }).code, "EMPLOYEE_DISABLED");
  });

  it("reports employee activity from traceable actors without counting untracked data", async () => {
    const fixture = await createFixture({ plan: "pro" });
    const actor = await createEmployeeActor(fixture, {
      name: "Vendedora Ativa",
      role: "SELLER",
      permissions: ["sales.create", "stock.adjust"],
    });
    const day = new Date("2026-05-20T12:00:00.000Z");

    const cashSession = await prisma.cashSession.create({
      data: {
        companyId: fixture.companyId,
        deviceId: fixture.deviceId,
        userId: actor.userId,
        localUuid: `${runId}-cash-session`,
        status: "closed",
        openedAt: new Date("2026-05-20T08:00:00.000Z"),
        closedAt: new Date("2026-05-20T18:00:00.000Z"),
        openingBalanceCents: 1000,
        closingBalanceCents: 13500,
      },
    });

    const traceableSale = await prisma.sale.create({
      data: {
        companyId: fixture.companyId,
        cashSessionId: cashSession.id,
        localUuid: `${runId}-traceable-sale`,
        paymentType: "cash",
        paymentMethod: "cash",
        status: "active",
        totalAmountCents: 12500,
        totalCostCents: 5000,
        soldAt: day,
      },
    });
    await prisma.syncEvent.create({
      data: {
        companyId: fixture.companyId,
        deviceId: fixture.deviceId,
        userId: actor.userId,
        eventId: `${runId}-sale-event`,
        feature: "sales",
        entity: "sale",
        operation: "create",
        entityServerId: traceableSale.id,
        occurredAt: day,
        payload: { totalAmountCents: 12500 },
        status: SyncEventStatus.ACCEPTED,
        serverVersion: 2,
        materializedAt: day,
      },
    });
    await prisma.sale.create({
      data: {
        companyId: fixture.companyId,
        localUuid: `${runId}-untracked-sale`,
        paymentType: "cash",
        paymentMethod: "cash",
        status: "active",
        totalAmountCents: 99900,
        totalCostCents: 1000,
        soldAt: day,
      },
    });
    await prisma.operationalOrder.create({
      data: {
        companyId: fixture.companyId,
        localUuid: `${runId}-discounted-order`,
        sellerUserId: actor.userId,
        status: "closed",
        subtotalCents: 14000,
        discountCents: 1500,
        totalCents: 12500,
        closedAt: day,
        updatedAt: day,
      },
    });
    const deduction = await prisma.stockDeduction.create({
      data: {
        companyId: fixture.companyId,
        localUuid: `${runId}-manual-stock-deduction`,
        quantityMil: 1000,
        createdAt: day,
      },
    });
    await prisma.syncEvent.create({
      data: {
        companyId: fixture.companyId,
        deviceId: fixture.deviceId,
        userId: actor.userId,
        eventId: `${runId}-stock-event`,
        feature: "inventory",
        entity: "stockDeduction",
        operation: "create",
        entityServerId: deduction.id,
        occurredAt: day,
        payload: {},
        status: SyncEventStatus.ACCEPTED,
        serverVersion: 1,
        materializedAt: day,
      },
    });
    const saleLinkedDeduction = await prisma.stockDeduction.create({
      data: {
        companyId: fixture.companyId,
        saleId: traceableSale.id,
        localUuid: `${runId}-sale-stock-deduction`,
        quantityMil: 1000,
        createdAt: day,
      },
    });
    await prisma.syncEvent.create({
      data: {
        companyId: fixture.companyId,
        deviceId: fixture.deviceId,
        userId: actor.userId,
        eventId: `${runId}-sale-stock-event`,
        feature: "inventory",
        entity: "stockDeduction",
        operation: "create",
        entityServerId: saleLinkedDeduction.id,
        occurredAt: day,
        payload: {},
        status: SyncEventStatus.ACCEPTED,
        serverVersion: 3,
        materializedAt: day,
      },
    });

    const otherFixture = await createFixture({ plan: "pro" });
    await prisma.sale.create({
      data: {
        companyId: otherFixture.companyId,
        localUuid: `${runId}-other-company-sale`,
        paymentType: "cash",
        paymentMethod: "cash",
        status: "active",
        totalAmountCents: 77700,
        totalCostCents: 1000,
        soldAt: day,
      },
    });

    const response = await requestJson(
      "GET",
      "/employees/activity/summary?from=2026-05-20&to=2026-05-20",
      { token: fixture.token },
    );

    assert.equal(response.status, 200);
    const payload = response.data as EmployeeActivitySummaryResponse;
    assert.equal(payload.totalSalesCount, 1);
    assert.equal(payload.totalSalesAmountCents, 12500);
    assert.equal(payload.totalDiscountAmountCents, 1500);
    assert.equal(payload.totalStockAdjustments, 1);
    const actorRow = payload.rows.find(
      (row) => row.employeeId === actor.employeeId,
    );
    assert.ok(actorRow);
    assert.equal(actorRow.salesCount, 1);
    assert.equal(actorRow.cashActionsCount, 2);
    assert.equal(actorRow.lastActivityAt, "2026-05-20T18:00:00.000Z");

    const emptyPeriod = await requestJson(
      "GET",
      "/employees/activity/summary?from=2026-05-19&to=2026-05-19",
      { token: fixture.token },
    );
    assert.equal(emptyPeriod.status, 200);
    assert.equal(
      (emptyPeriod.data as EmployeeActivitySummaryResponse).totalSalesCount,
      0,
    );

    const detail = await requestJson(
      "GET",
      `/employees/${actor.employeeId}/activity?from=2026-05-20&to=2026-05-20`,
      { token: fixture.token },
    );
    assert.equal(detail.status, 200);
    const detailPayload = detail.data as EmployeeActivityDetailResponse;
    assert.equal(detailPayload.timeline.length, 5);
    assert.equal(
      detailPayload.timeline.some((item) => item.metadata != null),
      false,
    );
  });

  it("protects employee activity summary and allows employees to view only their own detail", async () => {
    const fixture = await createFixture({
      plan: "pro",
      role: "OPERATOR",
    });
    const ownEmployee = await createEmployeeProfileForFixture(fixture, {
      name: "Funcionario Logado",
      role: "SELLER",
      permissions: ["sales.create"],
    });
    const otherEmployee = await createEmployeeActor(fixture, {
      name: "Outro Funcionario",
      role: "CASHIER",
      permissions: ["sales.create"],
    });

    const summary = await requestJson(
      "GET",
      "/employees/activity/summary?from=2026-05-20&to=2026-05-20",
      { token: fixture.token },
    );
    assert.equal(summary.status, 403);
    assert.equal(
      (summary.data as { code?: string }).code,
      "EMPLOYEE_ACTIVITY_PERMISSION_REQUIRED",
    );

    const ownDetail = await requestJson(
      "GET",
      `/employees/${ownEmployee.id}/activity?from=2026-05-20&to=2026-05-20`,
      { token: fixture.token },
    );
    assert.equal(ownDetail.status, 200);
    assert.equal(
      (ownDetail.data as EmployeeActivityDetailResponse).employee.id,
      ownEmployee.id,
    );

    const otherDetail = await requestJson(
      "GET",
      `/employees/${otherEmployee.employeeId}/activity?from=2026-05-20&to=2026-05-20`,
      { token: fixture.token },
    );
    assert.equal(otherDetail.status, 403);
  });

  it("returns a safe not found for activity detail from another company", async () => {
    const first = await createFixture({ plan: "pro" });
    const second = await createFixture({ plan: "pro" });
    const otherEmployee = await createEmployeeActor(second, {
      name: "Funcionario Outra Empresa",
      role: "SELLER",
      permissions: ["sales.create"],
    });

    const response = await requestJson(
      "GET",
      `/employees/${otherEmployee.employeeId}/activity?from=2026-05-20&to=2026-05-20`,
      { token: first.token },
    );

    assert.equal(response.status, 404);
    assert.equal(
      (response.data as { code?: string }).code,
      "EMPLOYEE_NOT_FOUND",
    );
  });

  it("allows existing report permission to view employee activity summary", async () => {
    const fixture = await createFixture({
      plan: "pro",
      role: "OPERATOR",
    });
    await createEmployeeProfileForFixture(fixture, {
      name: "Analista de Relatorio",
      role: "READ_ONLY",
      permissions: ["reports.advanced"],
    });

    const response = await requestJson(
      "GET",
      "/employees/activity/summary?from=2026-05-20&to=2026-05-20",
      { token: fixture.token },
    );

    assert.equal(response.status, 200);
    assert.equal(
      (response.data as EmployeeActivitySummaryResponse).totalSalesCount,
      0,
    );
  });

  it("validates employee activity date range before querying", async () => {
    const fixture = await createFixture({ plan: "pro" });

    const invalidDate = await requestJson(
      "GET",
      "/employees/activity/summary?from=2026-02-31&to=2026-03-01",
      { token: fixture.token },
    );
    assert.equal(invalidDate.status, 422);

    const tooLong = await requestJson(
      "GET",
      "/employees/activity/summary?from=2026-01-01&to=2026-05-20",
      { token: fixture.token },
    );
    assert.equal(tooLong.status, 422);
  });

  it("configures employee commission and calculates net, gross and profit bases safely", async () => {
    const fixture = await createFixture({ plan: "pro" });
    const seller = await createEmployeeActor(fixture, {
      name: "Gabriel Vendedor",
      role: "SELLER",
      permissions: ["sales.create"],
    });
    const day = new Date("2026-05-20T14:00:00.000Z");

    const settings = await requestJson(
      "PATCH",
      `/employees/${seller.employeeId}/commission-settings`,
      {
        token: fixture.token,
        body: {
          commissionEnabled: true,
          commissionType: "PERCENTAGE",
          commissionBase: "NET_SALES",
          commissionRateBps: 500,
        },
      },
    );
    assert.equal(settings.status, 200);

    await createCommissionSale(fixture, seller.userId, {
      localUuid: `${runId}-commission-net`,
      soldAt: day,
      subtotalCents: 100000,
      totalAmountCents: 90000,
      items: [
        {
          localUuid: `${runId}-commission-net-item`,
          totalPriceCents: 100000,
          unitCostCents: 60000,
          totalCostCents: 60000,
        },
      ],
    });

    const netSummary = await requestJson(
      "GET",
      "/employees/commissions/summary?from=2026-05-20&to=2026-05-20",
      { token: fixture.token },
    );
    assert.equal(netSummary.status, 200);
    let row = (
      netSummary.data as EmployeeCommissionSummaryResponse
    ).rows.find((candidate) => candidate.employeeId === seller.employeeId);
    assert.ok(row);
    assert.equal(row.eligibleBaseAmountCents, 90000);
    assert.equal(row.commissionAmountCents, 4500);

    await requestJson("PATCH", `/employees/${seller.employeeId}/commission-settings`, {
      token: fixture.token,
      body: {
        commissionEnabled: true,
        commissionType: "PERCENTAGE",
        commissionBase: "GROSS_SALES",
        commissionRateBps: 500,
      },
    });
    const grossSummary = await requestJson(
      "GET",
      "/employees/commissions/summary?from=2026-05-20&to=2026-05-20",
      { token: fixture.token },
    );
    row = (grossSummary.data as EmployeeCommissionSummaryResponse).rows.find(
      (candidate) => candidate.employeeId === seller.employeeId,
    );
    assert.ok(row);
    assert.equal(row.eligibleBaseAmountCents, 100000);
    assert.equal(row.commissionAmountCents, 5000);

    await requestJson("PATCH", `/employees/${seller.employeeId}/commission-settings`, {
      token: fixture.token,
      body: {
        commissionEnabled: true,
        commissionType: "PERCENTAGE",
        commissionBase: "GROSS_PROFIT",
        commissionRateBps: 2000,
      },
    });
    const profitSummary = await requestJson(
      "GET",
      "/employees/commissions/summary?from=2026-05-20&to=2026-05-20",
      { token: fixture.token },
    );
    row = (profitSummary.data as EmployeeCommissionSummaryResponse).rows.find(
      (candidate) => candidate.employeeId === seller.employeeId,
    );
    assert.ok(row);
    assert.equal(row.grossProfitCents, 30000);
    assert.equal(row.commissionAmountCents, 6000);

    await requestJson("PATCH", `/employees/${seller.employeeId}/commission-settings`, {
      token: fixture.token,
      body: {
        commissionEnabled: true,
        commissionType: "FIXED_PER_SALE",
        commissionBase: "GROSS_PROFIT",
        commissionFixedCents: 777,
      },
    });
    const fixedSummary = await requestJson(
      "GET",
      "/employees/commissions/summary?from=2026-05-20&to=2026-05-20",
      { token: fixture.token },
    );
    row = (fixedSummary.data as EmployeeCommissionSummaryResponse).rows.find(
      (candidate) => candidate.employeeId === seller.employeeId,
    );
    assert.ok(row);
    assert.equal(row.eligibleSalesCount, 1);
    assert.equal(row.commissionAmountCents, 777);

    await requestJson("PATCH", `/employees/${seller.employeeId}/commission-settings`, {
      token: fixture.token,
      body: {
        commissionEnabled: false,
        commissionType: "NONE",
        commissionBase: "NET_SALES",
      },
    });
    const noneSummary = await requestJson(
      "GET",
      "/employees/commissions/summary?from=2026-05-20&to=2026-05-20",
      { token: fixture.token },
    );
    row = (noneSummary.data as EmployeeCommissionSummaryResponse).rows.find(
      (candidate) => candidate.employeeId === seller.employeeId,
    );
    assert.ok(row);
    assert.equal(row.commissionEnabled, false);
    assert.equal(row.commissionAmountCents, 0);
  });

  it("ignores canceled and unattributed sales, flags missing cost and does not expose cost details", async () => {
    const fixture = await createFixture({ plan: "pro" });
    const seller = await createEmployeeActor(fixture, {
      name: "Vendedora Lucro",
      role: "SELLER",
      permissions: ["sales.create"],
    });
    const day = new Date("2026-05-20T15:00:00.000Z");
    await requestJson("PATCH", `/employees/${seller.employeeId}/commission-settings`, {
      token: fixture.token,
      body: {
        commissionEnabled: true,
        commissionType: "PERCENTAGE",
        commissionBase: "GROSS_PROFIT",
        commissionRateBps: 1000,
      },
    });

    await createCommissionSale(fixture, seller.userId, {
      localUuid: `${runId}-missing-cost`,
      soldAt: day,
      subtotalCents: 10000,
      totalAmountCents: 10000,
      items: [
        {
          localUuid: `${runId}-missing-cost-item`,
          totalPriceCents: 10000,
          unitCostCents: 0,
          totalCostCents: 0,
        },
      ],
    });
    await createCommissionSale(fixture, seller.userId, {
      localUuid: `${runId}-negative-profit`,
      soldAt: day,
      subtotalCents: 10000,
      totalAmountCents: 10000,
      items: [
        {
          localUuid: `${runId}-negative-profit-item`,
          totalPriceCents: 10000,
          unitCostCents: 12000,
          totalCostCents: 12000,
        },
      ],
    });
    await createCommissionSale(fixture, seller.userId, {
      localUuid: `${runId}-canceled-commission`,
      soldAt: day,
      status: "canceled",
      canceledAt: day,
      subtotalCents: 20000,
      totalAmountCents: 20000,
      items: [
        {
          localUuid: `${runId}-canceled-commission-item`,
          totalPriceCents: 20000,
          unitCostCents: 1000,
          totalCostCents: 1000,
        },
      ],
    });
    await prisma.sale.create({
      data: {
        companyId: fixture.companyId,
        localUuid: `${runId}-no-actor-commission`,
        paymentType: "cash",
        paymentMethod: "cash",
        status: "active",
        totalAmountCents: 50000,
        totalCostCents: 1000,
        soldAt: day,
      },
    });

    const summary = await requestJson(
      "GET",
      "/employees/commissions/summary?from=2026-05-20&to=2026-05-20",
      { token: fixture.token },
    );
    assert.equal(summary.status, 200);
    const payload = summary.data as EmployeeCommissionSummaryResponse;
    const row = payload.rows.find(
      (candidate) => candidate.employeeId === seller.employeeId,
    );
    assert.ok(row);
    assert.equal(row.commissionAmountCents, 0);
    assert.equal(row.canceledSalesCount, 1);
    assert.equal(row.salesWithoutReliableCostCount, 1);
    assert.equal(payload.totals.salesWithoutReliableActorCount, 1);

    const detail = await requestJson(
      "GET",
      `/employees/${seller.employeeId}/commissions?from=2026-05-20&to=2026-05-20`,
      { token: fixture.token },
    );
    assert.equal(detail.status, 200);
    assert.equal(JSON.stringify(detail.data).includes("unitCostCents"), false);
    assert.equal(JSON.stringify(detail.data).includes("totalCostCents"), false);
  });

  it("attributes event-only sales by sale date even when sync arrives later", async () => {
    const fixture = await createFixture({ plan: "pro" });
    const seller = await createEmployeeActor(fixture, {
      name: "Sincronizado depois",
      role: "SELLER",
      permissions: ["sales.create"],
    });
    await requestJson("PATCH", `/employees/${seller.employeeId}/commission-settings`, {
      token: fixture.token,
      body: {
        commissionEnabled: true,
        commissionType: "PERCENTAGE",
        commissionBase: "NET_SALES",
        commissionRateBps: 10000,
      },
    });

    const sale = await prisma.sale.create({
      data: {
        companyId: fixture.companyId,
        localUuid: `${runId}-event-only-commission`,
        paymentType: "cash",
        paymentMethod: "cash",
        status: "active",
        totalAmountCents: 12345,
        totalCostCents: 5000,
        soldAt: new Date("2026-05-20T18:00:00.000Z"),
        items: {
          create: [
            {
              localUuid: `${runId}-event-only-commission-item`,
              productNameSnapshot: "Produto evento",
              quantityMil: 1000,
              unitPriceCents: 12345,
              totalPriceCents: 12345,
              unitCostCents: 5000,
              totalCostCents: 5000,
            },
          ],
        },
      },
    });
    await prisma.syncEvent.create({
      data: {
        companyId: fixture.companyId,
        deviceId: fixture.deviceId,
        userId: seller.userId,
        eventId: `${runId}-event-only-commission-sync`,
        feature: "pdv",
        entity: "sale",
        operation: "create",
        entityLocalId: sale.localUuid,
        entityServerId: sale.id,
        occurredAt: new Date("2026-05-21T02:00:00.000Z"),
        payload: {},
        status: SyncEventStatus.ACCEPTED,
        materializedAt: new Date("2026-05-21T02:00:00.000Z"),
      },
    });

    const summary = await requestJson(
      "GET",
      "/employees/commissions/summary?from=2026-05-20&to=2026-05-20",
      { token: fixture.token },
    );
    assert.equal(summary.status, 200);
    const payload = summary.data as EmployeeCommissionSummaryResponse;
    const row = payload.rows.find(
      (candidate) => candidate.employeeId === seller.employeeId,
    );
    assert.ok(row);
    assert.equal(row.eligibleSalesCount, 1);
    assert.equal(row.commissionAmountCents, 12345);
    assert.equal(payload.totals.salesWithoutReliableActorCount, 0);
  });

  it("hides profit amounts from common employee own commission detail", async () => {
    const fixture = await createFixture({ plan: "pro", role: "OPERATOR" });
    const ownEmployee = await createEmployeeProfileForFixture(fixture, {
      name: "Funcionario lucro proprio",
      role: "SELLER",
      permissions: ["sales.create"],
    });
    await prisma.employeeProfile.update({
      where: { id: ownEmployee.id },
      data: {
        commissionEnabled: true,
        commissionType: "PERCENTAGE",
        commissionBase: "GROSS_PROFIT",
        commissionRateBps: 2000,
      },
    });
    await createCommissionSale(fixture, fixture.userId, {
      localUuid: `${runId}-own-profit-hidden`,
      soldAt: new Date("2026-05-20T16:00:00.000Z"),
      subtotalCents: 10000,
      totalAmountCents: 10000,
      items: [
        {
          localUuid: `${runId}-own-profit-hidden-item`,
          totalPriceCents: 10000,
          unitCostCents: 7000,
          totalCostCents: 7000,
        },
      ],
    });

    const detail = await requestJson(
      "GET",
      `/employees/${ownEmployee.id}/commissions?from=2026-05-20&to=2026-05-20`,
      { token: fixture.token },
    );
    assert.equal(detail.status, 200);
    const body = JSON.stringify(detail.data);
    assert.equal(body.includes("unitCostCents"), false);
    assert.equal(body.includes("totalCostCents"), false);
    assert.equal(body.includes("grossProfitCents"), false);
    const payload = detail.data as {
      summary: { eligibleBaseAmountCents: number; commissionAmountCents: number };
      sales: Array<{ baseAmountCents: number; commissionAmountCents: number }>;
    };
    assert.equal(payload.summary.eligibleBaseAmountCents, 0);
    assert.equal(payload.summary.commissionAmountCents, 600);
    assert.equal(payload.sales[0]?.baseAmountCents, 0);
    assert.equal(payload.sales[0]?.commissionAmountCents, 600);
  });

  it("protects commission settings, tenant isolation and employee feature entitlement", async () => {
    const fixture = await createFixture({ plan: "pro", role: "OPERATOR" });
    const ownEmployee = await createEmployeeProfileForFixture(fixture, {
      name: "Funcionario comum",
      role: "SELLER",
      permissions: ["sales.create"],
    });
    const other = await createFixture({ plan: "pro" });
    const otherEmployee = await createEmployeeActor(other, {
      name: "Outra empresa",
      role: "SELLER",
      permissions: ["sales.create"],
    });
    const sameCompanyOther = await createEmployeeActor(fixture, {
      name: "Outro funcionario da mesma empresa",
      role: "SELLER",
      permissions: ["sales.create"],
    });

    const forbiddenPatch = await requestJson(
      "PATCH",
      `/employees/${ownEmployee.id}/commission-settings`,
      {
        token: fixture.token,
        body: {
          commissionEnabled: true,
          commissionType: "PERCENTAGE",
          commissionBase: "NET_SALES",
          commissionRateBps: 500,
        },
      },
    );
    assert.equal(forbiddenPatch.status, 403);

    const ownSettings = await requestJson(
      "GET",
      `/employees/${ownEmployee.id}/commission-settings`,
      { token: fixture.token },
    );
    assert.equal(ownSettings.status, 200);

    const sameCompanyOtherSettings = await requestJson(
      "GET",
      `/employees/${sameCompanyOther.employeeId}/commission-settings`,
      { token: fixture.token },
    );
    assert.equal(sameCompanyOtherSettings.status, 403);

    const otherSettings = await requestJson(
      "GET",
      `/employees/${otherEmployee.employeeId}/commission-settings`,
      { token: fixture.token },
    );
    assert.equal(otherSettings.status, 404);

    const invalidPatch = await requestJson(
      "PATCH",
      `/employees/${otherEmployee.employeeId}/commission-settings`,
      {
        token: other.token,
        body: {
          commissionEnabled: true,
          commissionType: "PERCENTAGE",
          commissionBase: "NET_SALES",
          commissionRateBps: 10001,
        },
      },
    );
    assert.equal(invalidPatch.status, 422);

    const basic = await createFixture({ plan: "basic", pendingPlan: "PRO" });
    const blocked = await requestJson(
      "GET",
      "/employees/commissions/summary?from=2026-05-20&to=2026-05-20",
      { token: basic.token },
    );
    assert.equal(blocked.status, 403);
    assert.equal((blocked.data as { code?: string }).code, "FEATURE_NOT_AVAILABLE");
  });
});

type EmployeeDto = {
  id: string;
  email: string | null;
  role: string;
  status: string;
  permissions: string[];
  accessStatus?: string;
  temporaryPasswordExpiresAt?: string | null;
};

type EmployeeActivitySummaryResponse = {
  totalSalesCount: number;
  totalSalesAmountCents: number;
  totalDiscountAmountCents: number;
  totalStockAdjustments: number;
  rows: Array<{
    employeeId: string;
    salesCount: number;
    cashActionsCount: number;
    lastActivityAt: string | null;
  }>;
};

type EmployeeActivityDetailResponse = {
  employee: {
    id: string;
  };
  timeline: Array<{
    metadata?: unknown;
  }>;
};

type EmployeeCommissionSummaryResponse = {
  totals: {
    salesWithoutReliableActorCount: number;
  };
  rows: Array<{
    employeeId: string;
    eligibleSalesCount: number;
    eligibleBaseAmountCents: number;
    grossProfitCents: number;
    commissionAmountCents: number;
    canceledSalesCount: number;
    salesWithoutReliableCostCount: number;
  }>;
};

async function createFixture(options: {
  plan: string;
  role?: "OWNER" | "ADMIN" | "OPERATOR";
  pendingPlan?: string | null;
}) {
  const unique = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
  const company = await prisma.company.create({
    data: {
      name: "Employees Company",
      legalName: "Employees Company LTDA",
      slug: `${runId}-company-${unique}`,
    },
  });
  const user = await prisma.user.create({
    data: {
      email: `${runId}-${unique}@tatuzin.test`,
      name: "Employees User",
      passwordHash: "not-used",
    },
  });
  const membership = await prisma.membership.create({
    data: {
      userId: user.id,
      companyId: company.id,
      role: options.role ?? "OWNER",
      isDefault: true,
    },
  });
  await prisma.license.create({
    data: {
      companyId: company.id,
      plan: options.plan,
      pendingPlan: options.pendingPlan,
      status: "ACTIVE",
      startsAt: new Date(),
      syncEnabled: true,
    },
  });
  const clientInstanceId = `${runId}-device-${unique}`;
  const device = await prisma.companyDevice.create({
    data: {
      companyId: company.id,
      userId: user.id,
      clientInstanceId,
      deviceLabel: "Employees Test Device",
      platform: "node-test",
      appVersion: "employees-test",
      status: "ACTIVE",
      approvedAt: new Date(),
      approvedByUserId: user.id,
      lastSeenAt: new Date(),
    },
  });

  return {
    userId: user.id,
    companyId: company.id,
    membershipId: membership.id,
    deviceId: device.id,
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

async function createEmployeeActor(
  fixture: Awaited<ReturnType<typeof createFixture>>,
  input: {
    name: string;
    role: string;
    permissions: string[];
  },
) {
  const unique = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
  const user = await prisma.user.create({
    data: {
      email: `${runId}-${unique}@tatuzin.test`,
      name: input.name,
      passwordHash: "not-used",
    },
  });
  const membership = await prisma.membership.create({
    data: {
      userId: user.id,
      companyId: fixture.companyId,
      role: "OPERATOR",
    },
  });
  const employee = await prisma.employeeProfile.create({
    data: {
      companyId: fixture.companyId,
      userId: user.id,
      membershipId: membership.id,
      name: input.name,
      email: user.email,
      emailNormalized: user.email.toLowerCase(),
      role: input.role,
      status: "ACTIVE",
      permissions: input.permissions,
    },
  });

  return {
    userId: user.id,
    membershipId: membership.id,
    employeeId: employee.id,
  };
}

async function createEmployeeProfileForFixture(
  fixture: Awaited<ReturnType<typeof createFixture>>,
  input: {
    name: string;
    role: string;
    permissions: string[];
  },
) {
  return prisma.employeeProfile.create({
    data: {
      companyId: fixture.companyId,
      userId: fixture.userId,
      membershipId: fixture.membershipId,
      name: input.name,
      email: fixture.email,
      emailNormalized: fixture.email.toLowerCase(),
      role: input.role,
      status: "ACTIVE",
      permissions: input.permissions,
    },
  });
}

async function createCommissionSale(
  fixture: Awaited<ReturnType<typeof createFixture>>,
  sellerUserId: string,
  input: {
    localUuid: string;
    soldAt: Date;
    subtotalCents: number;
    totalAmountCents: number;
    status?: string;
    canceledAt?: Date | null;
    items: Array<{
      localUuid: string;
      totalPriceCents: number;
      unitCostCents: number;
      totalCostCents: number;
    }>;
  },
) {
  const sale = await prisma.sale.create({
    data: {
      companyId: fixture.companyId,
      localUuid: input.localUuid,
      paymentType: "cash",
      paymentMethod: "cash",
      status: input.status ?? "active",
      totalAmountCents: input.totalAmountCents,
      totalCostCents: input.items.reduce(
        (total, item) => total + item.totalCostCents,
        0,
      ),
      soldAt: input.soldAt,
      canceledAt: input.canceledAt,
      items: {
        create: input.items.map((item) => ({
          localUuid: item.localUuid,
          productNameSnapshot: "Produto comissao",
          quantityMil: 1000,
          unitPriceCents: item.totalPriceCents,
          totalPriceCents: item.totalPriceCents,
          unitCostCents: item.unitCostCents,
          totalCostCents: item.totalCostCents,
        })),
      },
    },
  });

  await prisma.operationalOrder.create({
    data: {
      companyId: fixture.companyId,
      localUuid: `${input.localUuid}-order`,
      sellerUserId,
      status: input.status === "canceled" ? "cancelled" : "closed",
      subtotalCents: input.subtotalCents,
      discountCents: Math.max(input.subtotalCents - input.totalAmountCents, 0),
      totalCents: input.totalAmountCents,
      closedAt: input.soldAt,
      cancelledAt: input.canceledAt,
      convertedSaleId: sale.id,
    },
  });

  return sale;
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
    { expiresIn: "15m" },
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
      ...(options?.body == null ? {} : { "Content-Type": "application/json" }),
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
