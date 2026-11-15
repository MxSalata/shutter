/**
 * One of the site's own scenarios on a case (CONTRACTS 6.8): a site entry, id L<n>, that matched and so answers
 * alone. The matcher writes it into the evidence's catalogue item with what it displaced (`overridden`) and the other
 * site entries that matched too (`site_also`); everything here is read from there, and nothing decides anything.
 */

const SITE_ENTRY = /^L[1-9]\d*$/;

/** Whether a catalogue entry's id is one of the site's own (L1), not a shipped one (E7). */
export function isSiteEntryId(id: unknown): id is string {
  return typeof id === 'string' && SITE_ENTRY.test(id);
}

export interface SiteInstruction {
  id: string;
  version?: number;
  title: string;
  instructions: string;
  team?: string;
}

export interface Displaced {
  id: string;
  decides: string;
  outcome: string;
}

export interface SiteMatch extends SiteInstruction {
  why: string;
  /** The other site entries that matched this case too, each with its own instructions. */
  also: SiteInstruction[];
  /** The shipped entries the site entry displaced: what the case would have matched without it. */
  displaced: Displaced[];
}

const obj = (v: unknown): Record<string, unknown> | undefined =>
  v && typeof v === 'object' && !Array.isArray(v) ? (v as Record<string, unknown>) : undefined;
const list = (v: unknown): unknown[] => (Array.isArray(v) ? v : []);
const text = (v: unknown): string => (typeof v === 'string' ? v : typeof v === 'number' ? String(v) : '');

function instruction(v: unknown): SiteInstruction | undefined {
  const o = obj(v);
  if (!o || !isSiteEntryId(o.id)) return undefined;
  const version = Number(o.version);
  return {
    id: o.id,
    version: Number.isFinite(version) && version > 0 ? version : undefined,
    title: text(o.title),
    instructions: text(o.instructions),
    team: text(o.team) || undefined,
  };
}

/** The site entry a case's evidence shows as its match, or undefined when a shipped entry, several or none matched. */
export function siteMatchOf(summary: unknown): SiteMatch | undefined {
  const catalogue = obj(obj(summary)?.catalogue);
  const matches = list(catalogue?.matches);
  if (matches.length !== 1) return undefined;
  const match = obj(matches[0]);
  if (!match || match.origin !== 'site') return undefined;
  const lead = instruction(match);
  if (!lead) return undefined;
  return {
    ...lead,
    why: text(obj(match.preferred)?.why),
    also: list(catalogue?.site_also)
      .map(instruction)
      .filter((i): i is SiteInstruction => !!i),
    displaced: list(catalogue?.overridden)
      .map(obj)
      .filter((o): o is Record<string, unknown> => !!o && text(o.id) !== '')
      .map((o) => ({ id: text(o.id), decides: text(o.decides), outcome: text(o.outcome) })),
  };
}

const OUTCOMES: Record<string, string> = {
  resend: 'a resend',
  resend_chain: 'a resend of the chain',
  resend_latest: 'a resend of the latest movement',
  resend_after_occupant: 'a resend once the bed is free',
  resend_unconditional: 'an unconditional resend',
  reconcile: 'closed as already applied, nothing sent',
  none: 'closed, nothing sent',
  escalate: 'a person',
  correct_history: 'a correction of the history by a person',
};

const DECIDES: Record<string, string> = {
  policy: 'by site policy',
  board: 'decided by the board',
  person: 'decided by a person',
};

/** One displaced entry in words: "E2, a resend by site policy". */
export function displacedWords(d: Displaced): string {
  const outcome = OUTCOMES[d.outcome] ?? d.outcome.replace(/_/g, ' ');
  // An entry that asks for a person says so once.
  if (d.outcome === 'escalate') return `${d.id}, a person decides`;
  return `${d.id}, ${outcome} ${DECIDES[d.decides] ?? ''}`.trim();
}

/**
 * What the case would have done without the site entry, in one line: "Without it: E2, a resend by site policy". With no
 * shipped match it would have been a new pattern; with several, the board's.
 */
export function withoutItWords(displaced: Displaced[]): string {
  if (displaced.length === 0) return 'Without it: no shipped entry matches, so this would be a new pattern.';
  if (displaced.length === 1) return `Without it: ${displacedWords(displaced[0])}.`;
  return `Without it: ${displaced.map((d) => d.id).join(', ')} all match, so the board would decide.`;
}
