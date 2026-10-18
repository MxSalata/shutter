import type { Chain, IncidentSummary } from '@/api/types';
import { humanize } from '@/lib/format';

export type Meaning = Record<string, [colour: string, hint: string]>;

/** The incident's states (CONTRACTS 7.5): blue while it takes cases, yellow when a person is needed. */
export const INCIDENT_STATES: Meaning = {
  open: ['blue', 'Taking cases: failures to the receiver join it until the quiet period passes'],
  classified: ['cyan', 'The chains are formed and classified, and the plan is made'],
  awaiting_approval: ['yellow', 'A person must approve the release of the policy chains'],
  releasing: ['indigo', 'Releasing the chains in order, one operation at a time'],
  closed: ['gray', 'Every chain has an outcome'],
};

export const CHAIN_STATES: Meaning = {
  pending: ['gray', 'Waiting for its turn'],
  awaiting_approval: ['yellow', 'Waiting for a person to approve its release'],
  approved: ['indigo', 'Approved: released in sequence order'],
  rejected: ['red', 'A person rejected it: its cases went to a person'],
  releasing: ['violet', 'Its operations are released one at a time'],
  resolved: ['green', 'Every operation verified at the receiver'],
  stopped: ['red', 'Stopped at the first surprise: the rest went to a person'],
  escalated: ['orange', 'Handed to a person: a board chain or no catalogue match'],
};

export const ITEM_STATES: Meaning = {
  pending: ['gray', 'Not released yet'],
  released: [
    'violet',
    'Released: the case runs its own dispatch (the preflight read, the gate, the rehearsal, the write, the verification)',
  ],
  resolved: ['green', 'Verified at the receiver'],
  blocked: ['red', 'A check stopped it: nothing was sent'],
  escalated: ['orange', 'Handed to a person'],
  failed: ['gray', 'The workflow itself failed'],
  stopped: ['gray', 'Never released: the chain stopped before it'],
};

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
