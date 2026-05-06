import {
  domainIdentityFor,
  firstDate,
  firstString,
  positiveInt,
  syncMetadataFor,
} from './payload-utils';
import { SaleMaterializer } from './sale.materializer';
import type {
  SyncMaterializerInput,
  SyncMaterializerResult,
} from './materializer.types';

export class PaymentMaterializer {
  constructor(private readonly saleMaterializer = new SaleMaterializer()) {}

  async materialize(
    input: SyncMaterializerInput,
  ): Promise<SyncMaterializerResult> {
    if (!['create', 'append', 'upsert'].includes(input.event.operation)) {
      return {
        outcome: 'rejected',
        code: 'INVALID_OPERATION',
        message: 'payment aceita create, append ou upsert nesta etapa.',
      };
    }

    const localUuid = domainIdentityFor(
      input.event,
      input.payload,
      [
        'paymentLocalId',
        'paymentUuid',
        'paymentKey',
        'uuid',
        'localUuid',
        'localId',
        'id',
      ],
      { preferIdempotencyKey: true },
    );
    if (localUuid == null) {
      return {
        outcome: 'rejected',
        code: 'LOCAL_ID_REQUIRED',
        message: 'payment precisa de entityLocalId, uuid ou paymentLocalId.',
      };
    }

    const amountCents = positiveInt(input.payload, ['amountCents', 'amount']);
    if (amountCents == null) {
      return {
        outcome: 'rejected',
        code: 'INVALID_PAYMENT_AMOUNT',
        message: 'payment precisa de amountCents positivo.',
      };
    }

    const sale = await this.saleMaterializer.findSale(input);
    if (sale == null) {
      return {
        outcome: 'conflict',
        code: 'SALE_NOT_FOUND',
        message: 'Venda nao encontrada para materializar pagamento.',
        payload: {
          entityLocalId: input.event.entityLocalId,
          saleUuid: firstString(input.payload, ['saleUuid', 'saleLocalId']),
        },
      };
    }

    const existing = await input.tx.financialEvent.findUnique({
      where: {
        companyId_localUuid: {
          companyId: input.context.company.id,
          localUuid,
        },
      },
    });
    if (existing != null) {
      return { outcome: 'duplicate', entityServerId: existing.id };
    }

    const created = await input.tx.financialEvent.create({
      data: {
        companyId: input.context.company.id,
        saleId: sale.id,
        eventType: 'sale_payment',
        localUuid,
        amountCents,
        paymentType: firstString(input.payload, ['paymentMethod', 'paymentType']),
        metadata: {
          source: 'operational_sync',
          receiptNumber: firstString(input.payload, ['receiptNumber']),
          eventId: input.event.eventId,
          sync: syncMetadataFor(input.event, input.payload),
        },
        createdAt: firstDate(input.payload, ['occurredAt', 'createdAt'], new Date()),
      },
    });

    return {
      outcome: 'accepted',
      entityServerId: created.id,
      materializedAt: created.updatedAt,
    };
  }
}
