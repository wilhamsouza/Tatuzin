import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { sanitizeForAdmin } from './billing-sanitizer';

describe('billing admin sanitizer', () => {
  it('sanitizes recursively without breaking scalar values or dates', () => {
    const date = new Date('2026-05-07T12:00:00.000Z');
    const payload = {
      authorization: 'Bearer secret',
      apiToken: 'token-secret',
      checkoutUrl: 'https://mercadopago.test/checkout/full?token=secret',
      nested: [
        {
          card_number: '4111111111111111',
          createdAt: date,
          ok: true,
          count: 2,
          empty: null,
        },
      ],
    };

    const sanitized = sanitizeForAdmin(payload);

    assert.equal(sanitized.authorization, '[redacted]');
    assert.equal(sanitized.apiToken, '[redacted]');
    assert.match(
      sanitized.checkoutUrl,
      /^https:\/\/mercadopago\.test\/\.\.\.#/,
    );
    assert.equal(sanitized.nested[0]?.card_number, '[redacted]');
    assert.equal(sanitized.nested[0]?.createdAt, date);
    assert.equal(sanitized.nested[0]?.ok, true);
    assert.equal(sanitized.nested[0]?.count, 2);
    assert.equal(sanitized.nested[0]?.empty, null);
  });
});
