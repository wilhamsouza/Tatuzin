import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';
import type { AddressInfo } from 'node:net';

import bcrypt from 'bcryptjs';
import type { Server } from 'http';

import { createApp } from '../app';
import { prisma } from '../database/prisma';
import { resetRateLimitStore } from '../shared/http/rate-limit';
import { platformJobsService } from '../shared/platform/platform-jobs';

type JsonResponse = {
  status: number;
  headers: Headers;
  data: unknown;
};

const runId = `phase3-${Date.now()}`;
const adminPassword = 'StrongPass123!';
const rateLimitPassword = 'AnotherStrongPass123!';
const adminEmail = `${runId}.admin@tatuzin.test`;
const rateLimitEmail = `${runId}.ratelimit@tatuzin.test`;
const baseClientPayload = {
  clientType: 'admin_web',
  clientInstanceId: `${runId}-web`,
  deviceLabel: 'Node Test Browser',
  platform: 'node-test',
  appVersion: 'phase3-tests',
};

let server: Server;
let apiBaseUrl = '';
let primaryCompanyId = '';
let companiesPrefix = `Tatuzin Platform ${runId}`;

before(async () => {
  await prisma.$connect();
  await seedFixtures();

  server = createApp().listen(0);
  const address = server.address() as AddressInfo;
  apiBaseUrl = `http://127.0.0.1:${address.port}/api`;
});

beforeEach(() => {
  resetRateLimitStore();
});

after(async () => {
  resetRateLimitStore();
  await new Promise<void>((resolve, reject) => {
    server.close((error) => {
      if (error != null) {
        reject(error);
        return;
      }
      resolve();
    });
  });
  platformJobsService.stop();
  await cleanupFixtures();
  await prisma.$disconnect();
});

describe('platform backend hardening', () => {
  it('keeps health and readiness endpoints available', async () => {
    const health = await requestJson('GET', '/health');
    assert.equal(health.status, 200);
    assert.equal((health.data as { ok?: boolean }).ok, true);
    assert.ok(health.headers.get('x-request-id'));

    const readiness = await requestJson('GET', '/readiness');
    assert.equal(readiness.status, 200);
    const readinessPayload = readiness.data as {
      ready?: boolean;
      checks?: {
        database?: string;
      };
    };
    assert.equal(readinessPayload.ready, true);
    assert.equal(readinessPayload.checks?.database, 'ok');
  });

  it('keeps admin endpoints protected', async () => {
    const response = await requestJson('GET', '/admin/companies');
    assert.equal(response.status, 401);
    assert.equal(
      (response.data as { code?: string }).code,
      'AUTH_REQUIRED',
    );
  });

  it('keeps login, refresh and logout working', async () => {
    const login = await requestJson('POST', '/auth/login', {
      body: {
        email: adminEmail,
        password: adminPassword,
        ...baseClientPayload,
      },
    });

    assert.equal(login.status, 200);
    const loginPayload = login.data as {
      accessToken: string;
      refreshToken: string;
      session: { id: string };
      user: { email: string };
    };
    assert.equal(loginPayload.user.email, adminEmail);
    assert.ok(loginPayload.accessToken.length > 20);
    assert.ok(loginPayload.refreshToken.length > 20);

    const me = await requestJson('GET', '/auth/me', {
      token: loginPayload.accessToken,
    });
    assert.equal(me.status, 200);

    const refresh = await requestJson('POST', '/auth/refresh', {
      body: {
        refreshToken: loginPayload.refreshToken,
        ...baseClientPayload,
      },
    });
    assert.equal(refresh.status, 200);
    const refreshPayload = refresh.data as {
      accessToken: string;
      refreshToken: string;
    };
    assert.ok(refreshPayload.accessToken.length > 20);
    assert.notEqual(refreshPayload.refreshToken, loginPayload.refreshToken);

    const logout = await requestJson('POST', '/auth/logout', {
      token: refreshPayload.accessToken,
    });
    assert.equal(logout.status, 204);

    const afterLogout = await requestJson('GET', '/auth/me', {
      token: refreshPayload.accessToken,
    });
    assert.equal(afterLogout.status, 401);
    assert.equal(
      (afterLogout.data as { code?: string }).code,
      'SESSION_REVOKED',
    );
  });

  it('paginates companies, licenses, audit and sync summaries', async () => {
    const token = await loginAsPlatformAdmin();

    const companies = await requestJson(
      'GET',
      `/admin/companies?search=${encodeURIComponent(
        companiesPrefix,
      )}&page=1&pageSize=5&sortBy=name&sortDirection=asc`,
      {
        token,
      },
    );
    assert.equal(companies.status, 200);
    const companiesPayload = companies.data as {
      items: unknown[];
      total: number;
      page: number;
      pageSize: number;
      hasNext: boolean;
    };
    assert.equal(companiesPayload.page, 1);
    assert.equal(companiesPayload.pageSize, 5);
    assert.equal(companiesPayload.total, 15);
    assert.equal(companiesPayload.items.length, 5);
    assert.equal(companiesPayload.hasNext, true);

    const licenses = await requestJson(
      'GET',
      `/admin/licenses?search=${encodeURIComponent(
        companiesPrefix,
      )}&page=2&pageSize=4&sortBy=companyName&sortDirection=asc`,
      {
        token,
      },
    );
    assert.equal(licenses.status, 200);
    const licensesPayload = licenses.data as {
      items: unknown[];
      total: number;
      page: number;
      pageSize: number;
      hasPrevious: boolean;
    };
    assert.equal(licensesPayload.page, 2);
    assert.equal(licensesPayload.pageSize, 4);
    assert.equal(licensesPayload.total, 15);
    assert.equal(licensesPayload.items.length, 4);
    assert.equal(licensesPayload.hasPrevious, true);

    const patchLicense = await requestJson(
      'PATCH',
      `/admin/licenses/${primaryCompanyId}`,
      {
        token,
        body: {
          syncEnabled: false,
        },
      },
    );
    assert.equal(patchLicense.status, 200);

    const audit = await requestJson(
      'GET',
      `/admin/audit/summary?page=1&pageSize=5&companyId=${encodeURIComponent(
        primaryCompanyId,
      )}`,
      {
        token,
      },
    );
    assert.equal(audit.status, 200);
    const auditPayload = audit.data as {
      totalEvents: number;
      recentEvents: unknown[];
      pagination: {
        page: number;
        pageSize: number;
      };
    };
    assert.equal(auditPayload.pagination.page, 1);
    assert.equal(auditPayload.pagination.pageSize, 5);
    assert.ok(auditPayload.totalEvents >= 1);
    assert.ok(auditPayload.recentEvents.length >= 1);

    const sync = await requestJson(
      'GET',
      `/admin/sync/summary?search=${encodeURIComponent(
        companiesPrefix,
      )}&page=1&pageSize=3&sortBy=remoteRecordCount&sortDirection=desc`,
      {
        token,
      },
    );
    assert.equal(sync.status, 200);
    const syncPayload = sync.data as {
      companies: unknown[];
      pagination: {
        total: number;
        pageSize: number;
      };
    };
    assert.equal(syncPayload.pagination.total, 15);
    assert.equal(syncPayload.pagination.pageSize, 3);
    assert.equal(syncPayload.companies.length, 3);
  });

  it('applies login rate limiting without breaking normal usage', async () => {
    for (let attempt = 1; attempt <= 8; attempt += 1) {
      const response = await requestJson('POST', '/auth/login', {
        body: {
          email: rateLimitEmail,
          password: 'wrong-password',
          ...baseClientPayload,
          clientInstanceId: `${runId}-rate-limit`,
        },
      });

      assert.equal(response.status, 401);
      assert.equal(
        (response.data as { code?: string }).code,
        'INVALID_CREDENTIALS',
      );
    }

    const blocked = await requestJson('POST', '/auth/login', {
      body: {
        email: rateLimitEmail,
        password: 'wrong-password',
        ...baseClientPayload,
        clientInstanceId: `${runId}-rate-limit`,
      },
    });

    assert.equal(blocked.status, 429);
    assert.equal(
      (blocked.data as { code?: string }).code,
      'AUTH_LOGIN_RATE_LIMITED',
    );
    assert.ok(blocked.headers.get('retry-after'));
  });
});

async function loginAsPlatformAdmin() {
  const response = await requestJson('POST', '/auth/login', {
    body: {
      email: adminEmail,
      password: adminPassword,
      ...baseClientPayload,
    },
  });

  assert.equal(response.status, 200);
  return (response.data as { accessToken: string }).accessToken;
}

async function requestJson(
  method: string,
  path: string,
  options?: {
    token?: string;
    body?: Record<string, unknown>;
  },
): Promise<JsonResponse> {
  const response = await fetch(`${apiBaseUrl}${path}`, {
    method,
    headers: {
      ...(options?.body == null
          ? {}
          : {
              'Content-Type': 'application/json',
            }),
      ...(options?.token == null
          ? {}
          : {
              Authorization: `Bearer ${options.token}`,
            }),
    },
    body:
      options?.body == null ? undefined : JSON.stringify(options.body),
  });

  const rawBody = await response.text();
  let data: unknown = null;
  if (rawBody.trim().length > 0) {
    data = JSON.parse(rawBody);
  }

  return {
    status: response.status,
    headers: response.headers,
    data,
  };
}

async function seedFixtures() {
  const adminPasswordHash = await bcrypt.hash(adminPassword, 10);
  const rateLimitPasswordHash = await bcrypt.hash(rateLimitPassword, 10);

  const companies = await Promise.all(
    Array.from({ length: 15 }, async (_value, index) => {
      const company = await prisma.company.create({
        data: {
          name: `${companiesPrefix} ${index + 1}`,
          legalName: `${companiesPrefix} ${index + 1} LTDA`,
          slug: `${runId}-company-${index + 1}`,
        },
      });

      await prisma.license.create({
        data: {
          companyId: company.id,
          plan: index % 2 === 0 ? 'pro' : 'starter',
          status: index % 3 === 0 ? 'TRIAL' : 'ACTIVE',
          startsAt: new Date(),
          expiresAt: new Date(Date.now() + 15 * 24 * 60 * 60 * 1000),
          maxDevices: index % 4 === 0 ? 2 : 5,
          syncEnabled: index % 2 === 0,
        },
      });

      return company;
    }),
  );

  primaryCompanyId = companies[0]!.id;

  const adminUser = await prisma.user.create({
    data: {
      email: adminEmail,
      name: 'Tatuzin Platform Admin',
      passwordHash: adminPasswordHash,
      isPlatformAdmin: true,
    },
  });

  await prisma.membership.create({
    data: {
      userId: adminUser.id,
      companyId: primaryCompanyId,
      role: 'OWNER',
      isDefault: true,
    },
  });

  const rateLimitUser = await prisma.user.create({
    data: {
      email: rateLimitEmail,
      name: 'Tatuzin Rate Limit User',
      passwordHash: rateLimitPasswordHash,
      isPlatformAdmin: false,
    },
  });

  await prisma.membership.create({
    data: {
      userId: rateLimitUser.id,
      companyId: primaryCompanyId,
      role: 'OPERATOR',
      isDefault: true,
    },
  });
}

async function cleanupFixtures() {
  const users = await prisma.user.findMany({
    where: {
      email: {
        in: [adminEmail, rateLimitEmail],
      },
    },
    select: {
      id: true,
    },
  });

  await prisma.adminAuditLog.deleteMany({
    where: {
      actorUserId: {
        in: users.map((user) => user.id),
      },
    },
  });

  await prisma.user.deleteMany({
    where: {
      email: {
        in: [adminEmail, rateLimitEmail],
      },
    },
  });

  await prisma.company.deleteMany({
    where: {
      slug: {
        startsWith: `${runId}-company-`,
      },
    },
  });
}
