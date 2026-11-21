import assert from 'node:assert/strict';
import { test } from 'node:test';
import { cashReceiptSummary } from './cash-receipt-summary';
test('actual Pix, cash partial fiado and cancellation receipts; no sale double counting',()=>{
 const result=cashReceiptSummary([{sales:[{paymentType:'avista',totalAmountCents:1000},{paymentType:'fiado',totalAmountCents:5000}],cashEvents:[{eventType:'venda',amountCents:1000,paymentMethod:'pix'},{eventType:'cancelamento',amountCents:-1000,paymentMethod:'pix'},{eventType:'recebimento_fiado',amountCents:300,paymentMethod:'dinheiro'},{eventType:'suprimento',amountCents:200,paymentMethod:'dinheiro'}]}]);
 assert.equal(result.receiptBreakdownAvailable,true);
 assert.equal(result.byPaymentMethod.find(x=>x.key==='pix')?.amountCents,0);
 assert.equal(result.byPaymentMethod.find(x=>x.key==='dinheiro')?.amountCents,300);
});
test('missing receipts, unknown tenders and admin refunds report unavailable',()=>{
 for(const session of [
 {sales:[{paymentType:'avista',totalAmountCents:1000}],cashEvents:[]},
 {sales:[],cashEvents:[{eventType:'recebimento_fiado',amountCents:300,paymentMethod:null}]},
 {sales:[{paymentType:'fiado',totalAmountCents:5000,financialEvents:[{eventType:'sale_return_admin'}]}],cashEvents:[]},
 ]) { const result=cashReceiptSummary([session]);assert.equal(result.receiptBreakdownAvailable,false);assert.deepEqual(result.byPaymentMethod,[]); }
});
test('session mixes payment methods without inventing split tenders',()=>{
 const result=cashReceiptSummary([{sales:[{paymentType:'avista',totalAmountCents:500},{paymentType:'avista',totalAmountCents:700}],cashEvents:[{eventType:'venda',amountCents:500,paymentMethod:'pix'},{eventType:'venda',amountCents:700,paymentMethod:'cartao'}]}]);
 assert.equal(result.receiptBreakdownAvailable,true);assert.equal(result.byPaymentMethod.reduce((sum,x)=>sum+x.amountCents,0),1200);
});
