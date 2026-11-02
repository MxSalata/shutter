/**
 * Window events that pass between the pages and the guide. This module imports nothing, so a page every live install
 * loads can name an event without bringing the guide, which only trial pages load, into its chunk.
 */

/** The case page's event when its replay after a trial approval has ended; the guide waits for it before scrolling. */
export const REPLAY_DONE = 'shutter:replay-done';
