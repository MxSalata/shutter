import type { SiteProfile, WhatIfFact } from '@/api/types';
import { KIND_LABELS, TIERS } from './profile';

/**
 * A suggested change to the site profile, as a case's What-if fact gives it: one field, the value it had when the facts
 * were computed and the value suggested, with why and what it reaches. Only the case and the fact's id travel to the
 * Site profile page (the `suggest` and `fact` query parameters); the page reads the fact again from
 * GET /cases/{id}/whatif and makes the change a pre-filled draft, which an approver reviews and saves through the
 * page's own save. Nothing is changed by opening it, and no wording comes from the address.
 */
export interface SuggestedChange {
  /** The case the suggestion came from, and its What-if fact. */
  caseId: string;
  fact: string;
  field: string;
  receiver?: string;
  from: string | boolean | null;
  to: string | boolean;
  why?: string;
  affects?: string[];
  /** The server's verdict on the change (CONTRACTS 14.1): no draft is offered when it is not valid or is stale. */
  valid?: boolean;
  problem?: string;
  stale?: boolean;
}

/** What the address carries: the case and the fact, nothing else. */
export interface SuggestionRef {
  caseId: string;
  fact: string;
}

export const SUGGEST_PARAM = 'suggest';
export const FACT_PARAM = 'fact';

export function suggestionFromFact(caseId: string, f: WhatIfFact): SuggestedChange {
  const c = f.suggested_change;
  return {
    caseId,
    fact: f.id,
    field: c.field,
    ...(c.receiver ? { receiver: c.receiver } : {}),
    from: c.from,
    to: c.to,
    why: c.why,
    affects: c.affects,
    valid: c.valid,
    ...(c.problem ? { problem: c.problem } : {}),
    stale: c.stale,
  };
}

/** The Site profile page's address for a case's What-if fact. */
export function suggestionHref(ref: SuggestionRef): string {
  return `/site-profile?${new URLSearchParams({ [SUGGEST_PARAM]: ref.caseId, [FACT_PARAM]: ref.fact }).toString()}`;
}

/** The case and fact in the address, or null when there are none or they are not ids. */
export function parseSuggestion(search: URLSearchParams): SuggestionRef | null {
  const caseId = search.get(SUGGEST_PARAM) ?? '';
  const fact = search.get(FACT_PARAM) ?? '';
  if (!/^[A-Za-z0-9_-]{1,64}$/.test(caseId) || !/^W\d{1,4}$/.test(fact)) return null;
  return { caseId, fact };
}

/** Where a field lives in the profile: a top-level setting, a tier's approval policy or a receiver's own field. */
type Place =
  | { kind: 'top'; key: 'authoritative_source' | 'unconditional_resend' | 'history_policy' | 'merges' }
  | { kind: 'policy'; tier: string; chain: 'single' | 'ordered' | 'interleaved' }
  | { kind: 'receiver'; key: string };

const TOP = ['authoritative_source', 'unconditional_resend', 'history_policy', 'merges'] as const;
/** The receivers' fields a suggestion may name; their endpoints, name and features are never suggested. */
const RECEIVER_KEYS = [
  'category',
  'history_policy',
  'cancels',
  'merges',
  'tier',
  'applies',
  'resend_timestamp',
];

function placeOf(field: string): Place | null {
  if ((TOP as readonly string[]).includes(field)) return { kind: 'top', key: field as (typeof TOP)[number] };
  const policy = /^policy\.(\d)\.(single|ordered|interleaved)$/.exec(field);
  if (policy && (TIERS as readonly string[]).includes(policy[1]))
    return { kind: 'policy', tier: policy[1], chain: policy[2] as 'single' | 'ordered' | 'interleaved' };
  const receiver = /^receivers\[\]\.(\w+)$/.exec(field);
  if (receiver && RECEIVER_KEYS.includes(receiver[1])) return { kind: 'receiver', key: receiver[1] };
  return null;
}

/** "", null and an absent value all mean not set. */
const norm = (v: unknown) => (v === undefined || v === null ? '' : v);
const same = (a: unknown, b: unknown) => String(norm(a)) === String(norm(b));

const CATEGORIES = ['current_state', 'history_of_record', 'orders_results'];

const category = (v: unknown) => (CATEGORIES.includes(String(v)) ? String(v) : 'current_state');
const policyOf = (v: unknown) => (v === 'correct' ? 'correct' : 'current');

/**
 * A field's value as the server reads it (Shutter.Store.SiteProfile ReceiverCategory and ReceiverHistoryPolicy): a
 * receiver with no category, or one it does not know, is current_state; a receiver's history policy is its own when it
 * has one, else correct for a history_of_record receiver and current for another category, else the site-wide one; a
 * profile with no history policy is current. The suggestion's `from` and `to` and the profile's value are all read this
 * way before they are compared, so an absent value matches the default it stands for.
 */
function effective(
  profile: SiteProfile,
  s: Pick<SuggestedChange, 'field' | 'receiver'>,
  v: unknown,
): unknown {
  if (s.field === 'receivers[].category') return category(v);
  if (s.field === 'history_policy') return policyOf(v);
  if (s.field === 'receivers[].history_policy') {
    if (v === 'current' || v === 'correct') return v;
    const r = profile.receivers.find((x) => x.name === s.receiver);
    if (r && r.category !== undefined && r.category !== null && r.category !== '')
      return category(r.category) === 'history_of_record' ? 'correct' : 'current';
    return policyOf(profile.history_policy);
  }
  return norm(v);
}

/** The field in a profile: its value as stored, and how to set it or put a stored value back. */
type Located = { get: () => unknown; set: (v: unknown) => void };

function locate(
  profile: SiteProfile,
  s: Pick<SuggestedChange, 'field' | 'receiver'>,
): Located | 'unsupported' | 'no_receiver' {
  const place = placeOf(s.field);
  if (!place) return 'unsupported';
  const write = (o: Record<string, unknown>, key: string, v: unknown) => {
    if (v === undefined) delete o[key];
    else o[key] = v;
  };
  if (place.kind === 'top') {
    const o = profile as unknown as Record<string, unknown>;
    return { get: () => o[place.key], set: (v) => write(o, place.key, v) };
  }
  if (place.kind === 'policy')
    return {
      get: () => profile.policy?.[place.tier]?.[place.chain],
      set: (v) => {
        profile.policy = profile.policy ?? {};
        const row = { ...(profile.policy[place.tier] ?? {}) } as Record<string, unknown>;
        write(row, place.chain, v === undefined ? undefined : String(v));
        profile.policy[place.tier] = row;
      },
    };
  const r = profile.receivers.find((x) => x.name === s.receiver);
  if (!r) return 'no_receiver';
  return {
    get: () => r[place.key],
    set: (v) => write(r, place.key, place.key === 'tier' && v !== undefined ? Number(v) : v),
  };
}

export type Applied =
  | { ok: true; profile: SiteProfile }
  | {
      ok: false;
      reason: 'unsupported' | 'no_receiver' | 'stale' | 'already' | 'no_fact' | 'unreadable' | 'invalid';
      current?: unknown;
    };

/**
 * The profile with the suggestion applied, on a copy. Refused when the page cannot place the field, when the receiver
 * is not in the profile, when the field no longer holds the suggestion's `from` (the profile changed since), or when it
 * already holds `to`; both compared as the server reads them.
 */
export function applySuggestion(profile: SiteProfile, s: SuggestedChange): Applied {
  // The server validated the change against a copy of the profile and checked its `from`: its verdict comes first
  if (s.valid === false) return { ok: false, reason: 'invalid' };
  if (s.stale === true) return { ok: false, reason: 'stale', current: undefined };
  const next = JSON.parse(JSON.stringify(profile)) as SiteProfile;
  const at = locate(next, s);
  if (typeof at === 'string') return { ok: false, reason: at };
  const current = at.get();
  const read = (v: unknown) => effective(next, s, v);
  const now = read(current);
  if (same(now, read(s.to))) return { ok: false, reason: 'already', current: now };
  if (!same(now, read(s.from))) return { ok: false, reason: 'stale', current: now };
  at.set(s.to);
  return { ok: true, profile: next };
}

/**
 * The draft with the suggested field put back as the stored profile has it, on a copy: every other edit in the draft
 * stays as it is.
 */
export function revertSuggestion(draft: SiteProfile, stored: SiteProfile, s: SuggestedChange): SiteProfile {
  const next = JSON.parse(JSON.stringify(draft)) as SiteProfile;
  const into = locate(next, s);
  const from = locate(stored, s);
  if (typeof into === 'string' || typeof from === 'string') return next;
  const v = from.get();
  into.set(v === undefined ? undefined : JSON.parse(JSON.stringify(v)));
  return next;
}

const FIELD_LABELS: Record<string, string> = {
  authoritative_source: 'Authoritative source',
  unconditional_resend: 'Unconditional resends',
  history_policy: 'History policy',
  merges: 'Merges',
  'receivers[].category': 'Category',
  'receivers[].history_policy': 'History policy',
  'receivers[].cancels': 'Accepts cancels',
  'receivers[].merges': 'Takes merges',
  'receivers[].tier': 'Tier',
  'receivers[].applies': 'Applies messages',
  'receivers[].resend_timestamp': 'A resend carries',
};

/** A field in words: "Authoritative source", "Approval of tier 2 single failures", "Category of Downstream Out". */
export function fieldLabel(field: string, receiver?: string): string {
  const policy = /^policy\.(\d)\.(\w+)$/.exec(field);
  if (policy)
    return `Approval of tier ${policy[1]} ${(KIND_LABELS as Record<string, string>)[policy[2]] ?? policy[2]}`;
  const label = FIELD_LABELS[field] ?? field;
  return receiver ? `${label} of ${receiver}` : label;
}

/** A value in words: not set, yes or no, or the value itself. */
export function valueLabel(field: string, v: unknown): string {
  if (v === undefined || v === null || v === '')
    return field === 'authoritative_source' ? 'none named' : 'not set';
  if (typeof v === 'boolean') return v ? 'yes' : 'no';
  return String(v);
}
