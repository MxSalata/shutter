import type { ChainKind, SiteProfile, SiteReceiver } from '@/api/types';

/**
 * The site profile's questionnaire, without React: labels, the diff the review and the history show, the port of
 * Shutter.Store.SiteProfile.Validate (the mock uses it too, so a profile the demo accepts is one the server accepts),
 * the PUT body and the mapping of the server's error path to a field.
 */

export const TIERS = ['1', '2', '3'] as const;
export const KINDS: ChainKind[] = ['single', 'ordered', 'interleaved'];

export const TIER_LABELS: Record<string, string> = {
  '1': '1, information',
  '2': '2, operations',
  '3': '3, clinical safety',
};

export const TIER_HINTS: Record<string, string> = {
  '1': 'Reporting feeds, a data warehouse',
  '2': 'Bed management, porters, the ward board',
  '3': 'Pharmacy, results, allergies',
};

export const KIND_LABELS: Record<ChainKind, string> = {
  single: 'single failures',
  ordered: 'ordered chains',
  interleaved: 'interleaved chains',
};

export const POLICY_LABELS: Record<string, string> = {
  automatic: 'Automatic: gated, rehearsed and verified, no person',
  approval: 'One approval for the case or incident',
  per_chain: 'One approval per chain',
  board: 'The board decides',
};

/** Short forms for the summary and the change lists. */
export const POLICY_SHORT: Record<string, string> = {
  automatic: 'automatic',
  approval: 'one approval',
  per_chain: 'an approval per chain',
  board: 'the board',
};

export const APPLIES_LABELS: Record<string, string> = {
  arrival_order: 'in arrival order',
  event_time: 'by event time',
};

export const RESEND_LABELS: Record<string, string> = {
  original: 'its original MSH-7',
  fresh: 'a fresh MSH-7',
};

export const HISTORY_LABELS: Record<string, string> = {
  current: 'keep what is current',
  correct: 'correct history',
};

export const SEED_SOURCE = 'knowledge/site/profile.json';

/** "Saved in Shutter", "Seeded from knowledge/site/profile.json" or the built-in defaults. */
export function describeSource(source: string | undefined): string {
  if (source === 'api') return 'Saved in Shutter';
  if (!source || source === 'defaults') return 'The built-in defaults, never stored';
  const tail = source.split('/').slice(-3).join('/');
  return `Seeded from ${tail.endsWith(SEED_SOURCE) ? SEED_SOURCE : tail}`;
}

/** The shipped answers are in force until someone saves the profile in Shutter. */
export const isShipped = (source: string | undefined) => source !== 'api';

export function newReceiver(): SiteReceiver {
  return {
    name: '',
    system: '',
    tier: 2,
    applies: 'arrival_order',
    resend_timestamp: 'original',
    cancels: false,
  };
}

/** A number as ObjectScript writes it: 0.5 is ".5" and -0.5 is "-.5". */
const canonical = (n: number) => String(n).replace(/^(-?)0\./, '$1.');

/**
 * ObjectScript's (x '= +x) on what %Get hands back: a JSON boolean arrives as 1 or 0, a number passes, and a string
 * passes only when it is the number written canonically ("2", not "2.0", " 2" or "0.5").
 */
function numeric(x: unknown): boolean {
  if (typeof x === 'boolean') return true;
  if (typeof x === 'number') return Number.isFinite(x);
  if (typeof x !== 'string' || x === '') return false;
  const n = Number(x);
  return Number.isFinite(n) && canonical(n) === x;
}

const asNumber = (x: unknown) => (typeof x === 'boolean' ? (x ? 1 : 0) : Number(x));

/** $ISOBJECT: a JSON object or a JSON array. */
const isObject = (x: unknown): x is Record<string, unknown> => typeof x === 'object' && x !== null;

/** %GetIterator over an object or an array: its keys, or its indexes. */
const members = (x: object): [string, unknown][] =>
  Array.isArray(x) ? x.map((v, i): [string, unknown] => [String(i), v]) : Object.entries(x);

/** The port of SiteProfile.Validate: "" when the profile is valid, else the server's message for the first problem. */
export function validateProfile(p: unknown): string {
  if (!isObject(p)) return 'the profile must be a JSON object';
  const top = [
    'version',
    'receivers',
    'history_policy',
    'authoritative_source',
    'unconditional_resend',
    'policy',
    'approvers',
    'incident',
  ];
  for (const key of Object.keys(p)) if (!top.includes(key)) return `${key}: unknown field`;
  if ('version' in p && (!numeric(p.version) || asNumber(p.version) < 0))
    return 'version: must be a whole number';
  const rcv = p.receivers;
  if (!isObject(rcv) || members(rcv).length === 0) return 'receivers: must be a non-empty array';
  for (const [i, r] of members(rcv)) {
    const at = `receivers[${i}]`;
    if (!isObject(r)) return `${at}: must be an object`;
    if (typeof r.name !== 'string' || r.name === '') return `${at}.name: required`;
    if (!numeric(r.tier) || asNumber(r.tier) < 1 || asNumber(r.tier) > 3)
      return `${at}.tier: must be 1, 2 or 3`;
    if ('cancels' in r && typeof r.cancels !== 'boolean') return `${at}.cancels: must be true or false`;
    if ('api' in r) {
      if (!isObject(r.api)) return `${at}.api: must be an object`;
      for (const [k, v] of members(r.api)) {
        if (!['base', 'state', 'receipt', 'capabilities', 'operations'].includes(k))
          return `${at}.api.${k}: unknown path`;
        if (typeof v !== 'string') return `${at}.api.${k}: must be a string`;
      }
    }
    if ('features' in r) {
      if (!isObject(r.features)) return `${at}.features: must be an object`;
      for (const [k, v] of members(r.features)) {
        if (!['conditional_writes', 'receipts', 'history', 'dry_run'].includes(k))
          return `${at}.features.${k}: unknown feature`;
        if (typeof v !== 'boolean') return `${at}.features.${k}: must be true or false`;
      }
    }
  }
  if ('unconditional_resend' in p && !['forbidden', 'allowed'].includes(p.unconditional_resend as string))
    return 'unconditional_resend: must be forbidden or allowed';
  if ('history_policy' in p && typeof p.history_policy !== 'string')
    return 'history_policy: must be a string';
  const pol = p.policy;
  if (!isObject(pol)) return 'policy: must be an object with the tiers 1, 2 and 3';
  for (const [tier, row] of members(pol)) {
    if (!(TIERS as readonly string[]).includes(tier)) return `policy.${tier}: the tiers are 1, 2 and 3`;
    if (!isObject(row)) return `policy.${tier}: must be an object with single, ordered and interleaved`;
    for (const [kind, value] of members(row)) {
      if (!(KINDS as string[]).includes(kind))
        return `policy.${tier}.${kind}: the chain kinds are single, ordered and interleaved`;
      if (!['automatic', 'approval', 'per_chain', 'board'].includes(value as string))
        return `policy.${tier}.${kind}: must be automatic, approval, per_chain or board`;
    }
  }
  if ('approvers' in p && !isObject(p.approvers)) return 'approvers: must be an object';
  if ('incident' in p) {
    if (!isObject(p.incident)) return 'incident: must be an object';
    for (const [k, n] of members(p.incident)) {
      if (!['threshold', 'window_minutes', 'quiet_seconds'].includes(k))
        return `incident.${k}: unknown setting`;
      const low = k === 'quiet_seconds' ? 0 : 1;
      if (!numeric(n) || asNumber(n) < low)
        return `incident.${k}: must be a whole number${k === 'quiet_seconds' ? '' : ' of 1 or more'}`;
    }
  }
  return '';
}

/**
 * What the page checks beyond the server: a receiver's name must be unique (the core takes the first match, so a
 * second one would be silently shadowed) and the incident numbers whole.
 */
export function checkDraft(p: SiteProfile): string {
  const seen = new Set<string>();
  for (const [i, r] of p.receivers.entries()) {
    if (r.name && seen.has(r.name)) return `receivers[${i}].name: another receiver already has this name`;
    seen.add(r.name);
  }
  for (const [k, n] of Object.entries(p.incident ?? {}))
    if (typeof n === 'number' && !Number.isInteger(n)) return `incident.${k}: must be a whole number`;
  return validateProfile(p);
}

/** The body of PUT /site-profile: the whole profile as read and edited, without its inner version, plus expectedVersion. */
export function toPutBody(draft: SiteProfile, version: number): SiteProfile & { expectedVersion: number } {
  const { version: _inner, ...rest } = draft;
  return { ...rest, expectedVersion: version };
}

const PREFIX = /^.*?6\.4\):\s*/;

/** The field the server's 400 names: "receivers[0].tier: must be 1, 2 or 3" gives that path and message. */
export function problemField(text: string): { path: string; message: string } | null {
  const body = text.replace(PREFIX, '');
  const m = /^([A-Za-z_][\w.[\]]*):\s*(.+)$/.exec(body);
  return m ? { path: m[1], message: m[2] } : null;
}

/** The DOM id of the control for a path, or "" when the page has no control for it (api, features). */
export function fieldId(path: string): string {
  let m = /^receivers\[(\d+)\]\.(name|system|tier|applies|resend_timestamp|cancels)$/.exec(path);
  if (m) return `site-receivers-${m[1]}-${m[2]}`;
  m = /^policy\.([123])\.(single|ordered|interleaved)$/.exec(path);
  if (m) return `site-policy-${m[1]}-${m[2]}`;
  m = /^incident\.(threshold|window_minutes|quiet_seconds)$/.exec(path);
  if (m) return `site-incident-${m[1]}`;
  m = /^approvers\.(role|escalation)$/.exec(path);
  if (m) return `site-approvers-${m[1]}`;
  if (path === 'history_policy') return 'site-history-policy';
  return '';
}

/** "Receiver 1, name: required" for the form's alert. */
export function describePath(path: string): string {
  let m = /^receivers\[(\d+)\]\.?(.*)$/.exec(path);
  if (m) return `Receiver ${Number(m[1]) + 1}${m[2] ? `, ${m[2].replace(/_/g, ' ')}` : ''}`;
  m = /^policy\.(\w+)\.(\w+)$/.exec(path);
  if (m) return `Tier ${m[1]}, ${m[2]} chains`;
  m = /^incident\.(\w+)$/.exec(path);
  if (m) return `Incidents, ${m[1].replace(/_/g, ' ')}`;
  return path.replace(/_/g, ' ');
}

const show = (labels: Record<string, string>, v: unknown) =>
  v === undefined || v === null || v === '' ? 'not set' : (labels[String(v)] ?? String(v));

/** A change between two profiles, in words. */
export interface Change {
  path: string;
  text: string;
  /** A change that takes a person out of a release: a policy moved to automatic, or a tier into an automatic row. */
  lessOversight?: boolean;
  /** Tier 3 moved to automatic, which the review asks the approver to acknowledge (CONTRACTS 6.4). */
  tier3Automatic?: boolean;
}

const same = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b);

function receiverChanges(a: SiteReceiver, b: SiteReceiver, p: SiteProfile): Change[] {
  const out: Change[] = [];
  const name = b.name || a.name || 'a receiver';
  const fields: [keyof SiteReceiver, string, Record<string, string>][] = [
    ['system', 'what it does', {}],
    ['applies', 'applies messages', APPLIES_LABELS],
    ['resend_timestamp', 'resends need', RESEND_LABELS],
  ];
  for (const [key, label, labels] of fields)
    if (!same(a[key], b[key]))
      out.push({
        path: String(key),
        text: `${name}, ${label}: from ${show(labels, a[key])} to ${show(labels, b[key])}`,
      });
  if (!same(a.tier, b.tier)) {
    const toRow = p.policy?.[String(b.tier)] ?? {};
    const fromRow = p.policy?.[String(a.tier)] ?? {};
    const lessOversight = KINDS.some((k) => toRow[k] === 'automatic' && fromRow[k] !== 'automatic');
    out.push({
      path: 'tier',
      text: `${name}, tier: from ${show(TIER_LABELS, a.tier)} to ${show(TIER_LABELS, b.tier)}`,
      lessOversight,
      tier3Automatic: String(b.tier) === '3' && KINDS.some((k) => toRow[k] === 'automatic'),
    });
  }
  if (!same(a.cancels, b.cancels))
    out.push({ path: 'cancels', text: `${name}, accepts cancels: ${b.cancels ? 'yes' : 'no'}` });
  if (!same(a.api, b.api)) out.push({ path: 'api', text: `${name}, its endpoints changed` });
  if (!same(a.features, b.features))
    out.push({ path: 'features', text: `${name}, its declared features changed` });
  return out;
}

/**
 * The changes from a to b in words, receivers keyed by name (a rename reads as one removed and one added). The inner
 * version is ignored: the store numbers versions itself.
 */
export function diffProfiles(a: SiteProfile | undefined, b: SiteProfile): Change[] {
  const out: Change[] = [];
  const before = a ?? ({ receivers: [], policy: {} } as SiteProfile);
  const byName = new Map(before.receivers.map((r) => [r.name, r]));
  const names = new Set(b.receivers.map((r) => r.name));
  for (const r of b.receivers) {
    const old = byName.get(r.name);
    if (!old) out.push({ path: 'receivers', text: `Receiver added: ${r.name || 'unnamed'}` });
    else out.push(...receiverChanges(old, r, b));
  }
  for (const r of before.receivers)
    if (!names.has(r.name)) out.push({ path: 'receivers', text: `Receiver removed: ${r.name || 'unnamed'}` });
  if (!same(before.history_policy, b.history_policy))
    out.push({
      path: 'history_policy',
      text: `History policy: from ${show(HISTORY_LABELS, before.history_policy)} to ${show(HISTORY_LABELS, b.history_policy)}`,
    });
  for (const tier of TIERS)
    for (const kind of KINDS) {
      const from = before.policy?.[tier]?.[kind];
      const to = b.policy?.[tier]?.[kind];
      if (from !== to)
        out.push({
          path: `policy.${tier}.${kind}`,
          text: `Tier ${tier} ${KIND_LABELS[kind]}: from ${show(POLICY_SHORT, from)} to ${show(POLICY_SHORT, to)}`,
          lessOversight: to === 'automatic',
          tier3Automatic: tier === '3' && to === 'automatic',
        });
    }
  if (!same(before.approvers?.role, b.approvers?.role))
    out.push({ path: 'approvers.role', text: `Who approves: ${b.approvers?.role || 'not set'}` });
  if (!same(before.approvers?.escalation, b.approvers?.escalation))
    out.push({
      path: 'approvers.escalation',
      text: `When nobody is available: ${b.approvers?.escalation || 'not set'}`,
    });
  const inc: [keyof NonNullable<SiteProfile['incident']>, string][] = [
    ['threshold', 'failures'],
    ['window_minutes', 'within (minutes)'],
    ['quiet_seconds', 'quiet period (seconds)'],
  ];
  for (const [k, label] of inc)
    if (!same(before.incident?.[k], b.incident?.[k]))
      out.push({
        path: `incident.${k}`,
        text: `Incidents, ${label}: from ${show({}, before.incident?.[k])} to ${show({}, b.incident?.[k])}`,
      });
  if (!same(before.unconditional_resend, b.unconditional_resend))
    out.push({
      path: 'unconditional_resend',
      text: `Unconditional resends: from ${show({}, before.unconditional_resend)} to ${show({}, b.unconditional_resend)}`,
    });
  if (!same(before.authoritative_source, b.authoritative_source))
    out.push({
      path: 'authoritative_source',
      text: `Authoritative source: from ${show({}, before.authoritative_source)} to ${show({}, b.authoritative_source)}`,
    });
  return out;
}

/** The receivers at a tier, for the summary. */
export const receiversAt = (p: SiteProfile, tier: string) =>
  p.receivers.filter((r) => String(r.tier) === tier).map((r) => r.name || 'unnamed');

/** The incident rule in one sentence. */
export function describeIncident(p: SiteProfile): string {
  const i = p.incident ?? {};
  const n = (x: unknown, d: number) => (x === undefined || x === null || x === '' ? d : x);
  return `An incident opens at ${n(i.threshold, 5)} delivery failures or refusals to one receiver within ${n(i.window_minutes, 10)} minutes, and takes no more cases after ${n(i.quiet_seconds, 60)} seconds with no new failure. Uncertain outcomes keep their own cases.`;
}
