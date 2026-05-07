import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  FEATURE_KEYS,
  getPlanEntitlements,
  normalizePlan,
} from './plan-catalog.service';

describe('plan catalog', () => {
  it('returns FREE, BASIC and PRO entitlements', () => {
    const free = getPlanEntitlements('FREE');
    assert.equal(free.plan, 'FREE');
    assert.equal(free.features.sales, true);
    assert.equal(free.features.products, true);
    assert.equal(free.features.reportsDaily, true);
    assert.equal(free.features.costs, false);
    assert.deepEqual(free.limits, {
      maxDevices: 1,
      maxEmployees: 0,
      reportPeriods: ['daily'],
    });

    const basic = getPlanEntitlements('BASIC');
    assert.equal(basic.plan, 'BASIC');
    assert.equal(basic.features.costs, true);
    assert.equal(basic.features.supplies, true);
    assert.equal(basic.features.fiadoManagement, true);
    assert.equal(basic.features.employees, false);
    assert.deepEqual(basic.limits, {
      maxDevices: 1,
      maxEmployees: 0,
      reportPeriods: ['daily', 'weekly', 'monthly'],
    });

    const pro = getPlanEntitlements('PRO');
    assert.equal(pro.plan, 'PRO');
    for (const feature of FEATURE_KEYS) {
      assert.equal(pro.features[feature], true, feature);
    }
    assert.deepEqual(pro.limits, {
      maxDevices: 100,
      maxEmployees: 100,
      reportPeriods: ['daily', 'weekly', 'monthly', 'yearly', 'custom'],
    });
  });

  it('normalizes lowercase and mixed-case plan values', () => {
    assert.equal(normalizePlan('free'), 'FREE');
    assert.equal(normalizePlan('Basic'), 'BASIC');
    assert.equal(normalizePlan('pRo'), 'PRO');
  });

  it('normalizes trial and unknown plan values to FREE', () => {
    assert.equal(normalizePlan('trial'), 'FREE');
    assert.equal(normalizePlan('enterprise'), 'FREE');
    assert.equal(normalizePlan(null), 'FREE');
  });
});
