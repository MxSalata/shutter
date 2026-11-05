import { TRIAL } from './mode';

/**
 * The live wording or the trial's, in one place, so both can be read side by side. Live speaks as the product always
 * has (exact, third person, every fact stated); the trial speaks to a newcomer (second person, short, and plain that
 * the action replays a recording and nothing leaves the browser).
 */
export const byEnv = <T>(v: { live: T; trial: T }): T => (TRIAL ? v.trial : v.live);

/** The reasons a control the trial cannot serve shows disabled, never hidden, so the capability stays visible. */
export const NOT_IN_TRIAL = {
  /** Convene the board, Reinvestigate: they need a model call, which the trial never makes. */
  model: 'Needs a real model: not in the trial',
  /** Abandon, and anything else the recording has no answer for. */
  recording: "Not in the trial's recording",
  /** Free-text questions in Ask about this case. */
  freeText: 'In the trial, pick a suggested question',
} as const;

/** What a reader without the approver role does about it. The trial has no sign-in of that kind: its roles are in the user menu. */
export const toBecomeApprover = () =>
  byEnv({ live: 'sign in as approver', trial: 'switch to Approver in the user menu' });
