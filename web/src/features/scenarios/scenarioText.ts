import type { ScenarioStep } from '@/api/types';
import type { PlayedResult, Proof } from '@/lib/proof';

/** The page's lead, in the live system's words or the trial's, which plays recordings rather than into a production. */
export const SCENARIOS_LEAD = {
  live: 'Known HL7 failures to play into the production, and the case each one opened.',
  trial: 'Known message failures to play, and the case each one opened.',
  /** Where the user may not run them, nothing here says to play them. */
  lookOnly: 'Known HL7 failures, and the case each one opened.',
};

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
  /** "Tested on 24 recorded failures, the board chose the expected action every time." */
  tested: string | null;
  /** Played end to end on the same failures: how many, the board's and Rules only's expected outcomes. */
  played: { of: number; board: number; rules: number; ofThem: boolean } | null;
  /** The bases in an engineer's words, for Technical. */
  bases: string | null;
}

/** The proof line from the evaluation's figures, on one base per comparison (DESIGN principle 7). */
export function proofParts(proof: Pick<Proof, 'board' | 'played'>): ProofParts {
  const { board, played } = proof;
  const tested = board
    ? `Tested on ${board.scored} recorded failures, the board chose the expected action ${
        board.matched === board.scored ? 'every time' : `in ${board.matched} of them`
      }.`
    : null;
  const bases = [
    board ? `${board.scored} scored passes, proposed action` : null,
    played ? `${played.of} scenarios, played end to end` : null,
  ].filter(Boolean);
  return {
    tested,
    played: played ? { of: played.of, board: played.board, rules: played.rules, ofThem: !!board } : null,
    bases: bases.length ? `(${bases.join('; ')})` : null,
  };
}
