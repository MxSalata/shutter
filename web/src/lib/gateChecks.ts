/**
 * The gate's twelve checks (CONTRACTS 6.5, Shutter.Operation.Gate), each with the question it answers in one line: the
 * words the case page's gate table shows under each check's name, and this site's guide lists. The order is the gate's
 * own, as docs/readme/how-shutter-works.md section 7 gives it.
 */
export const CHECK_QUESTIONS: Record<string, string> = {
  identity: 'Same patient and encounter at the receiver?',
  conformance: 'Does the message parse against its schema?',
  intent: "Does the plan send only the case's own operation, unchanged?",
  ordering: 'Has no later event moved the encounter on?',
  state_transition: "Can the encounter's state at the receiver take this event?",
  effect: 'Is the operation not committed at the receiver already?',
  authorization: "Has a person, or the site's written policy, released the write?",
  concurrency: 'Is the receiver still at the version the plan is conditional on?',
  evidence: 'Is the evidence recent enough to act on?',
  capability: 'Does the receiver take conditional writes, keep receipts and history?',
  catalogue: 'Does an entry of the scenario catalogue match the evidence?',
  rehearsal: "Did the receiver's dry run say this would apply?",
};

/**
 * When each check decides, as the gate runs them: every check runs at the proposal and again at the dispatch, after the
 * release and a fresh read of the receiver; the release and the dry run exist only after the proposal, so those two
 * checks pass there as not yet required and decide at the approval and the dispatch (Gate.cls, NOT_YET_REQUIRED).
 */
export const CHECK_STAGES: Record<string, string> = {
  authorization: 'Decides at the approval and at the dispatch',
  rehearsal: 'Decides at the approval and at the dispatch, on the dry run the approval binds',
};

export const CHECK_STAGE_DEFAULT = 'At the proposal, and again at the dispatch';

/** The sentence the gate's outcome comes to: the worst check wins, and an unknown counts as a block for a write. */
export const UNKNOWN_BLOCKS = 'An unknown answer blocks a write, as a block does.';
