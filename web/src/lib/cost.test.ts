import { describe, expect, it } from 'vitest';
import type { ModelPrice } from '@/api/types';
import { caseCostOf, caseCostWords, costAtPrice } from './cost';

const price: ModelPrice = {
  model: 'claude-opus-5-5',
  inputPerMTok: 4,
  outputPerMTok: 20,
  cacheReadPerMTok: 0.2,
  cacheWritePerMTok: 5,
  currency: 'USD',
  source: 'test',
  asOf: '2026-10-16',
};
const run = {
  model: 'claude-opus-5-5',
  promptTokens: 15_328,
  completionTokens: 972,
  cacheReadTokens: 5_718,
  cacheCreationTokens: 100,
};

describe('costAtPrice', () => {
  it('prices the tokens as the server prices a live run', () => {
    expect(costAtPrice(run, [price])).toBeCloseTo((15_328 * 4 + 972 * 20 + 5_718 * 0.2 + 100 * 5) / 1e6, 10);
  });

  it('charges a cache write at the input price when it has none of its own', () => {
    const noWrite = { ...price, cacheWritePerMTok: null as unknown as number };
    expect(
      costAtPrice({ ...run, promptTokens: 0, completionTokens: 0, cacheReadTokens: 0 }, [noWrite]),
    ).toBeCloseTo((100 * 4) / 1e6, 10);
  });

  it('has no answer for a model with no price', () => {
    expect(costAtPrice({ ...run, model: 'another-model' }, [price])).toBeUndefined();
    expect(costAtPrice(run, undefined)).toBeUndefined();
  });
});

const live = { mode: 'live', model: 'claude-opus-5-5', promptTokens: 1000, completionTokens: 200, costUsd: 0.015 };

describe('caseCostOf', () => {
  it('adds up what the runs that called a model spent, replays and the mimic at nothing', () => {
    const c = caseCostOf([
      live,
      { ...live, mode: 'record', costUsd: 0.0025 },
      { ...live, mode: 'replay', costUsd: 0.4 },
      { ...live, model: 'mock', costUsd: 0 },
      { ...live, costUsd: 0.002, questionId: 'Q-000001' },
    ]);
    expect(c.usd).toBeCloseTo(0.0195, 10);
    expect(c).toMatchObject({ unpriced: false, runs: 5, modelRuns: 3, replayedRuns: 1, mockRuns: 1, questionRuns: 1 });
    expect(c.questionUsd).toBeCloseTo(0.002, 10);
    expect(c.models).toEqual(['claude-opus-5-5']);
  });

  it('is unpriced when a run that called a model has no cost, and keeps the priced runs apart', () => {
    const c = caseCostOf([live, { ...live, model: 'new-model', costUsd: '' }]);
    expect(c).toMatchObject({ unpriced: true, unpricedRuns: 1, unpricedModels: ['new-model'], usd: 0.015 });
  });

  it('is never unpriced for a replay, or for a run that reached no model', () => {
    const c = caseCostOf([
      { ...live, mode: 'replay', model: 'new-model', costUsd: null },
      { ...live, model: 'new-model', promptTokens: 0, completionTokens: 0, costUsd: null },
    ]);
    expect(c).toMatchObject({ unpriced: false, usd: 0, runs: 2, modelRuns: 0, replayedRuns: 1 });
  });

  it('costs nothing with no runs', () => {
    expect(caseCostOf(undefined)).toMatchObject({ usd: 0, unpriced: false, runs: 0, models: [] });
  });
});

describe('caseCostWords', () => {
  it('says Unpriced, never $0.00, and names the model with no price', () => {
    const w = caseCostWords(caseCostOf([{ ...live, costUsd: 0.12 }, { ...live, model: 'new-model', costUsd: '' }]));
    expect(w?.short).toBe('Unpriced');
    expect(w?.detail).toContain('no price for new-model when its run was made');
    expect(w?.detail).toContain('The one other run that called a model came to $0.12.');
    expect(w?.detail).not.toContain('$0.00');
  });

  it('gives $0.00 for a case whose runs were all replays, and says why', () => {
    const w = caseCostWords(caseCostOf([{ ...live, mode: 'replay' }, { ...live, mode: 'replay' }]));
    expect(w).toEqual({
      short: '$0.00',
      detail: 'No run on this case called a model. 2 runs replayed from recordings, which call no model and cost nothing.',
    });
  });

  it('gives the sum and the model for a case that called one', () => {
    const w = caseCostWords(caseCostOf([live, { ...live, costUsd: 0.005 }]));
    expect(w?.short).toBe('$0.02');
    expect(w?.detail).toMatch(/^2 runs on claude-opus-5-5 called a model/);
  });

  it('says no agent ran when none did, and says nothing for a build that sends no cost', () => {
    expect(caseCostWords(caseCostOf([]))?.detail).toBe('No agent ran on this case, so no model was called.');
    expect(caseCostWords(undefined)).toBeUndefined();
  });
});
