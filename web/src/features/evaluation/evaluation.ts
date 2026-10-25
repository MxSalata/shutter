/**
 * The evaluation of the board (docs/readme/evaluation.json and evaluation.md, both written by scripts/evaluate.py
 * from the recorded live runs, with no model calls), read at build time through Vite: the shapes the page uses, and
 * the document's "Not yet measured" list, which the JSON does not carry.
 */
export interface EvaluationMember {
  disposition: string;
  /** The specialist's own confidence, 0 to 1; the coordinator's plan carries none. */
  confidence: number | null;
  /** Null when the scenario names no expected disposition. */
  matches_expected: boolean | null;
  model: string;
  duration_ms: number;
  prompt_tokens: number;
  completion_tokens: number;
  cache_read_tokens: number;
  cache_write_tokens: number;
  tool_calls: number;
  cost_usd: number;
}

/** One board decision on one case: the three specialists, then the coordinator's plan. */
export interface EvaluationPass {
  scenario: string;
  title: string;
  encounter: string;
  event: string;
  round: number;
  rounds: number;
  incident: boolean;
  /** Whether the pass is scored against the expected outcome (S7's first pass is not: it was planned again). */
  scored: boolean;
  /** The scenario's expected disposition and where it comes from (an incident's case: the entry matched in its evidence). */
  expected: { disposition: string; acceptable?: string[]; from?: string };
  members: Record<string, EvaluationMember>;
  catalogue_entry: string;
  entry_decides: string;
  /** The plan's disposition: the coordinator's. */
  board_disposition: string;
  /** unanimous, with the majority, with a minority, against all three. */
  agreement: string;
  runs: number;
  prompt_tokens: number;
  completion_tokens: number;
  cache_read_tokens: number;
  cache_write_tokens: number;
  cost_usd: number;
  /** From the first specialist's start to the coordinator's plan; agent_ms adds the four runs' own durations. */
  elapsed_ms: number;
  agent_ms: number;
  /** The case's outcome when the scenario was played end to end (comparison.md), by mode. */
  played: Record<string, { status: string; cost_usd: number | null }>;
}

/** One group of the specialists' confidence; an empty group has its count alone. */
export interface EvaluationConfidence {
  n: number;
  min?: number;
  mean?: number;
  max?: number;
}

export interface Evaluation {
  sources: Record<string, string>;
  prices_per_million: Record<
    string,
    { input: number; output: number; cache_read: number; cache_write: number }
  >;
  passes: EvaluationPass[];
  without_board: { scenario: string; title: string; why: string }[];
  totals: {
    runs: number;
    passes: number;
    cases: number;
    scenarios: number;
    prompt_tokens: number;
    completion_tokens: number;
    cache_read_tokens: number;
    cache_write_tokens: number;
    cost_usd: number;
    agent_ms: number;
    models: string[];
    /** The first and last runs' start, or "" when there are no recordings. */
    recorded_from: string;
    recorded_to: string;
    scored_passes: number;
    board_matches: number;
    specialist_matches: Record<string, number>;
    agreement: Record<string, number>;
    confidence: Record<string, EvaluationConfidence>;
  };
}

/**
 * What tests/e2e/boundary_check.py tries against the approval boundary (docs/readme/boundary.json, which the script
 * writes from its own list with --write-list, and CI checks with --check-list).
 */
export interface BoundaryChecks {
  script: string;
  runs: string;
  checks: { id: string; title: string; scenario: string; answer: string; proves: string }[];
}

/** The specialists in the order the board runs them; the coordinator's plan follows. */
export const SPECIALISTS = ['conformance', 'encounter', 'impact'] as const;

/**
 * The document's "Not yet measured" list: the bullet points under that heading, up to the next heading, each as its
 * bold lead and the rest of its text (inline code marks dropped).
 */
export function notYetMeasured(markdown: string): { title: string; text: string }[] {
  const lines = markdown.split('\n');
  const start = lines.findIndex((l) => /^##\s+Not yet measured\s*$/.test(l));
  if (start < 0) return [];
  const items: string[] = [];
  for (const line of lines.slice(start + 1)) {
    if (/^#{1,6}\s/.test(line)) break;
    if (line.startsWith('- ')) items.push(line.slice(2).trim());
    else if (items.length && line.trim()) items[items.length - 1] += ` ${line.trim()}`;
  }
  return items.map((item) => {
    const plain = item.replace(/`/g, '');
    const m = /^\*\*(.+?)\*\*\s*(.*)$/.exec(plain);
    return m ? { title: m[1], text: m[2] } : { title: '', text: plain };
  });
}

/** "S7 pass 2", "S11 ENC-1103 transfer": the pass as the evaluation names it. */
export function passName(p: EvaluationPass): string {
  const parts = [p.scenario];
  if (p.incident) parts.push(p.encounter, p.event);
  if (p.rounds > 1) parts.push(`pass ${p.round}`);
  return parts.join(' ');
}

/** A played outcome that was compared with the expected one: as expected or not. */
const compared = (status: string | undefined) => status === 'as expected' || status === 'differs';

/**
 * How often a way of playing (`rules`, `board_live`) ended as expected end to end, over the scored passes that were
 * played the way `over` names (by default the same way), so two ways can be set side by side on one set of passes.
 */
export function played(data: Evaluation, how: string, over = how): { matches: number; of: number } {
  const passes = data.passes.filter((p) => p.scored && compared(p.played?.[over]?.status));
  return {
    matches: passes.filter((p) => p.played?.[how]?.status === 'as expected').length,
    of: passes.length,
  };
}

/** The pass's played outcomes in words, for the plan's cell: the board's live run and rules alone. */
export function playedLine(p: EvaluationPass): string {
  // A pass that is not scored was planned again: the case's outcome belongs to its last pass
  if (!p.scored) return '';
  const words = (st: string | undefined) =>
    st === 'as expected' ? 'as expected' : st === 'differs' ? 'not as expected' : '';
  const board = words(p.played?.board_live?.status);
  const rules = words(p.played?.rules?.status);
  return [board ? `Played by the board: ${board}` : '', rules ? `by rules alone: ${rules}` : '']
    .filter(Boolean)
    .join('; ');
}
