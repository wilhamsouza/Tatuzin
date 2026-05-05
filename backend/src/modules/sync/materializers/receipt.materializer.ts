import { firstString, localIdentityFor } from './payload-utils';
import { SaleMaterializer } from './sale.materializer';
import type {
  SyncMaterializerInput,
  SyncMaterializerResult,
} from './materializer.types';

export class ReceiptMaterializer {
  constructor(private readonly saleMaterializer = new SaleMaterializer()) {}

  async materialize(
    input: SyncMaterializerInput,
  ): Promise<SyncMaterializerResult> {
    if (!['create', 'append', 'upsert'].includes(input.event.operation)) {
      return {
        outcome: 'rejected',
        code: 'INVALID_OPERATION',
        message: 'receipt aceita create, append ou upsert nesta etapa.',
      };
    }

    const receiptNumber =
      firstString(input.payload, ['receiptNumber', 'number']) ??
      localIdentityFor(input.event, input.payload);
    if (receiptNumber == null) {
      return {
        outcome: 'rejected',
        code: 'LOCAL_ID_REQUIRED',
        message: 'receipt precisa de receiptNumber ou entityLocalId.',
      };
    }

    const sale = await this.saleMaterializer.findSale(input);
    const existingReceiptOwner = await input.tx.sale.findFirst({
      where: {
        companyId: input.context.company.id,
        receiptNumber,
      },
      select: { id: true, localUuid: true },
    });

    if (existingReceiptOwner != null) {
      if (sale == null || existingReceiptOwner.id === sale.id) {
        return {
          outcome: 'duplicate',
          entityServerId: existingReceiptOwner.id,
        };
      }

      return {
        outcome: 'conflict',
        code: 'DUPLICATE_RECEIPT',
        message: 'Numero de comprovante ja pertence a outra venda.',
        payload: {
          receiptNumber,
          existingSaleId: existingReceiptOwner.id,
          requestedSaleId: sale.id,
        },
      };
    }

    if (sale == null) {
      return {
        outcome: 'conflict',
        code: 'SALE_NOT_FOUND',
        message: 'Venda nao encontrada para materializar comprovante.',
        payload: {
          receiptNumber,
          saleUuid: firstString(input.payload, ['saleUuid', 'saleLocalId']),
        },
      };
    }

    const updated = await input.tx.sale.update({
      where: { id: sale.id },
      data: { receiptNumber },
    });

    return {
      outcome: 'accepted',
      entityServerId: updated.id,
      materializedAt: updated.updatedAt,
    };
  }
}
