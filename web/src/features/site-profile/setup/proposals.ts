import type { SetupProposal, SetupTurnBody, SiteProfile, SiteReceiver } from '@/api/types';
import { KINDS, validateProfile } from '../profile';
import { effectsOf, lessStrict, type EffectId } from './effects';
import { classOf } from './fields';

/**
 * Set up the site, when Ask Shutter reads a typed answer: the web app's own copy of the core's checks
 * (Shutter.Util.ProfileSetup, CONTRACTS 14.7), run on the draft as it is when a turn comes back, before any drafted
 * answer enters it. The core has already checked the turn against the draft as it was sent; this is the second lock,
 * against a draft that changed meanwhile. The same words, row for row: tests/unit/Shutter/Test/ProfileSetup.cls holds
 * the one table both run.
 *
 * What an agent may draft is the field table's class A with its conditions: a receiver's description; the kind and the
 * tier only of a receiver that is not in the profile in force; no kind while the draft holds a site-wide
 * history_policy; never a tier whose policy row, in force or in the draft, releases any chain kind with no person.
 */

export const MAX_TEXT = 500;
const MAX_SAY = 800;
const MAX_QUOTE = 200;
const MAX_PROPOSALS = 3;
const MAX_SYSTEM = 120;
const KINDS_OF_SYSTEM = ['current_state', 'history_of_record', 'orders_results'];

/**
 * Why a text may not go to a model, or "": the port of ProfileSetup.TextProblem, the rule of a receiver's runbook line
 * with addresses added.
 */
export function textProblem(text: string): string {
  // eslint-disable-next-line no-control-regex
  if (/[\x00-\x1f\x7f]/.test(text)) return 'a control character';
  if (/:\/\/|\bwww\.|\bmailto:|\bjavascript:/i.test(text)) return 'a link';
  if (/[^\s@]@[^\s@]/.test(text)) return 'an address';
  if (/\b(password|passwd|pwd|secret|token|api[ _-]?key)\s*[:=]/i.test(text))
    return 'what looks like a credential';
  if (/\d{6}/.test(text)) return 'a run of six or more digits';
  return '';
}

/** What the person is told when a text is refused before it is sent. */
export const textRefusal = (what: string) =>
  `The text holds ${what}. Take that out and send again: Ask Shutter does not need it.`;

/** The person's text as it is sent, or the problem: the port of ProfileSetup.CleanText. */
export function cleanText(raw: string): { text: string; problem: string } {
  const text = raw.replace(/[\t\n\r]/g, ' ').trim();
  if (!text) return { text: '', problem: 'text is required' };
  if (text.length > MAX_TEXT) return { text: '', problem: `text is at most ${MAX_TEXT} characters` };
  const what = textProblem(text);
  return what ? { text: '', problem: textRefusal(what) } : { text, problem: '' };
}

/** A key path with every index written "[]". */
const plain = (path: string) => path.replace(/\[\d+\]/g, '[]');

/** Whether a tier's row of a policy table releases any chain kind with no person. */
export function rowAutomatic(profile: SiteProfile | undefined, tier: string): boolean {
  const row: unknown = (profile?.policy as Record<string, unknown> | undefined)?.[tier];
  if (typeof row !== 'object' || row === null || Array.isArray(row)) return false;
  return KINDS.some((kind) => (row as Record<string, unknown>)[kind] === 'automatic');
}

const jsonType = (v: unknown): string =>
  v === undefined
    ? 'unassigned'
    : v === null
      ? 'null'
      : Array.isArray(v)
        ? 'array'
        : typeof v === 'object'
          ? 'object'
          : typeof v;

/** The value as the core compares a tier or a kind: a number in its canonical form, text as it is. */
const asText = (v: unknown) => (typeof v === 'number' || typeof v === 'string' ? String(v) : '');

/**
 * Why Ask Shutter may not draft a field of a receiver, or "" when it may: the port of ProfileSetup.DraftRefusal. A
 * refusal is the end of a problem's path and its words. With `checkValue` the value is checked too.
 */
export function draftRefusal(
  field: string,
  base: SiteProfile,
  draft: SiteProfile,
  inForce: boolean,
  to?: unknown,
  checkValue = false,
): string {
  const at = `.field: ${field} `;
  const cls = classOf(field);
  if (cls === 'unknown') return `${at}is not a field of the site profile`;
  if (cls !== 'A') return `${at}is answered only by a person, with the page's control`;
  if (plain(field) !== field)
    return `${at}names an entry by its place: name the field as the request lists it`;
  const key = field.split('.')[1];
  const type = jsonType(to);
  if (key === 'system') {
    if (!checkValue) return '';
    if (type !== 'string') return '.to: must be text';
    const text = to as string;
    if (text.trim() === '') return '.to: must not be blank';
    if (text.length > MAX_SYSTEM) return `.to: must be at most ${MAX_SYSTEM} characters`;
    const what = textProblem(text);
    return what ? `.to: must not hold ${what}` : '';
  }
  if (inForce) return `${at}is changed only by a person on a receiver in force`;
  if (key === 'category') {
    if ('history_policy' in draft)
      return `${at}is not drafted while the profile holds a site-wide history_policy`;
    if (!checkValue) return '';
    return type === 'string' && KINDS_OF_SYSTEM.includes(to as string)
      ? ''
      : '.to: must be current_state, history_of_record or orders_results';
  }
  if (!checkValue) return '';
  const tier = asText(to);
  if (!['1', '2', '3'].includes(tier)) return '.to: must be 1, 2 or 3';
  if (rowAutomatic(base, tier) || rowAutomatic(draft, tier))
    return `.to: must not be ${tier}, a tier that releases without a person under the policy in force or in the draft: only a person chooses it`;
  return '';
}

/** A line of "What Shutter will do here" in words, for a refusal: the port of ProfileSetup.LineWords. */
export function lineWords(id: EffectId): string {
  if (id === 'overtaken') return 'an overtaken failure would no longer ask a person';
  if (id.startsWith('approval.')) {
    const kind = id.split('.')[1];
    const words =
      kind === 'single' ? 'single failures' : kind === 'ordered' ? 'ordered chains' : 'interleaved chains';
    return `a resend of ${words} would need no person's approval`;
  }
  if (id === 'case_write') return 'a write to the receiver from a case would become possible';
  if (id === 'engine_resend') return 'an engine resend would become possible';
  return 'recovery would be enabled';
}

const clone = <T>(x: T): T => JSON.parse(JSON.stringify(x)) as T;
const isObject = (x: unknown): x is Record<string, unknown> =>
  typeof x === 'object' && x !== null && !Array.isArray(x);

/** The draft with a batch applied, on a copy: the receiver's entry gets each value, a tier as a number. */
export function applyBatch(draft: SiteProfile, receiver: string, proposals: SetupProposal[]): SiteProfile {
  const copy = clone(draft);
  const entry = copy.receivers.find((r) => r.name === receiver) as Record<string, unknown> | undefined;
  if (!entry) return copy;
  for (const p of proposals) {
    const key = p.field.split('.')[1];
    entry[key] = key === 'tier' ? Number(p.to) : p.to;
  }
  return copy;
}

export type Checked = { ok: true; turn: SetupTurnBody } | { ok: false; problem: string };

/**
 * A turn against a draft: the port of ProfileSetup.CheckTurn without the quote's origin, which only the core can
 * check (it holds what the person typed). `base` is the profile in force, `draft` the draft as it is now, `receiver`
 * the receiver the turn is about. The proposals pass or fail together.
 */
export function checkTurn(turn: unknown, base: SiteProfile, draft: SiteProfile, receiver: string): Checked {
  const fail = (problem: string): Checked => ({ ok: false, problem });
  if (!isObject(turn)) return fail('the turn is not an object');
  if (typeof turn.say !== 'string') return fail('say: needs a sentence for the person');
  // eslint-disable-next-line no-control-regex
  const say = turn.say.replace(/[\t\n\r]/g, ' ').replace(/[\x00-\x1f\x7f-\x9f]/g, '');
  if (say.trim() === '') return fail('say: needs a sentence for the person');
  if (say.length > MAX_SAY) return fail(`say: at most ${MAX_SAY} characters`);
  const entry = draft.receivers.find((r) => r.name === receiver) as SiteReceiver | undefined;
  if (!entry) return fail(`the draft has no receiver named ${receiver}`);
  const inForce = base.receivers.some((r) => r.name === receiver);
  const type = jsonType(turn.proposals);
  if (!['array', 'unassigned', 'null'].includes(type)) return fail('proposals: must be a list');
  const proposals = (type === 'array' ? turn.proposals : []) as unknown[];
  if (proposals.length > MAX_PROPOSALS) return fail(`proposals: at most ${MAX_PROPOSALS} in one turn`);
  const seen = new Set<string>();
  const kept: SetupProposal[] = [];
  for (const [i, p] of proposals.entries()) {
    const at = `proposals[${i}]`;
    if (!isObject(p)) return fail(`${at}: must be an object`);
    const field = typeof p.field === 'string' ? p.field : '';
    if (!field) return fail(`${at}.field: required`);
    if ((typeof p.receiver === 'string' ? p.receiver : '') !== receiver)
      return fail(`${at}.receiver: this turn is about ${receiver} and no other receiver`);
    if (seen.has(field)) return fail(`${at}.field: ${field} is named twice`);
    seen.add(field);
    if (p.to === undefined || p.to === null) return fail(`${at}.to: required`);
    const why = draftRefusal(field, base, draft, inForce, p.to, true);
    if (why) return fail(`${at}${why}`);
    // eslint-disable-next-line no-control-regex
    const quote = typeof p.quote === 'string' ? p.quote.replace(/[\x00-\x1f\x7f-\x9f]/g, '') : '';
    if (quote.trim() === '' || quote.length > MAX_QUOTE)
      return fail(`${at}.quote: the person's own words, 1 to ${MAX_QUOTE} characters`);
    const key = field.split('.')[1];
    const from: unknown = (entry as Record<string, unknown>)[key];
    kept.push({
      field,
      receiver,
      quote,
      to: key === 'tier' ? Number(p.to) : key === 'system' ? (p.to as string).trim() : (p.to as string),
      from: ['string', 'number', 'boolean'].includes(typeof from) ? (from as SetupProposal['from']) : null,
    });
  }
  if (kept.length) {
    const applied = applyBatch(draft, receiver, kept);
    const after = effectsOf(
      applied,
      applied.receivers.find((r) => r.name === receiver)!,
    );
    const was = base.receivers.find((r) => r.name === receiver);
    let line = lessStrict(was ? effectsOf(base, was) : null, after);
    if (line) return fail(`proposals: less strict than the profile in force: ${lineWords(line.id)}`);
    line = lessStrict(effectsOf(draft, entry), after);
    if (line) return fail(`proposals: less strict than the draft: ${lineWords(line.id)}`);
    const invalid = validateProfile(applied);
    if (invalid && invalid !== validateProfile(draft))
      return fail(`proposals: the profile would not be valid: ${invalid}`);
  }
  let ask: SetupTurnBody['ask'] = null;
  if (turn.ask !== undefined && turn.ask !== null) {
    if (!isObject(turn.ask)) return fail('ask: must be {field, receiver} or null');
    const field = typeof turn.ask.field === 'string' ? turn.ask.field : '';
    if (!field || classOf(field) === 'unknown' || plain(field) !== field)
      return fail('ask.field: not a field of the site profile');
    if ((typeof turn.ask.receiver === 'string' ? turn.ask.receiver : '') !== receiver)
      return fail(`ask.receiver: this turn is about ${receiver} and no other receiver`);
    ask = { field, receiver };
  }
  return { ok: true, turn: { say, proposals: kept, ask } };
}
