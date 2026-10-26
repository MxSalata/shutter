import type { CaseDetail, CorrectionSteps, PlanView, ReceiverCategory, Snapshot } from '@/api/types';
import { CATEGORY_TEXT, asCategory } from '@/lib/categories';
import { asObject } from '@/lib/json';

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
