import type { ReceiverCategory, SiteProfile, SiteReceiver } from '@/api/types';

/**
 * The receiver's category (CONTRACTS 6.4, v1.23) in plain words, and the history policy it derives, as the server reads
 * them (Shutter.Store.SiteProfile.ReceiverCategory and ReceiverHistoryPolicy). The Site profile page explains each
 * category with these words, and the case page names its receiver's category with them.
 */

export const CATEGORIES: ReceiverCategory[] = ['current_state', 'history_of_record', 'orders_results'];

export interface CategoryText {
  /** The category's name, as a person says it. */
  label: string;
  /** What matters to such a system, in a few words. */
  gist: string;
  /** Systems of this kind. */
  examples: string;
  /** What Shutter does with a failure a later event has overtaken. */
  overtaken: string;
  /**
   * Whether a single case at this kind of receiver can end in a resend from the case: Shutter's catalogue covers patient
   * movements. An order or result case gets its findings and goes to a person, with no resend from the case.
   */
  modelled: boolean;
}

/**
 * Orders and results, in the parts its two forms share, so the card's line and the whole sentence cannot drift apart.
 * Checked against the server: the workflow sends such a case to a person before any model runs
 * (CaseWorkflow.NotModelledToPerson), with its findings (Shutter.Util.CaseFindings); the gate blocks every write from
 * the case (RECEIVER_NOT_MODELLED); and where the receiver's entry has a watch block and engine_resend, a person's one
 * approval of an outage's offered set has the engine send those messages again (Shutter.Operation.EngineResend,
 * CONTRACTS 17.8).
 */
const ORDERS_RESULTS = {
  person: 'A case goes to a person with its findings',
  findingsAre: "who holds the message, the receiver's own words and the result they name",
  before: 'before any model runs',
  noResend: 'and nothing is resent from the case.',
  outage:
    "At a receiver set up for it, an outage's messages that never arrived are listed, and after one approval the engine sends them again.",
} as const;

/**
 * Orders and results in a card's two sentences: what a case gets, and the one resend there is, an outage's. The whole
 * of it, with what the findings are, is `CATEGORY_TEXT.orders_results.overtaken`.
 */
export const ORDERS_RESULTS_BRIEF = `${ORDERS_RESULTS.person}, ${ORDERS_RESULTS.noResend} ${ORDERS_RESULTS.outage}`;

/**
 * What the whole sentence adds to the brief one, on its own: what a case's findings are and when they come. For a
 * second layer under words that have already said the rest, so nothing is said twice.
 */
export const ORDERS_RESULTS_FINDINGS = `A case's findings are ${ORDERS_RESULTS.findingsAre}, and they come ${ORDERS_RESULTS.before}.`;

export const CATEGORY_TEXT: Record<ReceiverCategory, CategoryText> = {
  current_state: {
    label: 'Current state',
    gist: 'This receiver keeps only current placement',
    examples: 'A bed manager, a ward whiteboard, portering',
    overtaken:
      'An overtaken failure closes with no write: a later event already put the patient where they are, so the old movement is never replayed.',
    modelled: true,
  },
  history_of_record: {
    label: 'History of record',
    gist: 'The history must be complete',
    examples: 'A PAS, an electronic patient record, a clinical data warehouse',
    overtaken:
      'An overtaken failure asks for a correction by hand: Shutter writes nothing and escalates the case with the steps that put the missing movement into the history, named on the case.',
    modelled: true,
  },
  orders_results: {
    label: 'Orders and results',
    gist: 'Each order or result is its own record',
    examples: 'Order communications, a laboratory system (LIMS)',
    overtaken: `${ORDERS_RESULTS.person} (${ORDERS_RESULTS.findingsAre}) ${ORDERS_RESULTS.before}, ${ORDERS_RESULTS.noResend} ${ORDERS_RESULTS.outage}`,
    modelled: false,
  },
};

export const HISTORY_POLICY_TEXT: Record<string, string> = {
  current: 'keep what is current',
  correct: 'correct the history',
};

const isCategory = (v: unknown): v is ReceiverCategory =>
  typeof v === 'string' && (CATEGORIES as string[]).includes(v);

/** The receiver's category: its entry's own, else current_state, which every profile before categories meant. */
export function categoryOf(r: SiteReceiver | undefined): ReceiverCategory {
  return isCategory(r?.category) ? r.category : 'current_state';
}

/** A category from a case's evidence (route.category), or undefined when the snapshot predates categories. */
export function asCategory(v: unknown): ReceiverCategory | undefined {
  return isCategory(v) ? v : undefined;
}

/**
 * The receiver's history policy: its entry's own when it sets one, else derived from its category (history of record
 * keeps the history straight; the others keep what is current), else, for an entry with neither, the deprecated
 * site-wide answer, else current.
 */
export function historyPolicyOf(r: SiteReceiver | undefined, p?: SiteProfile): 'current' | 'correct' {
  if (r?.history_policy === 'current' || r?.history_policy === 'correct') return r.history_policy;
  if (r?.category !== undefined && r.category !== '')
    return categoryOf(r) === 'history_of_record' ? 'correct' : 'current';
  return p?.history_policy === 'correct' ? 'correct' : 'current';
}

/** The policy a category derives when the entry sets none. */
export const derivedPolicy = (c: ReceiverCategory): 'current' | 'correct' =>
  c === 'history_of_record' ? 'correct' : 'current';
