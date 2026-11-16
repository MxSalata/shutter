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

/**
 * The FHIR gate's questions (docs/readme/fhir.md, "What stops it"): main's rows it keeps where they apply, with main's
 * words, then its own rows, and the two whose ADT question would be false there (no dry run exists for a FHIR receiver;
 * its capability is what was measured, not what it declares). The case page's gate table and this site's guide read it.
 */
export const FHIR_CHECK_QUESTIONS: Record<string, string> = {
  ...CHECK_QUESTIONS,
  rehearsal: 'No dry run exists for this receiver. What stands in its place?',
  capability: 'Does the server refuse a stale If-Match and keep version history, as measured?',
  enablement: 'Has the site turned recovery on for this receiver?',
  representation: 'Is the record whole enough to change?',
  mapping: 'Are both wards mapped to Locations that still match?',
  plan_shape: 'Is the change exactly the one move?',
  history: 'Was the history read, and is it free of an earlier update?',
  earlier_write: 'Is an earlier update of this case still unsettled?',
};

/** The rows of main's gate the FHIR gate keeps (docs/readme/fhir.md): the message's conformance, the plan's intent, the approval, fresh evidence, the catalogue. */
export const FHIR_KEEPS_MAIN = ['conformance', 'intent', 'authorization', 'evidence', 'catalogue'];

/** The FHIR gate's own rows and the two it answers its own way, in the order the guide lists them. */
export const FHIR_OWN = [
  'enablement',
  'representation',
  'mapping',
  'plan_shape',
  'history',
  'earlier_write',
  'capability',
  'rehearsal',
];

/** What stands in for a dry run at a FHIR receiver, in the words every FHIR gate decision carries (docs/readme/fhir.md). */
export const FHIR_NO_DRY_RUN =
  "No dry run exists for this receiver. Substituted: a complete versioned read, a bounded change, If-Match on the version read, this case's own approval by a person, and a search of the returned history for the marked version, read back by id when the answer named it.";
