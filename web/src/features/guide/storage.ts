import { INITIAL, isProgress, type GuideProgress } from './controller';

/**
 * The guide's progress on this device, in localStorage under one namespaced key. Storage can be missing or refuse
 * (a private window, blocked site data): then the progress lives in memory for the visit. A stored value this version
 * cannot read starts the guide afresh.
 */
export const GUIDE_KEY = 'shutter:guide:v2';

let memory: GuideProgress | null = null;

export function loadProgress(): GuideProgress {
  try {
    const raw = window.localStorage.getItem(GUIDE_KEY);
    if (raw !== null) {
      const value: unknown = JSON.parse(raw);
      if (isProgress(value)) return value;
    }
  } catch {
    // Unreadable storage or a damaged value: fall back to what this visit kept
  }
  return memory ?? INITIAL;
}

export function saveProgress(progress: GuideProgress): void {
  memory = progress;
  try {
    window.localStorage.setItem(GUIDE_KEY, JSON.stringify(progress));
  } catch {
    // Storage refused: the copy in memory lasts for the visit
  }
}

/** Sign-out: the copy in memory goes; what the device stored stays, like the appearance settings. */
export function forgetProgress(): void {
  memory = null;
}

/**
 * Explore on my own, for this tab: a full page load in it (a reload, a link that enters the trial again) does not bring
 * the welcome back, and a new tab may. Storage refused: it lasts for the page.
 */
export const GUIDE_SNOOZE_KEY = 'shutter:guide:snoozed';

export function loadSnoozed(): boolean {
  try {
    return window.sessionStorage.getItem(GUIDE_SNOOZE_KEY) !== null;
  } catch {
    return false;
  }
}

export function saveSnoozed(): void {
  try {
    window.sessionStorage.setItem(GUIDE_SNOOZE_KEY, '1');
  } catch {
    // Storage refused: the store's own copy lasts for the page
  }
}

export function forgetSnoozed(): void {
  try {
    window.sessionStorage.removeItem(GUIDE_SNOOZE_KEY);
  } catch {
    // Storage refused: nothing was kept
  }
}
