import type { AgentRun, PlanView, Snapshot } from '@/api/types';
import { catalogueEntriesOf, EVIDENCE_REFS, type EvidenceRef } from '@/lib/evidenceRefs';
import { humanize } from '@/lib/format';
import { asArray, asObject } from '@/lib/json';
import { answered, boardRounds, dispositionOf } from './boardRounds';
import { planLeader } from './follows';
import { investigationRuns } from './runClock';

/**
 * What the agents contributed to a case, beside what the gate decided and what was written: who proposed the current
 * plan, its recorded reason and the evidence it cites. Everything here is read from what the case stores (the plan's
 * own origin, reason and citations, the case's agent runs and the evidence's catalogue match); nothing is summarised
 * by a model, and a plan that no agent's run made is never called an agent's.
 */

const str = (v: unknown) => (v === undefined || v === null ? '' : String(v));

/** Who made the case's current plan, as the plan's origin (`createdBy`, CONTRACTS 5) and the case's runs say it. */
export type Proposer =
  /** An agent's run of this case: the board's coordinator, or the single investigator. */
  | { kind: 'agent'; role: 'coordinator' | 'generalist'; run: AgentRun }
  /** The board of the case this one followed. */
  | { kind: 'lead'; leader: string }
  | { kind: 'rules' }
  | { kind: 'policy'; entry: string }
  /** A merge or a cancel Shutter never sends: nobody proposed a write. */
  | { kind: 'withheld' }
  /** No plan, an origin this page does not know, or a run that is not among the case's runs. */
  | { kind: 'unknown' };

/**
 * The proposer of the plan. An agent is named only when the plan names a run (`run:<id>`) that is among the case's own
 * investigation runs, as its coordinator or its single investigator, and that run went through: a plan the rules or
 * the site's policy wrote, a board nobody answered on, and runs not read yet all name no agent.
 */
export function proposerOf(plan: PlanView | null | undefined, runs: AgentRun[] | null | undefined): Proposer {
  const by = str(plan?.plan?.createdBy);
  if (by === 'withheld') return { kind: 'withheld' };
  if (by === 'rules') return { kind: 'rules' };
  if (by.startsWith('policy:')) return { kind: 'policy', entry: by.slice('policy:'.length) };
  const leader = planLeader(by);
  if (leader) return { kind: 'lead', leader };
  if (by.startsWith('run:')) {
    const run = investigationRuns(runs).find((r) => str(r.id) === by.slice('run:'.length));
    if (
      run &&
      (run.role === 'coordinator' || run.role === 'generalist') &&
      (!run.status || run.status === 'ok')
    )
      return { kind: 'agent', role: run.role, run };
  }
  return { kind: 'unknown' };
}

/** The proposer in a few words, as the name of the receipt's first fact. */
export function proposalLabel(p: Proposer): string {
  switch (p.kind) {
    case 'agent':
      return p.role === 'coordinator' ? "Coordinator agent's proposal" : "One agent's proposal";
    case 'lead':
      return `Proposal from case ${p.leader}'s board`;
    case 'rules':
      return "The rules' proposal, no agent";
    case 'policy':
      return "Site policy's proposal, no agent";
    default:
      return 'Proposal';
  }
}

/** Whose words the plan's recorded reason is. */
export function reasonSource(p: Proposer): string {
  switch (p.kind) {
    case 'agent':
      return p.role === 'coordinator'
        ? "The coordinator agent's reason, as its run recorded it"
        : "The agent's reason, as its run recorded it";
    case 'lead':
      return `The reason recorded by the board of case ${p.leader}`;
    case 'policy':
      return "The site's policy gives this reason; no agent ran";
    default:
      return 'The reason recorded with the plan';
  }
}

export interface PlanReason {
  /** The plan's recorded reason, word for word; empty when it gave none. */
  why: string;
  /** The catalogue entry the plan follows, and its title when the case's evidence names the entry. */
  entry?: { code: string; title: string };
  /** The evidence sections the plan cites, in the Evidence tab's order. */
  refs: EvidenceRef[];
  /** The catalogue entries the plan's citations name, each of which the Evidence tab has a line about. */
  entries: string[];
}

/** The title of a catalogue entry, from the matches the case's evidence recorded; empty when it is not among them. */
function entryTitle(snapshot: Snapshot | null | undefined, code: string): string {
  const matches = asArray(asObject(asObject(snapshot?.summary)?.catalogue)?.matches);
  const match = matches.map((m) => asObject(m) ?? {}).find((m) => str(m.id) === code);
  return str(match?.title);
}

/**
 * Why the plan proposes what it does, as the plan itself records it: its reason, the catalogue entry it follows and
 * what it cites. Null for a plan with none of these (the rules' plain resend), so nothing is shown rather than made up.
 */
export function planReason(
  plan: PlanView | null | undefined,
  snapshot: Snapshot | null | undefined,
): PlanReason | null {
  const p = plan?.plan;
  if (!p) return null;
  const why = str(p.why).trim();
  const code = str(p.catalogueEntry).split('@')[0];
  const cited = asArray(p.evidenceRefs).filter((r): r is string => typeof r === 'string');
  const refs = EVIDENCE_REFS.filter((r) => cited.includes(r));
  // Only the entries the plan's own citations name: each has a line on the Evidence tab for its chip to open
  const entries = [...new Set(catalogueEntriesOf(cited).map((e) => e.split('@')[0]))];
  if (!why && !code && !refs.length) return null;
  return { why, entry: code ? { code, title: entryTitle(snapshot, code) } : undefined, refs, entries };
}

/** The name on the reason's disclosure: the entry's title when the evidence gives one. */
export function reasonLabel(reason: PlanReason): string {
  return reason.entry?.title ? `Why: ${reason.entry.title}` : 'Why, as recorded';
}

const list = (names: string[]) =>
  names.length > 1 ? `${names.slice(0, -1).join(', ')} and ${names.at(-1)}` : (names[0] ?? '');

/**
 * How the specialists of the plan's own sitting stood to it, in a sentence: who proposed the same, and who proposed
 * something else, with whether the coordinator kept that as dissent. Only for a plan the coordinator's run made; empty
 * when no specialist sat.
 */
export function specialistsLine(proposer: Proposer, runs: AgentRun[] | null | undefined): string {
  if (proposer.kind !== 'agent' || proposer.role !== 'coordinator') return '';
  const round = boardRounds(investigationRuns(runs)).find((r) => r.coordinator === proposer.run);
  if (!round?.specialists.length) return '';
  const result = asObject(proposer.run.result) ?? {};
  const planned = str(result.disposition);
  const kept = asArray(result.disagreements).map((d) => str(asObject(d)?.member));
  const name = (r: AgentRun) => r.member?.name ?? humanize(r.memberCode);
  const views = round.specialists.filter(answered);
  const same = views.filter((r) => dispositionOf(r) === planned);
  const other = views.filter((r) => dispositionOf(r) !== planned);
  const silent = round.specialists.filter((r) => !answered(r));
  const parts = [
    same.length ? `${list(same.map(name))} proposed the same` : '',
    ...other.map(
      (r) =>
        `${name(r)} proposed ${humanize(dispositionOf(r)).toLowerCase()}${
          kept.includes(r.memberCode) ? ', which the plan keeps as dissent' : ''
        }`,
    ),
    silent.length ? `${list(silent.map(name))} gave no answer` : '',
  ].filter(Boolean);
  return parts.length ? `${parts.join('; ')}.` : '';
}
