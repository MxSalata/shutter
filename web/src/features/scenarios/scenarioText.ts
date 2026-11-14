import type { ScenarioStep } from '@/api/types';
import { cohortLabel, type PlayedResult, type Proof } from '@/lib/proof';

/** The page's lead, in the live system's words or the trial's, which plays recordings rather than into a production. */
export const SCENARIOS_LEAD = {
  live: 'Known HL7 failures to play into the production, and the case each one opened.',
  trial: 'Known message failures to play, and the case each one opened.',
  /** Where the user may not run them, nothing here says to play them. */
  lookOnly: 'Known HL7 failures, and the case each one opened.',
};

/**
 * Why Run is greyed out for someone who may not run scenarios, in words that fit what the user menu shows them: a sign-in
 * with the operator or approver badge (the public demo's viewer, which reads and approves) is told what it lacks, never
 * that it needs a role it seems to have; one with neither badge is told the role that runs them.
 */
export function runNeedsWords(badges: boolean): string {
  return badges
    ? 'This sign-in reads and approves, and does not run scenarios'
    : 'Running a scenario needs the operator or approver role';
}

/**
 * What a run from a sign-in without the live agents does (1.4.4, the online demo's account): its agents answer from their
 * recordings. Said once under the modes (execution.ts), in the Run buttons' tooltips and when the run starts or finishes.
 */
export const REPLAY_ONLY = {
  /** Of scenario runs only: a question to Ask Shutter says of its own answer whether it was recorded or live. */
  line: 'Scenario runs from this sign-in replay the recorded agents on this IRIS instance: no new inference, nothing is spent, and the case says it was replayed.',
  play: (id: string, mode: string) => `Play ${id} in ${mode} mode from its recordings`,
  started: 'replayed from the recordings',
  notRecorded: 'No recording to replay',
  notRecordedWhy: 'The single investigator has no recordings, and this sign-in replays recorded agents only',
};

/**
 * Why Reset is greyed out for someone who may not reset the shared demo: a judge runs scenarios and does not reset, since a
 * reset clears the demo for everyone signed in to it. As for Run, a sign-in that shows the operator or approver badge is
 * told what it lacks.
 */
export function resetNeedsWords(badges: boolean, canRun: boolean): string {
  if (!badges) return 'Resetting the shared demo needs the operator or approver role';
  return canRun
    ? 'This sign-in runs scenarios but does not reset the shared demo, which would clear it for everyone signed in'
    : 'This sign-in reads and approves, and does not reset the shared demo';
}

/**
 * How many scenarios Shutter defines (fixtures/scenarios.json; scenarioText.test checks the figure against it). The trial
 * lists only the ones with recordings, so it says how many of these it has and where the rest are.
 */
export const SCENARIOS_DEFINED = 37;

/**
 * The count beside "Every scenario": "37 in all.", or, in the trial's list of recordings when it is short of them, "26 of
 * the 37 scenarios have recordings here; the rest run on an install."
 */
export function scenarioCount(listed: number, trial: boolean, defined = SCENARIOS_DEFINED): string {
  return trial && listed < defined
    ? `${listed} of the ${defined} scenarios have recordings here; the rest run on an install.`
    : `${listed} in all.`;
}

/**
 * A scenario's description as the list shows it: its first sentence in full, and the rest behind "More about <id>",
 * never cut mid-sentence. The split is at the first full stop followed by a space, so a version number ("HL7 2.4
 * messages", "2.5.1.") stays whole.
 */
export function splitSummary(summary: string): { first: string; rest: string } {
  const text = summary.trim();
  const at = text.indexOf('. ');
  if (at < 0) return { first: text, rest: '' };
  return { first: text.slice(0, at + 1), rest: text.slice(at + 2).trim() };
}

/**
 * The HL7 events a scenario plays, in order, as an engineer reads them: each file's event ("A01"), marked where its
 * delivery is meant to fail or be withheld, and a run of the same event counted ("A02 ×4 fails"). From the steps'
 * own files and expectations, so nothing is guessed.
 */
export function hl7Events(steps: ScenarioStep[]): string {
  const runs: { event: string; mark: string; n: number }[] = [];
  for (const step of steps) {
    const event = /(A\d{2})\.hl7$/i.exec(step.file ?? '')?.[1]?.toUpperCase();
    if (!event) continue;
    const mark = step.expect === 'delivery_fails' ? ' fails' : step.expect === 'withheld' ? ' withheld' : '';
    const last = runs[runs.length - 1];
    if (last && last.event === event && last.mark === mark) last.n += 1;
    else runs.push({ event, mark, n: 1 });
  }
  return runs.map((r) => `${r.event}${r.n > 1 ? ` ×${r.n}` : ''}${r.mark}`).join(', ');
}

const BOARD_WORDS: Partial<Record<PlayedResult, string>> = {
  'as-expected': 'board as expected',
  differs: 'board not as expected',
};

const RULES_WORDS: Partial<Record<PlayedResult, string>> = {
  'as-expected': 'Rules only as expected',
  stopped: 'Rules only stopped by the gate',
  'wrote-wrongly': 'Rules only wrote, not as expected',
  differs: 'Rules only not as expected',
};

/**
 * What the evaluation recorded when the comparison played the scenario end to end (lib/proof.ts playedFor): "Recorded:
 * board as expected; Rules only stopped by the gate". Null for a scenario the comparison did not play.
 */
export function recordedLine(played: { board: PlayedResult; rules: PlayedResult } | null): string | null {
  if (!played) return null;
  const parts = [BOARD_WORDS[played.board], RULES_WORDS[played.rules]].filter(Boolean);
  return parts.length ? `Recorded: ${parts.join('; ')}` : null;
}

/** The proof line's parts, each left out when the evaluation cannot give its figures. */
export interface ProofParts {
  /**
   * The cohort and release both figures belong to, said before them: "Catalogue demonstration, recorded before release
   * 1.0.0" (lib/proof.ts reads the release from the runs' own dates).
   */
  cohort: string | null;
  /**
   * "Tested on 24 cases from 19 scenarios (an incident gives several), the board chose the expected action every
   * time." The unit is named, so the case count is not read as a count of scenarios; that the cases are recorded is the
   * cohort's word, before it.
   */
  tested: string | null;
  /** Played end to end on the one-failure scenarios: how many, the board's and Rules only's expected outcomes. */
  played: { of: number; board: number; rules: number } | null;
  /** The bases in an engineer's words, for Technical. */
  bases: string | null;
}

/** The proof line from the evaluation's figures, on one base per comparison (DESIGN principle 7). */
export function proofParts(
  proof: Pick<Proof, 'board' | 'played'> & Partial<Pick<Proof, 'recordedTo'>>,
): ProofParts {
  const { board, played } = proof;
  const tested = board
    ? `Tested on ${board.scored} cases${
        board.scenarios && board.scenarios < board.scored
          ? ` from ${board.scenarios} scenarios (an incident gives several)`
          : ''
      }, the board chose the expected action ${
        board.matched === board.scored ? 'every time' : `in ${board.matched} of them`
      }.`
    : null;
  const bases = [
    board ? `${board.scored} scored passes, proposed action` : null,
    played ? `${played.of} scenarios, played end to end` : null,
  ].filter(Boolean);
  return {
    cohort: board || played ? cohortLabel(proof) : null,
    tested,
    played: played ? { of: played.of, board: played.board, rules: played.rules } : null,
    bases: bases.length ? `(${bases.join('; ')})` : null,
  };
}
