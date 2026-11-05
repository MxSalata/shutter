import type { AgentRun } from '@/api/types';
import { asObject } from '@/lib/json';
import { SPECIALISTS } from '@/lib/hues';

/** A finding's structured result, from the run or the stored finding. */
export const resultOf = (run: AgentRun) => asObject(run.finding?.findings) ?? asObject(run.result) ?? {};

/** A finding's disposition, from its structured result or the stored finding. */
export function dispositionOf(run: AgentRun): string {
  const result = resultOf(run);
  return String(result.disposition ?? run.finding?.disposition ?? '');
}

/** One time the board sat: the specialists that read one snapshot, the last run of each, and its coordinator. */
export interface BoardRound {
  key: string;
  /** From 1, in the order the board sat. */
  number: number;
  specialists: AgentRun[];
  coordinator?: AgentRun;
}

/**
 * The board's sittings, oldest first. A new snapshot is a new sitting, as a case that the receiver moved under goes back
 * to the board on fresh evidence, and each sitting's plan and dissent are its own. A run with no snapshot belongs to the
 * sitting before it, so a store that does not carry the id reads as one sitting rather than as many.
 */
export function boardRounds(runs: AgentRun[]): BoardRound[] {
  const rounds: BoardRound[] = [];
  const byMember = new Map<BoardRound, Map<string, AgentRun>>();
  for (const run of runs) {
    if (run.role !== 'specialist' && run.role !== 'coordinator') continue;
    const snapshot = run.snapshotId === undefined || run.snapshotId === null ? '' : String(run.snapshotId);
    let round = snapshot ? rounds.find((r) => r.key === snapshot) : rounds.at(-1);
    if (!round) {
      round = { key: snapshot, number: rounds.length + 1, specialists: [] };
      rounds.push(round);
      byMember.set(round, new Map());
    }
    if (run.role === 'coordinator') round.coordinator = run;
    else byMember.get(round)!.set(run.memberCode, run);
  }
  for (const round of rounds) round.specialists = [...byMember.get(round)!.values()];
  return rounds;
}

/** The sitting the board's headline speaks for: the last with a plan, or the first still waiting for its own. */
export function latestRound(rounds: BoardRound[]): BoardRound | undefined {
  return rounds.findLast((r) => r.coordinator) ?? rounds.at(-1);
}

/** Whether a specialist gave a view: its run went through and it proposed something. A run with neither has no view. */
export const answered = (run: AgentRun) => (!run.status || run.status === 'ok') && !!dispositionOf(run);

/** How far the specialists of a sitting went with its plan. */
export interface Agreement {
  /** The specialists that gave a view. */
  answered: AgentRun[];
  /** The evaluation's words, which are about a board of three: empty unless exactly three gave a view. */
  word: '' | 'against all three' | 'with a minority' | 'with the majority' | 'unanimous';
  /** Whether each member proposed the plan's action, for the agreement's dots. */
  proposed: Record<(typeof SPECIALISTS)[number], boolean>;
}

/**
 * Two members agreeing is not a unanimous board, and a missing member is not a member against the plan: without three
 * views there is no agreement to name. That holds whatever kept a member away, a run that failed or a member switched
 * off in the library, which the runs alone cannot tell apart.
 */
export function agreementOf(round: BoardRound | undefined, planned: string): Agreement {
  const views = (round?.specialists ?? []).filter(answered);
  const agreed = views.filter((r) => dispositionOf(r) === planned).length;
  const words = ['against all three', 'with a minority', 'with the majority', 'unanimous'] as const;
  return {
    answered: views,
    word: views.length === 3 ? words[agreed] : '',
    proposed: Object.fromEntries(
      SPECIALISTS.map((m) => [m, views.some((r) => r.memberCode === m && dispositionOf(r) === planned)]),
    ) as Agreement['proposed'],
  };
}
