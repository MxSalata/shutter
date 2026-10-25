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
import type { Chain, IncidentSummary } from '@/api/types';
import { humanize } from '@/lib/format';
import type { Status, Tone } from '@/lib/tone';

export type Meaning = Record<string, Status>;

const m = (tone: Tone, hint: string, icon?: Icon) => ({ tone, hint, icon });
const RUNNING = IconProgress;

/** Labels from the codes: "awaiting_approval" reads "Awaiting approval". */
const label = (meaning: Record<string, Omit<Status, 'label'>>): Meaning =>
  Object.fromEntries(Object.entries(meaning).map(([k, v]) => [k, { ...v, label: humanize(k) }]));

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

export const CHAIN_STATES: Meaning = label({
  pending: m('neutral', 'Waiting for its turn', IconClock),
  awaiting_approval: m('attention', 'Waiting for a person to approve its release', IconUserQuestion),
  approved: m('info', 'Approved: released in sequence order', IconUserCheck),
  rejected: m('blocking', 'A person rejected it: its cases went to a person', IconCircleX),
  releasing: m('info', 'Its operations are released one at a time', RUNNING),
  resolved: m('positive', 'Every operation verified at the receiver', IconCircleCheck),
  stopped: m('blocking', 'Stopped at the first surprise: the rest went to a person', IconHandStop),
  escalated: m('attention', 'Handed to a person: a board chain or no catalogue match', IconUserQuestion),
});

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

/** "6 cases in 6 chains: 4 single, 1 ordered, 1 interleaved". */
export function describeProgress(i: IncidentSummary): string {
  const p = i.progress;
  if (!p) return '';
  const kinds = Object.entries(p.byKind ?? {})
    .map(([k, n]) => `${n} ${humanize(k).toLowerCase()}`)
    .join(', ');
  const cases = `${p.cases} case${p.cases === 1 ? '' : 's'}`;
  if (!p.chains) return `${cases}, no chains yet`;
  return `${cases} in ${p.chains} chain${p.chains === 1 ? '' : 's'}${kinds ? `: ${kinds}` : ''}`;
}

/** "5 resolved, 1 escalated". */
export function describeOutcomes(i: IncidentSummary): string {
  return Object.entries(i.progress?.byState ?? {})
    .map(([s, n]) => `${n} ${humanize(s).toLowerCase()}`)
    .join(', ');
}

/** "Chain 2 for ENC-1102: ordered, decided by site policy, released under the incident's approval". */
export function describeChain(chain: Chain): string {
  const who = DECIDES_LABELS[chain.decides] ?? humanize(chain.decides).toLowerCase();
  const how =
    chain.decides === 'policy' && chain.policy
      ? `, ${POLICY_LABELS[chain.policy] ?? humanize(chain.policy)}`
      : '';
  return `${humanize(chain.kind)}, decided by ${who}${how}`;
}
