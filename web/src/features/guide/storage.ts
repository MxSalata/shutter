import { INITIAL, isProgress, type GuideProgress } from './controller';

/**
 * The guide's progress on this device, in localStorage under one namespaced key. Storage can be missing or refuse
 * (a private window, blocked site data): then the progress lives in memory for the visit. A stored value this version
 * cannot read starts the guide afresh.
 */
export const GUIDE_KEY = 'shutter:guide:v1';

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
