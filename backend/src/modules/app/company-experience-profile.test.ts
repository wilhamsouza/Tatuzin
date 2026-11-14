import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { companyReceiptSettingsPatchSchema } from './company-settings.schemas';
import { CompanySettingsService } from './company-settings.service';
import type { AppContext } from './app-context.types';
import { AppError } from '../../shared/http/app-error';

describe('company experience profile', () => {
  it('accepts all supported profiles and preserves legacy patches', () => {
    for (const experienceProfile of ['moda', 'alimentacao', 'misto']) {
      assert.equal(companyReceiptSettingsPatchSchema.parse({ experienceProfile }).experienceProfile, experienceProfile);
    }
    assert.deepEqual(companyReceiptSettingsPatchSchema.parse({ receiptPhone: '123' }), { receiptPhone: '123' });
    assert.equal(companyReceiptSettingsPatchSchema.safeParse({ experienceProfile: 'unknown' }).success, false);
    assert.equal(companyReceiptSettingsPatchSchema.safeParse({ experienceProfile: null }).success, false);
  });

  it('rejects profile changes by administrators and employees before database access', async () => {
    const service = new CompanySettingsService();
    for (const role of ['ADMIN', 'EMPLOYEE']) {
      await assert.rejects(
        service.updateReceiptSettings({ membership: { role } } as AppContext, { experienceProfile: 'moda' }),
        (error: unknown) => error instanceof AppError &&
          error.statusCode === 403 && error.code === 'COMPANY_SETTINGS_FORBIDDEN',
      );
    }
  });
});
