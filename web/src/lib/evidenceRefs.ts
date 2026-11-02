import type { AgentRun, Plan } from '@/api/types';

/**
 * What the board's members and the plan cite, tied to the Evidence tab's sections: each evidence ref the agents use
 * (`message`, `validation`, `error`, `operation`, `route`, `ward_state`, `receipt`, `timeline`, `later_event`) has
 * its section's anchor id and title, in the tab's order, and `citationsOf` says, for each section, which members cited
 * it and whether the plan did. A ref to a catalogue entry (`catalogue:E7`) is not a section: `catalogueEntriesOf` gives
 * the entries.
 */
export const EVIDENCE_REFS = [
  'message',
  'validation',
  'error',
  'operation',
  'route',
  'ward_state',
  'receipt',
  'timeline',
  'later_event',
] as const;

export type EvidenceRef = (typeof EVIDENCE_REFS)[number];

const TITLES: Record<EvidenceRef, string> = {
  message: 'The HL7 message',
  validation: 'Schema validation',
  error: 'What the connector reported',
  operation: 'The failed operation',
  route: 'The route and what the connector guarantees',
  ward_state: "The downstream system's encounter",
  receipt: "The downstream system's receipt for this operation",
  timeline: 'The operation timeline',
  later_event: 'Later events',
};

export const isEvidenceRef = (ref: string): ref is EvidenceRef =>
  (EVIDENCE_REFS as readonly string[]).includes(ref);

/**
 * A ref's section on the Evidence tab: its anchor id and its title, which names the case's receiver for what the
 * receiver itself recorded. Null for a ref that is no section (a catalogue entry, an unknown kind).
 */
export function evidenceSection(
  ref: string,
  receiver?: string,
): { ref: EvidenceRef; id: string; title: string } | null {
  if (!isEvidenceRef(ref)) return null;
  const title =
    receiver && ref === 'ward_state'
      ? `${receiver}'s encounter`
      : receiver && ref === 'receipt'
        ? `${receiver}'s receipt for this operation`
        : TITLES[ref];
  return { ref, id: `evidence-${ref}`, title };
}

/** The refs a list holds, as strings: the agents and the plan send a list of names, sometimes with entries. */
function refsOf(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((r): r is string => typeof r === 'string') : [];
}

/** The refs a run's answer cites (`result.evidence_refs`). */
function runRefs(run: AgentRun): string[] {
  const result = run.result as { evidence_refs?: unknown } | null | undefined;
  return refsOf(result?.evidence_refs);
}

/** The member a run belongs to, by its code: conformance, encounter, impact, coordinator, generalist. */
const memberOf = (run: AgentRun) => run.memberCode || run.member?.code || run.role;

export interface Citation {
  ref: EvidenceRef;
  /** The members whose runs cited it, by code, in the runs' order (the coordinator's own run included). */
  members: string[];
  /** Whether the plan cites it. */
  plan: boolean;
}

/**
 * For each evidence section, which members cited it and whether the plan did. Only the runs that made the plan count:
 * a case planned twice cites from its last round, the runs whose evidence snapshot is the plan's.
 */
export function citationsOf(
  runs: AgentRun[] | null | undefined,
  plan: (Pick<Plan, 'evidenceRefs'> & { snapshotId?: string | number }) | null | undefined,
): Citation[] {
  const all = runs ?? [];
  const snapshot = plan?.snapshotId;
  const used =
    snapshot !== undefined &&
    all.some((r) => String((r as { snapshotId?: unknown }).snapshotId) === String(snapshot))
      ? all.filter((r) => String((r as { snapshotId?: unknown }).snapshotId) === String(snapshot))
      : all;
  const planRefs = refsOf(plan?.evidenceRefs);
  return EVIDENCE_REFS.map((ref) => ({
    ref,
    members: [...new Set(used.filter((r) => runRefs(r).includes(ref)).map(memberOf))],
    plan: planRefs.includes(ref),
  }));
}

/** A catalogue entry's id, with its version or without: E7, E9@1. */
const ENTRY = /^E\d+(@\d+)?$/;

/**
 * The catalogue entries a list of refs names: "E7", "E9@1" from `catalogue:E7` and `catalogue:E9@1`, or from the entry's
 * id alone, as a v1.35 run cites a key of the evidence it was given (CONTRACTS 6.6), each once.
 */
export function catalogueEntriesOf(refs: unknown): string[] {
  const entries = refsOf(refs)
    .map((r) => (r.startsWith('catalogue:') ? r.slice('catalogue:'.length) : r))
    .filter((r) => ENTRY.test(r));
  return [...new Set(entries)];
}

const NAMES: Record<string, string> = {
  conformance: 'Conformance',
  encounter: 'Encounter Integrity',
  impact: 'Impact Analysis',
  generalist: 'the single investigator',
};
const SPECIALISTS = ['conformance', 'encounter', 'impact'];

/**
 * A section's citation line: "Cited by all three agents and the plan", "Cited by Conformance, Impact Analysis and the
 * plan", "Cited by the plan", "Not cited". The coordinator's own run is the plan's, so it is not named apart.
 */
export function citationWords(c: Citation, specialists: string[] = SPECIALISTS): string {
  const cited = c.members.filter((m) => m !== 'coordinator');
  const everyone = specialists.length > 1 && specialists.every((m) => cited.includes(m));
  const who = everyone
    ? [`all ${specialists.length === 3 ? 'three' : specialists.length} agents`]
    : cited.map((m) => NAMES[m] ?? m);
  const parts = [...who, ...(c.plan ? ['the plan'] : [])];
  if (!parts.length) return 'Not cited';
  return `Cited by ${parts.length === 1 ? parts[0] : `${parts.slice(0, -1).join(', ')} and ${parts[parts.length - 1]}`}`;
}
