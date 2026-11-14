import type { SiteProfile, SiteReceiver } from '@/api/types';
import type { PageFocus } from '@/features/assistant/store';
import { CATEGORIES, CATEGORY_TEXT, categoryOf, derivedPolicy } from '@/lib/categories';
import { KINDS, KIND_LABELS, POLICY_SHORT, TIER_LABELS, overtakenLine } from './profile';

/**
 * What "Ask Shutter about this" asks about the site profile's consequential questions: a receiver's kind (question 2), its
 * tier (question 3) and enabling recovery (question 14). Each focus carries the answer on the page and what it does, read
 * as the page and the server read them (the category's line, the policy row of the tier, the recovery switch), so the
 * consequence is the page's own, never a model's; and the written explanation shown wherever no live answer can be given.
 * A person chooses every one of these answers: Ask Shutter explains them and sets none.
 */

const PAGE = 'site-profile';

const nameOf = (r: SiteReceiver) => r.name.trim() || 'this receiver';

/** The written explanation of a receiver's kind. */
export const KIND_WRITTEN =
  "The kind says what the system keeps: only where the patient is now, every movement in order, or each order and result as its own record. Shutter reads it to decide what a failure that a later event has overtaken gets: a close with no write, a correction by hand, or a person's decision. A person chooses it here; Ask Shutter explains it and does not choose it.";

/** The written explanation of a receiver's tier. */
export const TIER_WRITTEN =
  "The tier is how sensitive the system is: 1 information, 2 operations, 3 clinical safety. It picks the tier's row of the approval table, so it decides who releases a write to this receiver: the site's written policy or a person. A person chooses it here; Ask Shutter explains it and does not choose it.";

/** The written explanation of enabling recovery. */
export const RECOVERY_WRITTEN =
  "Off is shadow mode, the default on a new install: Shutter investigates and sends no recovery write, rehearsal, resend preview or outage resend. On, a write may go only through the gate and the approvals this profile sets, and plans made while it was off are investigated again, not released. Only a person's saved answer turns it on; no report or agent does. The emergency stop in Settings is apart from this.";

/** Question 2 for one receiver: the kind it is answered as, and what an overtaken failure gets there. */
export function kindFocus(r: SiteReceiver, i: number): PageFocus {
  const category = categoryOf(r);
  const text = CATEGORY_TEXT[category];
  const stored = r.category ? String(r.category) : '';
  const known = (CATEGORIES as string[]).includes(stored);
  const own = r.history_policy === 'current' || r.history_policy === 'correct' ? r.history_policy : undefined;
  const name = nameOf(r);
  return {
    page: PAGE,
    id: `site-receivers-${i}-category`,
    title: `What kind of system is ${name}?`,
    question: `What does ${text.label} mean for ${name}, and what would another kind change?`,
    answer: !stored
      ? `Not answered: read as ${text.label}`
      : known
        ? text.label
        : `Kept as stored: ${stored}, read as ${text.label}`,
    consequence: `${text.examples}. ${overtakenLine(category, own ?? derivedPolicy(category))}${own ? ' (its own history policy)' : ''}`,
    written: KIND_WRITTEN,
  };
}

/** Question 3 for one receiver: its tier, and who releases each kind of write at that tier under the policy as drafted. */
export function tierFocus(r: SiteReceiver, i: number, policy: SiteProfile['policy'] | undefined): PageFocus {
  const tier = String(r.tier ?? '');
  const label = TIER_LABELS[tier];
  const name = nameOf(r);
  const releases = KINDS.map(
    (kind) => `${KIND_LABELS[kind]}, ${POLICY_SHORT[policy?.[tier]?.[kind] ?? 'approval'] ?? 'one approval'}`,
  ).join('; ');
  return {
    page: PAGE,
    id: `site-receivers-${i}-tier`,
    title: `The tier of ${name}`,
    question: label
      ? `What does tier ${tier} mean for ${name}, and what would another tier change?`
      : `What does the tier of ${name} decide?`,
    answer: label ? `Tier ${label}` : tier ? `Kept as stored: ${tier}` : 'Not answered',
    consequence: label
      ? `Who releases a write at tier ${tier}: ${releases}.`
      : 'Not a tier the approval table has.',
    written: TIER_WRITTEN,
  };
}

/** Question 14: whether recovery is enabled, and what that lets Shutter send. */
export function recoveryFocus(draft: SiteProfile): PageFocus {
  const enabled = draft.recovery?.mode === 'enabled';
  return {
    page: PAGE,
    id: 'site-recovery-mode',
    title: 'Enable recovery',
    question: enabled
      ? 'What does enabled recovery let Shutter do here, and what still needs a person?'
      : 'What would enabling recovery here change, and what stays the same?',
    answer: enabled ? 'On: recovery enabled' : 'Off: shadow mode',
    consequence: enabled
      ? 'A write may go only through the gate and the approvals this profile sets; plans made while it was off are investigated again.'
      : 'Shutter investigates and sends no recovery write, rehearsal, resend preview or outage resend.',
    written: RECOVERY_WRITTEN,
  };
}
