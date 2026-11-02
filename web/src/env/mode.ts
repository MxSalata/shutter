/**
 * Which environment this page is: the live system, or the trial (recorded cases answered in the browser, with nothing
 * sent to IRIS). It is chosen once, at start, from the build and the address, and fixed until the page unloads, so
 * modules may read it in their top-level constants. Entering or leaving the trial is a page load.
 */

/** The roles the trial can sign in as at start, as the mock's users are named. */
export type TrialRole = 'approver' | 'operator' | 'demo' | 'judge';

/** How much the pages say: the plain words only, or the technical detail as well (the header's Detail switch). */
export type DetailLevel = 'plain' | 'technical';

export interface Env {
  /** The trial: recorded cases answered in the browser. */
  trial: boolean;
  /** The demo build (GitHub Pages, `VITE_MOCK=1`): always the trial, with no live system to go back to. */
  demoBuild: boolean;
  /** A trial with a live system at the same address to go back to ("Leave trial"). */
  canLeave: boolean;
  /** The trial's user at start: `?as=operator|approver|demo|judge`, else the approver. */
  role: TrialRole;
  /** `?trial=tour` opens the guide's quick tour on arrival, `?trial=engineer` the integration engineers' tour. */
  openGuide: 'quick' | 'engineer' | false;
  /** `?detail=technical` (or `plain`) sets the Detail switch at start; null when the address says nothing. */
  detail: DetailLevel | null;
}

const ROLES: readonly TrialRole[] = ['approver', 'operator', 'demo', 'judge'];

/**
 * The environment an address describes, for a build that is or is not the demo build. Pure, so it is tested on its
 * own: `search` is the part of the address before the `#` (the hash belongs to the router), with or without its `?`.
 */
export function envFrom(search: string, demoBuild: boolean): Env {
  const q = new URLSearchParams(search);
  const trialValue = q.get('trial');
  const trial = demoBuild || trialValue !== null;
  const as = q.get('as');
  const detail = q.get('detail');
  return {
    trial,
    demoBuild,
    canLeave: trial && !demoBuild,
    role: ROLES.includes(as as TrialRole) ? (as as TrialRole) : 'approver',
    openGuide: trialValue === 'tour' ? 'quick' : trialValue === 'engineer' ? 'engineer' : false,
    detail: detail === 'technical' || detail === 'plain' ? detail : null,
  };
}

/** The demo build: recorded runs on the in-browser mock, with no IRIS instance behind it. */
export const DEMO_BUILD = import.meta.env.MODE === 'demo' || import.meta.env.VITE_MOCK === '1';

/** The tab's trial role, kept in `sessionStorage` so a reload signs the same fake user in again. */
export const TRIAL_ROLE_KEY = 'shutter:trial:as';

const isRole = (v: unknown): v is TrialRole => ROLES.includes(v as TrialRole);

/** The role this tab last chose in the trial, if any (storage can refuse: then none). */
function storedRole(): TrialRole | null {
  try {
    const v = window.sessionStorage.getItem(TRIAL_ROLE_KEY);
    return isRole(v) ? v : null;
  } catch {
    return null;
  }
}

/** Keeps the trial role chosen in this tab for its reloads (the trial's sign-in page, Switch trial role). */
export function rememberTrialRole(role: TrialRole): void {
  try {
    window.sessionStorage.setItem(TRIAL_ROLE_KEY, role);
  } catch {
    // Storage refused: a reload starts as the address says
  }
}

/**
 * The environment this page was loaded in, with the trial's starting role: the one `?as=` names, else the one this
 * tab chose before a reload, else the approver.
 */
export function pageEnv(search: string, demoBuild: boolean): Env {
  const env = envFrom(search, demoBuild);
  if (!env.trial || new URLSearchParams(search).has('as')) return env;
  return { ...env, role: storedRole() ?? env.role };
}

/** This page's environment, fixed for the life of the page: a trial page and a live one never share memory. */
export const ENV: Env = pageEnv(typeof window === 'undefined' ? '' : window.location.search, DEMO_BUILD);

/** This page is the trial. The demo build is always the trial. */
export const TRIAL = ENV.trial;

/**
 * The address after start: `?trial=tour` and `?trial=engineer` become `?trial`, so a reload does not open the tour's
 * welcome again; the rest of the address, and React Router's own history state, are kept.
 */
export function normalisedSearch(search: string): string {
  return search.replace(/([?&])trial=(tour|engineer)(?=&|$)/, '$1trial');
}

/** The trial's sign-in for a role: the mock's user of that name, with the demo users' password. */
export const trialUser = (role: TrialRole) => ({ username: role, password: 'shutter' });

const currentPath = () => (typeof window === 'undefined' ? '/' : window.location.pathname);

/**
 * The trial at this address: the same path, `?trial` (with `=tour` or `=engineer` to open a tour, and `as` for the
 * starting role), and the page to open.
 */
export function trialHref(
  hash = '#/scenarios',
  opts: { tour?: boolean | 'quick' | 'engineer'; as?: TrialRole } = {},
): string {
  const tour =
    opts.tour === true || opts.tour === 'quick' ? 'tour' : opts.tour === 'engineer' ? 'engineer' : null;
  const query = [tour ? `trial=${tour}` : 'trial', ...(opts.as ? [`as=${opts.as}`] : [])].join('&');
  return `${currentPath()}?${query}${hash.startsWith('#') ? hash : `#${hash}`}`;
}

/** The live app at this address: the path without its query, and the page to open. */
export function liveHref(hash = '#/scenarios'): string {
  return `${currentPath()}${hash.startsWith('#') ? hash : `#${hash}`}`;
}
