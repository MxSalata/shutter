import { describe, expect, it } from 'vitest';
import type { AgentRun } from '@/api/types';
import fixtures from '@/mocks/fixtures.json';
import { agreementOf, answered, boardRounds, latestRound } from './boardRounds';

const run = (
  role: string,
  memberCode: string,
  snapshotId: unknown,
  disposition?: string,
  status = 'ok',
): AgentRun => ({ role, memberCode, snapshotId, status, result: { disposition } }) as unknown as AgentRun;

const board = (snapshot: unknown, plan: string, ...views: [string, string][]) => [
  ...views.map(([m, d]) => run('specialist', m, snapshot, d)),
  run('coordinator', 'coordinator', snapshot, plan),
];

describe('boardRounds', () => {
  it("reads C-000007's two sittings apart, each with three specialists and its own plan", () => {
    const rounds = boardRounds(fixtures.cases['C-000007'].runs as unknown as AgentRun[]);
    expect(rounds.map((r) => r.specialists.map((s) => s.memberCode))).toEqual([
      ['conformance', 'encounter', 'impact'],
      ['conformance', 'encounter', 'impact'],
    ]);
    expect(rounds.map((r) => (r.coordinator?.result as { disposition: string }).disposition)).toEqual([
      'resend',
      'superseded',
    ]);
  });

  it('keeps the last run of a member that ran twice on one snapshot', () => {
    const rounds = boardRounds([
      run('specialist', 'impact', 1, 'resend'),
      run('specialist', 'impact', 1, 'escalate'),
    ]);
    expect(rounds).toHaveLength(1);
    expect((rounds[0].specialists[0].result as { disposition: string }).disposition).toBe('escalate');
  });

  it('reads runs with no snapshot as one sitting', () => {
    const rounds = boardRounds(board(undefined, 'resend', ['conformance', 'resend'], ['impact', 'resend']));
    expect(rounds).toHaveLength(1);
    expect(rounds[0].specialists).toHaveLength(2);
    expect(rounds[0].coordinator).toBeDefined();
  });

  it('leaves out runs that are not the board', () => {
    expect(boardRounds([run('generalist', 'generalist', 1, 'resend')])).toEqual([]);
  });

  it('speaks for the last sitting with a plan while a newer one has none yet', () => {
    const rounds = boardRounds([
      ...board(1, 'resend', ['conformance', 'resend']),
      run('specialist', 'conformance', 2, 'resend'),
    ]);
    expect(rounds).toHaveLength(2);
    expect(latestRound(rounds)?.number).toBe(1);
  });
});

describe('agreementOf', () => {
  const three: [string, string][] = [
    ['conformance', 'resend'],
    ['encounter', 'resend'],
    ['impact', 'resend'],
  ];
  const round = (views: [string, string][]) => boardRounds(board(1, 'resend', ...views))[0];

  it('names the agreement of three views', () => {
    expect(agreementOf(round(three), 'resend').word).toBe('unanimous');
    expect(agreementOf(round(three), 'escalate').word).toBe('against all three');
    expect(agreementOf(round([three[0], three[1], ['impact', 'escalate']]), 'resend').word).toBe(
      'with the majority',
    );
  });

  it('names none with two views, whether a member timed out or was switched off', () => {
    const a = agreementOf(round(three.slice(0, 2)), 'resend');
    expect(a.word).toBe('');
    expect(a.answered).toHaveLength(2);
  });

  it('counts a run with no answer as no view, not as a member against the plan', () => {
    const failed = run('specialist', 'impact', 1, undefined, 'no_record');
    const r = boardRounds([...board(1, 'resend', three[0], three[1]), failed])[0];
    expect(r.specialists).toHaveLength(3);
    expect(answered(failed)).toBe(false);
    const a = agreementOf(r, 'resend');
    expect(a.word).toBe('');
    expect(a.answered).toHaveLength(2);
    expect(a.proposed.impact).toBe(false);
  });

  it('does not take a failed run with a stale disposition as a view', () => {
    expect(answered(run('specialist', 'impact', 1, 'resend', 'failed'))).toBe(false);
  });

  it('names none for a site with a fourth specialist, whose agreement the three-way words do not cover', () => {
    const four = round([...three, ['extra', 'resend']]);
    expect(agreementOf(four, 'resend').word).toBe('');
    expect(agreementOf(four, 'resend').answered).toHaveLength(4);
  });
});
