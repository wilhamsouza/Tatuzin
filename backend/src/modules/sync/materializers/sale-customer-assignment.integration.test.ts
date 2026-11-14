import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { before, after, describe, it } from 'node:test';
import { PrismaClient } from '@prisma/client';
import { resolveIntegrationTestDatabaseConfig } from '../../../shared/testing/integration-prisma';
import type { AppContext } from '../../app/app-context.types';
import { SaleCustomerAssignmentMaterializer } from './sale-customer-assignment.materializer';
import { SaleMaterializer } from './sale.materializer';
import type { SyncMaterializerInput } from './materializer.types';

const config = resolveIntegrationTestDatabaseConfig();
(config.enabled ? describe : describe.skip)('sale customer assignment PostgreSQL', () => {
  let db: PrismaClient;
  let companyId: string;
  let otherCompanyId: string;
  let customerId: string;
  let otherCustomerId: string;
  const seller = randomUUID();
  const materializer = new SaleCustomerAssignmentMaterializer();
  before(async () => {
    if (!config.enabled) return;
    db = new PrismaClient({ datasources: { db: { url: config.databaseUrl } } });
    const company = () => db.company.create({ data: { name: 'Assignment isolated', legalName: 'Assignment isolated', slug: randomUUID() } });
    companyId = (await company()).id;
    otherCompanyId = (await company()).id;
    customerId = (await db.customer.create({ data: { companyId, localUuid: randomUUID(), name: 'Client A' } })).id;
    otherCustomerId = (await db.customer.create({ data: { companyId: otherCompanyId, localUuid: randomUUID(), name: 'Other company' } })).id;
  });
  after(async () => {
    if (db) { await db.company.deleteMany({ where: { id: { in: [companyId, otherCompanyId] } } }); await db.$disconnect(); }
  });
  const sale = () => db.sale.create({ data: { companyId, localUuid: randomUUID(), sellerUserId: seller,
    paymentType: 'cash', paymentMethod: 'pix', totalAmountCents: 2500, totalCostCents: 700, soldAt: new Date() } });
  function input(saleUuid: string, overrides: Record<string,unknown> = {}) {
    return {
      context: { company: { id: companyId }, user: { id: seller }, device: { id: 'device-a' },
        membership: { role: 'SELLER', permissions: ['sales.create'] } } as AppContext,
      event: { eventId: randomUUID(), feature: 'pdv', payload: {}, entity: 'saleCustomerAssignment', operation: 'append', occurredAt: new Date().toISOString() },
      payload: { saleUuid, customerServerId: customerId, customerUuid: randomUUID(), expectedRevision: 0,
        previousCustomerServerId: null, previousCustomerUuid: null },
      ...overrides,
    } as Omit<SyncMaterializerInput,'tx'>;
  }
  const run = (data: Omit<SyncMaterializerInput,'tx'>) => db.$transaction(tx => materializer.materialize({ ...data, tx }));

  it('changes only customer, persists audit and safely acknowledges retries', async () => {
    const original = await sale();
    const data = input(original.localUuid);
    assert.equal((await run(data)).outcome, 'accepted');
    assert.equal((await run(data)).outcome, 'duplicate');
    const changed = await db.sale.findUniqueOrThrow({ where: { id: original.id } });
    assert.equal(changed.customerId, customerId);
    assert.equal(changed.customerAssignmentRevision, 1);
    for (const key of ['totalAmountCents','totalCostCents','paymentMethod','paymentType','receiptNumber','cashSessionId','status'] as const)
      assert.equal(changed[key], original[key]);
    assert.equal(await db.saleCustomerAssignment.count({ where: { saleId: original.id } }), 1);
    assert.equal((await run(input(original.localUuid))).outcome, 'conflict');
  });
  it('accepts one of two concurrent edits without overwriting', async () => {
    const original = await sale();
    const results = await Promise.all([run(input(original.localUuid)), run(input(original.localUuid))]);
    assert.deepEqual(results.map(x=>x.outcome).sort(), ['accepted','conflict']);
    assert.equal(await db.saleCustomerAssignment.count({ where: { saleId: original.id } }), 1);
  });
  it('rejects other companies and other sellers, but allows the owner', async () => {
    const original = await sale();
    const data = input(original.localUuid);
    assert.equal((await run({ ...data, payload: { ...data.payload, customerServerId: otherCustomerId } })).outcome, 'rejected');
    const other = { ...data.context, user: { ...data.context.user, id: randomUUID() } };
    assert.equal((await run({ ...data, context: other })).outcome, 'rejected');
    assert.equal((await run({ ...data, context: { ...other, membership: { ...other.membership, role: 'OWNER' } } })).outcome, 'accepted');
    assert.equal((await run({ ...input(original.localUuid), context: { ...data.context, company: { ...data.context.company, id: otherCompanyId } } })).outcome, 'deferred');
  });
  it('rejects cancelled, fiado, credit use, generated credit and returned sales', async () => {
    for (const change of [{ status: 'canceled' }, { paymentType: 'fiado' }, { creditUsedCents: 100 },
      { creditGeneratedCents: 100 }, { customerAssignmentLocked: true }]) {
      const original = await sale();
      await db.sale.update({ where: { id: original.id }, data: change });
      const result = await run(input(original.localUuid));
      assert.equal(result.outcome, 'rejected');
      assert.equal(await db.saleCustomerAssignment.count({ where: { saleId: original.id } }), 0);
    }
  });
  it('defers missing dependencies and persists a one-way return restriction', async () => {
    assert.equal((await run(input(randomUUID()))).outcome, 'deferred');
    const original = await sale();
    const data = input(original.localUuid);
    const lock = { ...data, event: { ...data.event, entity: 'saleCustomerLock' } };
    assert.equal((await run(lock)).outcome, 'accepted');
    assert.equal((await run(input(original.localUuid))).outcome, 'rejected');
  });
  it('creates a sale with its customer and refuses a foreign customer before persistence', async () => {
    for (const [id, expected] of [[customerId,'accepted'],[otherCustomerId,'rejected']] as const) {
      const uuid=randomUUID();
      const data=input(uuid);
      const result=await db.$transaction(tx=>new SaleMaterializer().materializeSale({
        ...data,tx,event:{...data.event,entity:'sale',operation:'create',entityLocalId:uuid},
        payload:{uuid,customerServerId:id,paymentMethod:'pix',saleType:'vista',totalCents:2500},
      }));
      assert.equal(result.outcome,expected);
      const saved=await db.sale.findUnique({where:{companyId_localUuid:{companyId,localUuid:uuid}}});
      assert.equal(saved?.customerId ?? null,expected==='accepted'?customerId:null);
    }
  });
});
