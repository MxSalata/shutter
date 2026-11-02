/**
 * Window events that pass between the pages and the guide. This module imports nothing, so a page every live install
 * loads can name an event without bringing the guide, which only trial pages load, into its chunk.
 */

/** The case page's event when its replay after a trial approval has ended; the guide waits for it before scrolling. */
export const REPLAY_DONE = 'shutter:replay-done';

/**
 * The case page's action button (the header's, and its copy in the sticky tab bar): the Outcome band opens if it was
 * closed, scrolls "What needs you now" into view, opens its details and moves focus to its heading.
 */
export const SHOW_NEXT_ACTION = 'shutter:show-next-action';

export function showNextAction() {
  window.dispatchEvent(new CustomEvent(SHOW_NEXT_ACTION));
}
