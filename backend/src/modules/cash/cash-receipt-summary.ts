/** Actual receipt ledger only; sales totals describe orders, never money received. */
export function cashReceiptSummary(sessions: Array<{
  sales: Array<{paymentType: string; totalAmountCents: number; financialEvents?: Array<{eventType: string}>}>;
  cashEvents: Array<{eventType: string; amountCents: number; paymentMethod: string|null}>;
}>) {
  const totals = new Map<string,{amountCents:number;count:number}>();
  let unavailableReason: string|null = null;
  for (const session of sessions) {
    const expectedImmediate = session.sales.filter(s=>s.paymentType !== 'fiado').reduce((sum,s)=>sum+s.totalAmountCents,0);
    const actualImmediate = session.cashEvents.filter(e=>['venda','sale'].includes(e.eventType)).reduce((sum,e)=>sum+Math.max(0,e.amountCents),0);
    if (expectedImmediate !== actualImmediate) unavailableReason = 'RECEIPT_LEDGER_INCOMPLETE';
    if (session.sales.some(s=>s.financialEvents?.some(e=>['sale_return_admin','sale_canceled_admin'].includes(e.eventType)))) unavailableReason = 'ADMIN_ACTION_RECEIPT_RECONCILIATION_REQUIRED';
    for (const event of session.cashEvents) {
      if (!['venda','sale','recebimento_fiado','fiadoReceipt','cancelamento','cancellation'].includes(event.eventType)) continue;
      const raw = event.paymentMethod?.trim().toLowerCase();
      const key = raw === 'cash' ? 'dinheiro' : raw === 'card' ? 'cartao' : raw === 'credit_card' ? 'cartao_credito' : raw === 'debit_card' ? 'cartao_debito' : raw;
      if (!key || !['dinheiro','pix','cartao','cartao_credito','cartao_debito','credit_card','debit_card'].includes(key)) {
        unavailableReason ??= 'RECEIPT_PAYMENT_METHOD_UNKNOWN'; continue;
      }
      const current = totals.get(key) ?? {amountCents:0,count:0};
      current.amountCents += event.amountCents;
      current.count += event.amountCents > 0 ? 1 : 0;
      totals.set(key,current);
    }
  }
  return {receiptBreakdownAvailable:unavailableReason == null,receiptBreakdownUnavailableReason:unavailableReason,byPaymentMethod:unavailableReason == null ? [...totals].map(([key,value])=>({key,...value})) : []};
}
