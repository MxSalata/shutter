import { DEMO_BUILD, envFrom } from '@/env/mode';

/**
 * How a request reaches an answer: in a live page, `fetch` to the instance; in a trial page, the recorded mock in the
 * browser (src/trial/transport.ts), which never calls `fetch`. It is chosen once, at start (main.tsx), before the
 * first render, and never changes while the page lives: entering or leaving the trial is a page load.
 */
export type Transport = (request: Request) => Promise<Response>;

let chosen: Transport | null = null;

/** What a trial page's call answers before its mock has loaded (`request()` makes it an ApiError with status 0). */
export const TRIAL_OPENING = 'The trial is still opening';

/** The live transport: the browser's own `fetch`, as every call was sent before the trial existed. */
export const liveTransport: Transport = (request) => fetch(request);

/** Sets the page's transport, once. A second call is a bug: the page would change environment while it runs. */
export function chooseTransport(t: Transport): void {
  if (chosen) throw new Error('The transport is chosen once per page load');
  chosen = t;
}

/**
 * Whether the address and the build make this page a trial. Read from the address itself, not from a module
 * constant a test may stand in for, so the fail-closed rule below holds in every real trial page.
 */
const trialPage = () => typeof window !== 'undefined' && envFrom(window.location.search, DEMO_BUILD).trial;

/**
 * The page's transport. Before one is chosen, a live page sends with `fetch` (as the component tests do, through
 * `msw/node`), and a trial page refuses: a trial whose mock has not loaded must never fall back to the network.
 */
export function transport(): Transport {
  if (chosen) return chosen;
  if (trialPage()) return () => Promise.reject(new Error(TRIAL_OPENING));
  return liveTransport;
}

/** For tests only: forget the chosen transport, so a test file can choose another. */
export function resetTransportForTests(): void {
  chosen = null;
}
