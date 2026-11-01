import type { ChainKind, SiteProfile, SiteReceiver, SiteTeam } from '@/api/types';
import { CATEGORY_TEXT, categoryOf, historyPolicyOf } from '@/lib/categories';

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

/** A team as the form adds it: every required field empty, for the person to fill. */
export function newTeam(): SiteTeam {
  return { id: '', name: '', mailbox: '', cc: [], receivers: [], sources: [] };
}

/** "a@x.nhs.uk, b@x.nhs.uk" as a list, without the empty entries a trailing comma leaves. */
export const parseList = (text: string) =>
  text
    .split(/[,;\s]+/)
    .map((s) => s.trim())
    .filter(Boolean);

/** The feed's zone choices. A fixed offset is the third, with its own value. */
export const ZONE_LABELS: Record<string, string> = {
  'Europe/London': 'UK time (Europe/London)',
  UTC: 'UTC',
};

export function newReceiver(): SiteReceiver {
  return {
    name: '',
    system: '',
    category: 'current_state',
    tier: 2,
    applies: 'arrival_order',
    resend_timestamp: 'original',
    cancels: false,
    merges: false,
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

const ZONES = ['UTC', 'Europe/London'];
const FIXED_OFFSET = /^[+-](0[0-9]|1[0-4]):[0-5][0-9]$/;

// The ports of Shutter.Util.Mail (CONTRACTS 10): the same address passes or fails here as at the server.
// $ZSTRIP's C class: $CHAR(0) to $CHAR(31) and $CHAR(127) to $CHAR(159).
// eslint-disable-next-line no-control-regex
const CONTROL = /[\u0000-\u001f\u007f-\u009f]/;
const DOMAIN = /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$/;

/** The port of ControlProblem: "" when the text has no line break or other control character. */
export function controlProblem(text: string): string {
  return CONTROL.test(text) ? 'must not contain line breaks or control characters' : '';
}

/** The port of DomainProblem: "" when the text is a domain name, case ignored and whitespace not stripped. */
function domainProblem(domain: string): string {
  const d = domain.toLowerCase();
  return d !== '' && d.length <= 253 && DOMAIN.test(d)
    ? ''
    : 'must be a domain name such as example.nhs.uk (letters, digits, hyphens and dots)';
}

/** The port of ShapeProblem: "" when the text is one bare address, local@domain. */
function shapeProblem(address: string): string {
  const control = controlProblem(address);
  if (control) return control;
  const parts = address.split('@');
  if (parts.length !== 2) return 'must be one address with one @';
  if (/\s/.test(address) || /[<>,;"()[\]\\]/.test(address))
    return 'must be a bare address, local@domain, with no display name, brackets or spaces';
  if (parts[0] === '' || parts[1] === '') return 'must be an address';
  if (domainProblem(parts[1])) return 'the domain is not a valid domain name';
  return '';
}

/** The port of Domains: each allowed domain trimmed and lowercased, empty entries left out. */
function allowedDomains(domains: unknown[]): string[] {
  return domains
    .filter((d): d is string => typeof d === 'string')
    .map((d) => d.trim().toLowerCase())
    .filter(Boolean);
}

/** The port of AddressProblem: "" when fine, else why the address is refused. No allowed domains allow no address. */
function mailboxProblem(mailbox: string, domains: string[]): string {
  const shape = shapeProblem(mailbox);
  if (shape) return shape;
  if (domains.length === 0)
    return 'no allowed mail domains are set in the site profile (mail.allowed_domains)';
  const domain = mailbox.split('@')[1].toLowerCase();
  return domains.some((d) => domain === d || domain.endsWith(`.${d}`)) ? '' : 'not in the allowed domains';
}

/**
 * The port of AddressesProblem: the first address of a comma-separated list that is not one bare address inside the
 * allowed domains, as "<address>: <why>"; "" when every address is fine. A control character anywhere refuses the list.
 */
export function addressesProblem(list: string, domains: string[] = []): string {
  const control = controlProblem(list);
  if (control) return control;
  const allowed = allowedDomains(domains);
  for (const a of list.split(',').map((x) => x.trim())) {
    if (!a) continue;
    const problem = mailboxProblem(a, allowed);
    if (problem) return `${a}: ${problem}`;
  }
  return '';
}

/** The port of SiteProfile.Validate: "" when the profile is valid, else the server's message for the first problem. */
export function validateProfile(p: unknown): string {
  if (!isObject(p)) return 'the profile must be a JSON object';
  const top = [
    'version',
    'receivers',
    'history_policy',
    'authoritative_source',
    'unconditional_resend',
    'merges',
    'policy',
    'approvers',
    'incident',
    'model_content',
    'teams',
    'mail',
    'feed',
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
    // The receiver's category (v1.23) and its own history policy, which the category derives when absent.
    if (
      'category' in r &&
      !['current_state', 'history_of_record', 'orders_results'].includes(r.category as string)
    )
      return `${at}.category: must be current_state, history_of_record or orders_results`;
    if ('history_policy' in r && !['current', 'correct'].includes(r.history_policy as string))
      return `${at}.history_policy: must be current or correct`;
    // A demo receiver's namespace (v1.25): where the scenario runner resets it and sets its faults.
    if ('demo' in r) {
      if (!isObject(r.demo) || Array.isArray(r.demo)) return `${at}.demo: must be an object`;
      if ('namespace' in r.demo && typeof r.demo.namespace !== 'string')
        return `${at}.demo.namespace: must be a string`;
    }
    if ('cancels' in r && typeof r.cancels !== 'boolean') return `${at}.cancels: must be true or false`;
    if ('merges' in r && typeof r.merges !== 'boolean') return `${at}.merges: must be true or false`;
    if ('api' in r) {
      if (!isObject(r.api)) return `${at}.api: must be an object`;
      for (const [k, v] of members(r.api)) {
        if (!['base', 'state', 'receipt', 'capabilities', 'operations'].includes(k))
          return `${at}.api.${k}: unknown path`;
        if (typeof v !== 'string') return `${at}.api.${k}: must be a string`;
      }
      // Without a state path nothing can be read, and without an operations path nothing can be sent.
      if (!r.api.state) return `${at}.api.state: required when api is given`;
      if (!r.api.operations) return `${at}.api.operations: required when api is given`;
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
  if ('merges' in p && !['forbidden', 'allowed'].includes(p.merges as string))
    return 'merges: must be forbidden or allowed';
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
  // Who approves what; close_needs_approver is the two-person rule for closing a case by hand, off unless the site says
  // so. Every key is named, so a misspelt switch cannot pass as off.
  if ('approvers' in p) {
    if (!isObject(p.approvers) || Array.isArray(p.approvers)) return 'approvers: must be an object';
    for (const [k, v] of members(p.approvers)) {
      if (!['role', 'escalation', 'close_needs_approver'].includes(k))
        return `approvers.${k}: unknown setting`;
      if (k === 'close_needs_approver' && typeof v !== 'boolean')
        return 'approvers.close_needs_approver: must be true or false';
      if (k !== 'close_needs_approver' && typeof v !== 'string') return `approvers.${k}: must be a string`;
    }
  }
  // The feed: the time zone of timestamps that carry no offset, and whether a message whose schema is not loaded is held.
  if ('feed' in p) {
    if (!isObject(p.feed)) return 'feed: must be an object';
    for (const [k, v] of members(p.feed)) {
      if (k === 'prevent_failures') {
        if (typeof v !== 'boolean') return 'feed.prevent_failures: must be true or false';
        continue;
      }
      if (k !== 'time_zone') return `feed.${k}: unknown setting`;
      if (typeof v !== 'string' || !(ZONES.includes(v) || FIXED_OFFSET.test(v)))
        return 'feed.time_zone: must be UTC, Europe/London or a fixed offset such as +01:00 (up to 14:00)';
    }
  }
  // What may leave IRIS for a model: free text off unless the site says so.
  if ('model_content' in p) {
    if (!isObject(p.model_content)) return 'model_content: must be an object';
    for (const [k, v] of members(p.model_content)) {
      if (k !== 'free_text') return `model_content.${k}: unknown setting`;
      if (typeof v !== 'boolean') return `model_content.${k}: must be true or false`;
    }
  }
  // The teams an escalation can go to, and the mail rules: the sender and every mailbox are bare addresses, and a
  // mailbox needs a domain in mail.allowed_domains, so a team while the list is empty or absent is refused.
  let domains: string[] = [];
  if ('mail' in p) {
    if (!isObject(p.mail)) return 'mail: must be an object';
    for (const [k, v] of members(p.mail)) {
      if (!['from', 'allowed_domains'].includes(k)) return `mail.${k}: unknown setting`;
      if (k === 'from') {
        if (typeof v !== 'string') return 'mail.from: must be a string';
        const problem = v === '' ? '' : shapeProblem(v);
        if (problem) return `mail.from: ${problem}`;
      }
      if (k === 'allowed_domains') {
        if (!Array.isArray(v)) return 'mail.allowed_domains: must be an array of domains';
        for (const [j, d] of members(v)) {
          if (typeof d !== 'string' || d === '') return `mail.allowed_domains[${j}]: must be a domain`;
          const problem = domainProblem(d);
          if (problem) return `mail.allowed_domains[${j}]: ${problem}`;
        }
        domains = allowedDomains(v);
      }
    }
  }
  if ('teams' in p) {
    if (!Array.isArray(p.teams)) return 'teams: must be an array';
    const ids: unknown[] = [];
    for (const [i, t] of members(p.teams)) {
      const at = `teams[${i}]`;
      if (!isObject(t)) return `${at}: must be an object`;
      for (const k of Object.keys(t))
        if (!['id', 'name', 'mailbox', 'cc', 'receivers', 'sources'].includes(k))
          return `${at}.${k}: unknown field`;
      for (const f of ['id', 'name', 'mailbox'])
        if (typeof t[f] !== 'string' || t[f] === '') return `${at}.${f}: required`;
      if (ids.includes(t.id)) return `${at}.id: must be unique`;
      ids.push(t.id);
      const problem = mailboxProblem(t.mailbox as string, domains);
      if (problem) return `${at}.mailbox: ${problem}`;
      if ('cc' in t) {
        if (!Array.isArray(t.cc)) return `${at}.cc: must be an array of mailboxes`;
        for (const [j, m] of members(t.cc)) {
          if (typeof m !== 'string') return `${at}.cc[${j}]: must be a mailbox`;
          const ccProblem = mailboxProblem(m, domains);
          if (ccProblem) return `${at}.cc[${j}]: ${ccProblem}`;
        }
      }
      if ('receivers' in t) {
        if (!Array.isArray(t.receivers)) return `${at}.receivers: must be an array of receiver names`;
        for (const [j, m] of members(t.receivers))
          if (typeof m !== 'string' || m === '') return `${at}.receivers[${j}]: must be a receiver name`;
      }
      // The sending applications (MSH-3) whose merges the team decides, such as PAS
      if ('sources' in t) {
        if (!Array.isArray(t.sources)) return `${at}.sources: must be an array of sending applications`;
        for (const [j, m] of members(t.sources))
          if (typeof m !== 'string' || m === '')
            return `${at}.sources[${j}]: must be a sending application (MSH-3)`;
      }
    }
  }
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
  let m =
    /^receivers\[(\d+)\]\.(name|system|category|history_policy|tier|applies|resend_timestamp|cancels|merges)$/.exec(
      path,
    );
  if (m) return `site-receivers-${m[1]}-${m[2]}`;
  m = /^policy\.([123])\.(single|ordered|interleaved)$/.exec(path);
  if (m) return `site-policy-${m[1]}-${m[2]}`;
  m = /^incident\.(threshold|window_minutes|quiet_seconds)$/.exec(path);
  if (m) return `site-incident-${m[1]}`;
  m = /^approvers\.(role|escalation|close_needs_approver)$/.exec(path);
  if (m) return `site-approvers-${m[1]}`;
  if (path === 'history_policy') return 'site-history-policy';
  m = /^teams\[(\d+)\]\.(id|name|mailbox|cc|receivers|sources)(\[\d+\])?$/.exec(path);
  if (m) return `site-teams-${m[1]}-${m[2]}`;
  m = /^mail\.(from|allowed_domains)(\[\d+\])?$/.exec(path);
  if (m) return `site-mail-${m[1]}`;
  if (path === 'merges') return 'site-merges';
  if (path === 'feed.time_zone') return 'site-feed-time_zone';
  if (path === 'feed.prevent_failures') return 'site-feed-prevent_failures';
  if (path === 'model_content.free_text') return 'site-model_content-free_text';
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
  m = /^teams\[(\d+)\]\.?([a-z_]*)(?:\[(\d+)\])?$/.exec(path);
  if (m)
    return `Team ${Number(m[1]) + 1}${m[2] ? `, ${m[2] === 'cc' ? 'copies' : m[2]}` : ''}${m[3] ? ` ${Number(m[3]) + 1}` : ''}`;
  m = /^mail\.(\w+)(?:\[(\d+)\])?$/.exec(path);
  if (m) return `Mail, ${m[1].replace(/_/g, ' ')}${m[2] ? ` ${Number(m[2]) + 1}` : ''}`;
  if (path === 'feed.time_zone') return 'Feed, time zone';
  if (path === 'feed.prevent_failures') return 'Feed, prevent failures';
  if (path === 'model_content.free_text') return 'Model, note text';
  if (path === 'approvers.close_needs_approver') return 'Approvers, closing a case by hand';
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
    ['category', 'category', {}],
    ['applies', 'applies messages', APPLIES_LABELS],
    ['resend_timestamp', 'resends need', RESEND_LABELS],
  ];
  for (const [key, label, labels] of fields)
    if (!same(a[key], b[key]))
      out.push({
        path: String(key),
        text: `${name}, ${label}: from ${show(labels, a[key])} to ${show(labels, b[key])}`,
      });
  if (categoryOf(a) !== categoryOf(b))
    out.push({
      path: 'category',
      text: `${name}, category: from ${CATEGORY_TEXT[categoryOf(a)].label.toLowerCase()} to ${CATEGORY_TEXT[categoryOf(b)].label.toLowerCase()}`,
    });
  if (historyPolicyOf(a, p) !== historyPolicyOf(b, p) || !same(a.history_policy, b.history_policy))
    out.push({
      path: 'history_policy',
      text: `${name}, an overtaken failure: ${historyPolicyOf(b, p) === 'correct' ? 'the history is corrected by hand' : 'kept as current, closed with no write'}${b.history_policy ? ' (set on the receiver, not from its category)' : ' (from its category)'}`,
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
  if (!same(a.merges ?? false, b.merges ?? false))
    out.push({
      path: 'merges',
      text: `${name}, takes merges: ${b.merges ? 'yes' : 'no'}`,
      lessOversight: b.merges === true,
    });
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
      text: `Site-wide history policy, read only for a receiver with no category: from ${show(HISTORY_LABELS, before.history_policy)} to ${show(HISTORY_LABELS, b.history_policy)}`,
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
  if (closeNeedsApprover(before) !== closeNeedsApprover(b))
    out.push({
      path: 'approvers.close_needs_approver',
      text: closeNeedsApprover(b)
        ? 'Closing a case by hand: only an approver, from now on'
        : 'Closing a case by hand: an operator too, from now on',
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
  out.push(...teamChanges(before, b));
  const domains = (p: SiteProfile) => (p.mail?.allowed_domains ?? []).join(', ');
  if (domains(before) !== domains(b))
    out.push({ path: 'mail.allowed_domains', text: `Allowed mail domains: ${domains(b) || 'any'}` });
  if (!same(before.mail?.from ?? '', b.mail?.from ?? ''))
    out.push({
      path: 'mail.from',
      text: `Emails sent from: ${b.mail?.from || "the mail operation's own setting"}`,
    });
  if (!same(before.feed?.time_zone, b.feed?.time_zone))
    out.push({
      path: 'feed.time_zone',
      text: `Feed time zone: from ${before.feed?.time_zone || 'not answered (read as UTC)'} to ${b.feed?.time_zone || 'not answered (read as UTC)'}. Every operation key read from now on uses it`,
    });
  if ((before.feed?.prevent_failures === true) !== (b.feed?.prevent_failures === true))
    out.push({
      path: 'feed.prevent_failures',
      text:
        b.feed?.prevent_failures === true
          ? "Prevent failures: from now on, a message whose HL7 schema isn't loaded here is held as a case, and nothing is sent until the schema is imported"
          : "Prevent failures off: a message whose HL7 schema isn't loaded here is delivered as before",
    });
  if ((before.model_content?.free_text === true) !== (b.model_content?.free_text === true))
    out.push({
      path: 'model_content.free_text',
      text:
        b.model_content?.free_text === true
          ? 'Note text: sent to the model from now on'
          : 'Note text: no longer sent to the model; it sees a flag instead',
    });
  if ((before.merges ?? 'forbidden') !== (b.merges ?? 'forbidden'))
    out.push({
      path: 'merges',
      text:
        b.merges === 'allowed'
          ? 'Merges may be sent to receivers that take them'
          : 'Merges are never sent: each goes to the PAS team',
      lessOversight: b.merges === 'allowed',
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

/**
 * A team in words, by its place in the list as the server routes (EscalationDraft.Team): a merge goes to the first team
 * whose sources name its sending application; any case to the first team whose receivers name its receiver, else to
 * the first team; a later team that names neither gets a case only when a person picks it.
 */
function teamText(t: SiteTeam, first: boolean) {
  const parts = [
    ...(t.receivers?.length ? [t.receivers.join(', ')] : []),
    ...(first ? ['any receiver no team names'] : []),
    ...(t.sources?.length ? [`merges from ${t.sources.join(', ')}`] : []),
  ];
  const routes = parts.join(', and ') || 'no receiver: only when a person picks it on the case';
  return `${t.name || 'unnamed'} <${t.mailbox || 'no mailbox'}>${t.cc?.length ? `, copies ${t.cc.join(', ')}` : ''}, for ${routes}`;
}

/** Teams added, removed or changed, matched by id (a team whose id changed reads as removed and added). */
function teamChanges(a: SiteProfile, b: SiteProfile): Change[] {
  const out: Change[] = [];
  const before = new Map((a.teams ?? []).map((t) => [t.id, t]));
  const ids = new Set((b.teams ?? []).map((t) => t.id));
  for (const [i, t] of (b.teams ?? []).entries()) {
    const old = before.get(t.id);
    if (!old) out.push({ path: 'teams', text: `Team added: ${teamText(t, i === 0)}` });
    else if (!same(old, t))
      out.push({ path: 'teams', text: `Team ${t.id} changed: ${teamText(t, i === 0)}` });
  }
  for (const t of a.teams ?? [])
    if (!ids.has(t.id)) out.push({ path: 'teams', text: `Team removed: ${t.name || t.id || 'unnamed'}` });
  // The order routes: the first team takes the cases no team names, and the earlier of two naming a receiver wins
  const kept = (x: SiteProfile, y: SiteProfile) =>
    (x.teams ?? []).map((t) => t.id).filter((id) => (y.teams ?? []).some((u) => u.id === id));
  const firstBefore = a.teams?.[0];
  const firstAfter = b.teams?.[0];
  if (firstBefore && firstAfter && firstBefore.id !== firstAfter.id)
    out.push({
      path: 'teams',
      text: `Cases no team names: now to ${firstAfter.name || firstAfter.id}, before to ${firstBefore.name || firstBefore.id}`,
    });
  else if (!same(kept(a, b), kept(b, a)))
    out.push({
      path: 'teams',
      text: 'Teams reordered: where two teams name a receiver, the earlier one gets its cases',
    });
  return out;
}

/**
 * Whether closing a case by hand ("Mark as handled by the team") needs an approver on this site: the two-person rule
 * some trusts keep. Off unless the profile says true, as the server reads it (SiteProfile.CloseNeedsApprover).
 */
export function closeNeedsApprover(p: SiteProfile | undefined): boolean {
  return p?.approvers?.close_needs_approver === true;
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
