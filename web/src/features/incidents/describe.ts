import {
  IconAlertCircle,
  IconCircleCheck,
  IconCircleX,
  IconClock,
  IconHandStop,
  IconMinus,
  IconProgress,
  IconUserCheck,
  IconUserQuestion,
  type Icon,
} from '@tabler/icons-react';
import type { Chain, ChainItem, IncidentApproval, IncidentEvent, IncidentSummary } from '@/api/types';
import { formatDuration, humanize, parseTime, plural } from '@/lib/format';
import type { OutcomeCase } from '@/lib/status';
import type { Status, Tone } from '@/lib/tone';

export type Meaning = Record<string, Status>;

type Row = Omit<Status, 'label'> & { label?: string };

const m = (tone: Tone, hint: string, icon?: Icon, label?: string): Row => ({ tone, hint, icon, label });
const RUNNING = IconProgress;

/** Labels from the codes ("awaiting_approval" reads "Waiting for approval"), unless a row names its own. */
const label = (meaning: Record<string, Row>): Meaning =>
  Object.fromEntries(Object.entries(meaning).map(([k, v]) => [k, { ...v, label: v.label ?? humanize(k) }]));

/** The incident's states (CONTRACTS 7.5): information while it takes and releases cases, attention when a person is needed. */
export const INCIDENT_STATES: Meaning = label({
  open: m('info', 'Taking cases: failures to the receiver join it until the quiet period passes', RUNNING),
  classified: m('info', 'The chains are formed and classified, and the plan is made', RUNNING),
  awaiting_approval: m(
    'attention',
    'A person must approve the release of the chains the site policy does not release by itself',
    IconUserQuestion,
  ),
  releasing: m('info', 'Releasing the chains in order, one operation at a time', RUNNING),
  closed: m('neutral', 'Every chain has an outcome', IconCircleCheck),
});

/** A chain's states; a chain whose every operation was verified at the receiver reads "Verified" (N14). */
export const CHAIN_STATES: Meaning = label({
  pending: m('neutral', 'Waiting for its turn', IconClock),
  awaiting_approval: m('attention', 'Waiting for a person to approve its release', IconUserQuestion),
  approved: m('info', 'Approved: released in sequence order', IconUserCheck),
  rejected: m('blocking', 'A person rejected it: its cases went to a person', IconCircleX),
  releasing: m('info', 'Its operations are released one at a time', RUNNING),
  resolved: m('positive', 'Every operation verified at the receiver', IconCircleCheck, 'Verified'),
  stopped: m('blocking', 'Stopped at the first surprise: the rest went to a person', IconHandStop),
  escalated: m('attention', 'Handed to a person: a board chain or no catalogue match', IconUserQuestion),
});

/** An operation's own state, used where its case's outcome is not known yet or never came (pending, stopped). */
export const ITEM_STATES: Meaning = label({
  pending: m('neutral', 'Not released yet', IconClock),
  released: m(
    'info',
    'Released: the case runs its own dispatch (the preflight read, the gate, the rehearsal, the write, the verification)',
    RUNNING,
  ),
  resolved: m('positive', 'Verified at the receiver', IconCircleCheck),
  blocked: m('blocking', 'A check stopped it: nothing was sent', IconHandStop),
  escalated: m('attention', 'Handed to a person', IconUserQuestion),
  failed: m('blocking', 'The workflow itself failed', IconAlertCircle),
  stopped: m('neutral', 'Never released: the chain stopped before it', IconMinus),
});

export const KIND_HINTS: Record<string, string> = {
  single: 'One failure for the encounter, nothing later applied',
  ordered: 'Several failures for the encounter, no successful delivery between them',
  interleaved: 'Successful deliveries between the failures, or a later event already applied',
};

export const DECIDES_LABELS: Record<string, string> = {
  policy: 'site policy',
  board: 'the board',
  person: 'a person',
};

export const POLICY_LABELS: Record<string, string> = {
  automatic: 'released automatically',
  approval: "released under the incident's approval",
  per_chain: 'released under its own approval',
  path: "each case's own path",
  board: 'the board',
  none: 'no policy chain',
};

/** How the incident's policy chains were authorised, as one sentence. */
export function describePolicy(policy: string | undefined): string {
  switch (policy) {
    case 'automatic':
      return 'The policy chains are released automatically, as the site profile allows';
    case 'approval':
      return "The policy chains are released under one approval of the incident's plan";
    case 'per_chain':
      return 'Each policy chain is released under its own approval';
    case 'approval+per_chain':
      return "Some policy chains go under the incident's approval, others each under their own";
    case 'none':
      return "No policy chain: every case took its own path, as on a single case's page";
    default:
      return policy ? humanize(policy) : '';
  }
}

/** "8 cases in 6 chains": what the incident holds. */
export function describeHeld(i: Pick<IncidentSummary, 'progress'>): string {
  const p = i.progress;
  if (!p) return '';
  if (!p.chains) return `${plural(p.cases, 'case')}, no chains yet`;
  return `${plural(p.cases, 'case')} in ${plural(p.chains, 'chain')}`;
}

/** "4 single, 1 ordered, 1 interleaved": how the chains' failures relate. */
export function describeKinds(i: Pick<IncidentSummary, 'progress'>): string {
  return Object.entries(i.progress?.byKind ?? {})
    .map(([k, n]) => `${n} ${humanize(k).toLowerCase()}`)
    .join(', ');
}

/** "Ordered, decided by site policy, released under the incident's approval": a chain's long form, for the expert. */
export function describeChain(chain: Chain): string {
  const who = DECIDES_LABELS[chain.decides] ?? humanize(chain.decides).toLowerCase();
  const how =
    chain.decides === 'policy' && chain.policy
      ? `, ${POLICY_LABELS[chain.policy] ?? humanize(chain.policy)}`
      : '';
  return `${humanize(chain.kind)}, decided by ${who}${how}`;
}

/** Who decides a chain, in the newcomer's words (N1): "Site policy, one approval", "The board of agents decides". */
export function chainLine(chain: Chain): string {
  if (chain.decides === 'board') return 'The board of agents decides';
  if (chain.decides === 'person') return 'A person decides';
  if (chain.decides !== 'policy') return humanize(chain.decides);
  switch (chain.policy) {
    case 'automatic':
      return 'Site policy, automatic';
    case 'approval':
      return 'Site policy, one approval';
    case 'per_chain':
      return 'Site policy, its own approval';
    default:
      return 'Site policy';
  }
}

/** The chain states in the order a sentence counts them: what went well first, what needs a person last. */
const TALLY: [string, string][] = [
  ['resolved', 'verified'],
  ['stopped', 'stopped'],
  ['rejected', 'rejected'],
  ['escalated', 'with a person'],
  ['awaiting_approval', 'waiting for approval'],
  ['approved', 'being released'],
  ['releasing', 'being released'],
  ['pending', 'waiting for their turn'],
];

/** "4 chains verified, 1 stopped, 1 with a person": the chains by how they ended, the first with its noun. */
export function chainTally(byState: Record<string, number>): string {
  const parts: [string, number][] = [];
  for (const [state, words] of TALLY) {
    const n = byState[state] ?? 0;
    if (!n) continue;
    const last = parts[parts.length - 1];
    // "being released" covers two chain states
    if (last && last[0] === words) last[1] += n;
    else parts.push([words, n]);
  }
  return parts
    .map(([words, n], i) => (i === 0 ? `${plural(n, 'chain')} ${words}` : `${n} ${words}`))
    .join(', ');
}

/** How long the incident took from its opening to its closing, or undefined while it is open or a time is missing. */
export function openToClosed(i: Pick<IncidentSummary, 'openedAt' | 'closedAt'>): number | undefined {
  const a = parseTime(i.openedAt);
  const b = parseTime(i.closedAt);
  return a && b ? Math.max(0, b.getTime() - a.getTime()) : undefined;
}

/** Whether the incident is closed with every one of its chains resolved. */
export function allVerified(i: Pick<IncidentSummary, 'state' | 'progress'>): boolean {
  const p = i.progress;
  return i.state === 'closed' && !!p && p.chains > 0 && (p.byState.resolved ?? 0) === p.chains;
}

/**
 * The incident page's hero sentence (N21): what a manager measures first, in at most 24 words. Closed with every chain
 * verified: how many failed, for how many patients, all verified, how fast. Otherwise the chains by how they ended,
 * and while the incident is open, "so far, taking cases".
 */
export function heroSentence(
  i: Pick<IncidentSummary, 'state' | 'openedAt' | 'closedAt' | 'progress'>,
): string {
  const p = i.progress;
  if (!p || !p.cases) return i.state === 'open' ? 'Taking failed messages for the receiver.' : 'Closed.';
  const messages = plural(p.cases, 'failed message');
  const encounters = p.chains ? ` for ${plural(p.chains, 'patient encounter')}` : '';
  if (i.state === 'open') return `${messages}${encounters} so far, taking cases.`;
  if (allVerified(i)) {
    const ms = openToClosed(i);
    const took = ms === undefined ? '' : `, in ${formatDuration(ms)}`;
    return `${messages}${encounters}, ${p.chains === 1 ? '' : 'all '}closed and verified at the receiver${took}.`;
  }
  if (!p.chains) return `${messages}, no chains yet.`;
  return `${messages}${encounters}: ${chainTally(p.byState)}.`;
}

/** The page's lead, built from the cases it holds and its receiver (N21): 15 words. */
export function incidentLead(i: Pick<IncidentSummary, 'receiver' | 'progress'>): string {
  const n = i.progress?.cases ?? 0;
  const failed = n ? plural(n, 'failed delivery', 'failed deliveries') : 'Failed deliveries';
  return `${failed} to ${i.receiver}, grouped and released in order, one at a time.`;
}

/** One of the deciders in the "Decided by" tile: who, and which chains (by sequence number). */
export interface Decider {
  key: string;
  label: string;
  seqs: number[];
}

const DECIDER_LABELS: Record<string, string> = {
  policy: 'Site policy',
  board: 'The board',
  person: 'A person',
};

/**
 * Who decided the chains and how many approvals the release took: the deciders by how many chains each decided
 * (largest first), and the approvals counted from the chains' policies (one for the incident's approval, one for each
 * chain released under its own).
 */
export function decidedBy(chains: Chain[]): { deciders: Decider[]; approvals: number } {
  const by = new Map<string, Decider>();
  for (const c of chains) {
    const key = c.decides || 'policy';
    const d = by.get(key) ?? { key, label: DECIDER_LABELS[key] ?? humanize(key), seqs: [] };
    d.seqs.push(c.seq);
    by.set(key, d);
  }
  const deciders = [...by.values()].sort((a, b) => b.seqs.length - a.seqs.length);
  const policy = chains.filter((c) => c.decides === 'policy');
  const approvals =
    (policy.some((c) => c.policy === 'approval') ? 1 : 0) +
    policy.filter((c) => c.policy === 'per_chain').length;
  return { deciders, approvals };
}

/** The receiver version an operation went at and the one its verification read: "v1 → v2", "fresh evidence → v2". */
export function versions(item: ChainItem): string {
  const at = item.expectedVersion === null ? 'fresh evidence' : `v${item.expectedVersion}`;
  if (item.verifiedVersion !== null) return `${at} → v${item.verifiedVersion}`;
  return item.state === 'pending' || item.state === 'released' ? `${at} → …` : at;
}

/** The operation states whose case ran, so the case's outcome says what came of it. */
const RAN = new Set(['released', 'resolved', 'blocked', 'escalated', 'failed']);

const SENDS = /^resend/;

/**
 * What came of an operation, as a case's outcome (N14): "Delivered, verified" or "Nothing to send, verified" for a
 * resolved one, "Blocked", "Escalated" and the rest as a case would read. A chain operation carries its case's state
 * and the catalogue outcome it was released under, not the case's write count, so a resolved operation counts as one
 * write when that outcome is a resend (resend, resend_chain, resend_latest) and as none otherwise. Null for an
 * operation not released yet or never released: its own state badge says so.
 */
export function itemOutcome(item: ChainItem): OutcomeCase | null {
  if (!RAN.has(item.state)) return null;
  const sends = SENDS.test(item.releaseOutcome ?? item.outcome);
  const settled = item.state === 'resolved';
  return {
    state: item.caseState,
    disposition: sends ? 'resend' : 'superseded',
    writes: settled ? (sends ? 1 : 0) : undefined,
    verification: settled ? 'verified' : undefined,
  };
}

/** The server writes "6 chain(s)" and "1 approval task(s)"; the page says "6 chains" and "1 approval task". */
export function tidy(text: string): string {
  return text.replace(
    /(\d+) ((?:[A-Za-z-]+ )*?)([A-Za-z-]+)\(s\)/g,
    (_, n: string, middle: string, word: string) => {
      const noun = Number(n) === 1 ? word : /(s|x|ch|sh)$/.test(word) ? `${word}es` : `${word}s`;
      return `${n} ${middle}${noun}`;
    },
  );
}

/** A timeline line: one event, or a run of events of one kind collapsed under one label. */
export interface TimelineLine {
  key: string;
  at: string;
  /** The person behind the line, when one person is (an approval); empty for the system. */
  actor: string;
  /** The line's words: a short form of the event, or "6 cases joined". */
  label: string;
  /** The events behind it, as the server wrote them. */
  events: IncidentEvent[];
  /** Whether the events say more than the label does, so the line opens to show them. */
  opens: boolean;
}

const JOINED = /^Case \S+ joined\b/;
const OPENED = /^Incident opened for .+?: .+$/;
const OPENED_FACT = /^Incident opened for .+?: (.+?)(?: \(mode \w+\))?$/;

/**
 * The first clause of an event's text, in full: "Incident opened for Downstream Out: 5 failures within 10 minutes
 * (mode policy)" reads "Opened: 5 failures within 10 minutes", and a digest, a task number or a long list behind a
 * semicolon or a full stop is left to the whole text.
 */
export function shortEvent(text: string): string {
  const opened = OPENED_FACT.exec(text);
  if (opened) return `Opened: ${tidy(opened[1])}`;
  const first = tidy(text)
    .replace(/\s*\([^)]*\)/g, '')
    .split(/; |\. (?=[A-Za-z0-9])/)[0];
  return first.replace(/\.$/, '');
}

const KIND_PLURALS: Record<string, string> = {
  state: 'status changes',
  note: 'notes',
  release: 'release steps',
  approval: 'approvals',
};

/**
 * The incident's events as timeline lines: consecutive "Case X joined" notes become "6 cases joined", any other run of
 * one kind collapses to a count ("26 release steps"), and a lone event shows its first clause, opening to the whole
 * text when that says more.
 */
export function timelineLines(events: IncidentEvent[]): TimelineLine[] {
  const runs: { key: string; events: IncidentEvent[] }[] = [];
  for (const e of events) {
    const key = JOINED.test(e.text) ? 'joined' : e.kind;
    const last = runs[runs.length - 1];
    if (last && last.key === key) last.events.push(e);
    else runs.push({ key, events: [e] });
  }
  return runs.map((run, i) => {
    const first = run.events[0];
    const n = run.events.length;
    const people = new Set(run.events.map((e) => e.actor).filter((a) => a && a !== 'system'));
    const actor = people.size === 1 ? [...people][0] : '';
    const key = `${i}:${first.at}`;
    if (n > 1) {
      const label =
        run.key === 'joined'
          ? `${plural(n, 'case')} joined`
          : `${n} ${KIND_PLURALS[run.key] ?? `${run.key} events`}`;
      return { key, at: first.at, actor, label, events: run.events, opens: true };
    }
    const label = shortEvent(first.text);
    // Opening names the receiver and the mode the page already shows, so nothing is held back; a "(s)" fixed is no loss
    const opens = label !== tidy(first.text) && !OPENED.test(first.text);
    return { key, at: first.at, actor, label, events: run.events, opens };
  });
}

/** The chains' states in a stable order, from the list's counts: verified first, then the ones that need a person. */
const CHAIN_ORDER = [
  'resolved',
  'approved',
  'releasing',
  'pending',
  'awaiting_approval',
  'escalated',
  'rejected',
  'stopped',
];

/** One state per chain from `progress.byState`, in the order above (unknown states last). */
export function statesFromCounts(byState: Record<string, number> | undefined): string[] {
  const entries = Object.entries(byState ?? {});
  const rank = (s: string) => (CHAIN_ORDER.includes(s) ? CHAIN_ORDER.indexOf(s) : CHAIN_ORDER.length);
  entries.sort(([a], [b]) => rank(a) - rank(b));
  return entries.flatMap(([state, n]) => Array.from({ length: n }, () => state));
}

/** How many chains the page names before the rest wait behind one button, so the approval stays within reach. */
export const CHAINS_LISTED = 6;

/**
 * What the one approval covers, in one sentence (9 words for the usual case): "One approval released the ordered
 * chain: C-000038 then C-000043." Waiting, it releases; decided, it released or stopped them.
 */
export function approvalSentence(covered: Chain[], decision: IncidentApproval | undefined): string {
  const cases = (c: Chain) => c.items.map((i) => i.caseId).join(' then ');
  const named = covered.slice(0, CHAINS_LISTED).map(cases).join('; ');
  const rest = covered.length - CHAINS_LISTED;
  const what =
    covered.length === 1
      ? `the ${humanize(covered[0].kind).toLowerCase()} chain: ${cases(covered[0])}`
      : `${plural(covered.length, 'chain')}: ${named}${rest > 0 ? `; and ${rest} more` : ''}`;
  if (decision?.decision === 'rejected') return `One rejection stopped ${what}. Nothing was sent.`;
  return `One approval ${decision?.decision === 'approved' ? 'released' : 'releases'} ${what}.`;
}

/**
 * The plan in one sentence (N21), from the chains' policies: "One plan, approved once, covers the ordered chain." A
 * plan whose chains need no approval says so.
 */
export function planSentence(chains: Chain[]): string {
  const approved = chains.filter((c) => c.decides === 'policy' && c.policy === 'approval');
  if (approved.length === 0) return 'One plan covers every chain; none of them needs an approval.';
  const what =
    approved.length === 1
      ? `the ${humanize(approved[0].kind).toLowerCase()} chain`
      : plural(approved.length, 'chain');
  return `One plan, approved once, covers ${what}.`;
}
