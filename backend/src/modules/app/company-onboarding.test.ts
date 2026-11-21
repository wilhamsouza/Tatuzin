import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import type { PrismaClient } from '@prisma/client';
import type { AppContext } from './app-context.types';
import { CompanyOnboardingService, isCompanyExperienceEnabled, isCompanyOnboardingEnabled } from './company-onboarding.service';
import { env } from '../../config/env';

describe('onboarding access and rollout', () => {
  it('enables only selected companies until the general rollout is enabled', () => {
    const original = {
      PRODUCT_ONBOARDING_ENABLED: env.PRODUCT_ONBOARDING_ENABLED,
      PRODUCT_ONBOARDING_COMPANY_IDS: env.PRODUCT_ONBOARDING_COMPANY_IDS,
      PRODUCT_EXPERIENCE_ENABLED: env.PRODUCT_EXPERIENCE_ENABLED,
      PRODUCT_EXPERIENCE_COMPANY_IDS: env.PRODUCT_EXPERIENCE_COMPANY_IDS,
    };
    try {
      env.PRODUCT_ONBOARDING_ENABLED = false;
      env.PRODUCT_EXPERIENCE_ENABLED = false;
      env.PRODUCT_ONBOARDING_COMPANY_IDS = 'internal, pilot';
      env.PRODUCT_EXPERIENCE_COMPANY_IDS = 'pilot';
      assert.equal(isCompanyOnboardingEnabled('internal'), true);
      assert.equal(isCompanyOnboardingEnabled('other'), false);
      assert.equal(isCompanyExperienceEnabled('internal'), false);
      assert.equal(isCompanyExperienceEnabled('pilot'), true);
      env.PRODUCT_EXPERIENCE_ENABLED = true;
      assert.equal(isCompanyExperienceEnabled('other'), true);
    } finally {
      Object.assign(env, original);
    }
  });
  it('does not touch storage when rollout is disabled', async () => {
    const service = new CompanyOnboardingService({} as PrismaClient, () => false);
    assert.deepEqual(await service.reconcile({ company: { id: 'company' }, membership: { role: 'OWNER' } } as AppContext),
      { enabled: false, productReady: false, cashReady: false, completedAt: null });
  });
  it('rejects non-owners before accessing storage', async () => {
    const service = new CompanyOnboardingService({} as PrismaClient, () => true);
    for (const role of ['ADMIN', 'OPERATOR']) {
      await assert.rejects(service.reconcile({ company: { id: 'company' }, membership: { role } } as AppContext),
        { code: 'ONBOARDING_FORBIDDEN', statusCode: 403 });
    }
  });
});
