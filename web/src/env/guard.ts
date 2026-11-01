import { journal } from '@/trial/journal';
import { API_BASE } from '@/api/client';

/** What a guarded `fetch` answers a request for the API in a trial page. */
export const TRIAL_REFUSAL = 'The trial does not reach IRIS';

/** The policy a trial page adds to its own: no network call of any kind, from anything on the page. */
export const TRIAL_POLICY = "connect-src 'none'";

let locked = false;
const countViolation = () => journal.violation();

/**
 * The trial's three locks, applied at start in trial pages only, before anything can call out:
 *
 * 1. the transport: the trial's own (src/trial/transport.ts) never calls `fetch` (chosen in main.tsx);
 * 2. a guarded `fetch`: any request to `/api/shutter` rejects with "The trial does not reach IRIS", and is counted;
 * 3. the browser's refusal: a second Content-Security-Policy, `connect-src 'none'`, appended to `<head>`. A policy
 *    from a `<meta>` applies once the element is inserted, and a second policy can only tighten the first, so from
 *    then on the browser itself refuses fetch, XHR, EventSource, WebSocket and beacons from the page. Scripts,
 *    styles, images and fonts are other directives and keep loading. Left out under Vite's development server
 *    (`csp: false` there), whose hot reload needs a WebSocket.
 *
 * Each lock is enough on its own; together the claim "nothing you do here reaches IRIS" rests on the browser, not on
 * this code alone. `window.shutterTrial.journal` shows what was answered and refused.
 */
export function lockNetworkForTrial({ csp = !import.meta.env.DEV }: { csp?: boolean } = {}): void {
  if (locked) return;
  locked = true;
  const original = window.fetch.bind(window);
  const guarded: typeof window.fetch = (input, init) => {
    const url = new URL(
      typeof input === 'string' ? input : input instanceof URL ? input.href : input.url,
      window.location.href,
    );
    if (url.pathname.startsWith(API_BASE)) {
      journal.refuse();
      return Promise.reject(new TypeError(TRIAL_REFUSAL));
    }
    return original(input, init);
  };
  window.fetch = guarded;
  if (csp) {
    const meta = document.createElement('meta');
    meta.httpEquiv = 'Content-Security-Policy';
    meta.content = TRIAL_POLICY;
    meta.dataset.shutterTrial = 'true';
    document.head.append(meta);
  }
  // A violation is fired at the document or an element and bubbles to the window: counted once, there
  window.addEventListener('securitypolicyviolation', countViolation);
  window.shutterTrial = { journal };
}

/** For tests only: lift the locks' bookkeeping so the next call applies them again. */
export function unlockForTests(): void {
  locked = false;
  window.removeEventListener('securitypolicyviolation', countViolation);
}
