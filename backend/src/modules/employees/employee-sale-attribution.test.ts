import assert from 'node:assert/strict';
import { it } from 'node:test';
import { resolveSaleActorUserId } from './employee-sale-attribution';

const event = { userId: 'uploader', occurredAt: new Date('2026-05-20T10:00:00Z') };
it('keeps the recorded seller when the cashier and uploader differ', () => {
  assert.equal(resolveSaleActorUserId({ sellerUserId: 'seller', cashSession: { userId: 'cashier' } }, event), 'seller');
});
it('preserves the converted order seller attribution', () => {
  assert.equal(resolveSaleActorUserId({ sellerUserId: 'checkout-operator', convertedOperationalOrder: { sellerUserId: 'order-seller' } }, event), 'order-seller');
});
it('uses authenticated event authors for legacy sales before cash session owners', () => {
  assert.equal(resolveSaleActorUserId({ cashSession: { userId: 'cashier' } }, event), 'uploader');
});
it('retains cash session fallback for traceable older sales', () => {
  assert.equal(resolveSaleActorUserId({ cashSession: { userId: 'cashier' } }, null), 'cashier');
});
it('does not invent a seller for an untracked sale', () => {
  assert.equal(resolveSaleActorUserId({}, null), null);
});
