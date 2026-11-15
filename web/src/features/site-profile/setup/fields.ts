import type { SiteProfile, SiteReceiver } from '@/api/types';
import { CATEGORY_TEXT, categoryOf, historyPolicyOf } from '@/lib/categories';
import { KIND_WRITTEN, TIER_WRITTEN } from '../askAbout';
import {
  APPLIES_LABELS,
  EFFECT_WORDS,
  KINDS,
  KIND_LABELS,
  POLICY_SHORT,
  RESEND_LABELS,
  TIER_LABELS,
  overtakenLine,
} from '../profile';

/**
 * Set up the site: the one table that says who may supply each key of the site profile, and the checklist of questions
 * the page asks about one receiver.
 *
 * Class A is what Ask Shutter may draft from a person's own words, and it is narrow on purpose: a receiver's description,
 * and the kind and tier of a receiver that is being added. Class P is asked on the page and answered only by a person
 * with the page's own control: every policy, every capability, every site-wide switch and `recovery.mode`. `kept` is
 * stored as it is and never set from this page. A key the table does not know is preserved untouched.
 */

export type FieldClass = 'A' | 'P' | 'kept';

/**
 * A key path and its class. `[]` stands for any index, and a path ending `.*` covers the key and everything under it.
 * Every key `validateProfile` accepts is in exactly one row.
 */
export const FIELD_TABLE: readonly (readonly [path: string, cls: FieldClass])[] = [
  // What describes a receiver: the only keys a model may ever draft, each with its conditions (`draftRefusal`)
  ['receivers[].system', 'A'],
  ['receivers[].category', 'A'],
  ['receivers[].tier', 'A'],
  // A receiver's identity, what it does and takes, and its outages: a person's declaration
  ['receivers[].name', 'P'],
  ['receivers[].history_policy', 'P'],
  ['receivers[].applies', 'P'],
  ['receivers[].resend_timestamp', 'P'],
  ['receivers[].cancels', 'P'],
  ['receivers[].merges', 'P'],
  ['receivers[].api.*', 'P'],
  ['receivers[].features.*', 'P'],
  ['receivers[].strict_answers', 'P'],
  ['receivers[].manual_check.*', 'P'],
  ['receivers[].watch.*', 'P'],
  ['receivers[].ack_level', 'P'],
  ['receivers[].duplicates.*', 'P'],
  ['receivers[].engine_resend', 'P'],
  ['receivers[].hold.*', 'P'],
  ['receivers[].mail.*', 'P'],
  ['receivers[].approvers.*', 'P'],
  ['receivers[].runbook', 'P'],
  ['receivers[].call', 'P'],
  ['receivers[].resend_approval_minutes', 'P'],
  ['receivers[].settle_minutes', 'P'],
  ['receivers[].window_minutes', 'P'],
  // The site's own switches and rules
  ['recovery.*', 'P'],
  ['notifications.*', 'P'],
  ['policy.*', 'P'],
  ['merges', 'P'],
  ['unconditional_resend', 'P'],
  ['authoritative_source', 'P'],
  ['feed.*', 'P'],
  ['incident.*', 'P'],
  ['teams.*', 'P'],
  ['reminders.*', 'P'],
  ['model_content.*', 'P'],
  ['further_messages.*', 'P'],
  ['approvers.*', 'P'],
  ['mail.*', 'P'],
  // Kept as stored, never set from this page
  ['version', 'kept'],
  ['history_policy', 'kept'],
  ['failure_census.*', 'kept'],
  ['receivers[].demo.*', 'kept'],
  ['receivers[].fhir.*', 'kept'],
  ['receivers[].documents.*', 'kept'],
  ['receivers[].draft', 'kept'],
  ['receivers[].namespace', 'kept'],
  ['receivers[].item', 'kept'],
];

/** The rows a path falls under: one for a key the table knows, none for a key it does not. */
export function rowsFor(path: string): (readonly [string, FieldClass])[] {
  const plain = path.replace(/\[\d+\]/g, '[]');
  return FIELD_TABLE.filter(([row]) => {
    if (!row.endsWith('.*')) return row === plain;
    const stem = row.slice(0, -2);
    return plain === stem || plain.startsWith(`${stem}.`) || plain.startsWith(`${stem}[`);
  });
}

/** The class of a key path, or `unknown` for a key the table does not name (preserved untouched, never set). */
export function classOf(path: string): FieldClass | 'unknown' {
  return rowsFor(path)[0]?.[1] ?? 'unknown';
}

/** Every leaf key path of a profile, indexes written `[]`, once each: what the table's test walks. */
export function keyPaths(value: unknown, at = ''): string[] {
  const out = new Set<string>();
  const walk = (v: unknown, path: string) => {
    if (Array.isArray(v)) {
      if (!v.length && path) out.add(path);
      for (const item of v) walk(item, `${path}[]`);
    } else if (typeof v === 'object' && v !== null) {
      const entries = Object.entries(v);
      if (!entries.length && path) out.add(path);
      for (const [k, item] of entries) walk(item, path ? `${path}.${k}` : k);
    } else if (path) out.add(path);
  };
  walk(value, at);
  return [...out];
}

/** The questions of the checklist for one receiver, in order (the design's steps 0 to 6; the summary is step 7). */
export type QuestionId = 'name' | 'system' | 'category' | 'tier' | 'applies' | 'resend_timestamp' | 'takes';

export interface SetupQuestion {
  id: QuestionId;
  /** Its number in the checklist, as the page shows it. */
  n: number;
  /** The question, in the Site profile form's wording where it has one. */
  text: string;
  /** A short name for lists: "Kind of system". */
  short: string;
  /** The receiver's keys the answer is stored under. */
  keys: (keyof SiteReceiver & string)[];
  /** Who may supply the value: A is Ask Shutter or the person, for a receiver being added; P is the person only. */
  who: 'A' | 'P';
  /** A receiver that is being added cannot go to review without it. */
  required: boolean;
  /** Whether the answer changes what Shutter does, or is kept on record. */
  acts: boolean;
  /** What the question reads as while it is not answered. */
  unanswered: string;
  /** The written explanation, shown wherever no live answer is given: two sentences, 40 words at most. */
  written: string;
}

export const QUESTIONS: readonly SetupQuestion[] = [
  {
    id: 'name',
    n: 1,
    text: 'Which receiver? Name it by its production item.',
    short: 'Production item',
    keys: ['name'],
    who: 'P',
    required: true,
    acts: true,
    unanswered: 'No name: the receiver cannot be saved.',
    written:
      "Shutter finds a receiver's answers by the name of the production item that delivers to it, exactly as the production spells it. A name that matches no item is read by no case.",
  },
  {
    id: 'system',
    n: 2,
    text: 'What is the system, in a few words?',
    short: 'What it is',
    keys: ['system'],
    who: 'A',
    required: false,
    acts: false,
    unanswered: 'No description: cases show the production item alone.',
    written:
      "A few words people read beside the receiver's name, such as the ward whiteboard. It is a label: no check, policy or release reads it.",
  },
  {
    id: 'category',
    n: 3,
    text: 'What kind of system is it?',
    short: 'Kind of system',
    keys: ['category'],
    who: 'A',
    required: true,
    acts: true,
    unanswered: 'Not answered: it must be answered before review.',
    written: KIND_WRITTEN,
  },
  {
    id: 'tier',
    n: 4,
    text: 'Its tier',
    short: 'Tier',
    keys: ['tier'],
    who: 'A',
    required: true,
    acts: true,
    unanswered: 'Not answered: it must be answered before review.',
    written: TIER_WRITTEN,
  },
  {
    id: 'applies',
    n: 5,
    text: 'Does it apply messages in arrival order or by event time?',
    short: 'Applies messages',
    keys: ['applies'],
    who: 'P',
    required: false,
    acts: false,
    unanswered: 'Not answered: kept off the record.',
    written:
      'A system that applies messages as they arrive lets a late message move the record backwards; one that orders by event time does not. The answer is kept on record for the people who review a case.',
  },
  {
    id: 'resend_timestamp',
    n: 6,
    text: 'Does it take a resend with its original MSH-7, or need a fresh one?',
    short: 'A resend carries',
    keys: ['resend_timestamp'],
    who: 'P',
    required: false,
    acts: false,
    unanswered: 'Not answered: kept off the record.',
    written:
      'MSH-7 is the time a message was written. Some systems refuse a resend that carries the old time, and an engine resend sends the stored message unchanged, so it is refused beside a fresh one.',
  },
  {
    id: 'takes',
    n: 7,
    text: 'Does it accept cancels (A11, A12, A13) and merges (A40)?',
    short: 'Cancels and merges',
    keys: ['cancels', 'merges'],
    who: 'P',
    required: false,
    acts: true,
    unanswered: 'Not answered: read as no. Shutter sends it neither.',
    written:
      'A receiver that accepts neither is never sent one: the case goes to a person who corrects the receiver by hand. A merge also needs the site to allow merges.',
  },
];

export const questionById = (id: QuestionId): SetupQuestion => QUESTIONS.find((q) => q.id === id)!;

/** The question a receiver's key belongs to, or undefined for a key the checklist does not ask about. */
export const questionOfKey = (key: string): SetupQuestion | undefined =>
  QUESTIONS.find((q) => (q.keys as string[]).includes(key));

const KINDS_OF_SYSTEM = ['current_state', 'history_of_record', 'orders_results'];

/**
 * Whether a receiver's entry answers a question, by what the entry holds: a name or a description that is not blank,
 * one of the three kinds, a tier of 1 to 3, an answer the form knows, and for cancels and merges either key present.
 */
export function holdsAnswer(q: SetupQuestion, r: SiteReceiver): boolean {
  switch (q.id) {
    case 'name':
      return r.name.trim() !== '';
    case 'system':
      return typeof r.system === 'string' && r.system.trim() !== '';
    case 'category':
      return KINDS_OF_SYSTEM.includes(String(r.category));
    case 'tier':
      return [1, 2, 3].includes(Number(r.tier));
    case 'applies':
      return r.applies !== undefined && r.applies !== '';
    case 'resend_timestamp':
      return r.resend_timestamp !== undefined && r.resend_timestamp !== '';
    case 'takes':
      return r.cancels !== undefined || r.merges !== undefined;
  }
}

const yesNo = (v: unknown) => (v === true ? 'yes' : 'no');

/** The answer in words, as the draft pane and a "You:" turn say it; "" when the entry holds none. */
export function answerText(q: SetupQuestion, r: SiteReceiver): string {
  if (!holdsAnswer(q, r)) return '';
  switch (q.id) {
    case 'name':
      return r.name;
    case 'system':
      return r.system ?? '';
    case 'category':
      return CATEGORY_TEXT[categoryOf(r)].label;
    case 'tier':
      return `Tier ${TIER_LABELS[String(r.tier)] ?? String(r.tier)}`;
    case 'applies':
      return APPLIES_LABELS[String(r.applies)] ?? `Kept as stored: ${String(r.applies)}`;
    case 'resend_timestamp':
      return RESEND_LABELS[String(r.resend_timestamp)] ?? `Kept as stored: ${String(r.resend_timestamp)}`;
    case 'takes':
      return `Accepts cancels: ${yesNo(r.cancels)}. Takes merges: ${yesNo(r.merges)}.`;
  }
}

/** Who releases each kind of write at a tier, under a policy table: "single failures, one approval; ...". */
export function releasesAt(tier: string, policy: SiteProfile['policy'] | undefined): string {
  return KINDS.map(
    (kind) => `${KIND_LABELS[kind]}, ${POLICY_SHORT[policy?.[tier]?.[kind] ?? 'approval'] ?? 'one approval'}`,
  ).join('; ');
}

/**
 * What an answer does, in the page's own words and read as the server reads the draft: never a model's sentence. For a
 * question that is not answered, what it reads as until it is.
 */
export function consequence(q: SetupQuestion, r: SiteReceiver, profile: SiteProfile): string {
  if (!holdsAnswer(q, r)) return q.unanswered;
  switch (q.id) {
    case 'name':
      return 'Shutter reads these answers for cases whose failed delivery was through this production item.';
    case 'system':
      return 'A label people read. No decision reads it.';
    case 'category': {
      const category = categoryOf(r);
      return `${CATEGORY_TEXT[category].examples}. ${overtakenLine(category, historyPolicyOf(r, profile))}`;
    }
    case 'tier':
      return `Who releases a write at tier ${String(r.tier)}: ${releasesAt(String(r.tier), profile.policy)}.`;
    case 'applies':
    case 'resend_timestamp':
      return `${EFFECT_WORDS.record}.`;
    case 'takes':
      return [
        r.cancels === true
          ? 'Cancels may be sent to it, through the gate and the approvals.'
          : 'Shutter never sends it a cancel: such a case goes to a person.',
        r.merges === true
          ? profile.merges === 'allowed'
            ? 'Merges may be sent to it.'
            : 'It takes merges, but the site forbids them: each goes to the PAS team.'
          : 'No merge is sent to it.',
      ].join(' ');
  }
}

/** The page's name, as the page question route and the guide know it. */
export const SETUP_PAGE = 'site-setup';

/** What "Why does this matter?" asks of the Explain agent about one question: an explanation, never a choice. */
export function whyQuestion(q: SetupQuestion, name: string): string {
  const of = name.trim() || 'a receiver being added';
  return `Set up the site asks "${q.text}" about ${of}. Why does this answer matter, and what does each choice change? Explain; do not recommend one.`;
}
