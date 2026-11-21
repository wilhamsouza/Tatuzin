import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';
import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';
import { randomUUID } from 'node:crypto';
import jwt from 'jsonwebtoken';
import { prisma } from '../../database/prisma';
import { env } from '../../config/env';
import { createApp } from '../../app';
import { assertSafeIntegrationTestDatabaseUrl } from '../../shared/testing/integration-prisma';

let server: Server;
let base = '';
const companies: string[] = [];
const users: string[] = [];
const runId = `support-cases-${randomUUID()}`;

type CaseDto = { id: string; companyId: string; companyName: string; status: string; subject: string; priority: string; revision: number; assignee: { id: string; name: string } | null; resolution: string | null; events: Array<{ id: string; type: string; body: string; author: { id: string }; createdAt: string }> };

describe('admin support cases HTTP', () => {
  before(async () => {
    // Never fall back to a repository environment or the application database.
    assertSafeIntegrationTestDatabaseUrl(process.env.DATABASE_URL ?? '');
    await prisma.$connect();
    server = createApp().listen(0);
    base = `http://127.0.0.1:${(server.address() as AddressInfo).port}/api/admin/support/cases`;
  });
  beforeEach(cleanup);
  after(async () => {
    await cleanup();
    if (server) await new Promise<void>(resolve => server.close(() => resolve()));
    await prisma.$disconnect();
  });

  it('requires authentication, platform-admin identity and an explicit support permission', async () => {
    const f = await fixture();
    assert.equal((await request('GET', '')).status, 401);
    assert.equal((await request('GET', '', f.operator.token)).status, 403);
    assert.equal((await request('GET', '', f.noAccess.token)).status, 403);
    assert.equal((await request('POST', '', f.reader.token, body(f.company.id))).status, 403);
    assert.equal((await request('POST', '', f.noAccess.token, body(f.company.id))).status, 403);
    assert.equal(await prisma.adminSupportCase.count({ where: { companyId: f.company.id } }), 0);
  });

  it('creates, assigns, follows up, resolves and reopens with an immutable audited timeline', async () => {
    const f = await fixture();
    const created = await request('POST', '', f.manager.token, { ...body(f.company.id), assigneeId: f.manager.id });
    assert.equal(created.status, 201);
    let row = (created.data as { item: CaseDto }).item;
    assert.equal(row.revision, 0);
    assert.equal(row.assignee?.id, f.manager.id);
    assert.equal(row.events.length, 1);
    assert.equal(row.events[0]!.type, 'CREATED');
    const updated = await request('PATCH', `/${row.id}`, f.manager.token, { expectedRevision: 0, status: 'IN_PROGRESS', priority: 'HIGH' });
    assert.equal(updated.status, 200);
    row = (updated.data as { item: CaseDto }).item;
    const note = await request('POST', `/${row.id}/notes`, f.manager.token, { expectedRevision: 1, body: 'Reproduzido em dispositivo de testes.' });
    assert.equal(note.status, 200);
    row = (note.data as { item: CaseDto }).item;
    assert.equal(row.revision, 2);
    assert.equal(row.events[2]!.body, 'Reproduzido em dispositivo de testes.');
    const resolved = await request('PATCH', `/${row.id}`, f.manager.token, { expectedRevision: 2, status: 'RESOLVED', resolution: 'Correção validada no dispositivo.' });
    assert.equal(resolved.status, 200);
    row = (resolved.data as { item: CaseDto }).item;
    assert.equal(row.resolution, 'Correção validada no dispositivo.');
    assert.equal(row.revision, 3);
    const reopened = await request('PATCH', `/${row.id}`, f.manager.token, { expectedRevision: 3, status: 'OPEN', assigneeId: null });
    assert.equal(reopened.status, 200);
    row = (reopened.data as { item: CaseDto }).item;
    assert.equal(row.status, 'OPEN');
    assert.equal(row.resolution, null);
    assert.equal(row.assignee, null);
    assert.equal(row.revision, 4);
    assert.equal(row.events.length, 5);
    assert.ok(row.events.every(event => event.author.id === f.manager.id));
    const audits = await prisma.adminAuditLog.findMany({ where: { actorUserId: f.manager.id, targetCompanyId: f.company.id, action: { startsWith: 'admin.support.case.' } } });
    assert.equal(audits.length, 5);
    assert.deepEqual(new Set(audits.map(audit => (audit.details as { eventId: string }).eventId)), new Set(row.events.map(event => event.id)));
    assert.equal((await request('GET', `/${row.id}`, f.reader.token)).status, 200);
  });

  it('filters company-scoped reads, rejects cross-company evidence and never grants by admin flag alone', async () => {
    const f = await fixture();
    const other = await newCompany();
    const original = await request('POST', '', f.manager.token, body(f.company.id));
    const foreign = await request('POST', '', f.manager.token, body(other.id));
    assert.equal(original.status, 201);
    assert.equal(foreign.status, 201);
    const response = await request('GET', '', f.reader.token);
    assert.equal(response.status, 200);
    assert.equal((response.data as { total: number }).total, 1);
    assert.equal((response.data as { items: CaseDto[] }).items[0]!.companyId, f.company.id);
    assert.equal((await request('GET', `?companyId=${other.id}`, f.reader.token)).status, 403);
    const foreignId = (foreign.data as { item: CaseDto }).item.id;
    assert.equal((await request('GET', `/${foreignId}`, f.reader.token)).status, 404);
    const scopedManager = await newActor(f.company.id, [{ key: 'admin.support.manage', companyId: f.company.id }]);
    assert.equal((await request('PATCH', `/${foreignId}`, scopedManager.token, { expectedRevision: 0, subject: 'Not authorized' })).status, 404);
    assert.equal((await request('POST', '', scopedManager.token, body(other.id))).status, 403);
    const device = await prisma.companyDevice.create({ data: { companyId: other.id, userId: f.manager.id, clientInstanceId: randomUUID(), status: 'ACTIVE' } });
    const crossEvidence = await request('POST', '', f.manager.token, { ...body(f.company.id), evidence: { type: 'DEVICE', id: device.id } });
    assert.equal(crossEvidence.status, 422);
    assert.equal((crossEvidence.data as { code: string }).code, 'SUPPORT_CASE_EVIDENCE_INVALID');
  });

  it('deduplicates retried creation and simultaneous active cases from the same evidence', async () => {
    const f = await fixture();
    const device = await prisma.companyDevice.create({ data: { companyId: f.company.id, userId: f.manager.id, clientInstanceId: randomUUID(), status: 'ACTIVE' } });
    const input = { ...body(f.company.id), evidence: { type: 'DEVICE', id: device.id } };
    const [a, b] = await Promise.all([
      request('POST', '', f.manager.token, input),
      request('POST', '', f.manager.token, { ...input, requestKey: randomUUID() }),
    ]);
    assert.deepEqual([a.status, b.status].sort(), [200, 201]);
    const caseId = (a.data as { item: CaseDto }).item.id;
    assert.equal((b.data as { item: CaseDto }).item.id, caseId);
    const retry = await request('POST', '', f.manager.token, input);
    assert.equal(retry.status, 200);
    assert.equal((retry.data as { reused: boolean }).reused, true);
    assert.equal((retry.data as { item: CaseDto }).item.id, caseId);
    assert.equal(await prisma.adminSupportCase.count({ where: { companyId: f.company.id } }), 1);
    assert.equal(await prisma.adminSupportCaseEvent.count({ where: { caseId } }), 1);
    assert.equal(await prisma.adminAuditLog.count({ where: { actorUserId: f.manager.id, action: 'admin.support.case.created' } }), 1);
  });

  it('detects concurrent notes and mutations without overwriting or creating stray audit entries', async () => {
    const f = await fixture();
    const created = await request('POST', '', f.manager.token, body(f.company.id));
    const id = (created.data as { item: CaseDto }).item.id;
    const [a, b] = await Promise.all([
      request('POST', `/${id}/notes`, f.manager.token, { expectedRevision: 0, body: 'First concurrent note' }),
      request('PATCH', `/${id}`, f.manager.token, { expectedRevision: 0, status: 'WAITING' }),
    ]);
    assert.deepEqual([a.status, b.status].sort(), [200, 409]);
    const conflict = a.status === 409 ? a : b;
    assert.equal((conflict.data as { code: string }).code, 'SUPPORT_CASE_REVISION_CONFLICT');
    const stored = await prisma.adminSupportCase.findUniqueOrThrow({ where: { id } });
    assert.equal(stored.revision, 1);
    assert.equal(await prisma.adminSupportCaseEvent.count({ where: { caseId: id } }), 2);
    assert.equal(await prisma.adminAuditLog.count({ where: { actorUserId: f.manager.id, action: { startsWith: 'admin.support.case.' } } }), 2);
  });

  it('requires a resolution and an active authorized assignee, validates inputs strictly and supports active/mine pagination', async () => {
    const f = await fixture();
    assert.equal((await request('POST', '', f.manager.token, { ...body(f.company.id), assigneeId: f.operator.id })).status, 422);
    assert.equal((await request('POST', '', f.manager.token, { ...body(f.company.id), assigneeId: f.noAccess.id })).status, 422);
    assert.equal((await request('POST', '', f.manager.token, { ...body(f.company.id), status: 'RESOLVED' })).status, 422);
    const created = await request('POST', '', f.manager.token, { ...body(f.company.id), assigneeId: f.manager.id });
    const row = (created.data as { item: CaseDto }).item;
    assert.equal((await request('PATCH', `/${row.id}`, f.manager.token, { expectedRevision: 0, status: 'RESOLVED' })).status, 422);
    assert.equal((await request('PATCH', `/${row.id}`, f.manager.token, { expectedRevision: 0, resolution: 'Result without resolution status' })).status, 422);
    const list = await request('GET', '?status=active&mine=true&page=1&pageSize=1', f.manager.token);
    assert.equal(list.status, 200);
    assert.equal((list.data as { total: number }).total, 1);
    assert.equal((list.data as { items: CaseDto[] }).items.length, 1);
    const assignees = await request('GET', `/assignees?companyId=${f.company.id}`, f.manager.token);
    assert.equal(assignees.status, 200);
    assert.ok((assignees.data as { items: Array<{ id: string }> }).items.some(item => item.id === f.manager.id));
    assert.ok(!(assignees.data as { items: Array<{ id: string }> }).items.some(item => item.id === f.noAccess.id));
    await request('PATCH', `/${row.id}`, f.manager.token, { expectedRevision: 0, status: 'RESOLVED', resolution: 'Concluído' });
    assert.equal(((await request('GET', '?status=active&mine=true', f.manager.token)).data as { total: number }).total, 0);
  });

  it('does not reopen a resolved case over another active case with the same evidence', async () => {
    const f = await fixture();
    const device = await prisma.companyDevice.create({ data: { companyId: f.company.id, userId: f.manager.id, clientInstanceId: randomUUID(), status: 'ACTIVE' } });
    const input = { ...body(f.company.id), evidence: { type: 'DEVICE', id: device.id } };
    const first = await request('POST', '', f.manager.token, input);
    const id = (first.data as { item: CaseDto }).item.id;
    await request('PATCH', `/${id}`, f.manager.token, { expectedRevision: 0, status: 'RESOLVED', resolution: 'Primeira ocorrência concluída.' });
    const second = await request('POST', '', f.manager.token, { ...input, requestKey: randomUUID() });
    assert.equal(second.status, 201);
    assert.notEqual((second.data as { item: CaseDto }).item.id, id);
    const reopen = await request('PATCH', `/${id}`, f.manager.token, { expectedRevision: 1, status: 'OPEN' });
    assert.equal(reopen.status, 409);
    assert.equal((reopen.data as { code: string }).code, 'SUPPORT_CASE_ACTIVE_EVIDENCE_EXISTS');
    const stored = await prisma.adminSupportCase.findUniqueOrThrow({ where: { id } });
    assert.equal(stored.status, 'RESOLVED');
    assert.equal(stored.revision, 1);
  });
});

function body(companyId: string) { return { companyId, subject: 'Problema reproduzido no aplicativo', description: 'Descrição interna do diagnóstico.', priority: 'NORMAL', requestKey: randomUUID() }; }
async function newCompany() {
  const company = await prisma.company.create({ data: { name: 'Support Cases Test', legalName: 'Support Cases Test', slug: `${runId}-${randomUUID()}` } });
  companies.push(company.id);
  return company;
}
async function newActor(companyId: string, grants: Array<{ key: string; companyId?: string }> = [], platform = true) {
  const user = await prisma.user.create({ data: { name: 'Test Admin', email: `${runId}-${randomUUID()}@test.invalid`, passwordHash: 'test-only', isPlatformAdmin: platform } });
  users.push(user.id);
  const membership = await prisma.membership.create({ data: { userId: user.id, companyId, role: 'OWNER' } });
  for (const grant of grants) await prisma.adminUserPermission.create({ data: { actorUserId: user.id, permissionKey: grant.key, scope: grant.companyId ? 'company' : 'platform', scopeId: grant.companyId ?? '*' } });
  return { id: user.id, token: jwt.sign({ sub: user.id, companyId, membershipId: membership.id, membershipRole: 'OWNER', isPlatformAdmin: platform, email: user.email }, env.JWT_SECRET, { expiresIn: '15m' }) };
}
async function fixture() {
  const company = await newCompany();
  const manager = await newActor(company.id, [{ key: 'admin.support.read' }, { key: 'admin.support.manage' }]);
  const reader = await newActor(company.id, [{ key: 'admin.support.read', companyId: company.id }]);
  const noAccess = await newActor(company.id);
  const operator = await newActor(company.id, [], false);
  return { company, manager, reader, noAccess, operator };
}
async function cleanup() {
  if (users.length) await prisma.adminAuditLog.deleteMany({ where: { actorUserId: { in: users } } });
  if (companies.length) await prisma.company.deleteMany({ where: { id: { in: companies } } });
  if (users.length) await prisma.user.deleteMany({ where: { id: { in: users } } });
  companies.length = 0; users.length = 0;
}
async function request(method: string, path: string, token?: string, body?: unknown) {
  const response = await fetch(base + path, { method, headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), ...(body === undefined ? {} : { 'Content-Type': 'application/json' }) }, body: body === undefined ? undefined : JSON.stringify(body) });
  return { status: response.status, data: await response.json() as unknown };
}
