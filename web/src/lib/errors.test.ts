import { describe, expect, it } from 'vitest';
import { ApiError, answerLost, describeError } from './errors';

const err = (status: number, method: string, body: unknown = null) =>
  new ApiError({ status, method, path: '/cases/C-000002/approvals', body });

describe('answerLost', () => {
  it('is a change with no HTTP answer at all', () => {
    const e = err(0, 'POST', 'Failed to fetch');
    expect(answerLost(e)).toBe(true);
    // The cause is still there to show beside the words
    expect(describeError(e)).toBe('Failed to fetch');
  });

  it("is a change answered by a gateway's page instead of the API", () => {
    for (const status of [502, 503, 504]) {
      expect(answerLost(err(status, 'POST', '<html><title>Gateway Timeout</title></html>'))).toBe(true);
    }
  });

  it("is never the API's own refusal, which says what happened", () => {
    expect(answerLost(err(409, 'POST', { error: 'stale_version', detail: 'The case changed' }))).toBe(false);
    expect(answerLost(err(503, 'POST', { error: 'unavailable', detail: 'Shutter is starting' }))).toBe(false);
    expect(answerLost(err(500, 'POST', 'Internal error'))).toBe(false);
    expect(answerLost(err(400, 'POST', { error: 'bad_request', detail: 'reason is empty' }))).toBe(false);
  });

  it('is never a read, which asked nothing to change', () => {
    expect(answerLost(err(0, 'GET', 'Failed to fetch'))).toBe(false);
    expect(answerLost(err(504, 'GET', 'Gateway Timeout'))).toBe(false);
  });

  it('is nothing for what is not an API error', () => {
    expect(answerLost(new Error('Failed to fetch'))).toBe(false);
    expect(answerLost('Failed to fetch')).toBe(false);
    expect(answerLost(undefined)).toBe(false);
  });
});
