import { describe, expect, it } from 'vitest';
import { caseState, checkCounts, checkState, disposition, gateOutcome, writes } from './status';

const check = (result: string, reason_code: string) => ({ result, reason_code });

describe('status', () => {
  it('keeps green for a passed check or a verified effect: an escalation needs a person, a resend is neutral', () => {
    expect(caseState('escalated').tone).toBe('attention');
    expect(caseState('blocked').tone).toBe('blocking');
    expect(caseState('resolved').tone).toBe('neutral');
    expect(disposition('resend').tone).toBe('neutral');
    expect(disposition('escalate').tone).toBe('attention');
    expect(writes(1)).toMatchObject({ tone: 'info', label: '1 write' });
    expect(writes(0)).toMatchObject({ tone: 'neutral', label: '0 writes' });
  });

  it('tells a passed check from one that does not apply, and an unknown from a block', () => {
    expect(checkState(check('pass', 'VERSION_MATCHES'))).toBe('passed');
    expect(checkState(check('pass', 'NOT_APPLICABLE'))).toBe('not_applicable');
    expect(checkState(check('pass', 'NOT_YET_REQUIRED'))).toBe('not_applicable');
    expect(checkState(check('block', 'SUPERSEDED_BY_LATER_EVENT'))).toBe('blocked');
    expect(checkState(check('unknown', ''))).toBe('unknown');
  });

  it('counts only the applicable checks as passed', () => {
    const checks = [
      check('pass', 'NO_WRITE'),
      check('pass', 'FRESH'),
      check('pass', 'NOT_APPLICABLE'),
      check('pass', 'NOT_APPLICABLE'),
      check('pass', 'NOT_YET_REQUIRED'),
    ];
    expect(gateOutcome('pass', checks)).toMatchObject({
      tone: 'positive',
      label: 'Passed 2 of 2 applicable checks',
    });
    expect(checkCounts(checks)).toBe('2 passed, 3 not applicable');
    expect(gateOutcome('block', [check('block', 'X'), check('unknown', '')])).toMatchObject({
      tone: 'blocking',
      label: 'Blocked',
      hint: '1 check blocked the write, 1 unknown',
    });
    expect(gateOutcome('unknown', [check('unknown', '')]).label).toBe('Unknown: write blocked');
  });
});
