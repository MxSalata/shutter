import type { SiteProfile, WhatIfFact } from '@/api/types';
import { KIND_LABELS, TIERS } from './profile';

/**
 * A suggested change to the site profile, as a case's What-if card offers it: one field, the value it had when the
 * facts were computed and the value suggested. It travels to the Site profile page in the `suggest` query parameter
 * and becomes a pre-filled draft there, which an approver reviews and saves through the page's own save; nothing is
 * changed by opening it.
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
}

export const SUGGEST_PARAM = 'suggest';

export function suggestionFromFact(caseId: string, f: WhatIfFact): SuggestedChange {
  return {
    caseId,
    fact: f.id,
    field: f.field,
    ...(f.receiver ? { receiver: f.receiver } : {}),
    from: f.from,
    to: f.to,
    why: f.would,
    affects: f.affects,
  };
}

/** The Site profile page's address with the suggestion in its query. */
export function suggestionHref(s: SuggestedChange): string {
  return `/site-profile?${new URLSearchParams({ [SUGGEST_PARAM]: JSON.stringify(s) }).toString()}`;
}

const isValue = (v: unknown): v is string | boolean => typeof v === 'string' || typeof v === 'boolean';

/** The suggestion in a query parameter, or null when there is none or it is not one. */
export function parseSuggestion(raw: string | null): SuggestedChange | null {
  if (!raw) return null;
  try {
    const v = JSON.parse(raw) as Record<string, unknown>;
    if (!v || typeof v !== 'object') return null;
    if (typeof v.field !== 'string' || !v.field || !isValue(v.to)) return null;
    if (!(v.from === null || isValue(v.from))) return null;
    return {
      caseId: typeof v.caseId === 'string' ? v.caseId : '',
      fact: typeof v.fact === 'string' ? v.fact : '',
      field: v.field,
      ...(typeof v.receiver === 'string' && v.receiver ? { receiver: v.receiver } : {}),
      from: v.from,
      to: v.to,
      ...(typeof v.why === 'string' ? { why: v.why } : {}),
      ...(Array.isArray(v.affects) ? { affects: v.affects.filter((a) => typeof a === 'string') } : {}),
    };
  } catch {
    return null;
  }
}

/** Where a field lives in the profile: a top-level setting, a tier's approval policy or a receiver's own field. */
type Place =
  | { kind: 'top'; key: 'authoritative_source' | 'unconditional_resend' | 'history_policy' | 'merges' }
  | { kind: 'policy'; tier: string; chain: 'single' | 'ordered' | 'interleaved' }
  | { kind: 'receiver'; key: string };

const TOP = ['authoritative_source', 'unconditional_resend', 'history_policy', 'merges'] as const;
/** The receivers' fields a suggestion may name; their endpoints, name and features are never suggested. */
const RECEIVER_KEYS = ['category', 'cancels', 'merges', 'tier', 'applies', 'resend_timestamp'];

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

export type Applied =
  | { ok: true; profile: SiteProfile }
  | { ok: false; reason: 'unsupported' | 'no_receiver' | 'stale' | 'already'; current?: unknown };

/**
 * The profile with the suggestion applied, on a copy. Refused when the page cannot place the field, when the receiver
 * is not in the profile, when the field no longer holds the suggestion's `from` (the profile changed since), or when it
 * already holds `to`.
 */
export function applySuggestion(profile: SiteProfile, s: SuggestedChange): Applied {
  const place = placeOf(s.field);
  if (!place) return { ok: false, reason: 'unsupported' };
  const next = JSON.parse(JSON.stringify(profile)) as SiteProfile;
  let current: unknown;
  let set: (v: unknown) => void;
  if (place.kind === 'top') {
    current = next[place.key];
    set = (v) => {
      (next as unknown as Record<string, unknown>)[place.key] = v;
    };
  } else if (place.kind === 'policy') {
    current = next.policy?.[place.tier]?.[place.chain];
    set = (v) => {
      next.policy = next.policy ?? {};
      next.policy[place.tier] = { ...(next.policy[place.tier] ?? {}), [place.chain]: String(v) };
    };
  } else {
    const r = next.receivers.find((x) => x.name === s.receiver);
    if (!r) return { ok: false, reason: 'no_receiver' };
    current = r[place.key];
    set = (v) => {
      r[place.key] = place.key === 'tier' ? Number(v) : v;
    };
  }
  if (same(current, s.to)) return { ok: false, reason: 'already', current };
  if (!same(current, s.from)) return { ok: false, reason: 'stale', current };
  set(s.to);
  return { ok: true, profile: next };
}

const FIELD_LABELS: Record<string, string> = {
  authoritative_source: 'Authoritative source',
  unconditional_resend: 'Unconditional resends',
  history_policy: 'History policy',
  merges: 'Merges',
  'receivers[].category': 'Category',
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
