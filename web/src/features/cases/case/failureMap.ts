import type { CaseDetail, Snapshot } from '@/api/types';
import { humanize } from '@/lib/format';
import type { CaseOutcome } from '@/lib/status';
import type { Tone } from '@/lib/tone';
import { notModelled } from './derive';
import { evidenceOf } from './message';
import { SYSTEMS } from './outcome';

const str = (v: unknown) => (v === undefined || v === null ? '' : String(v));

/**
 * "Where it failed": the message's path drawn as boxes, the sending system, IRIS and the receiving system, with the hop
 * that broke marked and where Shutter stands. Every part comes from the case and its evidence (the case's source system
 * and failure, the route its evidence recorded, a forwarded case's source); a part the data does not give is left out
 * or named by what is known, never invented.
 */
export interface FailureMap {
  /** The system that sent the message (the case's source system, else MSH-3); null when neither is recorded. */
  sender: { name: string; gloss: string } | null;
  /** What was sent: the event in words ("Transfer to WARD-B") and, for the engineer, MSH-9 ("ADT^A02"). */
  message: { plain: string; code: string };
  iris: {
    /** What IRIS is here, in words: Shutter's own feed, or the hospital's production that forwarded the case. */
    role: string;
    /** For the engineer: the production and namespace of a forwarded case, else empty. */
    where: string;
    /** For the engineer: the route's items in order, as the evidence recorded them (ADT In, ADT to Downstream, ...). */
    items: string[];
    /** Why IRIS itself stopped or could not read the message, in words; empty when it read it. */
    trouble: string;
  };
  receiver: {
    /** The receiving system in words ("Bed-management system"), else its production item. */
    name: string;
    /** For the engineer: the production item and the receiver's API, as the route recorded them. */
    item: string;
    api: string;
    /** What the receiver holds now, when Shutter's resend was verified there; empty otherwise. */
    now: string;
  };
  /**
   * The hop from IRIS to the receiver: what happened on it, the receiver's answer when it gave one, and for the
   * engineer the reason code of a delivery never attempted (a withheld merge); in a tone, broken when a delivery failed.
   */
  hop: { label: string; answer: string; code: string; tone: Tone; broken: boolean };
  shutter: {
    /** "Shutter picked up the failure", with where from for a forwarded case and its incident. */
    picked: string;
    /** The outcome as the band says it, in its tone. */
    outcome: CaseOutcome;
    /** For the engineer: the reason code the case stopped on, when it did. */
    code: string;
  };
  /** The whole picture in one sentence, for the diagram's accessible name. */
  sentence: string;
  /** The same facts as steps, for a screen reader's list. */
  steps: string[];
}

/** The route the evidence recorded for the receiver: "ADT In -> ADT to Downstream -> Downstream Out". */
function routeItems(route: Record<string, unknown> | null): string[] {
  return str(route?.feed)
    .split(/\s*(?:->|→)\s*/)
    .map((x) => x.trim())
    .filter(Boolean);
}

/**
 * The receiver's description in words, as the route records it: "the demo bed-management system (/downstream/api)"
 * gives "Bed-management system" and the API "/downstream/api".
 */
export function receiverWords(description: string): { name: string; api: string } {
  const api = /\(([^)]*)\)\s*$/.exec(description)?.[1] ?? '';
  const name = description
    .replace(/\([^)]*\)\s*$/, '')
    .replace(/^the\s+/i, '')
    .replace(/^demo\s+/i, '')
    .trim();
  return { name: name ? name.charAt(0).toUpperCase() + name.slice(1) : '', api };
}

/** The receiver's answer as it gave it: "HTTP 503 ward_unavailable"; empty when it gave none. */
function answerOf(c: CaseDetail): string {
  return [c.failureHttpStatus ? `HTTP ${c.failureHttpStatus}` : '', str(c.failureReasonCode)]
    .filter(Boolean)
    .join(' ');
}

/** The hop to the receiver, by how the delivery failed. */
function hopOf(c: CaseDetail): FailureMap['hop'] {
  const answer = answerOf(c);
  const code = str(c.failureReasonCode);
  // An order, a result or a document: "Not sent" would be false when the receiver refused it or never answered
  switch (notModelled(c)) {
    case 'not_delivered':
      return { label: 'Not delivered', answer: '', code: '', tone: 'blocking', broken: true };
    case 'refused':
      return { label: 'Refused', answer: '', code: '', tone: 'blocking', broken: true };
    case 'unknown':
      return { label: 'Answer lost: outcome unknown', answer: '', code: '', tone: 'attention', broken: true };
    default:
  }
  switch (c.failureKind) {
    case 'delivery_failed':
      return { label: 'Not delivered', answer, code: '', tone: 'blocking', broken: true };
    case 'rejected':
      return { label: 'Refused', answer, code: '', tone: 'blocking', broken: true };
    case 'uncertain_outcome':
      return { label: 'Answer lost: outcome unknown', answer, code: '', tone: 'attention', broken: true };
    case 'withheld':
      return {
        label: "Withheld by the site's policy: never sent",
        answer: '',
        code,
        tone: 'neutral',
        broken: false,
      };
    case 'unreadable':
      return { label: 'Held: nothing sent', answer: '', code, tone: 'neutral', broken: false };
    case 'unmappable':
      return c.failureHttpStatus
        ? { label: 'Not delivered', answer, code: '', tone: 'blocking', broken: true }
        : { label: 'Not sent', answer: '', code, tone: 'neutral', broken: false };
    default:
      return { label: humanize(c.failureKind) || 'Failed', answer, code: '', tone: 'blocking', broken: true };
  }
}

/** Why IRIS itself could not take the message on, in words: held unread, unmapped, or not read by the schema. */
function troubleOf(c: CaseDetail, snapshot: Snapshot | null | undefined): string {
  if (c.failureKind === 'unreadable') return "Couldn't read the message: its HL7 schema is not loaded here";
  if (c.failureKind === 'unmappable' && !notModelled(c)) return "Couldn't map the message to an operation";
  const validation = evidenceOf(snapshot, 'validation');
  if (validation && validation.parsed === false) return "Its schema couldn't read the message";
  return '';
}

const lowerFirst = (t: string) => t.charAt(0).toLowerCase() + t.slice(1);

/**
 * The map of a case, from its own data: the case (its source system, event, failure, receiver, forwarded source and
 * incident), the evidence's message, route and validation, and the outcome as the page shows it. `delivered` says the
 * receiver now holds Shutter's resend, verified there; `code` is the reason code a stopped case stopped on.
 */
export function failureMapOf(
  c: CaseDetail,
  snapshot: Snapshot | null | undefined,
  outcome: CaseOutcome,
  { delivered = false, code = '' }: { delivered?: boolean; code?: string } = {},
): FailureMap {
  const msg = evidenceOf(snapshot, 'message');
  const route = evidenceOf(snapshot, 'route');
  const senderName = str(c.sourceSystem) || str(msg?.sending_application);
  const sender = senderName ? { name: senderName, gloss: SYSTEMS[senderName] ?? '' } : null;
  const event = humanize(c.event) || 'The message';
  const message = {
    plain: `${event}${c.ward ? ` to ${c.ward}` : ''}`,
    code: str(msg?.message_type),
  };
  // A forwarded case's message went through the hospital's own production; the route the evidence names is Shutter's
  const forwarded = !!str(c.sourceNamespace);
  const items = forwarded ? [str(c.sourceRoute)].filter(Boolean) : routeItems(route);
  const iris = {
    role: forwarded ? "The hospital's production" : 'The message engine',
    where: forwarded
      ? [str(c.sourceProduction), str(c.sourceNamespace) ? `in ${str(c.sourceNamespace)}` : '']
          .filter(Boolean)
          .join(' ')
      : '',
    items,
    trouble: troubleOf(c, snapshot),
  };
  const described = receiverWords(str(route?.receiver));
  // A case recorded before the server named its receiver went to the only one there was, as caseReceiver says
  const item = c.receiver || str(route?.connector) || 'Downstream Out';
  // In a sentence: "the bed-management system", or the item's own name, which keeps its capitals
  const noun = described.name ? `the ${lowerFirst(described.name)}` : item;
  const receiver = {
    name: described.name || item,
    item: described.name ? item : '',
    api: described.api,
    now: delivered ? `Has the ${event.toLowerCase()} now: Shutter's resend, verified there` : '',
  };
  const hop = hopOf(c);
  const via = forwarded ? " from the hospital's production" : '';
  const incident = c.incidentId ? `, in incident ${c.incidentId}` : '';
  // A withheld merge or cancel is Shutter's own doing; a held message one the hospital's production stopped
  const picked =
    c.failureKind === 'withheld'
      ? 'Shutter withheld it and opened a case'
      : c.failureKind === 'unreadable'
        ? 'Shutter picked up the held message'
        : 'Shutter picked up the failure';
  const shutter = { picked: `${picked}${via}${incident}`, outcome, code };

  // The sentence: who sent what, through IRIS, to whom, what happened there, and where Shutter stands
  const what = lowerFirst(message.plain);
  const from = sender ? `${sender.name} sent the ${what}` : `The ${what} went`;
  const through = forwarded ? "through the hospital's production in IRIS" : 'through IRIS';
  const answered = hop.answer ? `, answered ${hop.answer}` : '';
  const happened = iris.trouble
    ? `in IRIS, ${lowerFirst(iris.trouble)}; ${lowerFirst(hop.label)}${answered}`
    : `${lowerFirst(hop.label)}${answered}`;
  const now = `now ${lowerFirst(outcome.label)}`;
  const sentence = `${from} ${through} to ${noun}: ${happened}. ${shutter.picked}; ${now}.${receiver.now ? ` The receiver ${lowerFirst(receiver.now)}.` : ''}`;
  const steps = [
    sender ? `Sender: ${sender.name}${sender.gloss ? `, the ${sender.gloss},` : ''} sent the ${what}.` : '',
    `IRIS, ${lowerFirst(iris.role)}${iris.trouble ? `: ${lowerFirst(iris.trouble)}` : ''}.`,
    `Receiver: ${noun}, ${lowerFirst(hop.label)}${answered}.${receiver.now ? ` It ${lowerFirst(receiver.now)}.` : ''}`,
    `${shutter.picked}; ${now}.`,
  ].filter(Boolean);
  return { sender, message, iris, receiver, hop, shutter, sentence, steps };
}
