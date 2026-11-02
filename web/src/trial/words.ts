import type { JournalCounts } from './journal';

/** The banner's two sentences: whose data it is, and that nothing leaves (DESIGN.md 1.3, 7.1). */
export const TRIAL_WORDS =
  'A demo hospital with made-up patients, recorded. Nothing you do here reaches a hospital system or IRIS.';
/** The one-line form's words, once the welcome has closed. */
export const TRIAL_WORDS_SHORT = 'Made-up patients; nothing leaves this browser';

const plural = (n: number, one: string, many: string) => `${n} ${n === 1 ? one : many}`;

/** "Answered in this browser: 48 reads, 3 actions. Sent to IRIS: none. Refused by the browser: 0." */
export function journalLine(c: JournalCounts): string {
  const refused = c.refused ? ` Refused by the trial's guard: ${c.refused}.` : '';
  return `Answered in this browser: ${plural(c.reads, 'read', 'reads')}, ${plural(c.actions, 'action', 'actions')}. Sent to IRIS: none. Refused by the browser: ${c.violations}.${refused}`;
}
