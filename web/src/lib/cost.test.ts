import { describe, expect, it } from 'vitest';
import type { ModelPrice } from '@/api/types';
import { costAtPrice } from './cost';

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
