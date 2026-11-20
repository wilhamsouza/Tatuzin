import assert from 'node:assert/strict';
import { it } from 'node:test';
import { summarizeExperience } from './experience-summary';

it('does not approve an empty or small pilot sample', () => {
  const report = { source: 'client_reported', timeBasis: 'receivedAt', since: '2026-11-13', steps: [] };
  assert.equal(summarizeExperience(report).checkout.status, 'insufficient_data');
  assert.equal(summarizeExperience({ ...report, steps: [{ name: 'checkout_completed', events: 4,
    companies: 1, attempts: 4, medianDurationMs: 1000 }] }).checkout.status, 'insufficient_data');
});

it('compares observed duration without claiming human validation or a sequential funnel', () => {
  for (const [median, status] of [[14999, 'within_target'], [15000, 'above_target']] as const) {
    const summary = summarizeExperience({ source: 'client_reported', timeBasis: 'receivedAt', since: '2026-11-13',
      steps: [{ name: 'checkout_completed', events: 5, companies: 1, attempts: 5, medianDurationMs: median }] });
    assert.equal(summary.checkout.status, status);
    assert.equal(summary.humanValidation, 'requires_five_observed_operator_sessions');
  }
});
