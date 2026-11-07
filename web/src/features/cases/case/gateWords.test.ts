import { describe, expect, it } from 'vitest';
import { gateFactLabel, laterChecksLine } from './gateWords';

const pass = (check: string) => ({ check, result: 'pass', reason_code: 'OK' });
const later = (check: string) => ({ check, result: 'pass', reason_code: 'NOT_YET_REQUIRED' });
const checks = [pass('identity'), later('authorization'), later('rehearsal')];

describe("the receipt's gate fact", () => {
  it('does not say Passed while checks of a later stage are still to come', () => {
    expect(gateFactLabel('pass', checks, 'awaiting_approval', false)).toBe('Eligible for approval');
  });

  it('says eligible only while an approval is awaited: a rejected or stopped case is past that', () => {
    expect(gateFactLabel('pass', checks, 'blocked', false)).toBe('Passed so far');
  });

  it('says Passed once nothing is left to check, and keeps the scope beside a plan that writes nothing', () => {
    expect(gateFactLabel('pass', [pass('identity')], 'resolved', false)).toBe('Passed');
    expect(gateFactLabel('pass', checks, 'escalated', true)).toBe('Passed: no write');
  });

  it('keeps a block and an unknown as they are', () => {
    expect(gateFactLabel('block', checks, 'blocked', false)).toBe('Blocked');
    expect(gateFactLabel('unknown', checks, 'blocked', false)).toBe('Unknown');
  });

  it('names the checks still to come, from the decision', () => {
    expect(laterChecksLine(checks)).toBe('Checked at dispatch: authorization, rehearsal.');
    expect(laterChecksLine([pass('identity')])).toBe('');
  });
});
