import type {
  FindingSource,
  FindingStatus,
  ReviewAgent,
  ReviewDetail,
  ReviewFinding,
  ReviewTarget,
  Severity,
} from '@/api/types';

/**
 * What the production review page decides from a review (CONTRACTS 13): the order of the findings, what a blank item
 * stands for, the agent's state in words and the note on the HL7 checks. Pure functions, so they are tested alone.
 */

export const READ_ONLY =
  'The review never changes the production: a person applies any change in the Management Portal.';

export const SEVERITIES: Severity[] = ['high', 'medium', 'low', 'info'];

export const SEVERITY_COLOURS: Record<Severity, string> = {
  high: 'red',
  medium: 'orange',
  low: 'yellow',
  info: 'gray',
};

export const CONFIDENCE_HINTS: Record<string, string> = {
  confirmed: 'Read from the configuration',
  consistent: 'The configuration is consistent with the pattern',
  indicative: 'A count that nobody has read yet',
};

export const SOURCE_LABELS: Record<FindingSource, string> = {
  item: "the item's own setting",
  default_setting: 'a system default setting',
  class_default: 'the class default',
  observed: 'observed',
};

export const STATUS_LABELS: Record<FindingStatus, string> = {
  new: 'New',
  intended: 'Intended',
  accepted_risk: 'Accepted risk',
  false_positive: 'False positive',
};

/** The findings about the namespace rather than its production: the purge task, and a namespace that could not be read. */
const NAMESPACE_CODES = /^(PURGE_|BODIES_KEPT$|NAMESPACE_UNREADABLE$)/;

/** What a finding is about: its item, or, when the item is blank, the production or the namespace. Never a blank. */
export function subjectOf(f: Pick<ReviewFinding, 'code' | 'item'>): string {
  if (f.item) return f.item;
  return NAMESPACE_CODES.test(f.code) ? 'the namespace' : 'the production';
}

/** The agent's order is used only when it answered and ranked every finding; otherwise the baseline order stands. */
export function rankedByAgent(review: Pick<ReviewDetail, 'agent' | 'findings'>): boolean {
  return (
    review.agent.state === 'ok' &&
    review.findings.length > 0 &&
    review.findings.every((f) => typeof f.rank === 'number')
  );
}

/** The findings as the page lists them: by the agent's rank when rankedByAgent, else as the server sent them. */
export function orderedFindings(review: Pick<ReviewDetail, 'agent' | 'findings'>): ReviewFinding[] {
  if (!rankedByAgent(review)) return review.findings;
  return [...review.findings].sort((a, b) => (a.rank as number) - (b.rank as number));
}

/**
 * Whether the page says the production has no HL7 TCP item: only when the server counted them and found none. The
 * reply code and framing checks need one; without the count the page says nothing either way.
 */
export function noHl7TcpItem(review: Pick<ReviewDetail, 'state' | 'unreadable' | 'summary'>): boolean {
  return review.state === 'done' && !review.unreadable && review.summary.hl7TcpItems === 0;
}

/**
 * Whether a finding's evidence.latestHeaderId is a message header. For RULE_ERRORS it is the id of a row in the rule
 * log (Ens_Rule.Log), which has no message page.
 */
export function evidenceIsHeader(f: Pick<ReviewFinding, 'code'>): boolean {
  return f.code !== 'RULE_ERRORS';
}

/** The items a production-wide finding lists (ALERTING_OFF, QUEUE_ALERTS_OFF write them "; " separated). */
export function foundList(f: Pick<ReviewFinding, 'code' | 'found'>): string[] {
  if (f.code !== 'ALERTING_OFF' && f.code !== 'QUEUE_ALERTS_OFF') return [f.found];
  return f.found
    .split('; ')
    .map((x) => x.trim())
    .filter(Boolean);
}

export interface AgentView {
  title: string;
  colour: string;
  text: string;
}

/** The agent's part in plain words, one per state; the deterministic report stands whatever it says. */
export function describeAgent(agent: ReviewAgent, reviewState: string): AgentView {
  if (reviewState === 'failed')
    return {
      title: 'Not asked',
      colour: 'gray',
      text: 'The agent was not asked because the sweep failed: there are no findings to rank.',
    };
  switch (agent.state) {
    case 'ok':
      return {
        title: agent.mode === 'replay' ? 'Ranked and explained (recorded)' : 'Ranked and explained',
        colour: 'teal',
        text:
          agent.mode === 'replay'
            ? 'The explanations were recorded on a run with a model for this exact configuration and are replayed here. The agent ranked the findings within their severity tiers only.'
            : 'The agent ranked the findings within their severity tiers only and explained each against the case history.',
      };
    case 'no_record':
      return {
        title: 'No recorded explanation for this configuration',
        colour: 'gray',
        text: 'This instance has no model provider and replays recorded runs, and no run was recorded for this configuration. The findings stay in the deterministic order.',
      };
    case 'skipped':
      return {
        title: 'Not asked',
        colour: 'gray',
        text: 'The agent was not asked: the review was started without it, it found nothing to rank, or the namespace could not be read. The findings stay in the deterministic order.',
      };
    case 'schema_failed':
      return {
        title: 'Explanation not accepted',
        colour: 'orange',
        text: `The agent's ranking was refused${agent.error ? `: ${agent.error}` : ''}. The findings stay in the deterministic order.`,
      };
    case 'error':
      return {
        title: 'The agent did not answer',
        colour: 'red',
        text: `${agent.error || 'The agent run failed'}. The findings stay in the deterministic order.`,
      };
    default:
      return {
        title: reviewState === 'ranking' ? 'Ranking' : 'Waiting for the sweep',
        colour: 'blue',
        text:
          reviewState === 'ranking'
            ? 'The agent is ranking the findings within their severity tiers; this page reads the review again every 2 seconds. The findings below are already final.'
            : 'The agent is asked once the sweep has stored the findings.',
      };
  }
}

/** "Shutter.Production in SHUTTER, Shutter's own" for a target choice. */
export function targetLabel(t: ReviewTarget): string {
  return `${t.production} in ${t.namespace}, ${t.own ? "Shutter's own" : 'watched'}`;
}

export const targetKey = (t: Pick<ReviewTarget, 'namespace' | 'production'>) =>
  `${t.namespace}|${t.production}`;

/**
 * The Management Portal page of a message header, in the namespace that holds it. The review carries no portal link of
 * its own (a case does, from Dispatch.PortalPath, the namespace's default web application), so the path is built: on
 * IRIS for Health a namespace's default application is /csp/healthshare/<namespace>/, and /csp/<namespace>/ is a 404.
 */
export function headerLink(namespace: string, headerId: number | string): string {
  return `/csp/healthshare/${namespace.toLowerCase()}/EnsPortal.MessageContents.zen?HeaderId=${encodeURIComponent(String(headerId))}`;
}

/**
 * An annotation's expiry as the API takes it: a date (YYYY-MM-DD) or a UTC time; "" is no expiry. Returns the problem,
 * or null when it is good.
 */
export function expiryProblem(
  value: string,
  today: string = new Date().toISOString().slice(0, 10),
): string | null {
  const v = value.trim();
  if (!v) return null;
  if (!/^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}(:\d{2})?Z)?$/.test(v) || Number.isNaN(Date.parse(v)))
    return 'Give a date as YYYY-MM-DD, or leave it empty for no expiry';
  if (v.slice(0, 10) <= today) return 'An expiry is a date after today';
  return null;
}

/**
 * The expiry as it is sent. The server ends a date-only expiry at 00:00 UTC of that date, so a date is sent as the
 * last second of that day in UTC, which is what the field promises; a time is sent as given, and "" is no expiry.
 */
export function expiryForApi(value: string): string {
  const v = value.trim();
  return /^\d{4}-\d{2}-\d{2}$/.test(v) ? `${v}T23:59:59Z` : v;
}
