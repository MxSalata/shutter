/**
 * The plain definitions a `Term` shows (a dotted underline with a popover on hover, focus and tap), checked against
 * the code's own hints. Each is at most 25 words. `standard: true` marks HL7's own terms, which an engineer knows:
 * with Detail on Technical they render as plain text. Shutter's own terms keep their definition there and lose only
 * the underline. Terms not defined here (epoch, operation key, plan digest) stay in layer 2 with their exact values.
 */
export interface GlossaryEntry {
  /** The words the definition is about, as a heading in the popover. */
  term: string;
  definition: string;
  /** One of HL7's own terms (ADT, its events, MSH-7, HL7, an HL7 transfer, the PAS). */
  standard?: boolean;
}

export const GLOSSARY = {
  gate: {
    term: 'Gate',
    definition:
      'Mechanical checks of the plan against the evidence, before the rehearsal and again before sending. An unknown answer blocks a write.',
  },
  rehearsal: {
    term: 'Rehearsal (dry run)',
    definition: 'The receiving system tries the exact write and rolls it back, so we know it would apply.',
  },
  'conditional-write': {
    term: 'Conditional write',
    definition:
      'A write that names the record version it expects. If the record changed, the receiver refuses it.',
  },
  release: {
    term: 'Release',
    definition:
      "After the gate, a person with the approver role, or the site's written policy, lets the write go.",
  },
  verified: {
    term: 'Verified at the receiver',
    definition:
      "Shutter read the receiving system's own history and found the update there. It shows the update landed, not that it was the right one.",
  },
  superseded: {
    term: 'Superseded',
    definition: 'A later event already moved the patient on. Sending the old message now would undo it.',
  },
  reconcile: {
    term: 'Reconcile',
    definition: 'The receiver already has it. Shutter records that and sends nothing.',
  },
  escalate: {
    term: 'Escalate',
    definition: 'A person must decide. Shutter writes nothing and drafts the hand-off.',
  },
  'catalogue-entry': {
    term: 'Catalogue entry (E1 to E19)',
    definition: "A known failure pattern and its recovery, in the site's catalogue.",
  },
  board: {
    term: 'Board',
    definition:
      'Three specialist agents read the same evidence in parallel; a coordinator agent turns their findings into one plan. They run on IRIS AI Hub.',
  },
  dissent: {
    term: 'Dissent',
    definition: 'A specialist agent disagreed with the plan. The coordinator kept the disagreement in it.',
  },
  production: {
    term: 'Production',
    definition:
      'The IRIS set-up that carries messages between hospital systems. In the trial, a recorded one.',
  },
  receiver: {
    term: 'Receiver',
    definition: 'The hospital system a message was going to, such as bed management or the patient record.',
  },
  write: {
    term: 'Write (a fix)',
    definition: 'An update Shutter sends to that system to put it right.',
  },
  iris: {
    term: 'IRIS',
    definition:
      "The InterSystems engine that carries messages between the hospital's systems. Shutter runs inside it.",
  },
  encounter: {
    term: 'Encounter',
    definition:
      "One patient's hospital stay or visit, with its own number. Admits, transfers and discharges move it.",
  },
  'patient-number': {
    term: 'Patient number',
    definition: 'The hospital number the message carries (PID-3). Shutter shows no name or date of birth.',
  },
  bedmgr: {
    term: 'BEDMGR',
    definition:
      'The bed manager: the system that allocates beds. It can send its own ward moves, as the PAS does.',
  },
  pas: {
    term: 'PAS',
    definition: 'The patient administration system, where admissions and transfers start.',
    standard: true,
  },
  hl7: {
    term: 'HL7',
    definition:
      'The standard format hospital systems use to send each other messages, such as a patient transfer.',
    standard: true,
  },
  'hl7-transfer': {
    term: 'HL7 transfer',
    definition: 'A message telling another hospital system that a patient moved ward.',
    standard: true,
  },
  'simple-rules': {
    term: 'Rules only (no agents)',
    definition:
      'The baseline mode, with no agents: resend the failed message unchanged and let the gate decide.',
  },
  'message-trace': {
    term: 'Message trace (Visual Trace)',
    definition: "IRIS's own picture of every message a session carried, in the Management Portal.",
  },
  incident: {
    term: 'Incident',
    definition: 'Many failures to one receiver within a few minutes, handled together.',
  },
  chain: {
    term: 'Chain',
    definition: "One patient encounter's failed messages in an incident, sent in event order.",
  },
  tier: {
    term: 'Tier',
    definition:
      'How sensitive a receiver is (1 information, 2 operations, 3 clinical safety). It sets who releases a write.',
  },
  'receiver-kind': {
    term: 'Current state / History of record',
    definition:
      'Two kinds of receiver: one needs only where the patient is now; the other needs every movement in its history.',
  },
  adt: {
    term: 'ADT, A01, A02, A03, A11 to A13, A40',
    definition:
      "HL7's admission, transfer and discharge messages: admit, transfer, discharge, their cancels, and a patient merge.",
    standard: true,
  },
  'msh-7': {
    term: 'MSH-7',
    definition: "The date and time field in an HL7 message's header.",
    standard: true,
  },
  pass: { term: 'Pass', definition: 'One board decision on one case.' },
  precedent: {
    term: 'Precedent',
    definition:
      'What an approver decided before on the same evidence at the same receiver. It informs a decision and never releases anything.',
  },
  replay: {
    term: 'Replay',
    definition: "The agent's answer is the one a run recorded with the real agent gave; no model is called.",
  },
  'cache-read': {
    term: 'Cache read',
    definition: 'Tokens the provider served from its prompt cache, at a lower price.',
  },
  outweighed: { term: 'Outweighed', definition: 'The plan set this view aside for another.' },
  knows: {
    term: 'Knows',
    definition:
      "The member's own knowledge collection: the documents it reads (contracts, lifecycle, effects, playbooks).",
  },
  'one-failure': { term: 'One failed message', definition: 'One failure with nothing applied after it.' },
  'in-a-row': {
    term: 'Several, in a row',
    definition: 'Several failures with no successful delivery between them.',
  },
  'with-deliveries-between': {
    term: 'Several, with deliveries between',
    definition: 'Successful deliveries between the failures, or a later event already applied.',
  },
} satisfies Record<string, GlossaryEntry>;

export type GlossaryKey = keyof typeof GLOSSARY;

export const glossary = (key: GlossaryKey): GlossaryEntry => GLOSSARY[key];
