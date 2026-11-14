import type { SiteProfile, SiteReceiver } from '@/api/types';
import type { PageFocus } from '@/features/assistant/store';
import { CATEGORIES, CATEGORY_TEXT, categoryOf, derivedPolicy, historyPolicyOf } from '@/lib/categories';
import { KINDS, KIND_LABELS, POLICY_SHORT, TIER_LABELS, overtakenLine } from './profile';

/**
 * What "Ask Shutter about this" asks about the site profile's consequential questions: a receiver's kind (question 2), its
 * tier (question 3) and enabling recovery (question 14). Each focus carries the answer on the page and what it does, read
 * as the page and the server read them (the category's line, the policy row of the tier, the recovery switch), so the
 * consequence is the page's own, never a model's; and the written explanation shown wherever no live answer can be given,
 * a card body of at most 40 words and 2 sentences (DESIGN 1.4). A person chooses every one of these answers: Ask Shutter
 * explains them and sets none, and each question asks it to explain, not to recommend.
 */

const PAGE = 'site-profile';

const nameOf = (r: SiteReceiver) => r.name.trim() || 'this receiver';

/** The written explanation of a receiver's kind. */
export const KIND_WRITTEN =
  "The kind says what the system keeps: where the patient is now, every movement in order, or each order and result. It decides what an overtaken failure gets: closed with no write, corrected by hand, or a person's decision.";

/** The written explanation of a receiver's tier. */
export const TIER_WRITTEN =
  "The tier is how sensitive the system is: 1 information, 2 operations, 3 clinical safety. It picks its row of the approval table, so it decides who releases a write to this receiver: the site's written policy or a person.";

/**
 * The written explanation of enabling recovery. The demo's install seeds it on (CONTRACTS 18), so only a site's own
 * install waits for a person's saved answer.
 */
export const RECOVERY_WRITTEN =
  "Off is shadow mode: Shutter investigates but sends no recovery write. On, every write needs the gate and this profile's approvals; on a site's own install only a person's saved answer turns it on; the demo install seeds it on.";

/** What each question asks of the agent beside the question itself: an explanation, never a choice made for the person. */
const EXPLAIN_ONLY = 'Explain each; do not recommend one.';

/**
 * Question 2 for one receiver: the kind it is answered as, and what an overtaken failure gets there, by the receiver's
 * history policy as the server reads it (`historyPolicyOf`): its own, else its kind's, else, for a receiver with neither,
 * the profile's deprecated site-wide answer.
 */
export function kindFocus(r: SiteReceiver, i: number, profile?: SiteProfile): PageFocus {
  const category = categoryOf(r);
  const text = CATEGORY_TEXT[category];
  const stored = r.category ? String(r.category) : '';
  const known = (CATEGORIES as string[]).includes(stored);
  const own = r.history_policy === 'current' || r.history_policy === 'correct';
  const policy = historyPolicyOf(r, profile);
  const from = own
    ? ' (its own history policy)'
    : policy !== derivedPolicy(category)
      ? ' (the site-wide history policy)'
      : '';
  const name = nameOf(r);
  return {
    page: PAGE,
    id: `site-receivers-${i}-category`,
    title: `What kind of system is ${name}?`,
    question: `What does ${text.label} mean for ${name}, and what would each other kind change? ${EXPLAIN_ONLY}`,
    answer: !stored
      ? `Not answered: read as ${text.label}`
      : known
        ? text.label
        : `Kept as stored: ${stored}, read as ${text.label}`,
    consequence: `${text.examples}. ${overtakenLine(category, policy)}${from}`,
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
      ? `What does tier ${tier} mean for ${name}, and what would each other tier change? ${EXPLAIN_ONLY}`
      : `What does the tier of ${name} decide? Explain it; do not recommend one.`,
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
      ? 'What does enabled recovery let Shutter do here, and what still needs a person? Explain it; do not recommend on or off.'
      : 'What would enabling recovery here change, and what stays the same? Explain it; do not recommend on or off.',
    answer: enabled ? 'On: recovery enabled' : 'Off: shadow mode',
    consequence: enabled
      ? 'A write may go only through the gate and the approvals this profile sets; a plan made while it was off is not released: it needs a fresh investigation.'
      : 'Shutter investigates and sends no recovery write, rehearsal, resend preview or outage resend.',
    written: RECOVERY_WRITTEN,
  };
}
