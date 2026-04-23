import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';

import { prisma } from '../../database/prisma';
import { CrmService } from './crm.service';

const runId = `crm-${Date.now()}`;

describe('crm service', () => {
  const crmService = new CrmService();

  before(async () => {
    await prisma.$connect();
  });

  beforeEach(async () => {
    await cleanupFixtures();
  });

  after(async () => {
    await cleanupFixtures();
    await prisma.$disconnect();
  });

  it('reuses customer as master and layers notes, tasks, tags and timeline as cloud CRM', async () => {
    const fixture = await createFixture();

    const noteResponse = await crmService.createCustomerNote(
      fixture.customerId,
      {
        companyId: fixture.companyId,
        body: 'Cliente quer campanha de burger premium.',
      },
      fixture.actorUserId,
    );
    assert.equal(noteResponse.note.body, 'Cliente quer campanha de burger premium.');

    const taskResponse = await crmService.createCustomerTask(
      fixture.customerId,
      {
        companyId: fixture.companyId,
        title: 'Ligar para cliente VIP',
        description: 'Confirmar interesse na campanha de sexta.',
        dueAt: new Date(Date.now() + 24 * 60 * 60 * 1000),
        assignedToUserId: fixture.actorUserId,
      },
      fixture.actorUserId,
    );
    assert.equal(taskResponse.task.title, 'Ligar para cliente VIP');
    assert.equal(taskResponse.task.status, 'open');

    const tagsResponse = await crmService.applyCustomerTags(
      fixture.customerId,
      {
        companyId: fixture.companyId,
        mode: 'replace',
        tags: [
          { label: 'VIP', color: '#f59e0b' },
          { label: 'Retencao', color: '#0ea5e9' },
        ],
      },
      fixture.actorUserId,
    );
    assert.equal(tagsResponse.tags.length, 2);

    const customerList = await crmService.listCustomersWithCommercialContext({
      companyId: fixture.companyId,
      page: 1,
      pageSize: 20,
      search: 'alice',
      tag: 'vip',
      sortBy: 'updatedAt',
      sortDirection: 'desc',
    });

    assert.equal(customerList.items.length, 1);
    assert.equal(customerList.items[0]?.name, 'Alice CRM');
    assert.equal(customerList.items[0]?.operationalNotes, 'Observacao operacional');
    assert.equal(customerList.items[0]?.commercialSummary.totalSalesCount, 1);
    assert.equal(customerList.items[0]?.commercialSummary.totalRevenueCents, 6500);
    assert.equal(
      customerList.items[0]?.commercialSummary.totalFiadoPaymentsCents,
      1800,
    );
    assert.equal(customerList.items[0]?.commercialSummary.openTasksCount, 1);
    assert.equal(customerList.items[0]?.tags.length, 2);

    const detail = await crmService.getCustomerDetail(fixture.customerId, {
      companyId: fixture.companyId,
    });
    assert.equal(detail.customer.name, 'Alice CRM');
    assert.equal(detail.notes.length, 1);
    assert.equal(detail.tasks.length, 1);
    assert.equal(detail.customer.tags.length, 2);

    const timeline = await crmService.getCustomerTimeline(fixture.customerId, {
      companyId: fixture.companyId,
      page: 1,
      pageSize: 20,
    });
    assert.ok(timeline.items.length >= 5);
    assert.equal(timeline.items[0]?.eventType, 'tags_updated');
    assert.equal(
      timeline.items.some((item) => item.eventType == 'sale_recorded'),
      true,
    );
    assert.equal(
      timeline.items.some((item) => item.eventType == 'fiado_payment_received'),
      true,
    );
  });
});

async function createFixture() {
  const company = await prisma.company.create({
    data: {
      name: 'Tatuzin CRM Cloud',
      legalName: 'Tatuzin CRM Cloud LTDA',
      slug: `${runId}-company`,
      documentNumber: null,
    },
  });

  const actor = await prisma.user.create({
    data: {
      email: `${runId}@tatuzin.test`,
      passwordHash: 'hash',
      name: 'Gestora CRM',
      isPlatformAdmin: true,
    },
  });

  const customer = await prisma.customer.create({
    data: {
      companyId: company.id,
      localUuid: `${runId}-customer`,
      name: 'Alice CRM',
      phone: '11999990000',
      address: 'Rua do Cliente',
      notes: 'Observacao operacional',
    },
  });

  const sale = await prisma.sale.create({
    data: {
      companyId: company.id,
      localUuid: `${runId}-sale`,
      customerId: customer.id,
      paymentType: 'vista',
      paymentMethod: 'pix',
      status: 'active',
      totalAmountCents: 6500,
      totalCostCents: 2600,
      soldAt: new Date(),
      items: {
        create: [
          {
            productNameSnapshot: 'Burger CRM',
            quantityMil: 2000,
            unitPriceCents: 3250,
            totalPriceCents: 6500,
            unitCostCents: 1300,
            totalCostCents: 2600,
            unitMeasure: 'un',
            productType: 'unidade',
          },
        ],
      },
    },
  });

  await prisma.fiadoPayment.create({
    data: {
      companyId: company.id,
      saleId: sale.id,
      localUuid: `${runId}-fiado-payment`,
      amountCents: 1800,
      paymentMethod: 'pix',
      createdAt: new Date(Date.now() - 60 * 60 * 1000),
    },
  });

  return {
    companyId: company.id,
    actorUserId: actor.id,
    customerId: customer.id,
  };
}

async function cleanupFixtures() {
  await prisma.company.deleteMany({
    where: {
      slug: `${runId}-company`,
    },
  });

  await prisma.user.deleteMany({
    where: {
      email: `${runId}@tatuzin.test`,
    },
  });
}
