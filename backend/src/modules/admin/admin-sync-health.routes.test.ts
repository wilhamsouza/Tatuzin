import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';
import type { AddressInfo } from 'node:net';

import type { Server } from 'http';
import jwt from 'jsonwebtoken';

import { createApp } from '../../app';
import { env } from '../../config/env';
import { prisma } from '../../database/prisma';

const runId = `admin-sync-health-${Date.now()}`;

let server: Server;
let apiBaseUrl = '';

describe('admin sync health routes', () => {
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

  it('keeps company sync health protected by platform admin auth', async () => {
    const fixture = await createFixture();

    const unauthenticated = await requestJson(
      'GET',
      `/admin/companies/${fixture.companyId}/sync/health`,
    );
    assert.equal(unauthenticated.status, 401);

    const forbidden = await requestJson(
      'GET',
      `/admin/companies/${fixture.companyId}/sync/health`,
      { token: fixture.operatorToken },
    );
    assert.equal(forbidden.status, 403);
    assert.equal(
      (forbidden.data as { code?: string }).code,
      'PLATFORM_ADMIN_REQUIRED',
    );
  });

  it('returns a company-level sync health snapshot', async () => {
    const fixture = await createFixture();

    const response = await requestJson(
      'GET',
      `/admin/companies/${fixture.companyId}/sync/health`,
      { token: fixture.adminToken },
    );

    assert.equal(response.status, 200);
    const payload = response.data as {
      companyId: string;
      currentServerVersion: string;
      syncEnabled: boolean;
      devices: {
        active: number;
        blocked: number;
        revoked: number;
        total: number;
      };
      events: {
        accepted: number;
        rejected: number;
        conflict: number;
        failed: number;
      };
      openConflictsCount: number;
      lastMaterializedAt: string | null;
      deviceSyncStates: Array<{
        deviceId: string;
        lastSyncAt: string | null;
      }>;
      lastIncident: { code: string; severity: string } | null;
      license: { status: string; syncEnabled: boolean } | null;
    };

    assert.equal(payload.companyId, fixture.companyId);
    assert.equal(payload.currentServerVersion, '7');
    assert.equal(payload.syncEnabled, true);
    assert.equal(payload.license?.status, 'active');
    assert.equal(payload.license?.syncEnabled, true);
    assert.equal(payload.devices.active, 1);
    assert.equal(payload.devices.blocked, 1);
    assert.equal(payload.devices.revoked, 1);
    assert.equal(payload.devices.total, 3);
    assert.equal(payload.events.accepted, 1);
    assert.equal(payload.events.rejected, 1);
    assert.equal(payload.events.conflict, 1);
    assert.equal(payload.events.failed, 1);
    assert.equal(payload.openConflictsCount, 1);
    assert.notEqual(payload.lastMaterializedAt, null);
    assert.equal(payload.lastIncident?.code, 'SYNC_MATERIALIZATION_FAILED');
    assert.equal(payload.lastIncident?.severity, 'error');
    assert.ok(
      payload.deviceSyncStates.some(
        (state) => state.deviceId === fixture.activeDeviceId && state.lastSyncAt,
      ),
    );
  });

  it('lists filtered events, conflicts, incidents and devices', async () => {
    const fixture = await createFixture();

    const events = await requestJson(
      'GET',
      `/admin/companies/${fixture.companyId}/sync/events?status=failed&entity=payment&feature=pdv&page=1&limit=5`,
      { token: fixture.adminToken },
    );
    assert.equal(events.status, 200);
    const eventsPayload = events.data as {
      items: Array<{
        eventId: string;
        status: string;
        entity: string;
        errorCode: string | null;
        payloadSummary: string | null;
        serverVersion: string | null;
      }>;
      pagination: { total: number; pageSize: number };
      filters: { status: string | null; entity: string | null };
    };
    assert.equal(eventsPayload.pagination.total, 1);
    assert.equal(eventsPayload.pagination.pageSize, 5);
    assert.equal(eventsPayload.filters.status, 'failed');
    assert.equal(eventsPayload.filters.entity, 'payment');
    assert.equal(eventsPayload.items[0]?.eventId, `${runId}-event-failed`);
    assert.equal(eventsPayload.items[0]?.status, 'failed');
    assert.equal(eventsPayload.items[0]?.entity, 'payment');
    assert.equal(
      eventsPayload.items[0]?.errorCode,
      'SYNC_MATERIALIZATION_FAILED',
    );
    assert.ok(eventsPayload.items[0]?.payloadSummary?.includes('amountCents'));

    const conflicts = await requestJson(
      'GET',
      `/admin/companies/${fixture.companyId}/sync/conflicts?status=open&page=1&limit=5`,
      { token: fixture.adminToken },
    );
    assert.equal(conflicts.status, 200);
    const conflictsPayload = conflicts.data as {
      items: Array<{
        status: string;
        event: { eventId: string; serverVersion: string | null };
      }>;
      pagination: { total: number };
      filters: { status: string | null };
    };
    assert.equal(conflictsPayload.pagination.total, 1);
    assert.equal(conflictsPayload.filters.status, 'open');
    assert.equal(conflictsPayload.items[0]?.status, 'open');
    assert.equal(
      conflictsPayload.items[0]?.event.eventId,
      `${runId}-event-conflict`,
    );
    assert.equal(conflictsPayload.items[0]?.event.serverVersion, '3');

    const incidents = await requestJson(
      'GET',
      `/admin/companies/${fixture.companyId}/sync/incidents?severity=error&page=1&limit=5`,
      { token: fixture.adminToken },
    );
    assert.equal(incidents.status, 200);
    const incidentsPayload = incidents.data as {
      items: Array<{ code: string; severity: string; event: { eventId: string } }>;
      pagination: { total: number };
      filters: { severity: string | null };
    };
    assert.equal(incidentsPayload.pagination.total, 1);
    assert.equal(incidentsPayload.filters.severity, 'error');
    assert.equal(
      incidentsPayload.items[0]?.code,
      'SYNC_MATERIALIZATION_FAILED',
    );
    assert.equal(incidentsPayload.items[0]?.event.eventId, `${runId}-event-failed`);

    const devices = await requestJson(
      'GET',
      `/admin/companies/${fixture.companyId}/devices`,
      { token: fixture.adminToken },
    );
    assert.equal(devices.status, 200);
    const devicesPayload = devices.data as {
      items: Array<{
        deviceLabel: string | null;
        platform: string | null;
        appVersion: string | null;
        status: string;
        userId: string;
        userName: string;
        clientInstanceId: string;
      }>;
      count: number;
    };
    assert.equal(devicesPayload.count, 3);
    assert.ok(
      devicesPayload.items.some(
        (device) =>
          device.status === 'active' &&
          device.deviceLabel === 'Active PDV' &&
          device.platform === 'android' &&
          device.appVersion === '2.0.0' &&
          device.userId === fixture.operatorUserId &&
          device.userName === 'Sync Operator' &&
          device.clientInstanceId === `${runId}-active-device`,
      ),
    );
  });
});

async function createFixture() {
  const company = await prisma.company.create({
    data: {
      name: 'Admin Sync Health Company',
      legalName: 'Admin Sync Health Company LTDA',
      slug: `${runId}-company-${Date.now()}-${Math.random()
        .toString(16)
        .slice(2)}`,
    },
  });
  const adminUser = await prisma.user.create({
    data: {
      email: `${runId}-admin-${Date.now()}@tatuzin.test`,
      name: 'Sync Platform Admin',
      passwordHash: 'not-used',
      isPlatformAdmin: true,
    },
  });
  const operatorUser = await prisma.user.create({
    data: {
      email: `${runId}-operator-${Date.now()}@tatuzin.test`,
      name: 'Sync Operator',
      passwordHash: 'not-used',
      isPlatformAdmin: false,
    },
  });
  const adminMembership = await prisma.membership.create({
    data: {
      companyId: company.id,
      userId: adminUser.id,
      role: 'OWNER',
      isDefault: true,
    },
  });
  const operatorMembership = await prisma.membership.create({
    data: {
      companyId: company.id,
      userId: operatorUser.id,
      role: 'OPERATOR',
      isDefault: true,
    },
  });
  await prisma.license.create({
    data: {
      companyId: company.id,
      plan: 'pro',
      status: 'ACTIVE',
      startsAt: new Date(),
      maxDevices: 5,
      syncEnabled: true,
    },
  });
  await prisma.companySyncState.create({
    data: {
      companyId: company.id,
      currentVersion: 7n,
      serverFirstSnapshotVersion: 2n,
      updatedAt: new Date(),
    },
  });

  const activeDevice = await prisma.companyDevice.create({
    data: {
      companyId: company.id,
      userId: operatorUser.id,
      clientInstanceId: `${runId}-active-device`,
      deviceLabel: 'Active PDV',
      platform: 'android',
      appVersion: '2.0.0',
      status: 'ACTIVE',
      approvedAt: new Date(),
      approvedByUserId: adminUser.id,
      lastSeenAt: new Date(),
    },
  });
  await prisma.companyDevice.create({
    data: {
      companyId: company.id,
      userId: operatorUser.id,
      clientInstanceId: `${runId}-blocked-device`,
      deviceLabel: 'Blocked PDV',
      platform: 'android',
      appVersion: '2.0.0',
      status: 'BLOCKED',
      revokedReason: 'device_limit_reached',
      lastSeenAt: new Date(),
    },
  });
  await prisma.companyDevice.create({
    data: {
      companyId: company.id,
      userId: operatorUser.id,
      clientInstanceId: `${runId}-revoked-device`,
      deviceLabel: 'Revoked PDV',
      platform: 'android',
      appVersion: '2.0.0',
      status: 'REVOKED',
      revokedAt: new Date(),
      revokedReason: 'test',
      lastSeenAt: new Date(),
    },
  });

  await prisma.syncCheckpoint.create({
    data: {
      companyId: company.id,
      deviceId: activeDevice.id,
      feature: 'pdv',
      lastServerVersion: 7n,
      lastPushedAt: new Date(),
    },
  });

  await prisma.syncEvent.create({
    data: {
      companyId: company.id,
      deviceId: activeDevice.id,
      userId: operatorUser.id,
      eventId: `${runId}-event-accepted`,
      feature: 'pdv',
      entity: 'sale',
      operation: 'create',
      entityLocalId: `${runId}-sale-local`,
      occurredAt: new Date(),
      payload: { totalCents: 1200 },
      status: 'ACCEPTED',
      serverVersion: 1n,
      materializedAt: new Date(),
    },
  });
  await prisma.syncEvent.create({
    data: {
      companyId: company.id,
      deviceId: activeDevice.id,
      userId: operatorUser.id,
      eventId: `${runId}-event-rejected`,
      feature: 'catalog',
      entity: 'product',
      operation: 'create',
      entityLocalId: `${runId}-product-local`,
      occurredAt: new Date(),
      payload: { name: 'Produto' },
      status: 'REJECTED',
      rejectionCode: 'ENTITY_NOT_LOCAL_FIRST',
      rejectionMessage: 'Entidade server-first.',
    },
  });
  const conflictEvent = await prisma.syncEvent.create({
    data: {
      companyId: company.id,
      deviceId: activeDevice.id,
      userId: operatorUser.id,
      eventId: `${runId}-event-conflict`,
      feature: 'pdv',
      entity: 'sale',
      operation: 'update',
      entityLocalId: `${runId}-sale-conflict`,
      occurredAt: new Date(),
      payload: { status: 'finalized' },
      status: 'CONFLICT',
      serverVersion: 3n,
    },
  });
  await prisma.syncConflict.create({
    data: {
      companyId: company.id,
      deviceId: activeDevice.id,
      userId: operatorUser.id,
      syncEventId: conflictEvent.id,
      entity: 'sale',
      entityLocalId: `${runId}-sale-conflict`,
      code: 'SALE_IMMUTABLE',
      message: 'Venda finalizada nao pode ser alterada.',
      payload: { status: 'finalized' },
    },
  });
  const failedEvent = await prisma.syncEvent.create({
    data: {
      companyId: company.id,
      deviceId: activeDevice.id,
      userId: operatorUser.id,
      eventId: `${runId}-event-failed`,
      feature: 'pdv',
      entity: 'payment',
      operation: 'create',
      entityLocalId: `${runId}-payment-failed`,
      occurredAt: new Date(),
      payload: { amountCents: 3_000_000_000 },
      status: 'FAILED',
      rejectionCode: 'SYNC_MATERIALIZATION_FAILED',
      rejectionMessage: 'Falha inesperada.',
    },
  });
  await prisma.syncIncident.create({
    data: {
      companyId: company.id,
      deviceId: activeDevice.id,
      userId: operatorUser.id,
      syncEventId: failedEvent.id,
      code: 'SYNC_MATERIALIZATION_FAILED',
      message: 'Falha inesperada.',
      severity: 'error',
      details: { amountCents: 3_000_000_000 },
    },
  });

  return {
    companyId: company.id,
    adminToken: signToken({
      userId: adminUser.id,
      companyId: company.id,
      membershipId: adminMembership.id,
      email: adminUser.email,
      isPlatformAdmin: true,
    }),
    operatorToken: signToken({
      userId: operatorUser.id,
      companyId: company.id,
      membershipId: operatorMembership.id,
      email: operatorUser.email,
      isPlatformAdmin: false,
    }),
    activeDeviceId: activeDevice.id,
    operatorUserId: operatorUser.id,
  };
}

function signToken(input: {
  userId: string;
  companyId: string;
  membershipId: string;
  email: string;
  isPlatformAdmin: boolean;
}) {
  return jwt.sign(
    {
      sub: input.userId,
      companyId: input.companyId,
      membershipId: input.membershipId,
      membershipRole: 'OWNER',
      email: input.email,
      isPlatformAdmin: input.isPlatformAdmin,
    },
    env.JWT_SECRET,
    { expiresIn: '15m' },
  );
}

async function requestJson(
  method: string,
  path: string,
  options?: { token?: string },
) {
  const response = await fetch(`${apiBaseUrl}${path}`, {
    method,
    headers: {
      ...(options?.token == null
        ? {}
        : { Authorization: `Bearer ${options.token}` }),
    },
  });
  const rawBody = await response.text();
  return {
    status: response.status,
    data: rawBody.trim().length === 0 ? null : JSON.parse(rawBody),
  };
}

async function cleanupFixtures() {
  await prisma.company.deleteMany({
    where: {
      slug: {
        startsWith: `${runId}-`,
      },
    },
  });
  await prisma.user.deleteMany({
    where: {
      email: {
        startsWith: `${runId}-`,
      },
    },
  });
}
