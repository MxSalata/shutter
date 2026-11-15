import { describe, expect, it } from 'vitest';
import { ApiError, describeError, httpStatusText } from './errors';

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
