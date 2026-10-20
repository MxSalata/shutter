import type { AgentRun, ModelPrice } from '@/api/types';

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
