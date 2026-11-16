import type {
  SiteEntryContent,
  SiteEntryImpactGroup,
  SiteEntryOverlap,
  SiteEntryProofResult,
} from '@/api/types';
import { displacedWords } from '@/lib/siteEntry';

/**
 * The words of the site's own scenarios on the workbench: each condition a case showed, in a sentence's words (Plain)
 * or by its name (Technical); what the last stored cases would have done instead; the entry as YAML. Words only:
 * nothing here decides what leads or what a case does, which the core answers.
 */

/** Each condition's values in the words of a sentence about the case. A value not listed is said as it is. */
const CONDITION_WORDS: Record<string, Record<string, string>> = {
  event: {
    admit: 'it is an admission',
    transfer: 'it is a transfer',
    discharge: 'it is a discharge',
    update: 'it is an update',
    merge: 'it is a merge',
    cancel: 'it is a cancellation',
    other: 'it is another kind of message',
  },
  delivery: {
    failed: 'its delivery failed',
    rejected: 'the receiver rejected it',
    uncertain: 'no answer came',
    unmappable: 'it could not be mapped',
    withheld: 'it was withheld',
    unreadable: 'it was held unread',
  },
  receiver_answer: {
    unavailable: 'the receiver was unavailable',
    timeout: 'the receiver timed out',
    duplicate: 'the receiver called it a duplicate',
    version_conflict: 'the receiver found a version conflict',
    refused: 'the receiver refused it',
    unread: "the receiver's answer could not be read",
    none: 'the receiver gave no answer',
  },
  receipt: {
    present: 'the receiver holds a receipt',
    absent: 'the receiver holds no receipt',
    unreadable: 'the receipt could not be read',
    none: 'no receipt was looked for',
  },
  later_applied: {
    none: 'nothing later was applied',
    transfer: 'a later transfer was applied',
    discharge: 'a later discharge was applied',
    update: 'a later update was applied',
    admit: 'a later admission was applied',
    cancelled: 'it was cancelled later',
    cancel_other: 'another movement was cancelled later',
    merge: 'a later merge was applied',
  },
  later_delivery: {
    applied: 'a later message was applied',
    sent: 'a later message was sent',
    none: 'no later message was sent',
  },
  event_time: {
    plausible: 'its time is plausible',
    before_admission: 'its time is before the admission',
    future: 'its time is in the future',
    far_from_recorded: 'its time is far from when it was recorded',
    clock_change: 'its time falls on a clock change',
    later_event_future: 'a later event is in the future',
  },
  encounter_state: {
    admitted: 'the patient is admitted',
    discharged: 'the patient is discharged',
    not_found: 'the encounter is not found',
    unknown: "the encounter's state is unknown",
  },
  transition: {
    allowed: 'the movement is allowed',
    invalid: 'the movement is not allowed',
    unknown: 'whether the movement is allowed is unknown',
  },
  patient_match: {
    yes: 'the patient matches',
    no: 'the patient does not match',
    unknown: 'whether the patient matches is unknown',
  },
  simultaneous_sources: { yes: 'two systems sent it at once', no: 'one system sent it' },
  conditional_writes: {
    yes: 'the receiver takes conditional writes',
    no: 'the receiver takes no conditional writes',
    unknown: 'whether the receiver takes conditional writes is unknown',
  },
  free_text: { yes: 'it carries free text', no: 'it carries no free text' },
  chain: {
    single: 'it is a single message',
    ordered: 'it is part of an ordered chain',
    interleaved: 'it is part of an interleaved chain',
  },
  receiver_category: {
    current_state: 'the receiver keeps current state',
    history_of_record: 'the receiver keeps a history of record',
    orders_results: 'the receiver takes orders and results',
  },
  bed_conflict: {
    none: 'the bed is free',
    occupant_leaving: "the bed's occupant is leaving",
    occupant_left: "the bed's occupant has left",
    occupant_staying: "the bed's occupant is staying",
    unknown: "the bed's state is unknown",
  },
  a08_location: {
    none: 'no update names a location',
    same: 'an update names the same location',
    different: 'an update names another location',
  },
};

/** One value of a condition in words: "its delivery failed". */
export const valueWords = (condition: string, value: string): string =>
  CONDITION_WORDS[condition]?.[value] ?? `${condition.replace(/_/g, ' ')} is ${value.replace(/_/g, ' ')}`;

/** A list's words joined: "a, b or c". */
export function joined(list: string[], last = 'or'): string {
  if (list.length <= 1) return list[0] ?? '';
  return `${list.slice(0, -1).join(', ')} ${last} ${list[list.length - 1]}`;
}

/** A condition and its values as a chip says it: Plain "its delivery failed or the receiver rejected it", Technical "delivery: failed, rejected". */
export function chipLabel(condition: string, values: string[], technical: boolean): string {
  if (technical) return `${condition}: ${values.join(', ')}`;
  return joined(values.map((v) => valueWords(condition, v)));
}

/** The four scope facts, named for a person. */
export const SCOPE_LABELS: Record<string, string> = {
  receiver: 'Receiver',
  source_system: 'Sending system',
  ward: 'Ward',
  reason_code: "The receiver's reason",
};

export const SCOPE_KEYS = ['receiver', 'source_system', 'ward', 'reason_code'] as const;

/** What the last stored cases would have done without the entry (P4), each group in words. */
export const GROUP_WORDS: Record<SiteEntryImpactGroup, string> = {
  automatic_resend: 'resent by site policy, with no person',
  approved_resend: "resent after a person's approval",
  closure: 'closed with nothing sent',
  board: 'decided by the board',
  person: 'already sent to a person',
  new_pattern: 'a new pattern',
  other_site_entry: 'led by another of our scenarios',
  other: 'something else',
};

type Impact = NonNullable<SiteEntryProofResult['impact']>;

/** The groups that hold cases, largest first. */
export function groupsOf(impact: Impact): { group: SiteEntryImpactGroup; n: number; cases: string[] }[] {
  return (Object.entries(impact.groups) as [SiteEntryImpactGroup, number][])
    .filter(([, n]) => n > 0)
    .sort((a, b) => b[1] - a[1])
    .map(([group, n]) => ({ group, n, cases: impact.cases[group] ?? [] }));
}

const cases = (n: number) => `${n} ${n === 1 ? 'case' : 'cases'}`;

/**
 * The line under the chips: "Of the last 200 cases, it would catch 3: 2 resent by site policy, with no person; 1 closed
 * with nothing sent." A retirement reads it the other way: the cases it catches, and what each would do without it.
 */
export function impactLine(impact: Impact, action: string = 'activate'): string {
  const head =
    action === 'retire'
      ? `Of the last ${cases(impact.scanned)}, it catches ${impact.caught}`
      : `Of the last ${cases(impact.scanned)}, it would catch ${impact.caught === 0 ? 'none' : impact.caught}`;
  const groups = groupsOf(impact);
  const body = groups.length
    ? `: ${groups.map((g) => `${g.n} ${GROUP_WORDS[g.group]}`).join('; ')}${action === 'retire' ? ', without it' : ' instead'}.`
    : '.';
  const notes = [
    impact.capped ? 'Shutter stopped reading after 10 seconds, so older cases were not counted.' : '',
    impact.unread ? `${cases(impact.unread)} could not be read.` : '',
  ].filter(Boolean);
  return `${head}${body}${notes.length ? ` ${notes.join(' ')}` : ''}`;
}

/**
 * What the entry displaces, as the dialogs say it: "Without it: E2, a resend by site policy; E10, a resend by site
 * policy; new patterns". The shipped entries come from the core's overlap report; "new patterns" when none covers it.
 */
export function displacesWords(overlap: SiteEntryOverlap[]): string {
  const rows = overlap.filter((o) => !o.leads);
  const parts = rows.map((o) => displacedWords({ id: o.id, decides: o.decides, outcome: o.outcome }));
  if (!rows.some((o) => o.covers)) parts.push('new patterns');
  return `Without it: ${parts.join('; ')}.`;
}

/** The plain words of an action. */
export const ACTION_WORDS: Record<string, string> = {
  activate: 'make it active',
  retire: 'retire it',
  resume: 'resume it',
};

const yamlValue = (v: unknown): string => {
  if (Array.isArray(v)) return `[${v.map((x) => yamlValue(x)).join(', ')}]`;
  if (typeof v === 'number' || typeof v === 'boolean') return String(v);
  const s = String(v ?? '');
  // Plain when it is safe as plain YAML, quoted otherwise.
  return /^[A-Za-z0-9][\w .-]*$/.test(s) && !/^(yes|no|true|false|null|on|off)$/i.test(s)
    ? s
    : JSON.stringify(s);
};

/** The entry as YAML, as CONTRACTS 6.8 writes it: the Technical view's copy of exactly what is stored. */
export function entryYaml(content: Partial<SiteEntryContent> & { id?: string }): string {
  const lines: string[] = [];
  const put = (key: string, v: unknown) => lines.push(`${key}: ${yamlValue(v)}`);
  if (content.id) put('id', content.id);
  put('kind', 'stop');
  put('title', content.title ?? '');
  put('priority', content.priority ?? 100);
  const map = (key: string, m: Record<string, string[]> | undefined) => {
    const entries = Object.entries(m ?? {});
    if (!entries.length) return lines.push(`${key}: {}`);
    lines.push(`${key}:`);
    for (const [k, v] of entries) lines.push(`  ${k}: ${yamlValue(v)}`);
  };
  map('scope', content.scope);
  map('pattern', content.pattern);
  put('why', content.why ?? '');
  if (content.team) put('team', content.team);
  put('instructions', content.instructions ?? '');
  if (content.prose) put('prose', content.prose);
  const fixtures = content.fixtures ?? [];
  if (!fixtures.length) lines.push('fixtures: []');
  else {
    lines.push('fixtures:');
    for (const f of fixtures) lines.push(`  - case: ${yamlValue(f.case)}`, `    expect: ${f.expect}`);
  }
  return lines.join('\n');
}
