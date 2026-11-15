import type { SiteProfile, SiteProfileView, SiteReceiver } from '@/api/types';
import { categoryOf, historyPolicyOf } from '@/lib/categories';
import { formatDay, formatZonedTime } from '@/lib/format';
import { DECIDES, OUTCOMES } from '@/lib/siteEntry';
import { POLICY_SHORT } from '@/features/site-profile/profile';
import { fhirOf } from '@/features/site-profile/receiverCapabilities';

/**
 * This site's guide without React: what GET /catalogue answers, the outcome a site's settings select for an entry
 * (computed as the core's matcher does), the failure in words, the stamp and the limits that apply to the install.
 * Everything here is read from the install's own answers at the moment of export; nothing is typed for the guide.
 */

/** An alternative outcome of a catalogue entry (CONTRACTS 6.2): `when` is `always` or `<flag>: <value>`. */
export interface CatalogueAlternative {
  outcome: string;
  why?: string;
  when?: string;
}

/** One entry as GET /catalogue gives it: a shipped E entry, or an active site entry as the matcher reads it. */
export interface CatalogueEntry {
  id: string;
  version: number;
  title: string;
  decides: string;
  scenarios?: string[];
  pattern?: Record<string, string | string[]>;
  preferred?: { outcome?: string; why?: string };
  alternatives?: CatalogueAlternative[];
  checks?: string[];
  prose?: string;
  /** "site" on a site entry. */
  origin?: string;
  kind?: string;
  priority?: number;
  scope?: Record<string, string[]>;
  instructions?: string;
  team?: string;
  sentence?: string;
}

/** GET /catalogue (CONTRACTS 6.8). */
export interface CatalogueView {
  version: string;
  shippedVersion: string;
  generation: number;
  shipped: CatalogueEntry[];
  site: CatalogueEntry[];
  vocabulary?: unknown;
  /** An active site entry that can't be read: the matcher then answers error for every case (R13). */
  siteError?: string;
}

// ---- the outcome a site's settings select (Shutter.Catalogue.Matcher, Settle and WhenHolds) ----

/** The facts a case's receiver gives an entry's `when` (Matcher.Facts): its history policy and its category. */
export interface ReceiverFacts {
  history_policy: string;
  receiver_category: string;
}

/** As SiteProfile.ReceiverHistoryPolicy and ReceiverCategory read the receiver. */
export function receiverFacts(r: SiteReceiver, profile: SiteProfile): ReceiverFacts {
  return { history_policy: historyPolicyOf(r, profile), receiver_category: categoryOf(r) };
}

/** Facts that come from the case itself, not from its receiver or the profile: known only when a case is matched. */
const CASE_FACTS = ['other_source', 'occupant_case'];

/** A profile flag as Shutter.Util.Json.Str reads it: a string or a number as written, a boolean as 1 or 0. */
function flagOf(profile: SiteProfile, flag: string): string {
  const v = (profile as unknown as Record<string, unknown>)[flag];
  if (typeof v === 'string') return v;
  if (typeof v === 'number') return String(v);
  if (typeof v === 'boolean') return v ? '1' : '0';
  return '';
}

/**
 * Whether an alternative's `when` holds at a receiver, as Matcher.WhenHolds decides it: true, false, or, where the
 * answer depends on the case (the other source system of a simultaneous movement), the condition in words.
 */
export function whenHolds(
  when: string,
  facts: ReceiverFacts,
  profile: SiteProfile,
): boolean | { onCase: string } {
  const w = when.trim();
  if (w === '' || w === 'always') return true;
  const at = w.indexOf(':');
  const flag = (at < 0 ? w : w.slice(0, at)).trim();
  const value = (at < 0 ? '' : w.slice(at + 1)).trim();
  // A fact of the flag's name (the receiver's history policy and category) answers before the site-wide flag
  const known = (f: string) =>
    f === 'history_policy' || f === 'receiver_category' ? facts[f] : flagOf(profile, f);
  if (value === 'other_source') {
    // The value is the case's other source system: it holds when that system is the one this flag names
    const named = CASE_FACTS.includes(flag) ? '' : known(flag);
    return named ? { onCase: `the other system sending at the same time is ${named}` } : false;
  }
  if (value === '') return false;
  if (CASE_FACTS.includes(flag)) return { onCase: `the case's ${flag.replace(/_/g, ' ')} is ${value}` };
  return known(flag) === value;
}

/** One way an entry settles at a receiver: its outcome, which of the entry's outcomes it is, and when it applies. */
export interface Branch {
  outcome: string;
  /** "preferred" or "alternative:<n>", as the plan names it. */
  ref: string;
  /** Set when it applies only on a case where this holds; the last branch has none. */
  condition?: string;
}

/**
 * The outcome a single match settles on at a receiver, as Matcher.Settle picks it: the preferred one, unless an
 * alternative whose `when` names a flag holds for the receiver (the first that holds, in the entry's order). `always`
 * and a `when` with no flag are board options, never a policy. An alternative that holds only on some cases comes first,
 * with its condition; the last branch is what applies otherwise.
 */
export function settle(entry: CatalogueEntry, facts: ReceiverFacts, profile: SiteProfile): Branch[] {
  const out: Branch[] = [];
  const alternatives = Array.isArray(entry.alternatives) ? entry.alternatives : [];
  for (const [n, alt] of alternatives.entries()) {
    if (!alt || typeof alt !== 'object') continue;
    const when = (alt.when ?? '').trim();
    if (when === '' || when === 'always' || !when.includes(':')) continue;
    const holds = whenHolds(when, facts, profile);
    if (holds === true) {
      out.push({ outcome: alt.outcome, ref: `alternative:${n + 1}` });
      return out;
    }
    if (holds !== false)
      out.push({ outcome: alt.outcome, ref: `alternative:${n + 1}`, condition: holds.onCase });
  }
  out.push({ outcome: entry.preferred?.outcome ?? '', ref: 'preferred' });
  return out;
}

/** Whether a gate would allow an alternative at a receiver (Gate.cls reads the same WhenHolds). */
export function alternativeHere(
  alt: CatalogueAlternative,
  facts: ReceiverFacts,
  profile: SiteProfile,
): boolean | { onCase: string } {
  return whenHolds(alt.when ?? 'always', facts, profile);
}

// ---- words ----

/** An outcome in the case page's words: "a resend", "closed, nothing sent", "a person". */
export const outcomeWords = (o: string) => OUTCOMES[o] ?? o.replace(/_/g, ' ');

/** Who settles a case the entry alone matches, in the case page's words. */
export const decidesWords = (d: string) => DECIDES[d] ?? d.replace(/_/g, ' ');

const WRITES = ['resend', 'resend_chain', 'resend_latest', 'resend_after_occupant', 'resend_unconditional'];

/** Whether an outcome writes to the receiver. */
export const isWrite = (o: string) => WRITES.includes(o);

const asList = (v: string | string[] | undefined): string[] =>
  v === undefined ? [] : (Array.isArray(v) ? v : [v]).map(String);

/** "a, b or c", as the core's SiteEntryVersion.Words joins them. */
export function orWords(list: string[]): string {
  if (list.length <= 1) return list.join('');
  return `${list.slice(0, -1).join(', ')} or ${list[list.length - 1]}`;
}

const EVENT_WORDS: Record<string, string> = {
  admit: 'an admission',
  update: 'an update',
  other: 'another kind of message',
};

const DELIVERY_WORDS: Record<string, string> = {
  failed: 'fails',
  rejected: 'is rejected',
  uncertain: 'gets no answer',
  unmappable: 'cannot be mapped',
  withheld: 'is withheld',
  unreadable: 'is held unread',
};

/**
 * A shipped entry's pattern in one sentence, in the words the core gives a site entry (SiteEntryVersion.Sentence):
 * "When a transfer fails or is rejected, and receipt is absent". The words of the vocabulary are its own (CONTRACTS 6.1).
 */
export function patternWords(pattern: CatalogueEntry['pattern']): string {
  const p = pattern ?? {};
  const events = asList(p.event);
  const what = events.length ? orWords(events.map((e) => EVENT_WORDS[e] ?? `a ${e}`)) : 'a message';
  const delivery = asList(p.delivery);
  let text = `When ${what} ${delivery.length ? orWords(delivery.map((d) => DELIVERY_WORDS[d] ?? d)) : 'is not delivered'}`;
  for (const [condition, values] of Object.entries(p)) {
    if (condition === 'event' || condition === 'delivery') continue;
    text += `, and ${condition.replace(/_/g, ' ')} is ${orWords(asList(values).map((v) => v.replace(/_/g, ' ')))}`;
  }
  return text;
}

/** The chain kind an entry's pattern names, for the release table: single when it names none or several. */
export function chainOf(entry: CatalogueEntry): 'single' | 'ordered' | 'interleaved' {
  const c = asList(entry.pattern?.chain);
  return c.length === 1 && (c[0] === 'ordered' || c[0] === 'interleaved') ? c[0] : 'single';
}

/** Who releases a write of a kind at the receiver's tier: the site's policy table (an unset cell is one approval). */
export function releaseAt(profile: SiteProfile, r: SiteReceiver, kind: string): string {
  return profile.policy?.[String(r.tier)]?.[kind as 'single'] ?? 'approval';
}

/** What a person is asked to do when a case settles on this outcome at this receiver. */
export function askedWords(outcome: string, release: string, decides: string): string {
  if (decides === 'board' && outcome !== 'escalate')
    return 'The board of agents proposes a plan; any write it proposes waits for a person to approve it.';
  if (outcome === 'escalate')
    return 'A person decides the case, with the entry named; Shutter sends nothing.';
  if (outcome === 'correct_history')
    return 'A person corrects the history by hand, with the steps named on the case; Shutter sends nothing.';
  if (outcome === 'none' || outcome === 'reconcile')
    return 'Nobody is asked: the case closes once the receiver is read again and agrees.';
  if (outcome === 'resend_unconditional') return 'An approver releases the write; it is never automatic.';
  if (isWrite(outcome))
    return release === 'automatic'
      ? "Nobody is asked: the site's written policy releases the write after the gate and the dry run."
      : `An approver releases the write (${POLICY_SHORT[release] ?? release.replace(/_/g, ' ')}).`;
  return 'A person decides.';
}

/** A receiver whose cases Shutter can write to from the case (not orders and results, not FHIR, which have their own). */
export function modelledReceiver(r: SiteReceiver): boolean {
  return categoryOf(r) !== 'orders_results' && !fhirOf(r);
}

/**
 * A receiver with no recovery API (SiteProfile.HasNoApi): no `api`, and declared features or the orders and results
 * category, or an onboarding draft. Shutter reads nothing there and a case is never resent from the case.
 */
export function hasNoRecoveryApi(r: SiteReceiver): boolean {
  if (fhirOf(r)) return false;
  if (r.draft === true) return true;
  const api = r.api as unknown;
  if (typeof api === 'object' && api !== null) return false;
  return (typeof r.features === 'object' && r.features !== null) || categoryOf(r) === 'orders_results';
}

/** One line per receiver group for an entry: who decides at those receivers, its outcome and what a person does. */
export interface EntryAt {
  receivers: string[];
  lines: string[];
}

/** What the entry comes to at each receiver Shutter can write to, receivers with the same words grouped together. */
export function entryAtReceivers(entry: CatalogueEntry, profile: SiteProfile): EntryAt[] {
  const groups: EntryAt[] = [];
  for (const r of profile.receivers.filter(modelledReceiver)) {
    const branches = settle(entry, receiverFacts(r, profile), profile);
    const lines = branches.map((b) => {
      const what = `${outcomeWords(b.outcome)}${b.ref === 'preferred' ? '' : ` (its alternative ${b.ref.split(':')[1]})`}`;
      const asked = askedWords(b.outcome, releaseAt(profile, r, chainOf(entry)), entry.decides);
      return b.condition
        ? `When ${b.condition}: ${what}. ${asked}`
        : `${branches.length > 1 ? 'Otherwise' : 'Outcome'}: ${what}. ${asked}`;
    });
    const same = groups.find((g) => g.lines.join('\n') === lines.join('\n'));
    if (same) same.receivers.push(r.name || 'unnamed');
    else groups.push({ receivers: [r.name || 'unnamed'], lines });
  }
  return groups;
}

/**
 * The entry's alternatives and where each is allowed here: an alternative the gate lets a plan name only where its
 * `when` holds (Gate.cls, OUTCOME_NOT_ALLOWED otherwise); `always` is the board's choice.
 */
export function alternativesHere(entry: CatalogueEntry, profile: SiteProfile): string[] {
  const alternatives = Array.isArray(entry.alternatives) ? entry.alternatives : [];
  const receivers = profile.receivers.filter(modelledReceiver);
  return alternatives.map((alt, n) => {
    const head = `Alternative ${n + 1}, ${outcomeWords(alt.outcome)}`;
    const when = (alt.when ?? 'always').trim();
    if (when === 'always' || when === '') return `${head}: the board's or a person's choice on any case.`;
    const at = receivers.map((r) => ({ r, holds: alternativeHere(alt, receiverFacts(r, profile), profile) }));
    const yes = at.filter((a) => a.holds === true).map((a) => a.r.name);
    const onCase = at.find((a) => typeof a.holds === 'object')?.holds as { onCase: string } | undefined;
    const rule = `only where ${when.replace(/_/g, ' ')}`;
    if (onCase) return `${head}: ${rule}; here, when ${onCase.onCase}.`;
    if (!yes.length) return `${head}: ${rule}, which does not hold at this site.`;
    if (yes.length === receivers.length) return `${head}: ${rule}, which holds at every receiver here.`;
    return `${head}: ${rule}, which holds at ${orWords(yes).replace(/ or /, ' and ')}.`;
  });
}

// ---- the stamp ----

/**
 * A moment in the feed's zone with its year always, since a printed guide outlives the year it was made in: "15 Nov
 * 2026, 23:50:12 GMT". (formatDay names the year whenever it differs from the one it is given as now.)
 */
export const stampTime = (iso: string) => `${formatDay(iso, 0)}, ${formatZonedTime(iso)}`;

export interface Stamp {
  trial: boolean;
  profileVersion: number;
  /** "Saved 26 Oct 2026, 03:31 GMT by Setup", or the shipped answers' words. */
  saved: string;
  catalogueVersion: string;
  gatePolicy: string;
  release: string;
  exportedAt: string;
}

/** The versions this guide describes, and when it was made. */
export function stampOf(input: {
  view: SiteProfileView;
  catalogue: CatalogueView;
  health: Record<string, unknown>;
  now: Date;
  trial: boolean;
  shippedWords: string;
}): Stamp {
  const { view, catalogue, health, now, trial } = input;
  const by = view.updatedBy || 'Setup';
  const saved = view.updatedAt
    ? `saved ${stampTime(view.updatedAt)} by ${by}${view.source === 'api' ? '' : ` (${input.shippedWords})`}`
    : input.shippedWords;
  const text = (k: string) => (typeof health[k] === 'string' ? (health[k] as string) : '');
  return {
    trial,
    profileVersion: view.version,
    saved,
    catalogueVersion: catalogue.version || catalogue.shippedVersion || '',
    gatePolicy: text('gate_policy_version'),
    release: text('version'),
    exportedAt: stampTime(now.toISOString()),
  };
}

/** The stamp in one line, for the foot of every printed page. */
export function stampLine(s: Stamp): string {
  return [
    s.trial ? 'Trial (sample data)' : null,
    `Site profile version ${s.profileVersion}`,
    `catalogue ${s.catalogueVersion || 'not read'}`,
    `gate policy ${s.gatePolicy || 'not read'}`,
    `release ${s.release || 'not read'}`,
    `exported ${s.exportedAt}`,
  ]
    .filter(Boolean)
    .join(' · ');
}

export const OUT_OF_DATE =
  'This guide describes these versions only. Any change to the site profile, the catalogue or the release makes it out of date: export it again.';

// ---- the limits that apply to this install (docs/readme/limits.md) ----

export interface Limit {
  title: string;
  text: string;
}

/** The limits of docs/readme/limits.md that this install's answers make apply, in that file's words, shortened. */
export function limitsFor(profile: SiteProfile): Limit[] {
  const out: Limit[] = [
    {
      title: 'Not measured at a hospital',
      text: "How many of a hospital's failures Shutter resolves has not been measured: the scenarios are written by its authors and the data is synthetic.",
    },
  ];
  if (profile.recovery?.mode !== 'enabled')
    out.push({
      title: 'Shadow mode',
      text: 'Recovery is not enabled: Shutter investigates and records what it would propose, and sends no rehearsal, recovery write, resend preview or outage resend.',
    });
  const noApi = profile.receivers.filter((r) => hasNoRecoveryApi(r) && categoryOf(r) !== 'orders_results');
  if (noApi.length)
    out.push({
      title: 'A receiver with no recovery API',
      text: `${orWords(noApi.map((r) => r.name)).replace(/ or /, ' and ')}: a case there is investigated and goes to a person, never resent from the case.`,
    });
  if (profile.receivers.some((r) => categoryOf(r) === 'orders_results'))
    out.push({
      title: 'Orders, results and documents',
      text: 'Up to 2 MB they get a case and a drafted email, never a resend from the case.',
    });
  if (profile.receivers.some((r) => fhirOf(r)))
    out.push({
      title: 'FHIR R4 is one profile',
      text: 'One ward move on an existing in-progress Encounter, off until the entry turns recovery on; no dry run. A person releases everything else.',
    });
  const reminders = (profile as unknown as { reminders?: { enabled?: boolean } }).reminders;
  if (reminders?.enabled !== true)
    out.push({
      title: 'Nobody is told',
      text: 'No reminder mail is set for cases left open: someone watches the Workflow inbox and the case list.',
    });
  out.push(
    {
      title: 'Further messages are read, not held',
      text: "At each write Shutter reads every HL7 message since the case's own; a read that runs out stops the write for a person. It can't see a change made by hand at the receiver.",
    },
    {
      title: 'A write whose answer was lost',
      text: 'It is judged at the last read: with no sign of it by then, the outcome is unknown and a person decides.',
    },
  );
  return out;
}
