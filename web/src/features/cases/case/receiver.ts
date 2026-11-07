import type {
  AttemptView,
  CaseDetail,
  CorrectionSteps,
  PlanView,
  ReceiverCategory,
  Snapshot,
} from '@/api/types';
import { CATEGORY_TEXT, asCategory } from '@/lib/categories';
import { asObject } from '@/lib/json';
import { notModelled } from './derive';
import { WRITE_OUTCOMES } from './receipt';

/**
 * The receiver a case is about: a case is one failed delivery to one receiver (CONTRACTS 1.25). Its name is the case's
 * own; its category and history policy are what the evidence recorded (route.category, route.history_policy), so a
 * later edit of the site profile never changes what the case says it was judged by.
 */
export interface CaseReceiver {
  /** The production item, such as Downstream Out or Records Out. */
  name: string;
  /** What it is, as the route describes it ("the demo patient records system (/records/api)"); may be empty. */
  system: string;
  /** Undefined for a case whose evidence predates categories. */
  category?: ReceiverCategory;
  historyPolicy?: string;
}

/** The route item of the snapshot: the connector, the receiver's description, its tier, category and policy. */
function routeOf(snapshot: Snapshot | null | undefined): Record<string, unknown> | null {
  const item = snapshot?.items?.find((i) => i.kind === 'route');
  return asObject(item?.data) ?? asObject(asObject(snapshot?.summary)?.route) ?? null;
}

export function caseReceiver(c: CaseDetail, snapshot: Snapshot | null | undefined): CaseReceiver {
  const route = routeOf(snapshot);
  const connector = typeof route?.connector === 'string' ? route.connector : '';
  return {
    // A case recorded before the server named its receiver went to the only one there was, the bed manager
    name: c.receiver || connector || 'Downstream Out',
    system: typeof route?.receiver === 'string' ? route.receiver : '',
    category: asCategory(route?.category),
    historyPolicy: typeof route?.history_policy === 'string' ? route.history_policy : undefined,
  };
}

/**
 * The receiver as a sentence names it: the case's production item (Records Out), or "the downstream system" for a case
 * recorded before cases named their receiver.
 */
export function receiverNoun(name?: string): string {
  return name || 'the downstream system';
}

/** The same at the start of a sentence. */
export function capitalReceiverNoun(name?: string): string {
  const n = receiverNoun(name);
  return n.charAt(0).toUpperCase() + n.slice(1);
}

/** Who an escalation goes to when no team is chosen: the team that owns the case's receiver. */
export function receiverTeam(name?: string): string {
  return name ? `the ${name} team` : "the downstream system's team";
}

/** "Records Out, history of record" for beside the outcome; the name alone when the evidence names no category. */
export function receiverLine(r: CaseReceiver): string {
  return r.category ? `${r.name}, ${CATEGORY_TEXT[r.category].label.toLowerCase()}` : r.name;
}

/**
 * The steps that correct a history-of-record receiver's history by hand, from the plan of a case escalated with the
 * outcome correct_history (CONTRACTS 10); null for any other plan.
 */
export function correctionStepsOf(plan: PlanView | null | undefined): CorrectionSteps | null {
  const inner = asObject(plan?.plan?.plan);
  const steps = asObject(inner?.correction_steps);
  if (!steps || !Array.isArray(steps.steps) || steps.steps.length === 0) return null;
  return {
    ...(steps as unknown as CorrectionSteps),
    steps: steps.steps.filter((s): s is string => typeof s === 'string'),
  };
}

/**
 * What the engine finishing with a message allows a case to say. Completed is the engine's word, and an acknowledgement
 * says only what the site declares it means: neither is a read of the receiver, which is what a receipt and the verifier
 * are. A level is the effective one the evidence's route item carries, when the build and the receiver give one.
 */
export type AckLevel = 'connection' | 'commit' | 'application';

/** Lowest first: the page never reads higher than the delivered sentence or the route item, whichever is lower. */
const ACK_LEVELS: AckLevel[] = ['connection', 'commit', 'application'];

const ACK_WORDS: Record<AckLevel, string> = {
  connection: 'accepted on the connection',
  commit: "accepted by the receiver's transport; processing not confirmed",
  application: "accepted by the receiver's application, as declared in the site profile",
};

export const NOT_CHECKED = 'Not checked at the receiver';

/** The heading of the step and the panel where a case has no receipt. */
export const AT_THE_RECEIVER = 'At the receiver';

/** The level on the route item; undefined when it carries none, or a word that is no level (no acceptance to claim). */
export function ackLevelOf(snapshot: Snapshot | null | undefined): AckLevel | undefined {
  const level = routeOf(snapshot)?.ack_level;
  return ACK_LEVELS.find((l) => l === level);
}

/** Whether the case was resolved by the engine's own delivery: the sentence both resolvers write, and no other. */
export function deliveredByEngine(c: Pick<CaseDetail, 'state' | 'outcome'>): boolean {
  return c.state === 'resolved' && /^delivered by the engine\b/i.test(c.outcome ?? '');
}

/** Whether the outcome is the engine's Completed with acceptance not established: it names no level. */
const completedOnly = (c: Pick<CaseDetail, 'outcome'>) =>
  /^IRIS marked (this|the) delivery Completed\b/.test(c.outcome ?? '');

/** The level the delivered sentence itself names, if any. */
function sentenceLevel(outcome: string): AckLevel | undefined {
  if (outcome.includes('accepted on the connection')) return 'connection';
  if (outcome.includes("receiver's transport")) return 'commit';
  if (outcome.includes("receiver's application")) return 'application';
  return undefined;
}

/** The words a delivered case's level allows: the lower of the route item's and its sentence's; empty with no level. */
function acceptedWords(c: Pick<CaseDetail, 'state' | 'outcome'>, level: AckLevel | undefined): string {
  if (!level || !deliveredByEngine(c)) return '';
  const said = sentenceLevel(c.outcome ?? '');
  const lower = said && ACK_LEVELS.indexOf(said) < ACK_LEVELS.indexOf(level) ? said : level;
  return ACK_WORDS[lower];
}

/** A receiver's answer, the verifier's or a write of Shutter's that may have landed: the case has something to read. */
function hasReceipt(attempts: AttemptView[]): boolean {
  return attempts.some(
    (x) =>
      x.verification ||
      asObject(x.attempt?.receipt) ||
      WRITE_OUTCOMES.includes(String(x.attempt?.outcome ?? '')),
  );
}

export interface NotChecked {
  /** The case's outcome in the server's words: DeliveredWords' sentence, with its level in it, on a delivered case. */
  outcome: string;
  /** What the level allows, only where the engine delivered the message: an unresolved case has accepted nothing. */
  accepted: string;
}

/**
 * How a case with no receipt reads, or null for today's words: a case with a receipt or a write of Shutter's keeps them,
 * and so does an ADT case at a receiver with no declared level that the engine did not deliver, whose words already say
 * why there is nothing to check. The rest, an order or a result, a case the engine delivered, a case at a receiver that
 * declares a level, are read from the engine's word and the site's, not from the receiver, and say so. With the attempts
 * not read yet, today's words stand, as they say unknown rather than guess.
 */
export function notCheckedAtReceiver(
  c: CaseDetail,
  snapshot: Snapshot | null | undefined,
  attempts: AttemptView[] | null | undefined,
): NotChecked | null {
  if (!attempts || hasReceipt(attempts)) return null;
  const level = ackLevelOf(snapshot);
  const orders = !!notModelled(c) || asCategory(routeOf(snapshot)?.category) === 'orders_results';
  if (!orders && !level && !deliveredByEngine(c) && !completedOnly(c)) return null;
  return { outcome: c.outcome ?? '', accepted: acceptedWords(c, level) };
}

/** The same for the failure map's receiver box, which reads only what the engine delivered. */
export function deliveredByEngineWords(c: CaseDetail, snapshot: Snapshot | null | undefined): string {
  if (!deliveredByEngine(c)) return '';
  return [NOT_CHECKED, acceptedWords(c, ackLevelOf(snapshot))].filter(Boolean).join('; ');
}
