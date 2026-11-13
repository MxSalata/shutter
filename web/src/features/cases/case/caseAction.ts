import { resolveCan } from '@/api/can';
import type { CaseDetail, Escalation, Me } from '@/api/types';
import { caseState } from '@/lib/status';
import { nextAction, type CaseFacts } from './outcome';
import { decisionLabels } from './planAction';

/**
 * What the case needs from the person reading it, for the action button at the top of the case page (and its copy in
 * the sticky tab bar): the same logic that fills "What needs you now" (`nextAction`), narrowed to what this user may
 * do. `needsYou` draws it in the attention tone; otherwise it is a quiet outline that still takes the reader to the card.
 */
export interface CaseAction {
  needsYou: boolean;
  /** The words on the button: "Decide on the resend", "Escalate to a team", "No action needed". */
  label: string;
  /** The compact copy's word: "Needs you" or "No action". */
  short: string;
  /** The accessible name, the state in a sentence, the label inside it: "Needs you: decide on the resend". */
  name: string;
  /**
   * Where the button goes when the action is done somewhere else than "What needs you now": the side by side of a
   * scenario's two runs, the review of the exact plan with its Approve and Reject, or the Escalations panel.
   */
  goes?: ActionPlace;
  /** Nothing is pending, but the outcome isn't what the scenario expects: never drawn as all clear. */
  differs?: boolean;
}

export type ActionPlace = 'compare' | 'approval' | 'escalations';

const lowerFirst = (t: string) => t.charAt(0).toLowerCase() + t.slice(1);

const yours = (label: string, goes?: ActionPlace): CaseAction => ({
  needsYou: true,
  label,
  short: 'Needs you',
  name: `Needs you: ${lowerFirst(label)}`,
  ...(goes ? { goes } : {}),
});

const nothing = (why = ''): CaseAction => ({
  needsYou: false,
  label: 'No action needed',
  short: 'No action',
  name: `No action needed on this case${why ? `: ${why}` : ''}`,
});

/**
 * A closed case that came out other than its scenario expects has nothing pending, and "No action needed" would still
 * read as all clear under a wrong write. S8 has its other run to compare with, once this install has played both;
 * otherwise, as for another scenario, the button shows the card's words.
 */
const notExpected = (scenario: string, comparable: boolean): CaseAction =>
  scenario === 'S8' && comparable
    ? {
        needsYou: false,
        label: 'Compare the two runs',
        short: 'Compare',
        name: 'Not the expected outcome: compare the two runs',
        goes: 'compare',
        differs: true,
      }
    : {
        needsYou: false,
        label: 'See what differs',
        short: 'Differs',
        name: 'Not the expected outcome: see what differs',
        differs: true,
      };

const notYours = (label: string, why = ''): CaseAction => ({
  needsYou: false,
  label,
  short: 'No action',
  name: `No action for you: ${why || lowerFirst(label)}`,
});

/**
 * Whether a stopped case can be marked handled by the team: once an escalation email was sent or saved as an email file
 * (a saved file may have been passed on by hand, and the close is a person's statement), or at once for a
 * withheld case (a merge or a cancel Shutter never sends), where reinvestigating could find nothing new. The
 * Escalations panel offers the button and the action button names it on this one rule.
 */
export const closableByHand = (c: Pick<CaseDetail, 'failureKind'>, escalations: Escalation[]): boolean =>
  c.failureKind === 'withheld' || escalations.some((e) => e.state === 'sent' || e.state === 'saved');

export interface ActionContext {
  /** The signed-in user, once read; undefined while not read. */
  me: Me | null | undefined;
  /**
   * Whether the site keeps the two-person rule for closing a case by hand (the site profile's `close_needs_approver`);
   * undefined while the profile is not read, when only an approver is known to be able to close.
   */
  closeNeedsApprover?: boolean;
  /** The trial: a reinvestigation needs a real model and is not offered. */
  trial?: boolean;
  /** The case closed with an outcome its scenario doesn't expect (lib/status.ts caseOutcome). */
  notAsExpected?: boolean;
  /** Both of S8's runs are here to compare; the side by side has nothing to show without them. */
  comparable?: boolean;
}

/**
 * The case's action for this user:
 * - waiting for approval: an approver decides on the plan ("Decide on the resend"), and the button opens the review of
 *   the exact plan directly; anyone else waits for one;
 * - stopped (blocked, escalated, failed): an operator marks it handled once the escalation went out (at once for a
 *   withheld case), escalates it
 *   when that is the next step, reinvestigates a failed one (not in the trial), and otherwise decides the next step
 *   "What needs you now" names; a user who cannot operate waits for an operator, and a site with the two-person rule
 *   leaves closing to an approver;
 * - closed other than its scenario expects: the way to see that;
 * - running, or closed: nothing is needed.
 */
export function caseActionOf(f: CaseFacts, ctx: ActionContext): CaseAction {
  const { c } = f;
  const next = nextAction(f);
  if (ctx.notAsExpected && next.kind === 'none') return notExpected(c.scenario, !!ctx.comparable);
  if (c.disposition === 'abandoned' || c.disposition === 'handled_by_hand' || next.kind === 'none')
    return nothing();
  if (next.kind === 'shutter') return nothing(`Shutter is ${caseState(c.state).label.toLowerCase()}`);
  const can = resolveCan(ctx.me);
  if (c.state === 'awaiting_approval') {
    if (!can.approve) return notYours('Waiting for an approver');
    return yours(decisionLabels(f.plan?.plan).decide, 'approval');
  }
  if (!can.operate) return notYours('Waiting for an operator');
  // Once the email to the team was sent or saved as a file (or at once for a withheld case) the team corrects the systems and the case
  // is marked handled, as the escalations' panel offers it; a site with the two-person rule leaves that to an approver
  if (closableByHand(c, f.escalations ?? [])) {
    const mayClose = !!ctx.me?.approver || ctx.closeNeedsApprover === false;
    return mayClose
      ? yours('Mark as handled', 'escalations')
      : notYours('Waiting for an approver', 'waiting for an approver to mark it handled');
  }
  if (next.escalate) return yours('Escalate to a team', 'escalations');
  if (c.state === 'failed')
    return ctx.trial
      ? notYours('Reinvestigate', 'reinvestigate needs a real model, not in the trial')
      : yours('Reinvestigate');
  return yours('Decide the next step');
}
