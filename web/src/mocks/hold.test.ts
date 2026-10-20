import { describe, expect, it } from 'vitest';
import fixtures from './fixtures.json';
import { canHold, type CaseFixture } from './hold';

const recorded = fixtures.cases['C-000002'] as CaseFixture;

describe('canHold', () => {
  it('holds a recorded case that waited for its approval and was approved', () => {
    expect(canHold(recorded)).toBe(true);
  });

  it('leaves a case whose recording was rejected, since approving it would replay a blocked outcome', () => {
    const rejected = {
      ...recorded,
      events: recorded.events.map((e) =>
        e.kind === 'state' && e.fromState === 'awaiting_approval' ? { ...e, toState: 'blocked' } : e,
      ),
    } as CaseFixture;
    expect(canHold(rejected)).toBe(false);
  });

  it('leaves a case that never waited for an approver', () => {
    expect(canHold(fixtures.cases['C-000014'] as CaseFixture)).toBe(false);
    expect(canHold(undefined)).toBe(false);
  });
});
