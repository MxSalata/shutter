import { describe, expect, it } from 'vitest';
import type { AttemptView, CaseDetail, CaseSummary, Closure, PlanView, Snapshot } from '@/api/types';
import fixtures from '@/mocks/fixtures.json';
import { compareSide, evidenceRows, playedMark, s8Pair } from './compare';
import { playedFor } from '@/lib/proof';

function sideOf(id: 'C-000008' | 'C-000021') {
  const x = fixtures.cases[id];
  return compareSide({
    c: x.detail as unknown as CaseDetail,
    plan: x.plan as unknown as PlanView,
    attempts: x.attempts as unknown as AttemptView[],
    closure: x.closure as unknown as Closure,
    snapshot: x.snapshot as unknown as Snapshot,
  });
}

describe('s8Pair', () => {
  it("finds the latest S8 case of each mode, and nothing for a mode S8 wasn't played in", () => {
    const all = Object.values(fixtures.cases).map((x) => x.summary as unknown as CaseSummary);
    const { rules, board } = s8Pair(all);
    expect(rules?.caseId).toBe('C-000021');
    expect(board?.caseId).toBe('C-000008');
    const newer = { ...board!, caseId: 'C-000099', openedAt: '2026-11-03T00:00:00Z' };
    expect(s8Pair([...all, newer]).board?.caseId).toBe('C-000099');
    expect(s8Pair(all.filter((c) => c.mode !== 'rules')).rules).toBeUndefined();
  });
});

describe('compareSide', () => {
  it('says what rules alone wrote over the bed manager', () => {
    const r = sideOf('C-000021');
    expect(r.result).toBe('Wrote WARD-B over WARD-C: version 2 to 3');
    expect(r.writes).toBe(1);
    expect(r.verification).toMatch(/^Verified: /);
    expect(r.patient).toBe("Patient ends in WARD-B, over the bed manager's WARD-C");
    expect(r.outcome).toMatchObject({
      state: 'resolved',
      writes: 1,
      verification: 'verified',
      mode: 'rules',
    });
  });

  it("says the board escalated citing E7, wrote nothing and kept the conformance member's dissent", () => {
    const b = sideOf('C-000008');
    expect(b.result).toBe('Escalate, citing E7; no write');
    expect(b.writes).toBe(0);
    expect(b.dissent).toMatch(/^Conformance said resend/);
    expect(b.patient).toBe('Patient stays in WARD-C; a person decides');
  });

  it('claims nothing about the patient when a write went out and none is confirmed', () => {
    const x = fixtures.cases['C-000021'];
    const attempt = x.attempts[0];
    const unconfirmed = compareSide({
      c: x.detail as unknown as CaseDetail,
      plan: x.plan as unknown as PlanView,
      attempts: [
        { ...attempt, attempt: { ...attempt.attempt, outcome: 'uncertain', receipt: null } },
      ] as unknown as AttemptView[],
      closure: null,
      snapshot: x.snapshot as unknown as Snapshot,
    });
    expect(unconfirmed.patient).toBe('');
  });
});

describe('evidenceRows', () => {
  it('reads the shared facts the same and the digests apart', () => {
    const rows = evidenceRows(sideOf('C-000021').evidence, sideOf('C-000008').evidence);
    const row = (label: string) => rows.find((r) => r.label === label)!;
    expect(row('The failed delivery')).toMatchObject({ same: true });
    expect(row('The failed delivery').rules).toMatch(
      /^PAS transfer to WARD-B at .*: unavailable \(HTTP 503\)$/,
    );
    expect(row('Another movement at the same time')).toMatchObject({ same: true });
    expect(row('Another movement at the same time').board).toMatch(/^BEDMGR transfer to WARD-C .*version 2$/);
    expect(row('The receiver when observed')).toMatchObject({ rules: 'WARD-C at version 2', same: true });
    expect(row('Receipt for the failed operation')).toMatchObject({
      rules: 'none: never committed',
      same: true,
    });
    expect(row('Later events')).toMatchObject({ rules: '0', same: true });
    expect(row('Snapshot digest').same).toBe(false);
    expect(row('Material digest').same).toBe(false);
    expect(row('Evidence taken').same).toBe(false);
  });

  it('is empty until both sides have evidence', () => {
    expect(evidenceRows(sideOf('C-000021').evidence, null)).toEqual([]);
  });
});

describe('playedMark', () => {
  it("marks S8 as the evaluation scored it: the board as expected, rules alone's write as differing", () => {
    const s8 = playedFor('S8');
    expect(playedMark('board', s8?.board)).toEqual({ label: 'Board: as expected', tone: 'positive' });
    expect(playedMark('rules', s8?.rules, 'WARD-B')).toEqual({
      label: 'Rules only: differs, wrote WARD-B',
      tone: 'blocking',
    });
  });

  it('marks a stop by the gate neutral, and nothing for a mode that did not play', () => {
    expect(playedMark('rules', 'stopped')).toEqual({
      label: 'Rules only: stopped by the gate, nothing written',
      tone: 'neutral',
    });
    expect(playedMark('board', 'not-played')).toBeNull();
    expect(playedMark('board', null)).toBeNull();
  });
});
