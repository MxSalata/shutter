import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { PrecedentSummary } from '@/api/types';
import { precedentSentence, precedentsOf, precedentWords, retiredBy } from './precedentWords';

const SOME: PrecedentSummary = {
  approved: 2,
  rejected: 0,
  lastDecision: 'approved',
  lastApprover: 'approver',
  lastAt: '2026-11-02T10:02:11Z',
  lastCaseId: 'C-000301',
  samePolicy: true,
  windowDays: 180,
  signature: 'sha256:ab',
};

describe('the precedents in words', () => {
  beforeEach(() => {
    vi.useFakeTimers({ now: new Date('2026-11-02T12:00:00Z'), toFake: ['Date'] });
  });
  afterEach(() => vi.useRealTimers());

  it('say what approvers decided here before, and who decided last, on which case', () => {
    expect(precedentSentence(SOME)).toBe(
      'Approved and verified 2 times, rejected 0 times here in the last 180 days; last approved by approver on 2 Nov (case C-000301).',
    );
    expect(precedentWords(SOME)).toMatchObject({ none: false, caseId: 'C-000301', tail: ').' });
  });

  it('say when the last decision was taken under an earlier policy', () => {
    expect(precedentSentence({ ...SOME, samePolicy: false })).toBe(
      'Approved and verified 2 times, rejected 0 times here in the last 180 days; last approved by approver on 2 Nov (case C-000301), under an earlier policy.',
    );
  });

  it('count one time as one, name a rejection, the window the site set and an earlier year', () => {
    expect(
      precedentSentence({
        ...SOME,
        approved: 1,
        rejected: 1,
        lastDecision: 'rejected',
        lastApprover: 'mx',
        lastAt: '2025-12-30T09:00:00Z',
        windowDays: 365,
      }),
    ).toBe(
      'Approved and verified 1 time, rejected 1 time here in the last 365 days; last rejected by mx on 30 Dec 2025 (case C-000301).',
    );
  });

  it('say so when no approver has seen these conditions here', () => {
    const none = { ...SOME, approved: 0, rejected: 0, lastDecision: '' as const, lastCaseId: '' };
    expect(precedentSentence(none)).toBe(
      'No approver has seen these conditions at this receiver in the last 180 days.',
    );
    expect(precedentWords(none).none).toBe(true);
  });

  it('never tell the approver what to do', () => {
    for (const p of [SOME, { ...SOME, samePolicy: false }, { ...SOME, approved: 0, rejected: 0 }])
      expect(precedentSentence(p)).not.toMatch(/recommend|should|suggest|approve it|safe to/i);
  });
});

describe('the precedents a snapshot carries', () => {
  it('are read from its summary', () => {
    expect(precedentsOf({ case_id: 'C-1', precedents: SOME })).toEqual(SOME);
  });

  it('are none to tell for a snapshot collected before them, or when the collector failed to read them', () => {
    expect(precedentsOf({ case_id: 'C-1' })).toBeNull();
    expect(precedentsOf({ precedents: { error: '<SQL ERROR>' } })).toBeNull();
    expect(precedentsOf(null)).toBeNull();
    expect(precedentsOf('{"precedents": {"approved": "x"}}')).toBeNull();
  });

  it("take the server's window when the summary does not name one", () => {
    expect(precedentsOf({ precedents: { ...SOME, windowDays: undefined } })?.windowDays).toBe(180);
  });
});

describe('who retired a precedent', () => {
  it("is read from the server's 409 detail", () => {
    expect(retiredBy('Precedent 7 was retired on 2026-11-02T10:00:00Z by approver')).toEqual({
      at: '2026-11-02T10:00:00Z',
      by: 'approver',
    });
    expect(retiredBy('Conflict')).toBeNull();
  });
});
