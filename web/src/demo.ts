/**
 * The demo build (`npm run build:demo`, and `VITE_MOCK=1` in development): the app runs on recorded data from a
 * real run, in the browser, with no IRIS instance behind it; the header says so.
 */
export const DEMO = import.meta.env.MODE === 'demo' || import.meta.env.VITE_MOCK === '1';

/**
 * The mock's one variant, chosen by the address (`?as=demo`, before the `#`): "Try the demo" signs in as the public
 * demo's role instead of the approver, so the screens can be seen as that role has them (no Run, no Reset, no Save,
 * and the live hospital's banner). Anything else is today's demo.
 */
export function demoUserFor(search: string) {
  return new URLSearchParams(search).get('as') === 'demo'
    ? { username: 'demo', password: 'shutter' }
    : { username: 'approver', password: 'shutter' };
}

/** The demo's sign-in: the mock's approver, who can do everything the screens show, or the public demo's role. */
export const DEMO_USER = demoUserFor(typeof window === 'undefined' ? '' : window.location.search);
