import { normalisedSearch } from '@/env/mode';

/**
 * The tab's memory of the trial, in `sessionStorage` (one tab, gone when it closes; never API data):
 *
 * - `shutter:trial:acted`: the tab approved, ran or saved something, which a page load starts afresh, so it says so;
 * - `shutter:trial:visited`, set by every trial page: a live page that loads, or comes back from the back-forward
 *   cache, in a tab that carries it says "You are back in the live system" (BackFromTrial), since Back is the likeliest
 *   way to mistake one for the other;
 * - the banner's form: full on the tab's first trial page, one line once the guide's welcome has closed or on any
 *   later trial page load in the same tab (`data-shutter-banner` on `<html>`, which sets the header's height).
 */
export const TRIAL_VISITED_KEY = 'shutter:trial:visited';

/** Set once the tab has changed something in the trial, so the next page load can say that it has gone. */
export const TRIAL_ACTED_KEY = 'shutter:trial:acted';

const read = (key: string): string | null => {
  try {
    return window.sessionStorage.getItem(key);
  } catch {
    return null;
  }
};
const write = (key: string, value: string | null) => {
  try {
    if (value === null) window.sessionStorage.removeItem(key);
    else window.sessionStorage.setItem(key, value);
  } catch {
    // Storage refused: the tab simply has no memory of the trial
  }
};

export type BannerForm = 'full' | 'compact';
let form: BannerForm = 'full';
const listeners = new Set<() => void>();

function setForm(next: BannerForm) {
  form = next;
  document.documentElement.dataset.shutterBanner = next;
  listeners.forEach((l) => l());
}

/** The banner's form now, and a way to follow it (useSyncExternalStore). */
export const bannerForm = {
  get: (): BannerForm => form,
  subscribe(listener: () => void) {
    listeners.add(listener);
    return () => {
      listeners.delete(listener);
    };
  },
};

/** The guide's welcome has closed: the banner keeps to one line from now on, in this tab. */
export function compactBanner(): void {
  if (form !== 'compact') setForm('compact');
}

/**
 * A trial page's start, before its first render: the page is marked as the trial (before the first paint
 * `public/color-scheme.js` has already done so), the tab is marked as having visited it, the banner takes its form,
 * the tab's title says "(trial)", and `?trial=tour` or `?trial=engineer` becomes `?trial`, so a reload does not start
 * the tour again (React Router's own history state is kept).
 */
export function enterTrialPage(): void {
  document.documentElement.dataset.shutterEnv = 'trial';
  const before = read(TRIAL_VISITED_KEY) !== null;
  write(TRIAL_VISITED_KEY, '1');
  setForm(before ? 'compact' : 'full');
  document.title = 'Shutter (trial)';
  const search = normalisedSearch(window.location.search);
  if (search !== window.location.search)
    window.history.replaceState(
      window.history.state,
      '',
      `${window.location.pathname}${search}${window.location.hash}`,
    );
}

/** A call the mock answered changed something (signing in does not count: the trial starts signed in). */
export function noteTrialAction(method: string, path: string): void {
  if (method === 'GET' || method === 'HEAD' || path.endsWith('/session')) return;
  write(TRIAL_ACTED_KEY, '1');
}

/** Whether what this tab did in the trial went with the last page load; said once. */
export function takeLostActions(): boolean {
  const acted = read(TRIAL_ACTED_KEY) !== null;
  if (acted) write(TRIAL_ACTED_KEY, null);
  return acted;
}

/** Whether this tab came from the trial since the live page last said so, and forgets it once asked. */
export function takeTrialVisit(): boolean {
  const visited = read(TRIAL_VISITED_KEY) !== null;
  if (visited) write(TRIAL_VISITED_KEY, null);
  return visited;
}
