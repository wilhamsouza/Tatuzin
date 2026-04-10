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
let observedCompanySlug = '';
let adminUserId = '';
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
    const unauthenticated = await requestJson('GET', '/admin/companies');
    assert.equal(unauthenticated.status, 401);
    assert.equal(
      (unauthenticated.data as { code?: string }).code,
      'AUTH_REQUIRED',
    );

    const operatorToken = await loginAsUser(rateLimitEmail, rateLimitPassword);
    const forbidden = await requestJson('GET', '/admin/companies', {
      token: operatorToken,
    });
    assert.equal(forbidden.status, 403);
    assert.equal(
      (forbidden.data as { code?: string }).code,
      'PLATFORM_ADMIN_REQUIRED',
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

  it('keeps companies contract stable for pagination, filters, ordering and shape', async () => {
    const token = await loginAsPlatformAdmin();

    const paginated = await requestJson(
      'GET',
      `/admin/companies?search=${encodeURIComponent(
        companiesPrefix,
      )}&page=2&pageSize=5&sortBy=name&sortDirection=asc`,
      {
        token,
      },
    );
    assert.equal(paginated.status, 200);
    const paginatedPayload = paginated.data as {
      items: Array<{
        id: string;
        name: string;
        slug: string;
        license: { status: string; syncEnabled: boolean } | null;
        counts: { products: number; categories: number };
      }>;
      pagination: {
        page: number;
        pageSize: number;
        total: number;
        count: number;
        hasPrevious: boolean;
        hasNext: boolean;
      };
      filters: {
        search: string | null;
      };
      sort: { by: string; direction: string };
    };
    assert.equal(paginatedPayload.pagination.page, 2);
    assert.equal(paginatedPayload.pagination.pageSize, 5);
    assert.equal(paginatedPayload.pagination.total, 15);
    assert.equal(paginatedPayload.pagination.count, 5);
    assert.equal(paginatedPayload.pagination.hasPrevious, true);
    assert.equal(paginatedPayload.pagination.hasNext, true);
    assert.equal(paginatedPayload.filters.search, companiesPrefix);
    assert.equal(paginatedPayload.sort.by, 'name');
    assert.equal(paginatedPayload.sort.direction, 'asc');
    assert.equal(paginatedPayload.items.length, 5);
    assert.ok(paginatedPayload.items[0]?.id);
    assert.ok(paginatedPayload.items[0]?.name);
    assert.equal(typeof paginatedPayload.items[0]?.counts.categories, 'number');
    assert.equal(typeof paginatedPayload.items[0]?.counts.products, 'number');

    const filtered = await requestJson(
      'GET',
      `/admin/companies?search=${encodeURIComponent(
        observedCompanySlug,
      )}&licenseStatus=active&syncEnabled=true&page=1&pageSize=5&sortBy=name&sortDirection=asc`,
      {
        token,
      },
    );
    assert.equal(filtered.status, 200);
    const filteredPayload = filtered.data as {
      items: Array<{
        name: string;
        license: { status: string; syncEnabled: boolean } | null;
      }>;
      pagination: {
        total: number;
        page: number;
        pageSize: number;
        count: number;
        hasPrevious: boolean;
        hasNext: boolean;
      };
      filters: {
        search: string | null;
        licenseStatus: string | null;
        syncEnabled: boolean | null;
      };
      sort: { by: string; direction: string };
    };
    assert.equal(filteredPayload.pagination.total, 1);
    assert.equal(filteredPayload.pagination.page, 1);
    assert.equal(filteredPayload.pagination.pageSize, 5);
    assert.equal(filteredPayload.pagination.count, 1);
    assert.equal(filteredPayload.pagination.hasPrevious, false);
    assert.equal(filteredPayload.pagination.hasNext, false);
    assert.equal(filteredPayload.filters.licenseStatus, 'active');
    assert.equal(filteredPayload.filters.syncEnabled, true);
    assert.equal(filteredPayload.sort.by, 'name');
    assert.equal(filteredPayload.sort.direction, 'asc');
    assert.equal(filteredPayload.items[0]?.name, `${companiesPrefix} 3`);
    assert.ok(
      filteredPayload.items.every(
        (item) =>
          item.license?.status === 'active' && item.license?.syncEnabled === true,
      ),
    );
  });

  it('keeps licenses contract stable for pagination, filters, ordering and shape', async () => {
    const token = await loginAsPlatformAdmin();

    const paginated = await requestJson(
      'GET',
      `/admin/licenses?search=${encodeURIComponent(
        companiesPrefix,
      )}&page=2&pageSize=4&sortBy=companyName&sortDirection=asc`,
      {
        token,
      },
    );
    assert.equal(paginated.status, 200);
    const paginatedPayload = paginated.data as {
      items: Array<{
        companyId: string;
        companyName: string;
        companySlug: string;
        status: string;
        syncEnabled: boolean;
      }>;
      pagination: {
        page: number;
        pageSize: number;
        total: number;
        count: number;
        hasNext: boolean;
        hasPrevious: boolean;
      };
      filters: {
        search: string | null;
      };
      sort: { by: string; direction: string };
    };
    assert.equal(paginatedPayload.pagination.page, 2);
    assert.equal(paginatedPayload.pagination.pageSize, 4);
    assert.equal(paginatedPayload.pagination.total, 15);
    assert.equal(paginatedPayload.pagination.count, 4);
    assert.equal(paginatedPayload.pagination.hasPrevious, true);
    assert.equal(paginatedPayload.pagination.hasNext, true);
    assert.equal(paginatedPayload.filters.search, companiesPrefix);
    assert.equal(paginatedPayload.sort.by, 'companyName');
    assert.equal(paginatedPayload.sort.direction, 'asc');
    assert.ok(paginatedPayload.items[0]?.companyId);
    assert.ok(paginatedPayload.items[0]?.companyName);
    assert.ok(paginatedPayload.items[0]?.status);

    const filtered = await requestJson(
      'GET',
      `/admin/licenses?search=${encodeURIComponent(
        observedCompanySlug,
      )}&status=active&syncEnabled=true&page=1&pageSize=3&sortBy=companyName&sortDirection=asc`,
      {
        token,
      },
    );
    assert.equal(filtered.status, 200);
    const filteredPayload = filtered.data as {
      items: Array<{
        companyName: string;
        status: string;
        syncEnabled: boolean;
      }>;
      pagination: {
        total: number;
        page: number;
        pageSize: number;
        count: number;
        hasPrevious: boolean;
        hasNext: boolean;
      };
      filters: {
        status: string | null;
        syncEnabled: boolean | null;
      };
      sort: { by: string; direction: string };
    };
    assert.equal(filteredPayload.pagination.total, 1);
    assert.equal(filteredPayload.pagination.page, 1);
    assert.equal(filteredPayload.pagination.pageSize, 3);
    assert.equal(filteredPayload.pagination.count, 1);
    assert.equal(filteredPayload.pagination.hasPrevious, false);
    assert.equal(filteredPayload.pagination.hasNext, false);
    assert.equal(filteredPayload.filters.status, 'active');
    assert.equal(filteredPayload.filters.syncEnabled, true);
    assert.equal(filteredPayload.sort.by, 'companyName');
    assert.equal(filteredPayload.sort.direction, 'asc');
    assert.equal(filteredPayload.items[0]?.companyName, `${companiesPrefix} 3`);
    assert.ok(
      filteredPayload.items.every(
        (item) => item.status === 'active' && item.syncEnabled === true,
      ),
    );
  });

  it('keeps audit summary contract stable for filters, pagination and response shape', async () => {
    const token = await loginAsPlatformAdmin();

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
      `/admin/audit/summary?page=1&pageSize=5&companyId=${encodeURIComponent(primaryCompanyId)}&actorUserId=${encodeURIComponent(adminUserId)}&action=${encodeURIComponent('license.updated')}`,
      {
        token,
      },
    );
    assert.equal(audit.status, 200);
    const auditPayload = audit.data as {
      items: Array<{
        source: string;
        action: string;
        actorUser: { id: string; email: string } | null;
        targetCompany: { id: string; slug: string } | null;
      }>;
      overview: {
        totalEvents: number;
        countsByAction: Array<{ action: string; count: number }>;
      };
      sort: null;
      pagination: {
        page: number;
        pageSize: number;
        count: number;
        hasPrevious: boolean;
      };
      filters: {
        action: string | null;
        actorUserId: string | null;
        companyId: string | null;
      };
    };
    assert.equal(auditPayload.pagination.page, 1);
    assert.equal(auditPayload.pagination.pageSize, 5);
    assert.equal(auditPayload.pagination.hasPrevious, false);
    assert.equal(auditPayload.sort, null);
    assert.ok(auditPayload.overview.totalEvents >= 1);
    assert.ok(auditPayload.items.length >= 1);
    assert.equal(auditPayload.filters.action, 'license.updated');
    assert.equal(auditPayload.filters.actorUserId, adminUserId);
    assert.equal(auditPayload.filters.companyId, primaryCompanyId);
    assert.ok(
      auditPayload.overview.countsByAction.some(
        (entry) => entry.action === 'license.updated' && entry.count >= 1,
      ),
    );
    assert.ok(
      auditPayload.items.every(
        (event) =>
          event.action === 'license.updated' &&
          event.source === 'admin' &&
          event.actorUser?.id === adminUserId &&
          event.targetCompany?.id === primaryCompanyId,
      ),
    );
    assert.ok(auditPayload.pagination.count <= 5);
  });

  it('keeps sync summary contract stable for pagination, filters, ordering and shape', async () => {
    const token = await loginAsPlatformAdmin();

    const paginated = await requestJson(
      'GET',
      `/admin/sync/summary?search=${encodeURIComponent(
        companiesPrefix,
      )}&page=1&pageSize=3&sortBy=remoteRecordCount&sortDirection=desc`,
      {
        token,
      },
    );
    assert.equal(paginated.status, 200);
    const paginatedPayload = paginated.data as {
      items: Array<{
        companySlug: string;
        licenseStatus: string | null;
        syncEnabled: boolean;
        remoteRecordCount: number;
        entityCounts: { categories: number; products: number };
      }>;
      overview: {
        totalCompanies: number;
        syncEnabledCompanies: number;
        licenseStatusCounts: Record<string, number>;
      };
      pagination: {
        total: number;
        page: number;
        pageSize: number;
        count: number;
        hasNext: boolean;
      };
      filters: {
        search: string | null;
        licenseStatus: string | null;
        syncEnabled: boolean | null;
      };
      sort: { by: string; direction: string };
    };
    const companies = paginatedPayload.items;
    assert.equal(paginatedPayload.overview.totalCompanies, 15);
    assert.equal(typeof paginatedPayload.overview.syncEnabledCompanies, 'number');
    assert.ok(paginatedPayload.overview.syncEnabledCompanies >= 0);
    assert.ok(
      paginatedPayload.overview.syncEnabledCompanies <=
        paginatedPayload.overview.totalCompanies,
    );
    assert.equal(paginatedPayload.overview.licenseStatusCounts.active, 10);
    assert.equal(paginatedPayload.pagination.total, 15);
    assert.equal(paginatedPayload.pagination.page, 1);
    assert.equal(paginatedPayload.pagination.pageSize, 3);
    assert.equal(paginatedPayload.pagination.count, 3);
    assert.equal(paginatedPayload.pagination.hasNext, true);
    assert.equal(paginatedPayload.filters.search, companiesPrefix);
    assert.equal(paginatedPayload.sort.by, 'remoteRecordCount');
    assert.equal(paginatedPayload.sort.direction, 'desc');
    assert.equal(companies.length, 3);
    assert.equal(companies[0]?.companySlug, observedCompanySlug);
    assert.ok(companies[0]?.remoteRecordCount >= (companies[1]?.remoteRecordCount ?? 0));
    assert.equal(typeof companies[0]?.entityCounts.categories, 'number');
    assert.equal(typeof companies[0]?.entityCounts.products, 'number');

    const filtered = await requestJson(
      'GET',
      `/admin/sync/summary?search=${encodeURIComponent(
        observedCompanySlug,
      )}&licenseStatus=active&syncEnabled=true&page=1&pageSize=5&sortBy=remoteRecordCount&sortDirection=desc`,
      {
        token,
      },
    );
    assert.equal(filtered.status, 200);
    const filteredPayload = filtered.data as {
      items: Array<{
        companySlug: string;
        licenseStatus: string | null;
        syncEnabled: boolean;
      }>;
      overview: {
        totalCompanies: number;
      };
      pagination: {
        total: number;
        count: number;
        hasNext: boolean;
      };
      filters: {
        search: string | null;
        licenseStatus: string | null;
        syncEnabled: boolean | null;
      };
      sort: { by: string; direction: string };
    };
    assert.equal(filteredPayload.overview.totalCompanies, 1);
    assert.equal(filteredPayload.pagination.total, 1);
    assert.equal(filteredPayload.pagination.count, 1);
    assert.equal(filteredPayload.pagination.hasNext, false);
    assert.equal(filteredPayload.filters.search, observedCompanySlug);
    assert.equal(filteredPayload.filters.licenseStatus, 'active');
    assert.equal(filteredPayload.filters.syncEnabled, true);
    assert.equal(filteredPayload.sort.by, 'remoteRecordCount');
    assert.equal(filteredPayload.sort.direction, 'desc');
    assert.ok(
      filteredPayload.items.every(
        (company) =>
          company.licenseStatus === 'active' && company.syncEnabled === true,
      ),
    );
    assert.equal(filteredPayload.items[0]?.companySlug, observedCompanySlug);
  });

  it('exposes an honest operational sync summary', async () => {
    const token = await loginAsPlatformAdmin();

    const response = await requestJson(
      'GET',
      `/admin/sync/operational-summary?search=${encodeURIComponent(
        observedCompanySlug,
      )}&page=1&pageSize=5&sortBy=companyName&sortDirection=asc`,
      {
        token,
      },
    );

    assert.equal(response.status, 200);
    const payload = response.data as {
      items: Array<{
        companySlug: string;
        status: string;
        statusSource: string;
        statusReason: string;
        activeMobileSessionsCount: number;
        observedRemoteRecordCount: number;
        telemetryAvailability: {
          hasLocalQueueSignals: boolean;
          hasConflictSignals: boolean;
          hasRetrySignals: boolean;
        };
        observedFeatures: Array<{
          featureKey: string;
          remoteRecordCount: number;
          observationKind: string;
        }>;
      }>;
      overview: {
        totalCompanies: number;
      };
      capabilities: {
        observedSignals: string[];
        unavailableSignals: string[];
        telemetryGaps: Array<{ featureKey: string }>;
        notes: string[];
      };
      pagination: {
        page: number;
        pageSize: number;
        total: number;
        count: number;
      };
      filters: {
        search: string | null;
        licenseStatus: string | null;
        syncEnabled: boolean | null;
      };
      sort: { by: string; direction: string };
    };

    assert.equal(payload.overview.totalCompanies, 1);
    assert.equal(payload.pagination.page, 1);
    assert.equal(payload.pagination.pageSize, 5);
    assert.equal(payload.pagination.total, 1);
    assert.equal(payload.pagination.count, 1);
    assert.equal(payload.filters.search, observedCompanySlug);
    assert.equal(payload.filters.licenseStatus, null);
    assert.equal(payload.filters.syncEnabled, null);
    assert.equal(payload.sort.by, 'companyName');
    assert.equal(payload.sort.direction, 'asc');
    assert.ok(payload.capabilities.observedSignals.includes('device_sessions'));
    assert.ok(payload.capabilities.unavailableSignals.includes('local_queue'));
    assert.ok(
      payload.capabilities.telemetryGaps.some(
        (entry) => entry.featureKey === 'sale_cancellations',
      ),
    );
    assert.ok(payload.capabilities.notes.length >= 2);
    assert.equal(payload.items.length, 1);

    const company = payload.items[0]!;
    assert.equal(company.companySlug, observedCompanySlug);
    assert.equal(company.status, 'healthy');
    assert.equal(company.statusSource, 'limited_inference');
    assert.ok(company.statusReason.length > 20);
    assert.equal(company.activeMobileSessionsCount, 1);
    assert.ok(company.observedRemoteRecordCount >= 2);
    assert.equal(company.telemetryAvailability.hasLocalQueueSignals, false);
    assert.equal(company.telemetryAvailability.hasConflictSignals, false);
    assert.equal(company.telemetryAvailability.hasRetrySignals, false);
    assert.ok(
      company.observedFeatures.some(
        (feature) =>
          feature.featureKey === 'categories' &&
          feature.remoteRecordCount >= 1 &&
          feature.observationKind === 'remote_mirror',
      ),
    );
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
  return loginAsUser(adminEmail, adminPassword);
}

async function loginAsUser(email: string, password: string) {
  const response = await requestJson('POST', '/auth/login', {
    body: {
      email,
      password,
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
  observedCompanySlug = companies[2]!.slug;

  const adminUser = await prisma.user.create({
    data: {
      email: adminEmail,
      name: 'Tatuzin Platform Admin',
      passwordHash: adminPasswordHash,
      isPlatformAdmin: true,
    },
  });
  adminUserId = adminUser.id;

  await prisma.membership.create({
    data: {
      userId: adminUser.id,
      companyId: primaryCompanyId,
      role: 'OWNER',
      isDefault: true,
    },
  });

  const observedMembership = await prisma.membership.create({
    data: {
      userId: adminUser.id,
      companyId: companies[2]!.id,
      role: 'ADMIN',
      isDefault: false,
    },
  });

  await prisma.deviceSession.create({
    data: {
      userId: adminUser.id,
      companyId: companies[2]!.id,
      membershipId: observedMembership.id,
      clientType: 'MOBILE_APP',
      clientInstanceId: `${runId}-mobile-observed`,
      deviceLabel: 'Observed Mobile Device',
      platform: 'android',
      appVersion: 'phase3-mobile',
      refreshTokenHash: `${runId}-observed-mobile-refresh-hash`,
      refreshTokenExpiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000),
      lastSeenAt: new Date(),
    },
  });

  await prisma.category.create({
    data: {
      companyId: companies[2]!.id,
      localUuid: `${runId}-category-observed`,
      name: 'Categorias observadas',
    },
  });

  await prisma.product.create({
    data: {
      companyId: companies[2]!.id,
      localUuid: `${runId}-product-observed`,
      name: 'Produto observado',
      salePriceCents: 1590,
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

  await prisma.sessionAuditLog.deleteMany({
    where: {
      OR: [
        {
          actorUserId: {
            in: users.map((user) => user.id),
          },
        },
        {
          subjectUserId: {
            in: users.map((user) => user.id),
          },
        },
      ],
    },
  });

  await prisma.deviceSession.deleteMany({
    where: {
      userId: {
        in: users.map((user) => user.id),
      },
    },
  });

  await prisma.adminAuditLog.deleteMany({
    where: {
      actorUserId: {
        in: users.map((user) => user.id),
      },
    },
  });

  await prisma.membership.deleteMany({
    where: {
      userId: {
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
