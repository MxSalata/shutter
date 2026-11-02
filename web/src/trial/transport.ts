import { getResponse } from 'msw';
import type { Transport } from '@/api/transport';
import type { TrialRole } from '@/env/mode';
import fixtures from '@/mocks/fixtures.json';
import { handlers, resetMock } from '@/mocks/handlers';
import { journal } from './journal';

/** What the trial answers a call no recorded handler knows: a 501 made in the browser, never the network. */
export const NOT_IN_TRIAL_ANSWER = {
  error: 'not_in_trial',
  detail: 'The trial has no recorded answer for this.',
} as const;

/** Rejects as `fetch` does when the request's signal aborts (React Query cancels a query this way). */
function untilAborted<T>(work: Promise<T>, signal: AbortSignal): Promise<T> {
  if (signal.aborted) return Promise.reject(new DOMException('The request was aborted', 'AbortError'));
  return new Promise<T>((resolve, reject) => {
    const abort = () => reject(new DOMException('The request was aborted', 'AbortError'));
    signal.addEventListener('abort', abort, { once: true });
    work.then(
      (v) => {
        signal.removeEventListener('abort', abort);
        resolve(v);
      },
      (e: unknown) => {
        signal.removeEventListener('abort', abort);
        reject(e instanceof Error ? e : new Error(String(e)));
      },
    );
  });
}

/**
 * The trial's transport: every call is answered by the recorded mock's own handlers, in memory (msw's `getResponse`,
 * with no service worker and no interceptor), and none can reach the network: there is no `fetch` here. The mock
 * starts afresh with the role signed in, so the trial opens signed in, and each answer is written to the journal.
 * Loaded only in trial pages, in its own chunk with the mock and the recordings.
 */
export function createTrialTransport(role: TrialRole): Transport {
  resetMock(role);
  journal.setRecording({ at: fixtures.recordedAt, source: fixtures.source });
  return async (request) => {
    const answer = await untilAborted(
      getResponse(handlers, request, { baseUrl: window.location.origin }),
      request.signal,
    );
    const response = answer ?? Response.json(NOT_IN_TRIAL_ANSWER, { status: 501 });
    journal.add(request.method, new URL(request.url).pathname, response.status);
    return response;
  };
}
