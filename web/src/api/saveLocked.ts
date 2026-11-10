import { toBecomeApprover } from '@/env/copy';
import { readOnlyDemo } from './can';
import type { Can } from './types';

// The locked Save's note, kept out of can.ts so the entry chunk, which loads can.ts for the shell, doesn't carry it: only
// the pages with a Save (the site profile, the agents' library, a review's annotations) load this.

/** The note beside a Save that is locked on the online demo: the editors work, and the server refuses the save. */
export const DEMO_LOCKED = "The online demo's settings are locked: nothing is saved.";

/**
 * Why this reader's Save is locked, or null when it is not. The editors stay usable for everyone who may read the page,
 * so a change can be tried and reviewed; only the save needs the configure right, which the server checks too. On the
 * online demo the note says its settings are locked; on a site, that only an approver saves.
 */
export const saveLocked = (can: Can): string | null =>
  can.configure
    ? null
    : readOnlyDemo(can)
      ? DEMO_LOCKED
      : `Only an approver saves here: ${toBecomeApprover()}.`;
