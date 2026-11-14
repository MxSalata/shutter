import type { CaseDetail, Plan, Snapshot } from '@/api/types';
import { humanize } from '@/lib/format';
import { asObject } from '@/lib/json';
import { fhirSummary, orderOrResult, quotedVersion, receiverKind } from './derive';
import { evidenceOf } from './message';

/**
 * The plan's action in plain words, put together once for every place that names it: the headline of The plan and of
 * the Approval section, the review dialog, the case's Next line, the receipt's Proposal and the buttons ("Approve the
 * resend"). It is read from the plan's own operation, never from a headline somebody wrote: the operation key the
 * plan carries names the sending system, the event and the encounter, and the ward and bed are those of the mapped
 * operation with that same key (the evidence's, else the case's own). A plan whose key matches neither names no
 * destination, and a version the plan does not carry is said as unknown: nothing here is guessed.
 */

/** The case's fields the words read: its own operation, and the receiver it went to. */
export type ActionCase = Pick<
  CaseDetail,
  'operationKey' | 'event' | 'ward' | 'bed' | 'sourceSystem' | 'receiver'
> &
  Partial<Pick<CaseDetail, 'failureText'>>;

/** The operation a plan sends, as far as the page can tell it from the plan's own key. */
export interface PlanOperation {
  key: string;
  sourceSystem: string;
  event: string;
  encounterId: string;
  /** The ward and bed the operation carries: an admission's or a transfer's; empty for any other event. */
  ward: string;
  bed: string;
  /**
   * Whether a mapped operation with the plan's key was at hand to read the ward and bed from. Without one they stay
   * empty, which then means unknown, not none.
   */
  mapped: boolean;
}

const str = (v: unknown) => (v === undefined || v === null ? '' : String(v));

/** An operation key's parts (CONTRACTS 2): source system, authority, patient, encounter, event and event time. */
function keyParts(key: string): { sourceSystem: string; encounterId: string; event: string } | null {
  const parts = key.split('^');
  if (parts.length !== 6 || parts.some((p) => !p)) return null;
  return { sourceSystem: parts[0], encounterId: parts[3], event: parts[4] };
}

/**
 * The operation the plan names by its key. The evidence's mapped operation is read when it carries that key, then the
 * case's own; a plan whose key is neither's (the gate's intent check blocks such a plan) is described by its key alone.
 */
export function planOperation(
  plan: Pick<Plan, 'operationKey'> | null | undefined,
  c: ActionCase,
  snapshot: Snapshot | null | undefined,
): PlanOperation | null {
  const key = str(plan?.operationKey);
  if (!key) return null;
  const parts = keyParts(key);
  const mapped = evidenceOf(snapshot, 'operation');
  if (mapped && str(mapped.operation_key) === key)
    return {
      key,
      sourceSystem: str(mapped.source_system) || parts?.sourceSystem || '',
      event: str(mapped.event) || parts?.event || '',
      encounterId: str(mapped.encounter_id) || parts?.encounterId || '',
      ward: str(mapped.ward),
      bed: str(mapped.bed),
      mapped: true,
    };
  if (c.operationKey === key)
    return {
      key,
      sourceSystem: str(c.sourceSystem) || parts?.sourceSystem || '',
      event: str(c.event) || parts?.event || '',
      encounterId: parts?.encounterId ?? '',
      ward: str(c.ward),
      bed: str(c.bed),
      mapped: true,
    };
  if (!parts) return null;
  return { key, ...parts, ward: '', bed: '', mapped: false };
}

/** The events as a sentence names them: "the PAS admission", not "the PAS admit". */
const EVENT_NOUNS: Record<string, string> = {
  admit: 'admission',
  transfer: 'transfer',
  discharge: 'discharge',
  update: 'update',
};

/**
 * "the PAS transfer to WARD-B", "the PAS discharge", "the QUILLON result" (an order or a result goes to no ward); a
 * plan that names no operation says so.
 */
function operationWords(op: PlanOperation | null, c: ActionCase): string {
  if (!op || !op.event) return 'an operation the plan does not name';
  const system = op.sourceSystem ? `${op.sourceSystem} ` : '';
  const kind = orderOrResult({ event: op.event, failureText: c.failureText });
  if (kind) return `the ${system}${kind}`;
  const noun = EVENT_NOUNS[op.event] ?? humanize(op.event).toLowerCase();
  return `the ${system}${noun}${op.ward ? ` to ${op.ward}` : ''}`;
}

/** The case's own operation: what a plan that sends nothing, and so often names no key, is about. */
const caseOperation = (c: ActionCase): PlanOperation => ({
  key: c.operationKey,
  sourceSystem: str(c.sourceSystem),
  event: str(c.event),
  encounterId: '',
  ward: str(c.ward),
  bed: str(c.bed),
  mapped: true,
});

/**
 * The receiver as a sentence names it: what the evidence's route calls it ("the bed-management system"), else the
 * case's production item (Downstream Out), else "the receiver".
 */
export function receiverPhrase(
  c: Pick<CaseDetail, 'receiver'>,
  snapshot: Snapshot | null | undefined,
): string {
  const described = str(evidenceOf(snapshot, 'route')?.receiver)
    .replace(/\([^)]*\)\s*$/, '')
    .replace(/^the\s+/i, '')
    .replace(/^demo\s+/i, '')
    .trim();
  return described ? `the ${described}` : c.receiver || 'the receiver';
}

const raise = (t: string) => t.charAt(0).toUpperCase() + t.slice(1);

/** The version a write is conditional on, when the plan carries one: 0 is a version, an empty value is not. */
function versionOf(plan: Pick<Plan, 'expectedVersion' | 'plan'>): string {
  const own = str(plan.expectedVersion);
  if (own !== '') return own;
  return str(asObject(asObject(plan.plan)?.action)?.expected_version);
}

export interface PlanWords {
  /** Whether releasing the plan writes to the receiver: only a resend does. */
  write: boolean;
  /** What the buttons name: "the resend", or "the plan" for one that writes nothing. */
  noun: string;
  /** The action alone, with no full stop: "Resend the PAS transfer to WARD-B, once". */
  action: string;
  /** What the write is conditional on, to follow the action: "only if ... is still at version 1"; empty with no write. */
  condition: string;
  /** The action and its condition as one sentence, the headline. */
  headline: string;
  /** The conditions as a short list, each a whole clause; empty for a plan that writes nothing. */
  onlyIf: string[];
}

/**
 * The words for a plan. A resend is one conditional write of the plan's own operation; every other disposition writes
 * nothing, and says so first.
 */
export function planWords(
  plan: Pick<Plan, 'disposition' | 'operationKey' | 'expectedVersion' | 'plan'>,
  c: ActionCase,
  snapshot: Snapshot | null | undefined,
): PlanWords {
  const op = planOperation(plan, c, snapshot);
  const receiver = receiverPhrase(c, snapshot);
  if (plan.disposition !== 'resend') {
    // A plan that sends nothing is about the case's own operation, whether or not it carries its key
    const what = operationWords(op ?? caseOperation(c), c);
    const action =
      plan.disposition === 'reconcile'
        ? `Send nothing: record ${what} as already delivered`
        : plan.disposition === 'superseded'
          ? `Send nothing: a later event overtook ${what}`
          : plan.disposition === 'escalate'
            ? `Send nothing: hand ${what} to a person`
            : `Send nothing to ${receiver}${plan.disposition ? `: ${humanize(plan.disposition).toLowerCase()}` : ''}`;
    return { write: false, noun: 'the plan', action, condition: '', headline: `${action}.`, onlyIf: [] };
  }
  if (receiverKind(snapshot) === 'fhir_r4') {
    // A FHIR case's write is one update of the Encounter's location with If-Match on the version read: the HL7
    // message is not sent again, and the version is the Encounter's own, quoted, with its ETag verbatim
    const e = fhirSummary(snapshot)?.encounter;
    const read = e?.etag ? `${quotedVersion(e.version_id)} (ETag ${e.etag})` : '';
    const action = "Update the Encounter's location once, with If-Match on the version read";
    const condition = read
      ? `only if the Encounter is still at version ${read}`
      : 'on an Encounter version the evidence does not name';
    return {
      write: true,
      noun: 'the resend',
      action,
      condition,
      headline: `${action}, ${condition}.`,
      onlyIf: [
        read
          ? `The Encounter is still at version ${read}`
          : 'The Encounter version the update is conditional on: unknown, the evidence names none',
        'No later event has moved the encounter on',
      ],
    };
  }
  const what = operationWords(op, c);
  const version = versionOf(plan);
  // An admission is conditional on version 0: the receiver has not seen the encounter yet (CONTRACTS 1.1)
  const unseen = version === '0' && op?.event === 'admit';
  const condition =
    version === ''
      ? 'on a receiver version the plan does not name'
      : unseen
        ? `only if ${receiver} still has no record of the encounter (version 0)`
        : `only if ${receiver} is still at version ${version}`;
  const action = `Resend ${what}, once`;
  return {
    write: true,
    noun: 'the resend',
    action,
    condition,
    headline: `${action}, ${condition}.`,
    onlyIf: [
      version === ''
        ? 'The receiver version the write is conditional on: unknown, the plan names none'
        : unseen
          ? `${raise(receiver)} still has no record of the encounter (version 0)`
          : `${raise(receiver)} still holds the encounter at version ${version}`,
      'No later event has moved the encounter on',
    ],
  };
}

/** The words on the buttons that decide on a plan, and the name of its review. */
export interface DecisionLabels {
  /** "the resend" or "the plan": what the labels name. */
  noun: string;
  approve: string;
  reject: string;
  decide: string;
  nextAction: string;
}

/**
 * "Approve the resend"; "Approve the plan" for a plan that writes nothing. Only a write waits for an approval, so a
 * plan not read yet is named as the resend, as the case's action button names it.
 */
export function decisionLabels(plan: Pick<Plan, 'disposition'> | null | undefined): DecisionLabels {
  const noun = plan && plan.disposition !== 'resend' ? 'the plan' : 'the resend';
  return {
    noun,
    approve: `Approve ${noun}`,
    reject: `Reject ${noun}`,
    decide: `Decide on ${noun}`,
    nextAction: `Approve or reject ${noun}`,
  };
}
