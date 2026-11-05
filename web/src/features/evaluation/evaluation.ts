import { playedResult, type PlayedResult } from '@/lib/proof';

/**
 * The evaluation of the board (docs/readme/evaluation.json and evaluation.md, both written by scripts/evaluate.py
 * from the recorded live runs, with no model calls), read at build time through Vite: the shapes the page uses, the
 * document's "Not yet measured" list, which the JSON does not carry, and the per-scenario table's filters.
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
  /** The receiver a pass was at, when it is not the production's default; "" otherwise */
  receiver?: string;
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
  /**
   * The case's outcome when the scenario was played end to end (comparison.md), by mode; rules alone's also says the
   * state it ended in and whether it wrote, when the document records them.
   */
  played: Record<string, { status: string; cost_usd: number | null; state?: string; wrote?: boolean }>;
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
    plans_with_a_catalogue_outcome?: number;
    plans_taking_the_preferred_outcome?: number;
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

/** "S7 pass 2", "S11 ENC-1103 transfer", "S22 Records Out": the pass as the evaluation names it. */
export function passName(p: EvaluationPass): string {
  const parts = [p.scenario];
  if (p.incident) parts.push(p.encounter, p.event);
  if (p.receiver) parts.push(p.receiver);
  if (p.rounds > 1) parts.push(`pass ${p.round}`);
  return parts.join(' ');
}

/** One key per pass, unique where two passes share a name (S23a's two encounters). */
export const passKey = (p: EvaluationPass) =>
  [p.scenario, p.encounter, p.event, p.receiver ?? '', p.round].join('|');

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
  return [board ? `Played by the board: ${board}` : '', rules ? `by Rules only: ${rules}` : '']
    .filter(Boolean)
    .join('; ');
}

/**
 * How a scored pass's scenario ended when it was played end to end: the board as expected or not, and rules alone as
 * expected, stopped by the gate with nothing written, written wrongly, or (an older document that does not say which)
 * not as expected; null for a pass that is not scored, whose case belongs to the next pass. The split is lib/proof.ts's,
 * the one the proof's figures use per scenario.
 */
export function passPlayed(p: EvaluationPass): { board: PlayedResult; rules: PlayedResult } | null {
  return p.scored ? playedResult(p.played) : null;
}

/** Whether rules alone ended otherwise than expected, whatever stopped it. */
export const rulesMissed = (r: PlayedResult) => r === 'differs' || r === 'stopped' || r === 'wrote-wrongly';

/** The specialists whose proposal the plan set aside, in a scored pass (a pass that is not scored marks none). */
export function outweighedIn(p: EvaluationPass): Specialist[] {
  if (!p.scored) return [];
  return SPECIALISTS.filter((s) => p.members[s] && p.members[s].disposition !== p.board_disposition);
}

/** Which specialists proposed the plan's action: the agreement's dots. */
export function proposedPlan(p: EvaluationPass): Record<Specialist, boolean> {
  return Object.fromEntries(
    SPECIALISTS.map((s) => [s, p.members[s]?.disposition === p.board_disposition]),
  ) as Record<Specialist, boolean>;
}

/** Whether the plan was not the scenario's expected action, in a scored pass. */
export const planDiffers = (p: EvaluationPass) =>
  p.scored && p.members.coordinator?.matches_expected === false;

export type Specialist = (typeof SPECIALISTS)[number];

/** The agreement levels in the evaluation's order, and each one's address form ("with-the-majority"). */
export const AGREEMENT_LEVELS = ['unanimous', 'with the majority', 'with a minority', 'against all three'];
export const agreementSlug = (level: string) => level.replace(/ /g, '-');

/**
 * The dots that stand for an agreement level in the Agreement card: the pattern most of that level's passes show (so
 * the usual dissenter shows), or, when no pass has it, the specialists in order filled up to the level's count.
 */
export function levelPattern(passes: EvaluationPass[], level: string): Record<Specialist, boolean> {
  const counts = new Map<string, number>();
  for (const p of passes.filter((q) => q.agreement === level)) {
    const key = SPECIALISTS.map((s) => (proposedPlan(p)[s] ? '1' : '0')).join('');
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  const top = [...counts.entries()].sort((a, b) => b[1] - a[1])[0]?.[0];
  const filled = 3 - Math.max(0, AGREEMENT_LEVELS.indexOf(level));
  const key = top ?? SPECIALISTS.map((_, i) => (i < filled ? '1' : '0')).join('');
  return Object.fromEntries(SPECIALISTS.map((s, i) => [s, key[i] === '1'])) as Record<Specialist, boolean>;
}

/** What the per-scenario table shows: one of the Show filters, who the cited entry says decides, who was outweighed. */
export interface PassFilters {
  show: string;
  decides: '' | 'policy' | 'board' | 'person';
  outweighed: '' | Specialist;
  sort: 'scenario' | 'cost' | 'elapsed';
}

/** The Show filters by their address form, each with its chip's words. */
export const SHOW_LABELS: Record<string, string> = {
  all: 'All',
  'rules-differs': 'Rules only not as expected',
  'not-unanimous': 'Not unanimous',
  'rules-stopped': 'Rules only stopped by the gate',
  'rules-wrote': 'Rules only wrote, not as expected',
  unanimous: 'Unanimous',
  'with-the-majority': 'With the majority',
  'with-a-minority': 'With a minority',
  'against-all-three': 'Against all three',
};
const DECIDES = ['policy', 'board', 'person'] as const;
const SORTS = ['scenario', 'cost', 'elapsed'] as const;

/** The table's filters from the address (`?show=rules-differs`, `?decides=board`, `?outweighed=conformance`). */
export function readFilters(params: URLSearchParams): PassFilters {
  const show = params.get('show') ?? '';
  const decides = params.get('decides') ?? '';
  const outweighed = params.get('outweighed') ?? '';
  const sort = params.get('sort') ?? '';
  return {
    show: show in SHOW_LABELS ? show : 'all',
    decides: (DECIDES as readonly string[]).includes(decides) ? (decides as PassFilters['decides']) : '',
    outweighed: (SPECIALISTS as readonly string[]).includes(outweighed) ? (outweighed as Specialist) : '',
    sort: (SORTS as readonly string[]).includes(sort) ? (sort as PassFilters['sort']) : 'scenario',
  };
}

/** Whether a pass passes the Show filter. */
function shows(p: EvaluationPass, show: string): boolean {
  const rules = passPlayed(p)?.rules;
  switch (show) {
    case 'all':
      return true;
    case 'rules-differs':
      return !!rules && rulesMissed(rules);
    case 'rules-stopped':
      return rules === 'stopped';
    case 'rules-wrote':
      return rules === 'wrote-wrongly';
    case 'not-unanimous':
      return p.agreement !== 'unanimous';
    default:
      return agreementSlug(p.agreement) === show;
  }
}

/** The passes the table shows, in the order it shows them: the document's (by scenario), or dearest or slowest first. */
export function filterPasses(passes: EvaluationPass[], f: PassFilters): EvaluationPass[] {
  const shown = passes.filter(
    (p) =>
      shows(p, f.show) &&
      (!f.decides || p.entry_decides === f.decides) &&
      (!f.outweighed || outweighedIn(p).includes(f.outweighed)),
  );
  if (f.sort === 'cost') return [...shown].sort((a, b) => b.cost_usd - a.cost_usd);
  if (f.sort === 'elapsed') return [...shown].sort((a, b) => b.elapsed_ms - a.elapsed_ms);
  return shown;
}

/**
 * A text's first sentence and the rest: the first stop that a space and a capital letter follow, so a file name
 * ("scenario_check.py") or a list inside the sentence does not end it.
 */
export function firstSentence(text: string): { first: string; rest: string } {
  const m = /^(.+?[.!?])\s+(?=[A-Z])(.*)$/s.exec(text.trim());
  return m ? { first: m[1], rest: m[2] } : { first: text.trim(), rest: '' };
}

/**
 * The comparison's cells (docs/readme/comparison.md), by scenario: what the board's run with the real agents and rules
 * alone each ended with, in the document's words, for the played marks' tooltips.
 */
export function comparisonCells(markdown: string): Record<string, { board: string; rules: string }> {
  const lines = markdown.split('\n').filter((l) => l.startsWith('|'));
  const head = lines[0]?.split('|').map((c) => c.trim()) ?? [];
  const boardAt = head.indexOf('Board, live');
  const rulesAt = head.indexOf('Rules only');
  const cells: Record<string, { board: string; rules: string }> = {};
  if (boardAt < 0 || rulesAt < 0) return cells;
  for (const line of lines.slice(1)) {
    const c = line.split('|').map((x) => x.trim().replace(/\*\*/g, ''));
    const id = /^(S\d+[a-z]?)\b/.exec(c[1] ?? '')?.[1];
    if (id && !cells[id]) cells[id] = { board: c[boardAt] ?? '', rules: c[rulesAt] ?? '' };
  }
  return cells;
}

const dayMonth = new Intl.DateTimeFormat('en-GB', { day: 'numeric', month: 'short', timeZone: 'UTC' });
const year = (d: Date) => d.getUTCFullYear();

/** "25 Oct to 1 Nov 2026" for the recordings' first and last days (UTC), "25 Oct 2026" for one day, "" for none. */
export function dayRange(from: string | null | undefined, to: string | null | undefined): string {
  if (!from) return '';
  const a = new Date(from);
  const b = new Date(to || from);
  const end = `${dayMonth.format(b)} ${year(b)}`;
  if (dayMonth.format(a) === dayMonth.format(b) && year(a) === year(b)) return end;
  return `${dayMonth.format(a)}${year(a) === year(b) ? '' : ` ${year(a)}`} to ${end}`;
}

const ORDINALS = [
  'first',
  'second',
  'third',
  'fourth',
  'fifth',
  'sixth',
  'seventh',
  'eighth',
  'ninth',
  'tenth',
];
/** "seventh"; a figure with "th" past ten. */
export const ordinal = (n: number) => ORDINALS[n - 1] ?? `${n}th`;

/** The list's "a, b and c" from a few parts. */
export const andList = (parts: string[]) => parts.join(', ').replace(/, ([^,]*)$/, ' and $1');
