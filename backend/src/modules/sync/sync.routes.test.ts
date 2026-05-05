import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';
import type { AddressInfo } from 'node:net';

import type { Server } from 'http';
import jwt from 'jsonwebtoken';

import { createApp } from '../../app';
import { env } from '../../config/env';
import { prisma } from '../../database/prisma';

const runId = `sync-real-${Date.now()}`;

let server: Server;
let apiBaseUrl = '';

describe('operational local-first sync routes', () => {
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

  it('rejects push without app context', async () => {
    const response = await requestJson('POST', '/sync/push', {
      body: { events: [] },
    });

    assert.equal(response.status, 401);
    assert.equal((response.data as { code?: string }).code, 'AUTH_REQUIRED');
  });

  it('rejects push when sync is disabled by license', async () => {
    const fixture = await createFixture({ syncEnabled: false });
    const response = await push(fixture, [buildEvent('sale-disabled', 'sale')]);

    assert.equal(response.status, 403);
    assert.equal((response.data as { code?: string }).code, 'SYNC_DISABLED');
  });

  it('accepts valid sale and cashSession events', async () => {
    const fixture = await createFixture();
    const response = await push(fixture, [
      buildEvent('sale-accepted', 'sale', {
        entityLocalId: `${runId}-sale-local`,
        payload: { status: 'finalized', totalCents: 4500 },
      }),
      buildEvent('cash-session-accepted', 'cashSession', {
        feature: 'cash',
        entityLocalId: `${runId}-cash-session`,
        payload: { status: 'open', openedAt: new Date().toISOString() },
      }),
    ]);

    assert.equal(response.status, 202);
    const payload = response.data as {
      accepted: Array<{
        eventId: string;
        serverVersion: string;
        entityServerId: string | null;
      }>;
      summary: { accepted: number };
    };
    assert.equal(payload.summary.accepted, 2);
    assert.deepEqual(
      payload.accepted.map((item) => item.eventId),
      ['sale-accepted', 'cash-session-accepted'],
    );
    assert.ok(payload.accepted.every((item) => item.entityServerId != null));

    const persisted = await prisma.syncEvent.findMany({
      where: { companyId: fixture.companyId, status: 'ACCEPTED' },
      orderBy: { serverVersion: 'asc' },
    });
    assert.equal(persisted.length, 2);
    assert.equal(persisted[0]?.serverVersion?.toString(), '1');
    assert.equal(persisted[1]?.serverVersion?.toString(), '2');

    const [salesCount, cashSessionsCount] = await Promise.all([
      prisma.sale.count({ where: { companyId: fixture.companyId } }),
      prisma.cashSession.count({ where: { companyId: fixture.companyId } }),
    ]);
    assert.equal(salesCount, 1);
    assert.equal(cashSessionsCount, 1);
  });

  it('returns duplicates without processing the same event twice', async () => {
    const fixture = await createFixture();
    const event = buildEvent('sale-duplicate', 'sale');
    const first = await push(fixture, [event]);
    assert.equal(first.status, 202);

    const second = await push(fixture, [event]);

    assert.equal(second.status, 202);
    const payload = second.data as {
      duplicates: Array<{ eventId: string }>;
      summary: { duplicates: number };
    };
    assert.equal(payload.summary.duplicates, 1);
    assert.equal(payload.duplicates[0]?.eventId, 'sale-duplicate');

    const count = await prisma.syncEvent.count({
      where: {
        companyId: fixture.companyId,
        eventId: 'sale-duplicate',
      },
    });
    assert.equal(count, 1);
  });

  it('rejects server-first entities sent to sync push', async () => {
    const fixture = await createFixture();
    const response = await push(fixture, [
      buildEvent('product-rejected', 'product'),
      buildEvent('customer-rejected', 'customer'),
      buildEvent('supplier-rejected', 'supplier'),
    ]);

    assert.equal(response.status, 202);
    const payload = response.data as {
      rejected: Array<{ eventId: string; code: string }>;
      summary: { rejected: number };
    };
    assert.equal(payload.summary.rejected, 3);
    assert.deepEqual(
      payload.rejected.map((item) => [item.eventId, item.code]),
      [
        ['product-rejected', 'ENTITY_NOT_LOCAL_FIRST'],
        ['customer-rejected', 'ENTITY_NOT_LOCAL_FIRST'],
        ['supplier-rejected', 'ENTITY_NOT_LOCAL_FIRST'],
      ],
    );
  });

  it('rejects invalid operations with INVALID_OPERATION', async () => {
    const fixture = await createFixture();
    const response = await push(fixture, [
      buildEvent('sale-invalid-operation', 'sale', {
        operation: 'merge',
      }),
    ]);

    assert.equal(response.status, 202);
    const rejected = (response.data as {
      rejected: Array<{ code: string }>;
    }).rejected;
    assert.equal(rejected[0]?.code, 'INVALID_OPERATION');
  });

  it('creates a conflict when a finalized sale receives an update', async () => {
    const fixture = await createFixture();
    const entityLocalId = `${runId}-finalized-sale`;
    const createSale = await push(fixture, [
      buildEvent('sale-finalized-create', 'sale', {
        entityLocalId,
        payload: { status: 'finalized', totalCents: 9900 },
      }),
    ]);
    assert.equal(createSale.status, 202);

    const updateSale = await push(fixture, [
      buildEvent('sale-finalized-update', 'sale', {
        operation: 'update',
        entityLocalId,
        payload: { status: 'finalized', totalCents: 8900 },
      }),
    ]);

    assert.equal(updateSale.status, 202);
    const payload = updateSale.data as {
      conflicts: Array<{ code: string; eventId: string }>;
    };
    assert.equal(payload.conflicts[0]?.eventId, 'sale-finalized-update');
    assert.equal(payload.conflicts[0]?.code, 'SALE_IMMUTABLE');

    const conflict = await prisma.syncConflict.findFirst({
      where: { companyId: fixture.companyId },
    });
    assert.equal(conflict?.status, 'OPEN');
  });

  it('materializes cashSession/create without duplicating the domain record', async () => {
    const fixture = await createFixture();
    const entityLocalId = `${runId}-cash-session-domain`;

    const first = await push(fixture, [
      buildEvent('cash-session-domain-create', 'cashSession', {
        feature: 'cash',
        entityLocalId,
        payload: { status: 'open', openingBalanceCents: 1200 },
      }),
    ]);
    const second = await push(fixture, [
      buildEvent('cash-session-domain-duplicate', 'cashSession', {
        feature: 'cash',
        entityLocalId,
        payload: { status: 'open', openingBalanceCents: 1200 },
      }),
    ]);

    assert.equal(first.status, 202);
    assert.equal(second.status, 202);
    assert.equal((second.data as { summary: { duplicates: number } }).summary.duplicates, 1);

    const [cashSessionsCount, duplicateEventsCount] = await Promise.all([
      prisma.cashSession.count({ where: { companyId: fixture.companyId } }),
      prisma.syncEvent.count({
        where: { companyId: fixture.companyId, status: 'DUPLICATE' },
      }),
    ]);
    assert.equal(cashSessionsCount, 1);
    assert.equal(duplicateEventsCount, 1);
  });

  it('materializes cashSession/update closing cash and blocks reopening', async () => {
    const fixture = await createFixture();
    const entityLocalId = `${runId}-cash-session-close`;
    await push(fixture, [
      buildEvent('cash-session-close-create', 'cashSession', {
        feature: 'cash',
        entityLocalId,
        payload: { status: 'open', openingBalanceCents: 1000 },
      }),
    ]);

    const closeResponse = await push(fixture, [
      buildEvent('cash-session-close-update', 'cashSession', {
        feature: 'cash',
        operation: 'update',
        entityLocalId,
        payload: { status: 'closed', closingBalanceCents: 1500 },
      }),
    ]);
    assert.equal(closeResponse.status, 202);

    const cashSession = await prisma.cashSession.findUniqueOrThrow({
      where: {
        companyId_localUuid: {
          companyId: fixture.companyId,
          localUuid: entityLocalId,
        },
      },
    });
    assert.equal(cashSession.status, 'closed');

    const reopenResponse = await push(fixture, [
      buildEvent('cash-session-reopen-conflict', 'cashSession', {
        feature: 'cash',
        operation: 'update',
        entityLocalId,
        payload: { status: 'open' },
      }),
    ]);

    const payload = reopenResponse.data as {
      conflicts: Array<{ code: string }>;
    };
    assert.equal(payload.conflicts[0]?.code, 'CASH_SESSION_CLOSED');
  });

  it('materializes cashMovement/create and keeps it idempotent', async () => {
    const fixture = await createFixture();
    const cashSessionLocalId = `${runId}-movement-cash-session`;
    const movementLocalId = `${runId}-cash-movement`;
    await push(fixture, [
      buildEvent('movement-cash-session-create', 'cashSession', {
        feature: 'cash',
        entityLocalId: cashSessionLocalId,
        payload: { status: 'open' },
      }),
    ]);

    await push(fixture, [
      buildEvent('cash-movement-create', 'cashMovement', {
        feature: 'cash',
        entityLocalId: movementLocalId,
        payload: {
          cashSessionLocalId,
          amountCents: -500,
          eventType: 'sangria',
        },
      }),
    ]);
    const duplicate = await push(fixture, [
      buildEvent('cash-movement-domain-duplicate', 'cashMovement', {
        feature: 'cash',
        entityLocalId: movementLocalId,
        payload: {
          cashSessionLocalId,
          amountCents: -500,
          eventType: 'sangria',
        },
      }),
    ]);

    assert.equal((duplicate.data as { summary: { duplicates: number } }).summary.duplicates, 1);
    const cashEventsCount = await prisma.cashEvent.count({
      where: { companyId: fixture.companyId },
    });
    assert.equal(cashEventsCount, 1);
  });

  it('materializes sale/create without duplicating the sale domain record', async () => {
    const fixture = await createFixture();
    const entityLocalId = `${runId}-sale-domain`;

    const first = await push(fixture, [
      buildEvent('sale-domain-create', 'sale', {
        entityLocalId,
        payload: { status: 'finalized', totalCents: 8800 },
      }),
    ]);
    const second = await push(fixture, [
      buildEvent('sale-domain-duplicate', 'sale', {
        entityLocalId,
        payload: { status: 'finalized', totalCents: 8800 },
      }),
    ]);

    assert.equal(first.status, 202);
    assert.equal((second.data as { summary: { duplicates: number } }).summary.duplicates, 1);
    const salesCount = await prisma.sale.count({
      where: { companyId: fixture.companyId, localUuid: entityLocalId },
    });
    assert.equal(salesCount, 1);
  });

  it('creates SALE_NOT_FOUND conflicts for saleItem and payment without sale', async () => {
    const fixture = await createFixture();
    const response = await push(fixture, [
      buildEvent('sale-item-missing-sale', 'saleItem', {
        entityLocalId: `${runId}-sale-item-missing`,
        payload: { saleLocalId: `${runId}-missing-sale`, quantityMil: 1000 },
      }),
      buildEvent('payment-missing-sale', 'payment', {
        entityLocalId: `${runId}-payment-missing`,
        payload: {
          saleLocalId: `${runId}-missing-sale`,
          amountCents: 2500,
        },
      }),
    ]);

    assert.equal(response.status, 202);
    const conflicts = (response.data as {
      conflicts: Array<{ eventId: string; code: string }>;
    }).conflicts;
    assert.deepEqual(
      conflicts.map((item) => [item.eventId, item.code]),
      [
        ['sale-item-missing-sale', 'SALE_NOT_FOUND'],
        ['payment-missing-sale', 'SALE_NOT_FOUND'],
      ],
    );
  });

  it('materializes duplicate payment as idempotent duplicate', async () => {
    const fixture = await createFixture();
    const saleLocalId = `${runId}-payment-sale`;
    const paymentLocalId = `${runId}-payment-local`;
    await push(fixture, [
      buildEvent('payment-sale-create', 'sale', {
        entityLocalId: saleLocalId,
        payload: { status: 'finalized', totalCents: 2500 },
      }),
    ]);
    await push(fixture, [
      buildEvent('payment-create', 'payment', {
        entityLocalId: paymentLocalId,
        payload: {
          saleLocalId,
          amountCents: 2500,
          paymentMethod: 'pix',
          idempotencyKey: paymentLocalId,
        },
      }),
    ]);

    const duplicate = await push(fixture, [
      buildEvent('payment-domain-duplicate', 'payment', {
        entityLocalId: `${paymentLocalId}-retry`,
        payload: {
          saleLocalId,
          amountCents: 2500,
          paymentMethod: 'pix',
          idempotencyKey: paymentLocalId,
        },
      }),
    ]);

    assert.equal((duplicate.data as { summary: { duplicates: number } }).summary.duplicates, 1);
    const paymentsCount = await prisma.financialEvent.count({
      where: { companyId: fixture.companyId, eventType: 'sale_payment' },
    });
    assert.equal(paymentsCount, 1);
  });

  it('treats repeated receipt for the same sale as idempotent', async () => {
    const fixture = await createFixture();
    const saleLocalId = `${runId}-receipt-same-sale`;
    const receiptNumber = `${runId}-R-001`;
    await push(fixture, [
      buildEvent('receipt-sale-create', 'sale', {
        entityLocalId: saleLocalId,
        payload: { status: 'finalized', totalCents: 1200 },
      }),
    ]);
    await push(fixture, [
      buildEvent('receipt-create', 'receipt', {
        entityLocalId: `${runId}-receipt-local`,
        payload: { saleLocalId, receiptNumber },
      }),
    ]);

    const duplicate = await push(fixture, [
      buildEvent('receipt-same-sale-duplicate', 'receipt', {
        entityLocalId: `${runId}-receipt-local-2`,
        payload: { saleLocalId, receiptNumber },
      }),
    ]);

    assert.equal((duplicate.data as { summary: { duplicates: number } }).summary.duplicates, 1);
    const sale = await prisma.sale.findUniqueOrThrow({
      where: {
        companyId_localUuid: {
          companyId: fixture.companyId,
          localUuid: saleLocalId,
        },
      },
    });
    assert.equal(sale.receiptNumber, receiptNumber);
  });

  it('creates DUPLICATE_RECEIPT when receipt number belongs to another sale', async () => {
    const fixture = await createFixture();
    const receiptNumber = `${runId}-R-002`;
    await push(fixture, [
      buildEvent('receipt-sale-a-create', 'sale', {
        entityLocalId: `${runId}-receipt-sale-a`,
        payload: { status: 'finalized', totalCents: 1200 },
      }),
      buildEvent('receipt-sale-b-create', 'sale', {
        entityLocalId: `${runId}-receipt-sale-b`,
        payload: { status: 'finalized', totalCents: 1400 },
      }),
    ]);
    await push(fixture, [
      buildEvent('receipt-sale-a-receipt', 'receipt', {
        entityLocalId: `${runId}-receipt-a`,
        payload: { saleLocalId: `${runId}-receipt-sale-a`, receiptNumber },
      }),
    ]);

    const conflict = await push(fixture, [
      buildEvent('receipt-sale-b-conflict', 'receipt', {
        entityLocalId: `${runId}-receipt-b`,
        payload: { saleLocalId: `${runId}-receipt-sale-b`, receiptNumber },
      }),
    ]);

    assert.equal(
      (conflict.data as { conflicts: Array<{ code: string }> }).conflicts[0]
        ?.code,
      'DUPLICATE_RECEIPT',
    );
  });

  it('creates stock conflicts for unavailable stock and missing remote variant', async () => {
    const fixture = await createFixture();
    const product = await createProduct(fixture, { stockMil: 0 });

    const response = await push(fixture, [
      buildEvent('stock-reservation-unavailable', 'stockReservation', {
        entityLocalId: `${runId}-stock-reservation`,
        payload: { productId: product.id, quantityMil: 1000 },
      }),
      buildEvent('stock-deduction-missing-variant', 'stockDeduction', {
        entityLocalId: `${runId}-stock-deduction`,
        payload: {
          productVariantId: '11111111-1111-4111-8111-111111111111',
          quantityMil: 1000,
        },
      }),
    ]);

    const conflicts = (response.data as {
      conflicts: Array<{ eventId: string; code: string }>;
    }).conflicts;
    assert.deepEqual(
      conflicts.map((item) => [item.eventId, item.code]),
      [
        ['stock-reservation-unavailable', 'STOCK_UNAVAILABLE'],
        ['stock-deduction-missing-variant', 'STOCK_VARIANT_NOT_FOUND'],
      ],
    );
  });

  it('creates SyncIncident when materialization fails unexpectedly', async () => {
    const fixture = await createFixture();
    const saleLocalId = `${runId}-payment-overflow-sale`;
    await push(fixture, [
      buildEvent('payment-overflow-sale-create', 'sale', {
        entityLocalId: saleLocalId,
        payload: { status: 'finalized', totalCents: 1000 },
      }),
    ]);

    const response = await push(fixture, [
      buildEvent('payment-overflow-failure', 'payment', {
        entityLocalId: `${runId}-payment-overflow`,
        payload: {
          saleLocalId,
          amountCents: 3_000_000_000,
        },
      }),
    ]);

    const rejected = (response.data as {
      rejected: Array<{ code: string }>;
    }).rejected;
    assert.equal(rejected[0]?.code, 'SYNC_MATERIALIZATION_FAILED');

    const [failedEvent, incident] = await Promise.all([
      prisma.syncEvent.findFirst({
        where: {
          companyId: fixture.companyId,
          eventId: 'payment-overflow-failure',
          status: 'FAILED',
        },
      }),
      prisma.syncIncident.findFirst({
        where: {
          companyId: fixture.companyId,
          code: 'SYNC_MATERIALIZATION_FAILED',
        },
      }),
    ]);
    assert.notEqual(failedEvent, null);
    assert.notEqual(incident, null);
  });

  it('materializes operationalOrder/create', async () => {
    const fixture = await createFixture();
    const orderLocalId = `${runId}-operational-order`;

    const response = await push(fixture, [
      buildEvent('operational-order-create', 'operationalOrder', {
        entityLocalId: orderLocalId,
        payload: {
          status: 'open',
          subtotalCents: 3200,
          discountCents: 200,
          totalCents: 3000,
          notes: 'Mesa 4',
        },
      }),
    ]);

    assert.equal(response.status, 202);
    const accepted = (response.data as {
      accepted: Array<{ entityServerId: string | null }>;
    }).accepted;
    assert.notEqual(accepted[0]?.entityServerId, null);

    const order = await prisma.operationalOrder.findUniqueOrThrow({
      where: {
        companyId_localUuid: {
          companyId: fixture.companyId,
          localUuid: orderLocalId,
        },
      },
    });
    assert.equal(order.status, 'open');
    assert.equal(order.totalCents, 3000);
    assert.equal(order.deviceId, fixture.deviceId);
    assert.equal(order.sellerUserId, fixture.userId);
  });

  it('keeps duplicate operationalOrder/create idempotent', async () => {
    const fixture = await createFixture();
    const orderLocalId = `${runId}-operational-order-duplicate`;

    await push(fixture, [
      buildEvent('operational-order-duplicate-a', 'operationalOrder', {
        entityLocalId: orderLocalId,
        payload: { status: 'open', totalCents: 1800 },
      }),
    ]);
    const duplicate = await push(fixture, [
      buildEvent('operational-order-duplicate-b', 'operationalOrder', {
        entityLocalId: orderLocalId,
        payload: { status: 'open', totalCents: 1800 },
      }),
    ]);

    assert.equal((duplicate.data as { summary: { duplicates: number } }).summary.duplicates, 1);
    const ordersCount = await prisma.operationalOrder.count({
      where: { companyId: fixture.companyId, localUuid: orderLocalId },
    });
    assert.equal(ordersCount, 1);
  });

  it('materializes operationalOrder/update status changes', async () => {
    const fixture = await createFixture();
    const orderLocalId = `${runId}-operational-order-update`;
    await push(fixture, [
      buildEvent('operational-order-update-create', 'operationalOrder', {
        entityLocalId: orderLocalId,
        payload: { status: 'open', totalCents: 1800 },
      }),
    ]);

    const response = await push(fixture, [
      buildEvent('operational-order-update-close', 'operationalOrder', {
        operation: 'update',
        entityLocalId: orderLocalId,
        payload: { status: 'closed', totalCents: 2000, notes: 'Fechado' },
      }),
    ]);

    assert.equal(response.status, 202);
    const order = await prisma.operationalOrder.findUniqueOrThrow({
      where: {
        companyId_localUuid: {
          companyId: fixture.companyId,
          localUuid: orderLocalId,
        },
      },
    });
    assert.equal(order.status, 'closed');
    assert.equal(order.totalCents, 2000);
    assert.notEqual(order.closedAt, null);
  });

  it('materializes operationalOrderItem/create', async () => {
    const fixture = await createFixture();
    const orderLocalId = `${runId}-order-item-order`;
    const itemLocalId = `${runId}-order-item`;
    await push(fixture, [
      buildEvent('order-item-order-create', 'operationalOrder', {
        entityLocalId: orderLocalId,
        payload: { status: 'open', totalCents: 1500 },
      }),
    ]);

    const response = await push(fixture, [
      buildEvent('order-item-create', 'operationalOrderItem', {
        entityLocalId: itemLocalId,
        payload: {
          operationalOrderLocalId: orderLocalId,
          description: 'Item avulso',
          quantityMil: 1000,
          unitPriceCents: 1500,
          totalCents: 1500,
        },
      }),
    ]);

    assert.equal(response.status, 202);
    const item = await prisma.operationalOrderItem.findUniqueOrThrow({
      where: {
        companyId_localUuid: {
          companyId: fixture.companyId,
          localUuid: itemLocalId,
        },
      },
    });
    assert.equal(item.description, 'Item avulso');
    assert.equal(item.quantityMil, 1000);
    assert.equal(item.totalCents, 1500);
  });

  it('creates OPERATIONAL_ORDER_NOT_FOUND for item without order', async () => {
    const fixture = await createFixture();

    const response = await push(fixture, [
      buildEvent('order-item-without-order', 'operationalOrderItem', {
        entityLocalId: `${runId}-order-item-without-order`,
        payload: {
          operationalOrderLocalId: `${runId}-missing-order`,
          description: 'Item perdido',
          quantityMil: 1000,
          totalCents: 1000,
        },
      }),
    ]);

    assert.equal(
      (response.data as { conflicts: Array<{ code: string }> }).conflicts[0]
        ?.code,
      'OPERATIONAL_ORDER_NOT_FOUND',
    );
  });

  it('keeps duplicate operationalOrderItem/create idempotent', async () => {
    const fixture = await createFixture();
    const orderLocalId = `${runId}-order-item-duplicate-order`;
    const itemLocalId = `${runId}-order-item-duplicate`;
    await push(fixture, [
      buildEvent('order-item-duplicate-order-create', 'operationalOrder', {
        entityLocalId: orderLocalId,
        payload: { status: 'open', totalCents: 1000 },
      }),
    ]);
    await push(fixture, [
      buildEvent('order-item-duplicate-a', 'operationalOrderItem', {
        entityLocalId: itemLocalId,
        payload: {
          operationalOrderLocalId: orderLocalId,
          description: 'Cafe',
          quantityMil: 1000,
          totalCents: 1000,
        },
      }),
    ]);

    const duplicate = await push(fixture, [
      buildEvent('order-item-duplicate-b', 'operationalOrderItem', {
        entityLocalId: itemLocalId,
        payload: {
          operationalOrderLocalId: orderLocalId,
          description: 'Cafe',
          quantityMil: 1000,
          totalCents: 1000,
        },
      }),
    ]);

    assert.equal((duplicate.data as { summary: { duplicates: number } }).summary.duplicates, 1);
    const count = await prisma.operationalOrderItem.count({
      where: { companyId: fixture.companyId, localUuid: itemLocalId },
    });
    assert.equal(count, 1);
  });

  it('marks operationalOrder as converted when sale/create references it', async () => {
    const fixture = await createFixture();
    const orderLocalId = `${runId}-order-sale-conversion`;
    const saleLocalId = `${runId}-sale-from-order`;
    await push(fixture, [
      buildEvent('order-sale-conversion-create', 'operationalOrder', {
        entityLocalId: orderLocalId,
        payload: { status: 'open', totalCents: 4500 },
      }),
    ]);

    const response = await push(fixture, [
      buildEvent('sale-from-operational-order', 'sale', {
        entityLocalId: saleLocalId,
        payload: {
          status: 'finalized',
          totalCents: 4500,
          operationalOrderLocalId: orderLocalId,
        },
      }),
    ]);

    assert.equal(response.status, 202);
    const [order, sale] = await Promise.all([
      prisma.operationalOrder.findUniqueOrThrow({
        where: {
          companyId_localUuid: {
            companyId: fixture.companyId,
            localUuid: orderLocalId,
          },
        },
      }),
      prisma.sale.findUniqueOrThrow({
        where: {
          companyId_localUuid: {
            companyId: fixture.companyId,
            localUuid: saleLocalId,
          },
        },
      }),
    ]);
    assert.equal(order.status, 'converted');
    assert.equal(order.convertedSaleId, sale.id);
    assert.notEqual(order.closedAt, null);
  });

  it('creates OPERATIONAL_ORDER_IMMUTABLE when updating a converted order', async () => {
    const fixture = await createFixture();
    const orderLocalId = `${runId}-converted-order`;
    await push(fixture, [
      buildEvent('converted-order-create', 'operationalOrder', {
        entityLocalId: orderLocalId,
        payload: { status: 'open', totalCents: 4500 },
      }),
    ]);
    await push(fixture, [
      buildEvent('converted-order-sale', 'sale', {
        entityLocalId: `${runId}-converted-order-sale`,
        payload: {
          status: 'finalized',
          totalCents: 4500,
          operationalOrderLocalId: orderLocalId,
        },
      }),
    ]);

    const response = await push(fixture, [
      buildEvent('converted-order-update-conflict', 'operationalOrder', {
        operation: 'update',
        entityLocalId: orderLocalId,
        payload: { status: 'open', totalCents: 4000 },
      }),
    ]);

    assert.equal(
      (response.data as { conflicts: Array<{ code: string }> }).conflicts[0]
        ?.code,
      'OPERATIONAL_ORDER_IMMUTABLE',
    );
  });

  it('does not create product or customer records from operational sync events', async () => {
    const fixture = await createFixture();
    const orderLocalId = `${runId}-free-description-order`;
    const missingCustomerId = '22222222-2222-4222-8222-222222222222';
    const missingProductId = '33333333-3333-4333-8333-333333333333';
    await push(fixture, [
      buildEvent('free-description-order-create', 'operationalOrder', {
        entityLocalId: orderLocalId,
        payload: {
          status: 'open',
          totalCents: 1000,
          customerId: missingCustomerId,
        },
      }),
      buildEvent('free-description-item-create', 'operationalOrderItem', {
        entityLocalId: `${runId}-free-description-item`,
        payload: {
          operationalOrderLocalId: orderLocalId,
          productId: missingProductId,
          description: 'Produto digitado no PDV',
          quantityMil: 1000,
          totalCents: 1000,
        },
      }),
    ]);

    const [customersCount, productsCount, order] = await Promise.all([
      prisma.customer.count({
        where: { companyId: fixture.companyId, id: missingCustomerId },
      }),
      prisma.product.count({
        where: { companyId: fixture.companyId, id: missingProductId },
      }),
      prisma.operationalOrder.findUniqueOrThrow({
        where: {
          companyId_localUuid: {
            companyId: fixture.companyId,
            localUuid: orderLocalId,
          },
        },
      }),
    ]);

    assert.equal(customersCount, 0);
    assert.equal(productsCount, 0);
    assert.equal(order.customerId, null);
  });

  it('pulls operationalOrder event only for the same company with entityServerId', async () => {
    const fixture = await createFixture();
    const otherFixture = await createFixture();
    await push(fixture, [
      buildEvent('pull-operational-order', 'operationalOrder', {
        entityLocalId: `${runId}-pull-operational-order`,
        payload: { status: 'open', totalCents: 1000 },
      }),
    ]);
    await push(otherFixture, [
      buildEvent('pull-other-operational-order', 'operationalOrder', {
        entityLocalId: `${runId}-pull-other-operational-order`,
        payload: { status: 'open', totalCents: 1000 },
      }),
    ]);

    const response = await requestJson('GET', '/sync/pull?sinceVersion=0', {
      token: fixture.token,
    });

    const events = (response.data as {
      events: Array<{
        eventId: string;
        entity: string;
        entityServerId: string | null;
      }>;
    }).events;
    assert.deepEqual(
      events.map((event) => event.eventId),
      ['pull-operational-order'],
    );
    assert.equal(events[0]?.entity, 'operationalOrder');
    assert.notEqual(events[0]?.entityServerId, null);
  });

  it('pulls only local-first PDV events from the same company', async () => {
    const fixture = await createFixture();
    const otherFixture = await createFixture();
    await push(fixture, [
      buildEvent('pull-sale', 'sale'),
      buildEvent('pull-product-rejected', 'product'),
    ]);
    await push(otherFixture, [buildEvent('other-company-sale', 'sale')]);

    const response = await requestJson('GET', '/sync/pull?sinceVersion=0', {
      token: fixture.token,
    });

    assert.equal(response.status, 200);
    const events = (response.data as {
      events: Array<{ eventId: string; entity: string }>;
    }).events;
    assert.deepEqual(
      events.map((event) => event.eventId),
      ['pull-sale'],
    );
    assert.ok(events.every((event) => event.entity !== 'product'));
  });

  it('returns checkpoints and current server version in status', async () => {
    const fixture = await createFixture();
    await push(fixture, [buildEvent('status-sale', 'sale')]);

    const response = await requestJson('GET', '/sync/status', {
      token: fixture.token,
    });

    assert.equal(response.status, 200);
    const payload = response.data as {
      currentServerVersion: string;
      checkpoints: Array<{ feature: string; lastServerVersion: string }>;
      openConflictsCount: number;
      acceptedCount: number;
      conflictCount: number;
      rejectedCount: number;
      failedCount: number;
      lastMaterializedAt: string | null;
    };
    assert.equal(payload.currentServerVersion, '1');
    assert.equal(payload.checkpoints[0]?.feature, 'pdv');
    assert.equal(payload.checkpoints[0]?.lastServerVersion, '1');
    assert.equal(payload.openConflictsCount, 0);
    assert.equal(payload.acceptedCount, 1);
    assert.equal(payload.conflictCount, 0);
    assert.equal(payload.rejectedCount, 0);
    assert.equal(payload.failedCount, 0);
    assert.notEqual(payload.lastMaterializedAt, null);
  });

  it('resolves open PDV conflicts', async () => {
    const fixture = await createFixture();
    const entityLocalId = `${runId}-resolve-conflict-sale`;
    await push(fixture, [
      buildEvent('resolve-sale-create', 'sale', {
        entityLocalId,
        payload: { status: 'finalized' },
      }),
    ]);
    await push(fixture, [
      buildEvent('resolve-sale-update', 'sale', {
        operation: 'update',
        entityLocalId,
      }),
    ]);
    const conflict = await prisma.syncConflict.findFirstOrThrow({
      where: { companyId: fixture.companyId },
    });

    const response = await requestJson(
      'POST',
      `/sync/conflicts/${conflict.id}/resolve`,
      {
        token: fixture.token,
        body: { resolution: { action: 'ignored_local_update' } },
      },
    );

    assert.equal(response.status, 200);
    assert.equal(
      (response.data as { conflict: { status: string } }).conflict.status,
      'RESOLVED',
    );
  });

  it('enforces the initial 100 events per push limit', async () => {
    const fixture = await createFixture();
    const events = Array.from({ length: 101 }, (_value, index) =>
      buildEvent(`too-many-${index}`, 'sale'),
    );

    const response = await push(fixture, events);

    assert.equal(response.status, 413);
    assert.equal(
      (response.data as { code?: string }).code,
      'SYNC_BATCH_TOO_LARGE',
    );
  });
});

async function createFixture(options?: {
  syncEnabled?: boolean;
}) {
  const company = await prisma.company.create({
    data: {
      name: 'Sync Real Company',
      legalName: 'Sync Real Company LTDA',
      slug: `${runId}-company-${Date.now()}-${Math.random().toString(16).slice(2)}`,
    },
  });
  const user = await prisma.user.create({
    data: {
      email: `${runId}-${Date.now()}-${Math.random().toString(16).slice(2)}@tatuzin.test`,
      name: 'Sync Real User',
      passwordHash: 'not-used',
    },
  });
  const membership = await prisma.membership.create({
    data: {
      userId: user.id,
      companyId: company.id,
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
      syncEnabled: options?.syncEnabled ?? true,
    },
  });

  const clientInstanceId = `${runId}-device-${Date.now()}-${Math.random()
    .toString(16)
    .slice(2)}`;
  const device = await prisma.companyDevice.create({
    data: {
      companyId: company.id,
      userId: user.id,
      clientInstanceId,
      deviceLabel: 'Sync Real Test Device',
      platform: 'node-test',
      appVersion: 'sync-real-test',
      status: 'ACTIVE',
      approvedAt: new Date(),
      approvedByUserId: user.id,
      lastSeenAt: new Date(),
    },
  });

  return {
    companyId: company.id,
    userId: user.id,
    deviceId: device.id,
    clientInstanceId,
    token: signToken({
      userId: user.id,
      companyId: company.id,
      membershipId: membership.id,
      email: user.email,
      clientInstanceId,
    }),
  };
}

async function createProduct(
  fixture: { companyId: string },
  options?: { stockMil?: number },
) {
  return prisma.product.create({
    data: {
      companyId: fixture.companyId,
      localUuid: `${runId}-product-${Date.now()}-${Math.random()
        .toString(16)
        .slice(2)}`,
      name: 'Produto Sync Materializer',
      salePriceCents: 1000,
      stockMil: options?.stockMil ?? 0,
    },
  });
}

function buildEvent(
  eventId: string,
  entity: string,
  overrides?: Partial<{
    feature: string;
    operation: string;
    entityLocalId: string;
    entityServerId: string;
    payload: Record<string, unknown>;
  }>,
) {
  return {
    eventId,
    feature: overrides?.feature ?? 'pdv',
    entity,
    operation: overrides?.operation ?? 'create',
    entityLocalId: overrides?.entityLocalId ?? `${eventId}-local`,
    entityServerId: overrides?.entityServerId,
    occurredAt: new Date().toISOString(),
    payload: overrides?.payload ?? { status: 'finalized' },
  };
}

async function push(
  fixture: { token: string },
  events: Array<Record<string, unknown>>,
) {
  return requestJson('POST', '/sync/push', {
    token: fixture.token,
    body: { events },
  });
}

function signToken(input: {
  userId: string;
  companyId: string;
  membershipId: string;
  email: string;
  clientInstanceId: string;
}) {
  return jwt.sign(
    {
      sub: input.userId,
      companyId: input.companyId,
      membershipId: input.membershipId,
      membershipRole: 'OPERATOR',
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
