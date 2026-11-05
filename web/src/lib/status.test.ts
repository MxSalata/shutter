import { describe, expect, it } from 'vitest';
import type { CaseSummary, Scenario } from '@/api/types';
import fixtures from '@/mocks/fixtures.json';
import { writesOf } from '@/mocks/handlers';
import {
  caseOutcome,
  caseState,
  checkCounts,
  checkState,
  disposition,
  DISPOSITIONS,
  expectationOf,
  gateOutcome,
  incidentOutcome,
  NOT_APPLICABLE_CODES,
  release,
  RELEASES,
  writes,
  type OutcomeCase,
} from './status';

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
    expect(checkState(check('pass', 'NOT_YET_REQUIRED'))).toBe('later');
    expect(checkState(check('block', 'SUPERSEDED_BY_LATER_EVENT'))).toBe('blocked');
    expect(checkState(check('unknown', ''))).toBe('unknown');
  });

  it("counts none of the gate's passes without a check as passed", () => {
    // Gate.cls: no write proposed, a later stage's check, no catalogue installed, no encounter to compare
    expect(NOT_APPLICABLE_CODES).toEqual([
      'NOT_APPLICABLE',
      'NOT_YET_REQUIRED',
      'NOT_CONFIGURED',
      'NO_ENCOUNTER',
    ]);
    for (const code of NOT_APPLICABLE_CODES)
      expect(checkState(check('pass', code))).toBe(code === 'NOT_YET_REQUIRED' ? 'later' : 'not_applicable');
    expect(checkState(check('pass', 'NEW_ENCOUNTER'))).toBe('passed');
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
    expect(checkCounts(checks)).toBe('2 passed, 1 checked later, 2 not applicable');
    expect(gateOutcome('block', [check('block', 'X'), check('unknown', '')])).toMatchObject({
      tone: 'blocking',
      label: 'Blocked',
      hint: '1 check blocked the write, 1 unknown',
    });
    expect(gateOutcome('unknown', [check('unknown', '')]).label).toBe('Unknown: write blocked');
  });
});

/** The recording's cases as the list sends them (writes and verification counted by the mock, as the API does). */
type Recorded = { summary: CaseSummary; attempts?: unknown[] };
const RECORDED = Object.values(fixtures.cases as unknown as Record<string, Recorded>).map((c) => ({
  ...c.summary,
  ...writesOf(c as never),
}));
const SCENARIOS = fixtures.scenarios as unknown as Scenario[];
const scenarioOf = (c: { scenario: string }) => SCENARIOS.find((s) => s.id === c.scenario);
const summary = (id: string) => RECORDED.find((c) => c.caseId === id)!;
const resolved = (over: Partial<OutcomeCase> = {}): OutcomeCase => ({
  state: 'resolved',
  disposition: 'resend',
  writes: 1,
  verification: 'verified',
  ...over,
});

describe('the case outcome, the first rule that matches', () => {
  it('gives every row its tone, its long words and its short ones', () => {
    const rows: [OutcomeCase, string, string, string][] = [
      [resolved({ disposition: 'handled_by_hand' }), 'neutral', 'Handled by hand', 'Handled by hand'],
      [{ state: 'blocked', disposition: 'abandoned' }, 'neutral', 'Abandoned', 'Abandoned'],
      [
        { state: 'awaiting_approval', disposition: 'resend' },
        'attention',
        'Waiting for approval',
        'Waiting for approval',
      ],
      [
        { state: 'escalated', disposition: 'escalate' },
        'attention',
        'Escalated: a person decides',
        'Escalated',
      ],
      [
        { state: 'blocked', disposition: 'resend', writes: 0 },
        'blocking',
        'Blocked: nothing sent',
        'Blocked',
      ],
      [{ state: 'blocked', disposition: 'resend' }, 'blocking', 'Blocked', 'Blocked'],
      [
        { state: 'blocked', disposition: 'resend', writes: 1 },
        'blocking',
        'Blocked: an earlier write went out',
        'Blocked',
      ],
      [{ state: 'failed', disposition: '' }, 'blocking', 'Failed', 'Failed'],
      [{ state: 'rehearsing', disposition: 'resend' }, 'info', 'Rehearsing', 'Rehearsing'],
      [
        resolved({ verification: 'not_committed' }),
        'blocking',
        "Didn't take effect at the receiver",
        "Didn't take effect",
      ],
      [
        resolved({ verification: 'failed' }),
        'blocking',
        'Contradiction at the receiver: a person must check',
        'Contradiction',
      ],
      [
        resolved({ verification: 'unresolved' }),
        'attention',
        "Couldn't verify at the receiver",
        "Couldn't verify",
      ],
      [resolved(), 'positive', 'Delivered: verified at the receiver', 'Delivered, verified'],
      [
        resolved({ writes: 0, disposition: 'superseded' }),
        'positive',
        'Nothing to send: verified at the receiver',
        'Nothing to send, verified',
      ],
      [
        resolved({ writes: 0, verification: '', disposition: 'reconcile' }),
        'neutral',
        'Nothing to send',
        'Nothing to send',
      ],
      [resolved({ writes: undefined, verification: undefined }), 'neutral', 'Resolved', 'Resolved'],
    ];
    for (const [c, tone, label, short] of rows)
      expect(caseOutcome(c), label).toMatchObject({ tone, label, short });
    // Row 15 says what it does not know
    expect(caseOutcome(resolved({ writes: undefined, verification: undefined })).hint).toBe(
      'Closed. The record does not say what was written or verified.',
    );
  });

  it("paints rules alone's S8 resend (C-000021) not as expected, however verified, never positive", () => {
    const c = summary('C-000021');
    expect(c).toMatchObject({ scenario: 'S8', mode: 'rules', writes: 1, verification: 'verified' });
    const outcome = caseOutcome(c, scenarioOf(c));
    expect(outcome).toMatchObject({
      tone: 'blocking',
      short: 'Not as expected',
      label: 'Not the expected outcome: S8 expects escalate',
    });
    // Without its scenario, a live install's view, it is a verified delivery
    expect(caseOutcome(c).short).toBe('Delivered, verified');
  });

  it('finds exactly one resolved case of the recording not as expected, and none of S11, S12 or S22', () => {
    const differs = RECORDED.filter((c) => expectationOf(c, scenarioOf(c)).kind === 'differs');
    expect(differs.map((c) => c.caseId)).toEqual(['C-000021']);
    for (const c of RECORDED.filter((x) => ['S11', 'S12', 'S22'].includes(x.scenario)))
      expect(caseOutcome(c, scenarioOf(c)).key, c.caseId).not.toBe('not-as-expected');
    for (const c of RECORDED.filter((x) => ['S11', 'S12'].includes(x.scenario)))
      expect(expectationOf(c, scenarioOf(c)).kind).toBe('unknown');
  });

  it("reads S20's blocked case as expected, and a Rules only S1 case as stopped by the gate", () => {
    const s20 = RECORDED.find((c) => c.scenario === 'S20' && c.state === 'blocked')!;
    expect(expectationOf(s20, scenarioOf(s20))).toMatchObject({ kind: 'as-expected', label: 'As expected' });
    const s1 = RECORDED.find((c) => c.scenario === 'S1' && c.mode === 'rules')!;
    expect(expectationOf(s1, scenarioOf(s1))).toMatchObject({
      kind: 'stopped',
      label: 'Stopped by the gate; S1 expects superseded',
    });
    // The gate catching a wrong proposal is never red beyond its Blocked badge
    expect(caseOutcome(s1, scenarioOf(s1)).short).toBe('Blocked');
  });

  it("takes S22's expectation from the case's receiver, and none while a case waits for approval", () => {
    const s22 = RECORDED.filter((c) => c.scenario === 'S22');
    expect(s22.map((c) => expectationOf(c, scenarioOf(c)).kind)).toEqual(['as-expected', 'as-expected']);
    expect(
      expectationOf({ state: 'awaiting_approval', disposition: 'resend' }, scenarioOf(summary('C-000002')))
        .kind,
    ).toBe('unknown');
    expect(expectationOf(summary('C-000002'))).toEqual({ kind: 'unknown', label: '' });
  });

  it('counts the recording as the trial shows it: every resolved case delivered or with nothing to send, verified', () => {
    const shorts = RECORDED.map((c) => caseOutcome(c, scenarioOf(c)).short);
    const count = (k: string) => shorts.filter((x) => x === k).length;
    expect(count('Resolved')).toBe(0);
    expect(count('Not as expected')).toBe(1);
    expect(count('Nothing to send, verified')).toBe(12);
    expect(count('Delivered, verified') + count('Not as expected')).toBe(28);
  });
});

describe('the other vocabularies', () => {
  it('gives each disposition its own icon', () => {
    const icons = Object.values(DISPOSITIONS).map((d) => d.icon);
    expect(new Set(icons).size).toBe(icons.length);
  });

  it('draws who releases a write: the policy information, a person attention, the board neutral', () => {
    expect(RELEASES.automatic).toMatchObject({ tone: 'info', label: "The site's written policy" });
    expect(RELEASES.approval).toMatchObject({ tone: 'attention', label: 'A person' });
    expect(RELEASES.per_chain).toMatchObject({ tone: 'attention', label: 'A person, per chain' });
    expect(RELEASES.board).toMatchObject({ tone: 'neutral', label: 'The board decides' });
    expect(release('other').tone).toBe('neutral');
  });

  it("reads an incident's outcome from its chains", () => {
    const byState = (s: Record<string, number>, state = 'closed') =>
      incidentOutcome({
        state: state as never,
        progress: { chains: Object.values(s).reduce((a, b) => a + b, 0), cases: 0, byKind: {}, byState: s },
      });
    expect(byState({ resolved: 6 })).toMatchObject({ tone: 'positive', label: 'All 6 chains verified' });
    expect(byState({ resolved: 3, stopped: 1 })).toMatchObject({ tone: 'blocking', label: '1 stopped' });
    expect(byState({ resolved: 3, escalated: 2 })).toMatchObject({ tone: 'attention', label: '2 escalated' });
    expect(byState({}, 'open')).toMatchObject({ tone: 'info', label: 'Taking cases' });
    for (const inc of Object.values(fixtures.incidents as unknown as Record<string, { summary: never }>))
      expect(incidentOutcome(inc.summary).label).not.toMatch(/\(s\)/);
  });
});
