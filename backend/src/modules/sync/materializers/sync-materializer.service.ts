import { CashMovementMaterializer } from './cash-movement.materializer';
import { CashSessionMaterializer } from './cash-session.materializer';
import type {
  SyncMaterializerInput,
  SyncMaterializerResult,
} from './materializer.types';
import { OperationalOrderMaterializer } from './operational-order.materializer';
import { PaymentMaterializer } from './payment.materializer';
import { ReceiptMaterializer } from './receipt.materializer';
import { SaleMaterializer } from './sale.materializer';
import { StockMaterializer } from './stock.materializer';

export class SyncMaterializerService {
  constructor(
    private readonly cashSessionMaterializer = new CashSessionMaterializer(),
    private readonly cashMovementMaterializer = new CashMovementMaterializer(),
    private readonly saleMaterializer = new SaleMaterializer(),
    private readonly paymentMaterializer = new PaymentMaterializer(
      saleMaterializer,
    ),
    private readonly receiptMaterializer = new ReceiptMaterializer(
      saleMaterializer,
    ),
    private readonly stockMaterializer = new StockMaterializer(
      saleMaterializer,
    ),
    private readonly operationalOrderMaterializer =
      new OperationalOrderMaterializer(),
  ) {}

  async materialize(
    input: SyncMaterializerInput,
  ): Promise<SyncMaterializerResult> {
    switch (input.event.entity) {
      case 'cashSession':
        return this.cashSessionMaterializer.materialize(input);
      case 'cashMovement':
        return this.cashMovementMaterializer.materialize(input);
      case 'sale':
        return this.saleMaterializer.materializeSale(input);
      case 'saleItem':
        return this.saleMaterializer.materializeSaleItem(input);
      case 'payment':
        return this.paymentMaterializer.materialize(input);
      case 'receipt':
        return this.receiptMaterializer.materialize(input);
      case 'stockReservation':
        return this.stockMaterializer.materializeReservation(input);
      case 'stockDeduction':
        return this.stockMaterializer.materializeDeduction(input);
      case 'operationalOrder':
      case 'operationalOrderItem':
      case 'offlineOperationLog':
        return this.operationalOrderMaterializer.materialize(input);
      default:
        return {
          outcome: 'rejected',
          code: 'ENTITY_NOT_LOCAL_FIRST',
          message:
            'Esta entidade nao faz parte do sync operacional local-first.',
        };
    }
  }
}
