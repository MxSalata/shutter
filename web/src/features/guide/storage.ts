import { INITIAL, isProgress, type GuideProgress } from './controller';

/**
 * The guide's progress on this device, in localStorage under one namespaced key. Storage can be missing or refuse
 * (a private window, blocked site data): then the progress lives in memory for the visit. A stored value this version
 * cannot read starts the guide afresh.
 */
export const GUIDE_KEY = 'shutter:guide:v2';

let memory: GuideProgress | null = null;
/** When the welcome was put off, for a page whose storage refuses (snoozeWelcome, below). */
let snoozedAt: number | null = null;

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
  snoozedAt = null;
}

/**
 * Explore on my own, or the welcome closed by Escape or its close button: the welcome stays closed for the rest of the
 * visit. The visit is kept on the device for 12 hours from that choice, so a reload, a link into the trial or a second
 * tab does not bring the welcome back; a later visit is welcomed again. Storage that refuses keeps it for the page.
 */
export const WELCOME_SNOOZE_KEY = 'shutter:guide:snoozed-at';

/** How long Explore on my own keeps the welcome closed: one visit, taken as 12 hours. */
export const WELCOME_SNOOZE_MS = 12 * 60 * 60 * 1000;

export function snoozeWelcome(now = Date.now()): void {
  snoozedAt = now;
  try {
    window.localStorage.setItem(WELCOME_SNOOZE_KEY, String(now));
  } catch {
    // Storage refused: the page keeps it
  }
}

/** Whether the welcome was put off on this device within the visit. */
export function welcomeSnoozed(now = Date.now()): boolean {
  let at: number | null;
  try {
    const raw = window.localStorage.getItem(WELCOME_SNOOZE_KEY);
    at = raw === null ? null : Number(raw);
  } catch {
    // Unreadable storage: what this page kept
    at = snoozedAt;
  }
  return at !== null && Number.isFinite(at) && now >= at && now - at < WELCOME_SNOOZE_MS;
}
