import { describe, expect, it } from 'vitest';
import { ApiError, answerLost, describeError, httpStatusText } from './errors';

const apiError = (status: number, body: unknown) =>
  new ApiError({ status, method: 'POST', path: '/scenarios/S3/run', body });

describe('describeError', () => {
  it("says a rate limit in the reader's words, whatever the proxy's page said", () => {
    const page =
      '<!doctype html><html><head><title>You are being rate-limited by the website owner&#39;s configuration</title></head></html>';
    expect(describeError(apiError(429, page))).toBe(
      'Too many requests at once: wait a few seconds, then try again',
    );
    expect(httpStatusText(429)).toBe('Too many requests at once: wait a few seconds, then try again');
  });

  it("says a 503 with no word of its own is a pause, and keeps a 503's own detail", () => {
    expect(describeError(apiError(503, { error: 'unavailable' }))).toBe(
      'Shutter is unavailable for a moment, perhaps updating: try again shortly',
    );
    expect(describeError(apiError(503, ''))).toBe(
      'Shutter is unavailable for a moment, perhaps updating: try again shortly',
    );
    expect(
      describeError(apiError(503, { error: 'no_service', detail: 'The API service is not running' })),
    ).toBe('The API service is not running (no_service)');
  });

  it("says a run in the way may be another user's or the hospital's, without the code", () => {
    expect(
      describeError(apiError(409, { error: 'wrong_state', detail: 'a run of S3 is still playing' })),
    ).toBe(
      "A run of S3 is still playing; perhaps another user's, or the hospital's. Try again when it ends.",
    );
    expect(describeError(apiError(409, { error: 'wrong_state', detail: 'a run of S8 is queued' }))).toBe(
      "A run of S8 is queued; perhaps another user's, or the hospital's. Try again when it ends.",
    );
    // Any other refusal keeps its own words and its code
    expect(
      describeError(
        apiError(409, { error: 'wrong_state', detail: 'The case is resolved, not awaiting approval' }),
      ),
    ).toBe('The case is resolved, not awaiting approval (wrong_state)');
  });
});

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
