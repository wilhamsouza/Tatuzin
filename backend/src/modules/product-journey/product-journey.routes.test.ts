import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';
import express from 'express';
import { errorHandler } from '../../shared/http/error-handler';
import { productJourneyRouter, productJourneyAdminRouter } from './product-journey.routes';

describe('product journey HTTP access', () => {
  let server: Server;
  let base: string;
  before(() => {
    const app = express();
    app.use(express.json());
    app.use('/api/product-journey', productJourneyRouter);
    app.use('/api/admin/product-journey', productJourneyAdminRouter);
    app.use(errorHandler);
    server = app.listen(0, '127.0.0.1');
    return new Promise<void>((resolve) => server.once('listening', () => {
      base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
      resolve();
    }));
  });
  after(() => new Promise<void>((resolve, reject) => server.close((error) => error ? reject(error) : resolve())));

  it('requires authentication before accepting any client events', async () => {
    const response = await fetch(`${base}/api/product-journey/events`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}',
    });
    assert.equal(response.status, 401);
    assert.equal((await response.json() as { code: string }).code, 'AUTH_REQUIRED');
  });

  it('does not expose the aggregate report publicly', async () => {
    const response = await fetch(`${base}/api/admin/product-journey/report`);
    assert.equal(response.status, 401);
  });
});
