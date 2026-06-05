import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { describe, it } from 'node:test';
import type { Request, Response } from 'express';

import { requestContextMiddleware } from './request-context';
import { safeRequestPath, sanitizeUrlForLogging } from './request-url-sanitizer';

describe('request URL sanitizer', () => {
  it('uses request.path so request logs keep useful path without query', () => {
    const path = safeRequestPath({
      path: '/api/test',
      originalUrl: '/api/test?token=abc&signature=xyz&data.id=123',
      url: '/api/test?token=abc&signature=xyz&data.id=123',
    });

    assert.equal(path, '/api/test');
  });

  it('falls back to URL path without leaking query values', () => {
    const path = safeRequestPath({
      path: '',
      originalUrl:
        '/api/auth/reset?code=abc123&email=cliente@email.com&document=123',
      url: '/api/auth/reset?code=abc123&email=cliente@email.com&document=123',
    });

    assert.equal(path, '/api/auth/reset');
  });

  it('masks sensitive query keys when a sanitized query is explicitly needed', () => {
    const sanitized = sanitizeUrlForLogging(
      '/api/billing/webhook?data.id=999&signature=secret-value&external_reference=providerRef123&ok=1',
    );

    assert.equal(
      sanitized,
      '/api/billing/webhook?data.id=%5Bredacted%5D&signature=%5Bredacted%5D&external_reference=%5Bredacted%5D&ok=1',
    );
    assert.doesNotMatch(sanitized, /999|secret-value|providerRef123/);
  });

  it('masks token-like query keys in sync URLs', () => {
    const sanitized = sanitizeUrlForLogging(
      '/api/sync/pull?access_token=abc&companyId=123',
    );

    assert.equal(
      sanitized,
      '/api/sync/pull?access_token=%5Bredacted%5D&companyId=123',
    );
    assert.doesNotMatch(sanitized, /abc/);
  });

  it('keeps request context logs useful without logging query string values', () => {
    const logs: string[] = [];
    const originalLog = console.log;
    console.log = (line?: unknown) => {
      logs.push(String(line));
    };

    try {
      const request = {
        headers: {
          'user-agent': 'node-test',
        },
        method: 'GET',
        path: '/api/test',
        originalUrl: '/api/test?token=abc&signature=xyz&data.id=sensitive-data-id',
        url: '/api/test?token=abc&signature=xyz&data.id=sensitive-data-id',
        ip: '127.0.0.1',
      } as unknown as Request;
      const response = new EventEmitter() as Response & EventEmitter;
      response.locals = {};
      response.statusCode = 200;
      response.setHeader = () => response;

      requestContextMiddleware(request, response, () => undefined);
      response.emit('finish');

      assert.equal(logs.length, 1);
      const logged = JSON.parse(logs[0]!);
      assert.equal(logged.message, 'http.request.completed');
      assert.equal(logged.context.path, '/api/test');
      assert.doesNotMatch(
        logs[0]!,
        /abc|xyz|sensitive-data-id|token|signature|data\.id/,
      );
    } finally {
      console.log = originalLog;
    }
  });
});
