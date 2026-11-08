import { startAddress } from '@/env/mode';

/**
 * The tab's memory of the trial, in `sessionStorage` (one tab, gone when it closes; never API data):
 *
 * - `shutter:trial:visited`, set by every trial page: a live page that loads, or comes back from the back-forward
 *   cache, in a tab that carries it says "You are back in the live system" (BackFromTrial), since Back is the likeliest
 *   way to mistake one for the other;
 * - the banner's form: full on the tab's first trial page, one line once the guide's welcome has closed or on any
 *   later trial page load in the same tab (`data-shutter-banner` on `<html>`, which sets the header's height).
 */
export const TRIAL_VISITED_KEY = 'shutter:trial:visited';

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
 * the tab's title says "(trial)", and `?trial=tour`, `?trial=engineer` or `?trial=judge` becomes `?trial`, so a reload
 * does not open the tour's welcome again or take the judges' path again (React Router's own history state is kept).
 * The judges' path (`?trial=judge`) also opens on Scenarios in Rules only mode, whatever page the address named.
 */
export function enterTrialPage(): void {
  document.documentElement.dataset.shutterEnv = 'trial';
  const before = read(TRIAL_VISITED_KEY) !== null;
  write(TRIAL_VISITED_KEY, '1');
  setForm(before ? 'compact' : 'full');
  document.title = 'Shutter (trial)';
  // The judges' path opens on Scenarios in Rules only mode, before the router reads the address
  const { search, hash } = startAddress(window.location.search, window.location.hash);
  if (search !== window.location.search || hash !== window.location.hash)
    window.history.replaceState(window.history.state, '', `${window.location.pathname}${search}${hash}`);
}

/** Whether this tab came from the trial since the live page last said so, and forgets it once asked. */
export function takeTrialVisit(): boolean {
  const visited = read(TRIAL_VISITED_KEY) !== null;
  if (visited) write(TRIAL_VISITED_KEY, null);
  return visited;
}
