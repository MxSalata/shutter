import { useSyncExternalStore } from 'react';

/**
 * Where the guide's step card stands while Ask about this case is open over the page (below 1440 px). The guide runs
 * only in trial pages; while one of its step cards is on the page it says so here, and Ask then opens as a sheet with no
 * overlay and no focus trap, with a dock just before it that the card moves into: left of the sheet on a laptop, at the
 * foot of the screen on a phone, and just before the sheet in the reading and tab order, so Shift+Tab from Ask's
 * heading reaches the card's Next. This module imports no guide code, so the case page, which live pages load too,
 * carries none of it.
 */

function cell<T>(initial: T) {
  let value = initial;
  const listeners = new Set<() => void>();
  return {
    get: (): T => value,
    set(next: T) {
      if (next === value) return;
      value = next;
      listeners.forEach((l) => l());
    },
    subscribe(listener: () => void) {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
  };
}

/** Whether a guide step's card is on the page now. */
export const guideCard = cell(false);

/** The dock the open Ask sheet offers the card, or null. */
export const guideDock = cell<HTMLElement | null>(null);

export const useGuideCardShown = () => useSyncExternalStore(guideCard.subscribe, guideCard.get, () => false);

export const useGuideDock = () => useSyncExternalStore(guideDock.subscribe, guideDock.get, () => null);
