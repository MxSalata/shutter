import type {
  FindingSource,
  FindingStatus,
  ReviewAgent,
  ReviewDetail,
  ReviewFinding,
  ReviewListItem,
  ReviewTarget,
  Severity,
} from '@/api/types';
import { formatInt, humanize, plural } from '@/lib/format';
import type { Tone } from '@/lib/tone';

/**
 * What the production review page decides from a review (CONTRACTS 13): the order of the findings, what a blank item
 * stands for, the agent's state in words and the note on the HL7 checks. Pure functions, so they are tested alone.
 */

export const READ_ONLY =
  'The review never changes the production: a person applies any change in the Management Portal.';

export const SEVERITIES: Severity[] = ['high', 'medium', 'low', 'info'];

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

/** Whether the agent's card leads the review: it ranked and explained, or is ranking now, so it is the headline. */
export const agentLeads = (review: Pick<ReviewDetail, 'agent' | 'state'>): boolean =>
  review.agent.state === 'ok' || (review.state === 'ranking' && review.agent.state === 'pending');

/** The findings as the page lists them: by the agent's rank when rankedByAgent, else as the server sent them. */
export function orderedFindings(review: Pick<ReviewDetail, 'agent' | 'findings'>): ReviewFinding[] {
  if (!rankedByAgent(review)) return review.findings;
  return [...review.findings].sort((a, b) => (a.rank as number) - (b.rank as number));
}

/**
 * What the page says about the HL7 checks that had no subject, only from the server's counts: the reply code checks need
 * an HL7 operation, the framing check an HL7 TCP item. Without the counts (older reviews) it says nothing either way.
 */
export function hl7Note(review: Pick<ReviewDetail, 'state' | 'unreadable' | 'summary'>): string {
  if (review.state !== 'done' || review.unreadable) return '';
  const noOps = review.summary.hl7Operations === 0;
  const noTcp = review.summary.hl7TcpItems === 0;
  const tail = 'which is not the same as no finding.';
  if (noOps && noTcp)
    return `No HL7 operation or HL7 TCP item in this production: the reply code and framing checks had no subject, ${tail}`;
  if (noOps) return `No HL7 operation in this production: the reply code checks had no subject, ${tail}`;
  if (noTcp) return `No HL7 TCP item in this production: the framing check had no subject, ${tail}`;
  return '';
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
  tone: Tone;
  text: string;
}

/** The agent's part in plain words, one per state; the deterministic report stands whatever it says. */
export function describeAgent(agent: ReviewAgent, reviewState: string): AgentView {
  if (reviewState === 'failed')
    return {
      title: 'Not asked',
      tone: 'neutral',
      text: 'The agent was not asked because the sweep failed: there are no findings to rank.',
    };
  switch (agent.state) {
    case 'ok':
      return {
        title: agent.mode === 'replay' ? 'Ranked and explained (recorded)' : 'Ranked and explained',
        tone: 'neutral',
        text:
          agent.mode === 'replay'
            ? 'The explanations were recorded on a run with a model for this exact configuration and are replayed here. The agent ranked the findings within their severity tiers only.'
            : 'The agent ranked the findings within their severity tiers only and explained each against the case history.',
      };
    case 'no_record':
      return {
        title: 'No recorded explanation for this configuration',
        tone: 'neutral',
        text: 'On a live system, an agent ranks these findings and explains each against the cases. This review was recorded without its ranking, so the findings keep the deterministic order.',
      };
    case 'skipped':
      return {
        title: 'Not asked',
        tone: 'neutral',
        text: 'The agent was not asked: the review was started without it, it found nothing to rank, or the namespace could not be read. The findings stay in the deterministic order.',
      };
    case 'schema_failed':
      return {
        title: 'Explanation not accepted',
        tone: 'attention',
        text: `The agent's ranking was refused${agent.error ? `: ${agent.error}` : ''}. The findings stay in the deterministic order.`,
      };
    case 'error':
      return {
        title: 'The agent did not answer',
        tone: 'blocking',
        text: `${agent.error || 'The agent run failed'}. The findings stay in the deterministic order.`,
      };
    default:
      return {
        title: reviewState === 'ranking' ? 'Ranking' : 'Waiting for the sweep',
        tone: 'info',
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

/**
 * What the explained count leaves out: a recording is matched to the current findings by code, item and setting, so
 * on another instance some findings can have no explanation and some recorded entries no finding. The count itself is
 * stated once, by explainedCount, beside the findings.
 */
export function explainedNotes(a: Pick<ReviewAgent, 'explained' | 'unexplained' | 'dropped'>): string {
  if (a.explained === undefined || a.explained === null) return '';
  const parts: string[] = [];
  if (a.unexplained) parts.push('The others keep the baseline order within their tier, with no explanation');
  if (a.dropped)
    parts.push(
      `${a.dropped} recorded explanation${a.dropped === 1 ? '' : 's'} matched no finding here and ${a.dropped === 1 ? 'was' : 'were'} left out`,
    );
  return parts.length ? `${parts.join('; ')}.` : '';
}

/**
 * How many findings the agent explained, of how many: the server's counts once the agent answered, else the findings
 * that carry an explanation (none, for a review with no recorded explanation).
 */
export function explainedCount(review: Pick<ReviewDetail, 'agent' | 'findings'>): {
  explained: number;
  total: number;
} {
  const a = review.agent;
  if (a.explained !== undefined && a.explained !== null)
    return { explained: a.explained, total: a.explained + (a.unexplained ?? 0) };
  return {
    explained: review.findings.filter((f) => f.explanation).length,
    total: review.findings.length,
  };
}

// ---- the closed row of a finding: a plain title, a chip, a one-line summary (DESIGN.md 5, reviews.md 3) ----

/** The plain titles of the codes the recordings hold; a code not listed here is humanised. */
export const PLAIN_TITLES: Record<string, string> = {
  ALERTING_OFF: 'No alert on error',
  QUEUE_ALERTS_OFF: 'No alert on a growing queue',
  NO_ALERT_CONSUMER: 'Alerts have nowhere to go',
  ERRORS_GROUPED: 'Repeated errors of one kind',
  MESSAGE_ERRORS: 'Messages that ended in error',
  PURGE_MISSING: 'No message purge task',
  FEED_SILENCE_UNWATCHED: 'A silent feed goes unnoticed',
};

/** A finding's title in plain words: "No alert on error" for ALERTING_OFF. */
export const findingTitle = (f: Pick<ReviewFinding, 'code'>): string =>
  PLAIN_TITLES[f.code] ?? humanize(f.code);

/** The longest `found` a chip carries; a longer one is shown in full when the finding is opened, never cut. */
const SHORT_FOUND = 24;

const wordCount = (text: string) => text.split(/\s+/).filter(Boolean).length;

/** The names in a production-wide finding's list: "ADT In (AlertOnError 0, class default)" is "ADT In". */
const namesOf = (f: Pick<ReviewFinding, 'code' | 'found'>): string[] =>
  foundList(f)
    .map((x) => x.replace(/\s*\(.*$/, '').trim())
    .filter(Boolean);

/**
 * The code chip of a closed finding: what an engineer looks up, by code (reviews.md 3, F12). Null when the finding has
 * nothing short to look up; a long `found` (ALERTING_OFF lists four items) is never cut, so the row shows the setting
 * and the open finding shows the value in full.
 */
export function findingChip(f: ReviewFinding): string | null {
  const found = f.found.trim();
  const short = found !== '' && found.length <= SHORT_FOUND && !found.includes('; ');
  switch (f.code) {
    case 'ERRORS_GROUPED':
      return found || null;
    case 'MESSAGE_ERRORS':
      return f.item || null;
    case 'ALERTING_OFF':
      return f.setting || null;
    case 'QUEUE_ALERTS_OFF':
      return short && f.setting ? `${f.setting} · ${found}` : f.setting || (short ? found : null);
    case 'NO_ALERT_CONSUMER':
      return short ? found : null;
    case 'PURGE_MISSING':
      return f.setting || (short ? found : null);
    default: {
      const value = short ? (f.setting ? `${f.setting} = ${found}` : found) : f.setting;
      const parts = [f.item, value].filter(Boolean);
      return parts.length ? parts.join(' · ') : null;
    }
  }
}

/** Whether the server's own sentence reads cleanly: no "(s)", no doubled space, no preposition with nothing after it. */
const isClean = (text: string) => !/\(s\)|\s{2,}|\b(?:by|on|from|for|of|to|in|at|with) \./.test(text);

/** The first sentence of a text, without its closing full stop's follower. */
const firstSentence = (text: string): string => /^.+?[.!?](?=\s|$)/.exec(text.trim())?.[0] ?? text.trim();

/**
 * A closed finding's one line, built from its own fields with real plurals (F12): never "1 error(s)", never "logged
 * by .". At most 15 words; a code without a template takes the first sentence of the server's `why` when that is
 * clean and short, else the plain title.
 */
export function findingSummary(f: ReviewFinding): string {
  const names = namesOf(f);
  const count = f.evidence.count;
  switch (f.code) {
    case 'ERRORS_GROUPED':
      if (count > 0)
        return `${plural(count, 'error')} with one signature, logged by ${f.item || 'the production itself'}.`;
      break;
    case 'MESSAGE_ERRORS': {
      const n = count > 0 ? count : Number(/^\d+/.exec(f.found)?.[0] ?? 0);
      const from = /\bin Error from (.+)$/i.exec(f.found)?.[1]?.trim();
      if (n > 0) return `${plural(n, 'message')} ended in error${from ? `, from ${from}` : ''}.`;
      break;
    }
    case 'ALERTING_OFF':
      return 'Failures reach the event log and wait for someone to read it.';
    case 'QUEUE_ALERTS_OFF': {
      const where =
        f.item || (names.length === 1 ? names[0] : names.length > 1 ? plural(names.length, 'item') : '');
      return where ? `A growing queue at ${where} raises no alert.` : 'A growing queue raises no alert.';
    }
    case 'NO_ALERT_CONSUMER':
      return 'An alert raised by any item reaches nobody.';
    case 'PURGE_MISSING':
      return 'Old messages are never purged.';
    case 'FEED_SILENCE_UNWATCHED':
      return 'A feed that falls silent is never noticed.';
  }
  const why = firstSentence(f.why);
  return why && isClean(why) && wordCount(why) <= 15 ? why : findingTitle(f);
}

/**
 * Where a closed finding sits, beside its chip: the items an alert is off on ("ADT In, HL7 Index, +2"), else its item,
 * or the namespace for a finding about it. Null when the chip or the summary already names the place, and for a
 * finding about the whole production that has a chip, where "the production" would only be filler.
 */
export function findingSubject(f: ReviewFinding): string | null {
  if (f.code === 'ERRORS_GROUPED') return null;
  if (f.code === 'ALERTING_OFF') {
    const names = namesOf(f);
    if (names.length)
      return names.length <= 2 ? names.join(', ') : `${names.slice(0, 2).join(', ')}, +${names.length - 2}`;
  }
  const chip = findingChip(f);
  if (f.item && chip?.includes(f.item)) return null;
  if (!f.item && chip) return null;
  return subjectOf(f);
}

/** "54 cases, 30 unique" for a finding with cases, else null. */
export const findingCases = (f: Pick<ReviewFinding, 'cases'>): string | null =>
  f.cases.count > 0 ? `${plural(f.cases.count, 'case')}, ${formatInt(f.cases.unique)} unique` : null;

// ---- grouping and filtering the findings ----

/** What the filter chips choose from: everything, a severity tier, the findings no one has marked, or those marked. */
export type FindingFilter = 'all' | Severity | 'new' | 'marked';

/** Whether a finding is in a filter. "Marked" is any status other than new, as the annotations stand now. */
export function inFilter(f: Pick<ReviewFinding, 'severity' | 'status'>, filter: FindingFilter): boolean {
  if (filter === 'all') return true;
  if (filter === 'new') return f.status === 'new';
  if (filter === 'marked') return f.status !== 'new';
  return f.severity === filter;
}

/** The findings grouped by severity, most severe first, each group in the order given; tiers with none are left out. */
export function groupBySeverity(
  findings: ReviewFinding[],
): { severity: Severity; findings: ReviewFinding[] }[] {
  return SEVERITIES.map((severity) => ({
    severity,
    findings: findings.filter((f) => f.severity === severity),
  })).filter((g) => g.findings.length > 0);
}

/** The newest review of each production, newest first: the list's "Latest per production" cards. */
export function latestPerProduction(items: ReviewListItem[]): ReviewListItem[] {
  const newest = new Map<string, ReviewListItem>();
  for (const r of items) {
    const key = `${r.namespace}|${r.production}`;
    const seen = newest.get(key);
    if (
      !seen ||
      r.startedAt > seen.startedAt ||
      (r.startedAt === seen.startedAt && r.reviewId > seen.reviewId)
    )
      newest.set(key, r);
  }
  return [...newest.values()].sort(
    (a, b) => b.startedAt.localeCompare(a.startedAt) || b.reviewId.localeCompare(a.reviewId),
  );
}
