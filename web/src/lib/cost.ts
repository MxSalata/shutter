import type { AgentRun, CaseCost, ModelPrice } from '@/api/types';
import { formatUsd } from '@/lib/format';

type Tokens = Pick<
  AgentRun,
  'model' | 'promptTokens' | 'completionTokens' | 'cacheReadTokens' | 'cacheCreationTokens'
>;

/**
 * What a run's tokens cost at its model's stored price, in US dollars, as the server prices a live run
 * (Shutter.Store.ModelPrice.Cost: prompt tokens exclude the cached ones, and a cache write without its own price
 * costs as input). A replay keeps the recorded run's tokens, so this is what the recorded run cost. Undefined when the
 * model has no price.
 */
export function costAtPrice(run: Tokens, prices: ModelPrice[] | undefined): number | undefined {
  const p = prices?.find((x) => x.model === run.model);
  if (!p) return undefined;
  const n = (v: unknown) => Number(v) || 0;
  const write =
    p.cacheWritePerMTok === null || p.cacheWritePerMTok === undefined ? p.inputPerMTok : p.cacheWritePerMTok;
  return (
    (n(run.promptTokens) * n(p.inputPerMTok) +
      n(run.completionTokens) * n(p.outputPerMTok) +
      n(run.cacheReadTokens) * n(p.cacheReadPerMTok) +
      n(run.cacheCreationTokens) * n(write)) /
    1_000_000
  );
}

/** The fields of a run that its case's cost reads, as `GET /cases/{id}/runs` and the recordings give them. */
export interface CostRun {
  mode?: string | null;
  model?: string | null;
  costUsd?: number | string | null;
  promptTokens?: number | null;
  completionTokens?: number | null;
  cacheReadTokens?: number | null;
  cacheCreationTokens?: number | null;
  questionId?: string | null;
}

/**
 * What a case cost from its runs, as the server reckons it (Shutter.Util.CaseCost, CONTRACTS 5), for the trial's recorded
 * cases: a live or record run spent its `costUsd`; a replay, the API mimic's run (model `mock`) and a run with no tokens
 * spent nothing; a run that reached a model and has no `costUsd` had no stored price, so the case is unpriced.
 */
export function caseCostOf(runs: readonly CostRun[] | null | undefined): CaseCost {
  const n = (v: unknown) => Number(v) || 0;
  const models = new Set<string>();
  const unpricedModels = new Set<string>();
  const c: CaseCost = {
    usd: 0,
    unpriced: false,
    runs: 0,
    modelRuns: 0,
    replayedRuns: 0,
    mockRuns: 0,
    unpricedRuns: 0,
    questionRuns: 0,
    questionUsd: 0,
    models: [],
    unpricedModels: [],
  };
  for (const r of runs ?? []) {
    const question = Boolean(r.questionId);
    c.runs += 1;
    if (question) c.questionRuns += 1;
    if (r.mode === 'replay') {
      c.replayedRuns += 1;
      continue;
    }
    if (r.model === 'mock') {
      c.mockRuns += 1;
      continue;
    }
    const tokens =
      n(r.promptTokens) + n(r.completionTokens) + n(r.cacheReadTokens) + n(r.cacheCreationTokens);
    if (tokens <= 0) continue;
    c.modelRuns += 1;
    if (r.model) models.add(r.model);
    if (r.costUsd === null || r.costUsd === undefined || r.costUsd === '') {
      c.unpricedRuns += 1;
      unpricedModels.add(r.model || '(no model named)');
      continue;
    }
    c.usd += n(r.costUsd);
    if (question) c.questionUsd += n(r.costUsd);
  }
  const round = (v: number) => Math.round(v * 1e6) / 1e6;
  return {
    ...c,
    usd: round(c.usd),
    questionUsd: round(c.questionUsd),
    unpriced: c.unpricedRuns > 0,
    models: [...models].sort(),
    unpricedModels: [...unpricedModels].sort(),
  };
}

const runsWord = (k: number) => `${k} run${k === 1 ? '' : 's'}`;

/**
 * How the case page says what a case cost: a short figure and a sentence for its hint. Unpriced when a run that reached a
 * model had no stored price, never $0.00; $0.00 when no agent ran or every run was a replay or the mimic's. Undefined when
 * the server sent no cost (an older build).
 */
export function caseCostWords(
  cost: CaseCost | null | undefined,
): { short: string; detail: string } | undefined {
  if (!cost || typeof cost !== 'object') return undefined;
  const free: string[] = [];
  if (cost.replayedRuns > 0) free.push(`${runsWord(cost.replayedRuns)} replayed from recordings`);
  if (cost.mockRuns > 0) free.push(`${runsWord(cost.mockRuns)} answered by the API mimic`);
  const freeLine = free.length
    ? ` ${capital(free.join(' and '))}, which call no model and cost nothing.`
    : '';
  const questions =
    cost.questionRuns > 0
      ? ` Questions asked about the case: ${runsWord(cost.questionRuns)}, ${formatUsd(cost.questionUsd)} of it.`
      : '';
  if (cost.unpriced) {
    const names = cost.unpricedModels.join(', ');
    const priced = cost.modelRuns - cost.unpricedRuns;
    const other = priced === 1 ? 'The one other run' : `The other ${priced} runs`;
    const rest = priced > 0 ? ` ${other} that called a model came to ${formatUsd(cost.usd)}.` : '';
    return {
      short: 'Unpriced',
      detail: `Shutter held no price for ${names} when ${cost.unpricedRuns === 1 ? 'its run was' : 'its runs were'} made, so what the case cost is not known.${rest}${freeLine}${questions} Settings shows the prices used for costs.`,
    };
  }
  if (cost.runs === 0)
    return { short: formatUsd(0), detail: 'No agent ran on this case, so no model was called.' };
  if (cost.modelRuns === 0)
    return { short: formatUsd(0), detail: `No run on this case called a model.${freeLine}`.trim() };
  const on = cost.models.length ? ` on ${cost.models.join(', ')}` : '';
  return {
    short: formatUsd(cost.usd),
    detail: `${capital(runsWord(cost.modelRuns))}${on} called a model, at the prices stored when they ran.${freeLine}${questions}`,
  };
}

function capital(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}
