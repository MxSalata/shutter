import { HOSPITAL_NAME } from '@/lib/hospital';
import type { JournalCounts } from './journal';

/** The banner's sentences: whose data it is, that nothing leaves, and that a reload starts over (DESIGN.md 1.3, 7.1). */
export const TRIAL_WORDS = `${HOSPITAL_NAME}: a demo hospital with made-up patients, recorded. Nothing you do here reaches a hospital system or IRIS. A reload starts the recording afresh.`;
/** The one-line form's words, once the welcome has closed. */
export const TRIAL_WORDS_SHORT = 'Made-up patients; nothing leaves this browser';

/**
 * Where Leave trial would be, in a copy that is the trial alone (the demo build: GitHub Pages, the preview), with no
 * live system to go back to: the user menu and the help menu say so, so nobody hunts for it.
 */
export const TRIAL_ONLY_WORDS =
  'This copy is the trial only. The live system runs on an IRIS instance: your own install or the online demo.';

const plural = (n: number, one: string, many: string) => `${n} ${n === 1 ? one : many}`;

/** "Answered in this browser: 48 reads, 3 actions. Sent to IRIS: none. Refused by the browser: 0." */
export function journalLine(c: JournalCounts): string {
  const refused = c.refused ? ` Refused by the trial's guard: ${c.refused}.` : '';
  return `Answered in this browser: ${plural(c.reads, 'read', 'reads')}, ${plural(c.actions, 'action', 'actions')}. Sent to IRIS: none. Refused by the browser: ${c.violations}.${refused}`;
}
