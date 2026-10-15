/**
 * The demo build (`npm run build:demo`, and `VITE_MOCK=1` in development): the app runs on recorded data from a
 * real run, in the browser, with no IRIS instance behind it; the header says so.
 */
export const DEMO = import.meta.env.MODE === 'demo' || import.meta.env.VITE_MOCK === '1';

/** The demo's sign-in: the mock's approver, who can do everything the screens show. */
export const DEMO_USER = { username: 'approver', password: 'interlock' };
