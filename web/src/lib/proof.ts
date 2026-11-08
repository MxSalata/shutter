import slice from '../../../docs/readme/evaluation.json?proof';

/**
 * The proof's figures, computed from the board's evaluation (docs/readme/evaluation.json, written by
 * scripts/evaluate.py from the runs recorded with the real agents), never typed: the board's proposals (24 of 24),
 * the comparison played end to end on one base (the board 11, Rules only 4, of the same 11 failures), rules alone's
 * misses split into the ones the gate stopped and the one that wrote, who the cited entries say decides, the cost of a
 * pass, and where and when the runs were recorded. The pages read this module, not the document: it imports a small
 * slice (`?proof`, vite.config.ts), so a page that shows a figure does not carry the whole evaluation.
 *
 * A figure the document cannot give (an older evaluation.json) is null, and the sentence that would say it is left
 * out.
 */

/** A played outcome as the comparison table gives it (docs/readme/comparison.md). */
export interface ProofPlayed {
  status?: string;
  cost_usd?: number | null;
  /** Rules alone only: the state the case ended in (blocked, resolved or escalated). */
  state?: string;
  /** Rules alone only: whether it wrote to the receiving system. */
  wrote?: boolean;
}

/** One pass as the slice carries it. */
export interface ProofPass {
  scenario: string;
  incident?: boolean;
  scored?: boolean;
  complete?: boolean;
  round?: number;
  rounds?: number;
  entry_decides?: string | null;
  board_disposition?: string;
  agreement?: string;
  cost_usd?: number | null;
  played?: { board_live?: ProofPlayed; board_replay?: ProofPlayed; rules?: ProofPlayed };
}

/** The slice of evaluation.json this module reads. */
export interface ProofSource {
  sources: { recorded_on?: string; prices_as_of?: string; [k: string]: unknown };
  totals: {
    runs?: number;
    passes?: number;
    cases?: number;
    scenarios?: number;
    scored_passes?: number;
    board_matches?: number;
    specialist_matches?: Record<string, number>;
    cost_usd?: number;
    models?: string[];
    recorded_from?: string;
    recorded_to?: string;
    agreement?: Record<string, number>;
    prompt_tokens?: number;
    completion_tokens?: number;
    cache_read_tokens?: number;
    [k: string]: unknown;
  };
  passes: ProofPass[];
}

/** How a scenario ended when it was played end to end: as expected, stopped by the gate, written wrongly, or not. */
export type PlayedResult = 'as-expected' | 'differs' | 'stopped' | 'wrote-wrongly' | 'not-played';

export interface Proof {
  /** The board's proposals: the scored passes whose plan proposed the scenario's expected action, of the scored. */
  board: {
    matched: number;
    scored: number;
    passes: number;
    cases: number;
    notScored: number;
    /** How many scenarios the scored cases come from (an incident gives several cases), when the evaluation says. */
    scenarios?: number;
  } | null;
  /** The specialists alone, each against the same scored passes: who proposed the expected action. */
  specialists: { conformance: number; encounter: number; impact: number } | null;
  /** Played end to end on the same failures (the single cases the board was convened for): the board, Rules only. */
  played: { of: number; board: number; rules: number; scenarios: string[] } | null;
  /** Rules only's misses among those: stopped by the gate with nothing written, and written wrongly. */
  rulesMisses: { total: number; stopped: string[]; wrote: string[] } | null;
  /** Who the entry the plan cited says decides, over the scored passes: the site's policy, the board, a person. */
  entryDecides: { policy: number; board: number; person: number; of: number } | null;
  /** The cheapest and the dearest board pass, at list prices, in US dollars. */
  costPerPass: { min: number; max: number } | null;
  /** The agreement of the specialists with the plan, by level (unanimous, with the majority, ...). */
  agreement: Record<string, number> | null;
  runs: number | null;
  /** What the recorded runs cost in all, at list prices, in US dollars. */
  totalUsd: number | null;
  recordedFrom: string | null;
  recordedTo: string | null;
  /** The AI Hub image the runs were recorded on, its build, and the build's number ("154"). */
  recordedOn: { image: string; build: string; number: string | null } | null;
  /** The model ids the runs used. */
  models: string[];
  /** Each played scenario's results, by its id. */
  playedBy: Record<string, { board: PlayedResult; rules: PlayedResult }>;
}

const num = (v: unknown): number | null => (typeof v === 'number' && Number.isFinite(v) ? v : null);

/** The board's played result from the comparison's status. */
export function boardResult(p: ProofPlayed | undefined): PlayedResult {
  if (p?.status === 'as expected') return 'as-expected';
  if (p?.status === 'differs') return 'differs';
  return 'not-played';
}

/** Rules only's played result: a miss split by whether the gate stopped it or it wrote. */
export function rulesResult(p: ProofPlayed | undefined): PlayedResult {
  if (p?.status === 'as expected') return 'as-expected';
  if (p?.status !== 'differs') return 'not-played';
  if (p.wrote === true) return 'wrote-wrongly';
  if (p.state === 'blocked' && p.wrote === false) return 'stopped';
  return 'differs';
}

/**
 * How one pass ended when it was played end to end, for the board (its live run) and for Rules only: per pass, as
 * the evaluation's table shows every scored pass, where `playedBy` keeps one row per scenario.
 */
export function playedResult(played: ProofPass['played']): { board: PlayedResult; rules: PlayedResult } {
  return { board: boardResult(played?.board_live), rules: rulesResult(played?.rules) };
}

/** The figures from a slice of the evaluation; pure, so a test can give it an older document. */
export function proofFrom(src: ProofSource): Proof {
  const t = src.totals ?? {};
  const passes = src.passes ?? [];
  const scoredPasses = passes.filter((p) => p.scored);

  // One row per played scenario: the single cases the board was convened for, its last round
  const playedBy: Proof['playedBy'] = {};
  const playedRows: { id: string; played: NonNullable<ProofPass['played']> }[] = [];
  for (const p of passes) {
    if (p.incident || !p.played?.board_live) continue;
    if (p.rounds && p.round && p.round !== p.rounds) continue;
    if (playedBy[p.scenario]) continue;
    const board = boardResult(p.played.board_live);
    if (board === 'not-played') continue;
    playedBy[p.scenario] = { board, rules: rulesResult(p.played.rules) };
    playedRows.push({ id: p.scenario, played: p.played });
  }
  const scenarios = playedRows.map((r) => r.id);
  const played = scenarios.length
    ? {
        of: scenarios.length,
        board: scenarios.filter((id) => playedBy[id].board === 'as-expected').length,
        rules: scenarios.filter((id) => playedBy[id].rules === 'as-expected').length,
        scenarios,
      }
    : null;
  const misses = playedRows.filter((r) => r.played.rules?.status === 'differs');
  const split = misses.every((r) => typeof r.played.rules?.wrote === 'boolean' && r.played.rules?.state);
  const rulesMisses =
    played && split
      ? {
          total: misses.length,
          stopped: misses.filter((r) => playedBy[r.id].rules === 'stopped').map((r) => r.id),
          wrote: misses.filter((r) => playedBy[r.id].rules === 'wrote-wrongly').map((r) => r.id),
        }
      : null;

  const decides = scoredPasses.map((p) => p.entry_decides);
  const entryDecides = decides.length
    ? {
        policy: decides.filter((d) => d === 'policy').length,
        board: decides.filter((d) => d === 'board').length,
        person: decides.filter((d) => d === 'person').length,
        of: decides.length,
      }
    : null;

  const costs = passes.map((p) => num(p.cost_usd)).filter((c): c is number => c !== null);
  const scored = num(t.scored_passes);
  const matched = num(t.board_matches);
  const passCount = num(t.passes);
  const cases = num(t.cases);
  const scenarioCount = num(t.scenarios);
  const sm = t.specialist_matches;
  const image = typeof src.sources?.recorded_on === 'string' ? src.sources.recorded_on : '';
  const build = image.includes(':') ? image.slice(image.indexOf(':') + 1) : image;

  return {
    board:
      scored !== null && matched !== null && passCount !== null && cases !== null
        ? {
            matched,
            scored,
            passes: passCount,
            cases,
            notScored: passCount - scored,
            ...(scenarioCount !== null ? { scenarios: scenarioCount } : {}),
          }
        : null,
    specialists:
      sm && ['conformance', 'encounter', 'impact'].every((k) => typeof sm[k] === 'number')
        ? { conformance: sm.conformance, encounter: sm.encounter, impact: sm.impact }
        : null,
    played,
    rulesMisses,
    entryDecides,
    costPerPass: costs.length ? { min: Math.min(...costs), max: Math.max(...costs) } : null,
    agreement: t.agreement && typeof t.agreement === 'object' ? t.agreement : null,
    runs: num(t.runs),
    totalUsd: num(t.cost_usd),
    recordedFrom: t.recorded_from || null,
    recordedTo: t.recorded_to || null,
    recordedOn: image ? { image, build, number: /AI\.(\d+)/.exec(build)?.[1] ?? null } : null,
    models: Array.isArray(t.models) ? t.models : [],
    playedBy,
  };
}

/** The proof's figures from the evaluation in this build. */
export const PROOF: Proof = proofFrom(slice);

/** How a scenario ended when the comparison played it, by the board and by Rules only; null if it was not played. */
export function playedFor(id: string): { board: PlayedResult; rules: PlayedResult } | null {
  return PROOF.playedBy[id] ?? null;
}
