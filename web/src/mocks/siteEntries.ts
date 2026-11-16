import { http, HttpResponse } from 'msw';
import vocabulary from '../../../knowledge/catalogue/vocabulary.json';
import { CLOSED_STATES } from '@/api/types';
import type {
  SiteEntriesView,
  SiteEntryContent,
  SiteEntryDetail,
  SiteEntryFixture,
  SiteEntryImpactGroup,
  SiteEntryItem,
  SiteEntryOverlap,
  SiteEntryPreview,
  SiteEntryProblem,
  SiteEntryProofResult,
  SiteEntryState,
} from '@/api/types';
import type { CaseFixture } from './hold';

/**
 * The site's own scenarios in the trial (CONTRACTS 6.8): two sample entries, labelled as such on the page, and every
 * route of the page answered in the browser as the core answers it, on the recorded cases. A change lasts until the
 * page is reloaded or left, as the site profile's does. As the core, it decides nothing a person could set: an entry
 * has no field for who decides, the matcher's answer is always a person, and the two-person rule holds (409
 * same_person). The digests here are the trial's own, not SHA-256.
 */

const BASE = '/api/shutter';

type Case = CaseFixture;
type Need = 'operator' | 'approver' | 'configure';

export interface SiteEntryDeps {
  csrf: (request: Request) => Response | null;
  guard: (need: Need) => Response | null;
  /** The signed-in user's name. */
  who: () => string;
  /** Every recorded case, newest first is not needed: the impact reads them all (fewer than 200). */
  cases: () => Case[];
  caseOf: (id: string) => Case | undefined;
  /** The site profile's receivers and team ids, for R4. */
  receivers: () => string[];
  teams: () => string[];
}

interface Version {
  version: number;
  status: 'draft' | 'approved';
  content: SiteEntryContent;
  digest: string;
  writtenBy: string;
  writtenAt: string;
  approvedBy?: string;
  approvedAt?: string;
  reason?: string;
  safetyReference?: string;
}

interface Proof {
  id: string;
  version: number;
  digest: string;
  action: string;
  passed: boolean;
  at: string;
  by: string;
  origin: string;
  result: SiteEntryProofResult;
}

interface Entry {
  id: string;
  state: 'draft' | 'active' | 'suspended' | 'retired';
  activeVersion: number;
  draftVersion: number;
  revision: number;
  proposal?: {
    action: 'activate' | 'retire' | 'resume';
    version: number;
    digest: string;
    by: string;
    at: string;
    proofId: string;
  };
  suspended?: { by: string; at: string; reason: string };
  versions: Version[];
  proofs: Proof[];
  events: SiteEntryDetail['events'];
  createdBy: string;
  createdAt: string;
  updatedAt: string;
}

const stamp = () => new Date().toISOString().replace(/\.\d+Z$/, 'Z');

/** The trial's digest: a stable 64-hex string of the canonical content. Not SHA-256. */
function digestOf(content: SiteEntryContent): string {
  const text = canonical(content);
  let out = '';
  for (let round = 0; round < 8; round++) {
    let h = 0x811c9dc5 ^ round;
    for (let i = 0; i < text.length; i++) {
      h ^= text.charCodeAt(i);
      h = Math.imul(h, 0x01000193) >>> 0;
    }
    out += h.toString(16).padStart(8, '0');
  }
  return `sha256:${out}`;
}

function canonical(v: unknown): string {
  if (Array.isArray(v)) return `[${v.map(canonical).join(',')}]`;
  if (v && typeof v === 'object')
    return `{${Object.keys(v)
      .sort()
      .map((k) => `${JSON.stringify(k)}:${canonical((v as Record<string, unknown>)[k])}`)
      .join(',')}}`;
  return JSON.stringify(v);
}

const VOCABULARY = vocabulary as unknown as {
  conditions: Record<string, string[]>;
  site: { scope: string[]; reserved_conditions: string[] };
};

const asList = (v: unknown): string[] =>
  Array.isArray(v)
    ? v.map((x) => String(x).trim()).filter(Boolean)
    : v === undefined || v === null || v === ''
      ? []
      : [String(v).trim()];

const conditionsOf = (c: Case): Record<string, string> =>
  ((c.snapshot as { summary?: { catalogue?: { conditions?: Record<string, string> } } } | null)?.summary
    ?.catalogue?.conditions ?? {}) as Record<string, string>;

const catalogueOf = (c: Case) =>
  ((c.snapshot as { summary?: { catalogue?: Record<string, unknown> } } | null)?.summary?.catalogue ??
    {}) as {
    decision?: string;
    outcome?: string;
    entry?: string;
    matches?: { id: string; title?: string; decides?: string; preferred?: { outcome?: string } }[];
  };

function scopeOf(c: Case): Record<string, string> {
  const d = c.detail as unknown as Record<string, unknown>;
  return {
    receiver: String(d.receiver ?? ''),
    source_system: String(d.sourceSystem ?? ''),
    ward: String(d.ward ?? ''),
    reason_code: String(d.failureReasonCode ?? ''),
  };
}

/** As Matcher.SiteHolds and ScopeHolds: every listed value set holds; a condition the case does not carry is passed over. */
function holds(
  content: Pick<SiteEntryContent, 'pattern' | 'scope'>,
  conditions: Record<string, string>,
  scope: Record<string, string>,
) {
  for (const [k, values] of Object.entries(content.pattern ?? {}))
    if (k in conditions && !values.includes(conditions[k])) return false;
  for (const [k, values] of Object.entries(content.scope ?? {}))
    if (!values.includes(scope[k] ?? '')) return false;
  return true;
}

/** The sample entries the trial starts with: one active (the worked example) and one waiting for a second person. */
function samples(): Entry[] {
  const l1: SiteEntryContent = {
    id: 'L1',
    kind: 'stop',
    title: 'A failed transfer into the isolation ward',
    priority: 10,
    scope: { receiver: ['Downstream Out'], source_system: ['PAS'], ward: ['WARD-ISO'] },
    pattern: { delivery: ['failed', 'rejected', 'uncertain'], event: ['transfer'] },
    why: "Infection control places every patient in this ward by hand, so a resend can't know the bed is right.",
    team: '',
    instructions: "Ring the ward's nurse in charge before anything is entered. Do not resend.",
    prose: '',
    fixtures: [],
  };
  const at = '2026-11-15T10:20:00Z';
  const v1: Version = {
    version: 1,
    status: 'approved',
    content: l1,
    digest: digestOf(l1),
    writtenBy: 'sample-author',
    writtenAt: '2026-11-15T09:40:00Z',
    approvedBy: 'sample-approver',
    approvedAt: at,
    reason: 'Agreed with infection control (sample)',
  };
  const e1: Entry = {
    id: 'L1',
    state: 'active',
    activeVersion: 1,
    draftVersion: 0,
    revision: 4,
    versions: [v1],
    proofs: [],
    events: [
      { at, actor: 'sample-approver', kind: 'activated', text: 'Version 1 is active (sample)', version: 1 },
    ],
    createdBy: 'sample-author',
    createdAt: '2026-11-15T09:40:00Z',
    updatedAt: at,
  };
  const e2: Entry = {
    id: 'L2',
    state: 'draft',
    activeVersion: 0,
    draftVersion: 1,
    revision: 3,
    versions: [],
    proofs: [],
    events: [],
    createdBy: 'sample-author',
    createdAt: '2026-11-15T11:00:00Z',
    updatedAt: '2026-11-15T11:05:00Z',
  };
  return [e1, e2];
}

export function siteEntryHandlers(deps: SiteEntryDeps) {
  let entries: Entry[] = [];
  let next = 0;
  let generation = 0;
  let proofs = 0;

  const fail = (status: number, error: string, detail: string, extra: object = {}) =>
    HttpResponse.json({ error, detail, ...extra }, { status });

  /** A fixture frozen from a recorded, closed case, or why the case cannot serve. */
  function freeze(caseId: string, expect: 'match' | 'no_match'): SiteEntryFixture | string {
    const c = deps.caseOf(caseId);
    if (!c) return `there is no case ${caseId.slice(0, 40)}`;
    if (!CLOSED_STATES.includes(c.summary.state as never))
      return `case ${caseId} is still being worked on (${c.summary.state}): a fixture is a closed case, whose evidence no longer changes`;
    const conditions = conditionsOf(c);
    return {
      case: caseId,
      expect,
      snapshot_digest: 'sample',
      chain: conditions.chain ?? 'single',
      conditions,
      scope: scopeOf(c),
    };
  }

  /** As SiteEntryVersion.Normalise: the rules R1 to R5 and R15, the content in its stored form. */
  function normalise(body: Record<string, unknown>, id: string) {
    const problems: SiteEntryProblem[] = [];
    const warnings: SiteEntryProblem[] = [];
    const add = (list: SiteEntryProblem[], rule: string, field: string, text: string) =>
      list.push({ rule, field, text });
    const known = [
      'id',
      'version',
      'kind',
      'title',
      'priority',
      'scope',
      'pattern',
      'why',
      'team',
      'instructions',
      'prose',
      'fixtures',
    ];
    for (const key of Object.keys(body)) {
      if (['decides', 'preferred', 'alternatives', 'checks', 'outcome', 'scenarios', 'origin'].includes(key))
        add(
          problems,
          'R1',
          key,
          `A site entry has no "${key}": it sends a case to a person and nothing else, so who decides and the outcome are not fields`,
        );
      else if (!known.includes(key)) add(problems, 'R1', key, `A site entry has no field "${key}"`);
    }
    const words = (field: string, max: number) => {
      const text = String(body[field] ?? '').trim();
      if (text.length > max)
        add(problems, 'R5', field, `The ${field} is ${text.length} characters; at most ${max}`);
      if ((field === 'title' || field === 'why') && !text)
        add(problems, 'R5', field, `The ${field} is required`);
      if (/\d{6,}/.test(text.replace(/[ -](?=\d)/g, '')))
        add(
          warnings,
          'R5',
          field,
          `The ${field} holds a run of six or more digits: check it identifies no patient`,
        );
      return text;
    };
    const content: SiteEntryContent = {
      id,
      kind: 'stop',
      title: words('title', 200),
      priority: typeof body.priority === 'number' ? body.priority : 100,
      scope: {},
      pattern: {},
      why: words('why', 500),
      team: String(body.team ?? '').trim(),
      instructions: words('instructions', 2000),
      prose: words('prose', 4000),
      fixtures: [],
    };
    if (!content.instructions)
      add(warnings, 'R5', 'instructions', 'No instructions: the person the case goes to is told only why');
    for (const [fact, value] of Object.entries((body.scope ?? {}) as Record<string, unknown>)) {
      if (!VOCABULARY.site.scope.includes(fact)) {
        add(
          problems,
          'R4',
          `scope.${fact}`,
          'The scope names only receiver, source_system, ward and reason_code',
        );
        continue;
      }
      const list = asList(value);
      if (!list.length) continue;
      if (fact === 'receiver')
        for (const r of list)
          if (!deps.receivers().includes(r))
            add(problems, 'R4', 'scope.receiver', `The site profile names no receiver ${r}`);
      content.scope[fact] = list;
    }
    if (content.team && !deps.teams().includes(content.team))
      add(problems, 'R4', 'team', `The site profile names no team ${content.team}`);
    const pattern = (body.pattern ?? {}) as Record<string, unknown>;
    if (!Object.keys(pattern).length)
      add(problems, 'R3', 'pattern', 'The pattern names at least one condition');
    for (const [condition, value] of Object.entries(pattern)) {
      if (VOCABULARY.site.reserved_conditions.includes(condition)) {
        add(
          problems,
          'R3',
          `pattern.${condition}`,
          `A site entry cannot name ${condition}: the shipped entry for it answers first, whatever a site entry says`,
        );
        continue;
      }
      const allowed = VOCABULARY.conditions[condition];
      if (!allowed) {
        add(
          problems,
          'R3',
          `pattern.${condition}`,
          `${condition} is not a condition of the vocabulary (CONTRACTS 6.1)`,
        );
        continue;
      }
      const list = asList(value);
      const bad = list.filter((w) => !allowed.includes(w));
      if (!list.length || bad.length) {
        add(
          problems,
          'R3',
          `pattern.${condition}`,
          `${condition} cannot be ${bad[0] ?? 'empty'} (allowed: ${allowed.join(', ')})`,
        );
        continue;
      }
      content.pattern[condition] = list;
    }
    const seen = new Set<string>();
    ((body.fixtures ?? []) as { case?: string; expect?: string }[]).forEach((f, n) => {
      const caseId = String(f?.case ?? '').trim();
      const expect = f?.expect;
      if (!caseId || (expect !== 'match' && expect !== 'no_match'))
        return add(problems, 'R1', 'fixtures', `Fixture ${n + 1} needs a case and expect: match or no_match`);
      if (seen.has(caseId)) return add(problems, 'R1', 'fixtures', `Case ${caseId} is listed twice`);
      seen.add(caseId);
      const frozen = freeze(caseId, expect);
      if (typeof frozen === 'string') return add(problems, 'R1', 'fixtures', `Fixture ${n + 1}: ${frozen}`);
      content.fixtures.push(frozen);
    });
    return { content, problems, warnings };
  }

  /** As SiteEntryVersion.Sentence. */
  function sentence(content: Pick<SiteEntryContent, 'pattern' | 'scope'>): string {
    const words = (l: string[]) =>
      l.length <= 1 ? (l[0] ?? '') : `${l.slice(0, -1).join(', ')} or ${l[l.length - 1]}`;
    const ev = content.pattern.event ?? [];
    const what = ev.length
      ? words(
          ev.map(
            (e) =>
              ({ admit: 'an admission', update: 'an update', other: 'another kind of message' })[e] ??
              `a ${e}`,
          ),
        )
      : 'a message';
    let text = `When ${what}`;
    if (content.scope.receiver) text += ` to ${words(content.scope.receiver)}`;
    if (content.scope.source_system) text += ` from ${words(content.scope.source_system)}`;
    const verbs: Record<string, string> = {
      failed: 'fails',
      rejected: 'is rejected',
      uncertain: 'gets no answer',
      unmappable: 'cannot be mapped',
      withheld: 'is withheld',
      unreadable: 'is held unread',
    };
    const d = content.pattern.delivery ?? [];
    text += d.length ? ` ${words(d.map((x) => verbs[x] ?? x))}` : ' is not delivered';
    for (const [k, v] of Object.entries(content.pattern))
      if (k !== 'event' && k !== 'delivery') text += `, and ${k.replace(/_/g, ' ')} is ${words(v)}`;
    if (content.scope.ward) text += `, and the ward is ${words(content.scope.ward)}`;
    if (content.scope.reason_code)
      text += `, and the receiver's reason is ${words(content.scope.reason_code)}`;
    return `${text}: a person decides`;
  }

  /**
   * What a pattern can displace, read from the recorded cases (the trial has no shipped patterns): each shipped entry
   * some recorded case matched where the pattern holds; it covers the pattern when it matched every such case.
   */
  function overlap(content: Pick<SiteEntryContent, 'pattern' | 'scope'>): SiteEntryOverlap[] {
    const hit = deps
      .cases()
      .filter((c) => holds({ pattern: content.pattern, scope: {} }, conditionsOf(c), scopeOf(c)));
    const byId = new Map<string, { o: SiteEntryOverlap; n: number }>();
    for (const c of hit)
      for (const m of catalogueOf(c).matches ?? []) {
        const row = byId.get(m.id) ?? {
          o: {
            id: m.id,
            title: m.title ?? '',
            decides: m.decides ?? '',
            outcome: m.preferred?.outcome ?? '',
            covers: false,
            leads: false,
          },
          n: 0,
        };
        row.n += 1;
        byId.set(m.id, row);
      }
    return [...byId.values()].map(({ o, n }) => ({ ...o, covers: n === hit.length && hit.length > 0 }));
  }

  const activeItems = (except = '') =>
    entries
      .filter((e) => e.state === 'active' && e.id !== except)
      .map((e) => ({ id: e.id, content: e.versions.find((v) => v.version === e.activeVersion)!.content }));
  const ordered = (list: { id: string; content: SiteEntryContent }[]) =>
    [...list].sort(
      (a, b) => a.content.priority - b.content.priority || Number(a.id.slice(1)) - Number(b.id.slice(1)),
    );

  /** What a recorded case did without the entry, in one word, from its recorded match and how it ended. */
  function groupOf(c: Case, others: { id: string; content: SiteEntryContent }[]): SiteEntryImpactGroup {
    if (others.some((o) => holds(o.content, conditionsOf(c), scopeOf(c)))) return 'other_site_entry';
    const cat = catalogueOf(c);
    if (cat.decision === 'board') return 'board';
    if (cat.decision === 'person') return 'person';
    if (cat.decision === 'new_pattern') return 'new_pattern';
    if (cat.decision === 'policy') {
      if (String(cat.outcome ?? '').startsWith('resend')) {
        const recorded = (c as unknown as { approvals?: { approvals?: { approver?: string }[] } }).approvals;
        const people = (recorded?.approvals ?? []).filter((a) => a.approver && a.approver !== 'policy');
        return people.length ? 'approved_resend' : 'automatic_resend';
      }
      if (cat.outcome === 'none' || cat.outcome === 'reconcile') return 'closure';
      return 'person';
    }
    return 'other';
  }

  /** As SiteEntryProof.Run: P1, P2 and P4 on the recorded cases. */
  function run(id: string, version: number, content: SiteEntryContent, action: string): SiteEntryProofResult {
    const problems: string[] = [];
    const others = activeItems(id);
    const withIt = ordered([...others, { id, content }]);
    let match = 0;
    let near = 0;
    let all = true;
    const fixtures = content.fixtures.map((f) => {
      const c = deps.caseOf(f.case);
      const conditions = c ? conditionsOf(c) : (f.conditions ?? {});
      const scope = c ? scopeOf(c) : (f.scope ?? {});
      const own = holds(content, conditions, scope);
      let ok: boolean;
      let lead: string | undefined;
      let text: string;
      if (f.expect === 'match') {
        match += 1;
        lead = withIt.find((e) => holds(e.content, conditions, scope))?.id ?? '';
        ok = own && lead === id;
        text = ok
          ? 'The entry matches and leads alone: a person decides'
          : !own
            ? "The entry's own scope and pattern do not hold on this case"
            : `The entry matches, but ${lead || 'nothing'} leads on this case`;
      } else {
        near += 1;
        ok = !own;
        text = ok
          ? 'The entry leaves this case alone'
          : "The entry's own scope and pattern hold on this case, which it should leave alone";
      }
      if (!ok) all = false;
      return {
        case: f.case,
        expect: f.expect,
        source: (c ? 'evidence' : 'frozen') as 'evidence' | 'frozen',
        holds: own,
        lead,
        ok,
        text,
      };
    });
    if (action !== 'retire') {
      if (!match)
        problems.push(
          'No fixture expects a match: the proof needs at least one stored case the entry must catch',
        );
      if (!near)
        problems.push(
          'No fixture expects no match: the proof needs at least one near miss the entry must leave alone',
        );
      if (!all) problems.push('A fixture did not answer as expected');
    }
    const groups: Partial<Record<SiteEntryImpactGroup, number>> = {};
    const cases: Partial<Record<SiteEntryImpactGroup, string[]>> = {};
    const scanned = deps.cases().slice(0, 200);
    let caught = 0;
    for (const c of scanned) {
      const lead = withIt.find((e) => holds(e.content, conditionsOf(c), scopeOf(c)))?.id;
      if (lead !== id) continue;
      caught += 1;
      const g = groupOf(c, others);
      groups[g] = (groups[g] ?? 0) + 1;
      (cases[g] ??= []).push(c.summary.caseId);
    }
    return {
      passed: problems.length === 0,
      action: action as SiteEntryProofResult['action'],
      version,
      digest: digestOf(content),
      fixtures,
      counts: { match, no_match: near },
      impact: { scanned: scanned.length, caught, unread: 0, capped: false, groups, cases },
      problems,
    };
  }

  const shownState = (e: Entry): SiteEntryState => (e.state === 'draft' && e.proposal ? 'proposed' : e.state);

  function describe(e: Entry, full = false): SiteEntryItem | SiteEntryDetail {
    const active = e.activeVersion ? e.versions.find((v) => v.version === e.activeVersion) : undefined;
    const draft = e.draftVersion ? e.versions.find((v) => v.version === e.draftVersion) : undefined;
    const shown = active ?? draft;
    const sent = 0;
    const item: SiteEntryItem = {
      id: e.id,
      state: shownState(e),
      kind: 'stop',
      title: shown?.content.title ?? '',
      sentence: shown ? sentence(shown.content) : '',
      version: shown?.version,
      digest: shown?.digest,
      content: shown?.content,
      activeVersion: e.activeVersion,
      draftVersion: e.draftVersion,
      revision: e.revision,
      ...(active ? { approvedBy: active.approvedBy, approvedAt: active.approvedAt } : {}),
      ...(draft && active
        ? {
            draft: {
              version: draft.version,
              digest: draft.digest,
              writtenBy: draft.writtenBy,
              writtenAt: draft.writtenAt,
              content: draft.content,
              sentence: sentence(draft.content),
            },
          }
        : {}),
      ...(e.proposal ? { proposal: { ...e.proposal } } : {}),
      needsReview: false,
      ...(e.state === 'suspended' && e.suspended ? { suspended: e.suspended } : {}),
      casesSent: sent,
      casesSent30: sent,
      createdBy: e.createdBy,
      createdAt: e.createdAt,
      updatedAt: e.updatedAt,
    };
    if (!full) return item;
    return {
      ...item,
      versions: [...e.versions].sort((a, b) => b.version - a.version).map(({ content: _c, ...v }) => v),
      proofs: [...e.proofs].reverse().slice(0, 20),
      events: [...e.events].reverse(),
    };
  }

  function view(): SiteEntriesView {
    const order = { active: 0, suspended: 1, draft: 2, retired: 3 } as const;
    const items = [...entries].sort(
      (a, b) => order[a.state] - order[b.state] || Number(a.id.slice(1)) - Number(b.id.slice(1)),
    );
    const warnings = entries
      .filter((e) => e.state === 'suspended')
      .map(
        (e) =>
          `Site entry ${e.id} is suspended (by ${e.suspended?.by}, ${e.suspended?.at}): its protection is off until a second person approves resuming it`,
      );
    return {
      items: items.map((e) => describe(e)),
      status: {
        active: entries.filter((e) => e.state === 'active').length,
        proposed: entries.filter((e) => e.proposal).length,
        generation,
        limit: 50,
        suspended: entries.filter((e) => e.state === 'suspended').map((e) => e.id),
        needsReview: [],
        onePerson: null,
        warnings,
      },
      catalogueVersion: '',
      waitingPlans: 0,
    };
  }

  const record = (e: Entry, kind: string, text: string, version?: number) => {
    e.events.push({ at: stamp(), actor: deps.who(), kind, text, source: 'api', version });
    e.revision += 1;
    e.updatedAt = stamp();
  };

  const keep = (
    e: Entry,
    version: number,
    digest: string,
    action: string,
    result: SiteEntryProofResult,
    origin = 'api',
  ) => {
    proofs += 1;
    const id = String(proofs);
    e.proofs.push({
      id,
      version,
      digest,
      action,
      passed: result.passed,
      at: stamp(),
      by: deps.who(),
      origin,
      result: { ...result, proofId: id },
    });
    return id;
  };

  function versionFor(e: Entry, action: string): Version | string {
    if (action === 'activate') {
      if (e.state === 'retired') return `${e.id} is retired`;
      return e.versions.find((v) => v.version === e.draftVersion) ?? `${e.id} has no draft to activate`;
    }
    if (action === 'retire') {
      if (e.state !== 'active' && e.state !== 'suspended')
        return `${e.id} is ${e.state}: only an active or suspended entry is retired`;
      return e.versions.find((v) => v.version === e.activeVersion)!;
    }
    if (action === 'resume') {
      if (e.state !== 'suspended') return `${e.id} is ${e.state}: only a suspended entry is resumed`;
      return e.versions.find((v) => v.version === e.activeVersion)!;
    }
    return 'The action is activate, retire or resume';
  }

  async function bodyOf(request: Request): Promise<Record<string, unknown> | null> {
    try {
      const b = (await request.json()) as unknown;
      return b && typeof b === 'object' && !Array.isArray(b) ? (b as Record<string, unknown>) : null;
    } catch {
      return null;
    }
  }

  /** As SiteEntry.FromCase: the case's conditions (the reserved one aside), its facts, the case as the first fixture. */
  function fromCase(body: Record<string, unknown>): { body: Record<string, unknown>; problem: string } {
    const caseId = String(body.fromCase ?? '');
    const { fromCase: _f, ...rest } = body;
    const frozen = freeze(caseId, 'match');
    if (typeof frozen === 'string') return { body: rest, problem: frozen };
    const out = { ...rest };
    if (!('pattern' in out))
      out.pattern = Object.fromEntries(
        Object.entries(frozen.conditions ?? {}).filter(
          ([k]) => !VOCABULARY.site.reserved_conditions.includes(k),
        ),
      );
    if (!('scope' in out))
      out.scope = Object.fromEntries(Object.entries(frozen.scope ?? {}).filter(([, v]) => v));
    if (!('fixtures' in out)) out.fixtures = [{ case: caseId, expect: 'match' }];
    return { body: out, problem: '' };
  }

  const find = (id: string) => entries.find((e) => e.id === id);

  return {
    reset() {
      entries = samples();
      next = entries.length;
      generation = 1;
      proofs = 0;
      // The sample waiting for a second person: written and proposed by someone else, proved on S2's and S1's cases
      const l2 = entries.find((e) => e.id === 'L2')!;
      const { content } = normalise(
        {
          title: 'A failed transfer into Ward B with nothing since',
          priority: 20,
          scope: { ward: ['WARD-B'] },
          pattern: { event: ['transfer'], delivery: ['failed'], later_applied: ['none'] },
          why: 'The ward places its patients by hand this month, so a resend cannot know the bed is right.',
          team: 'integration',
          instructions: "Ring the ward's nurse in charge before anything is entered. Do not resend.",
          fixtures: [
            { case: 'C-000028', expect: 'match' },
            { case: 'C-000027', expect: 'no_match' },
          ],
        },
        'L2',
      );
      const digest = digestOf(content);
      l2.versions = [
        {
          version: 1,
          status: 'draft',
          content,
          digest,
          writtenBy: 'sample-author',
          writtenAt: '2026-11-15T11:00:00Z',
        },
      ];
      const result = run('L2', 1, content, 'activate');
      proofs += 1;
      l2.proofs = [
        {
          id: '1',
          version: 1,
          digest,
          action: 'activate',
          passed: result.passed,
          at: '2026-11-15T11:04:00Z',
          by: 'sample-author',
          origin: 'api',
          result: { ...result, proofId: '1' },
        },
      ];
      l2.proposal = {
        action: 'activate',
        version: 1,
        digest,
        by: 'sample-author',
        at: '2026-11-15T11:05:00Z',
        proofId: '1',
      };
      l2.events = [
        {
          at: '2026-11-15T11:00:00Z',
          actor: 'sample-author',
          kind: 'created',
          text: 'Draft made (sample)',
          version: 1,
        },
        {
          at: '2026-11-15T11:05:00Z',
          actor: 'sample-author',
          kind: 'proposed',
          text: 'Proposed: activate version 1 (sample)',
          version: 1,
        },
      ];
    },
    /** For a test: the site as one with no entry of its own. */
    clear() {
      entries = [];
      next = 0;
      generation = 0;
    },
    handlers: [
      http.get(`${BASE}/site-entries`, () => deps.guard('operator') ?? HttpResponse.json(view())),
      http.post(`${BASE}/site-entries/validate`, async ({ request }) => {
        const denied = deps.csrf(request) ?? deps.guard('operator');
        if (denied) return denied;
        const body = await bodyOf(request);
        if (!body) return fail(400, 'bad_request', 'The body must be a JSON object');
        const { content, problems, warnings } = normalise({ ...body, fixtures: [] }, '');
        return HttpResponse.json({
          valid: !problems.length,
          problems,
          warnings,
          sentence: sentence(content),
          overlap: overlap(content),
        });
      }),
      http.post(`${BASE}/site-entries/preview`, async ({ request }) => {
        const denied = deps.csrf(request) ?? deps.guard('operator');
        if (denied) return denied;
        let body = await bodyOf(request);
        if (!body) return fail(400, 'bad_request', 'The body must be a JSON object');
        const action = String(body.action ?? 'activate');
        if (!['activate', 'retire', 'resume'].includes(action))
          return fail(400, 'bad_request', 'The action is activate, retire or resume');
        const { action: _a, expectedVersion: _x, ...rest } = body;
        body = rest;
        let id = String(body.id ?? '');
        if (id && !find(id)) return fail(404, 'not_found', `No site entry ${id}`);
        if (!id) id = `L${next + 1}`;
        let problem = '';
        if ('fromCase' in body) ({ body, problem } = fromCase(body));
        const { content, problems, warnings } = normalise(body, id);
        if (problem) problems.unshift({ rule: 'R1', field: 'fromCase', text: problem });
        const answer: SiteEntryPreview = {
          valid: !problems.length,
          problems,
          warnings,
          id,
          action,
          sentence: sentence(content),
          overlap: overlap(content),
          content,
          proof: Object.keys(content.pattern).length ? run(id, 0, content, action) : null,
        };
        return HttpResponse.json(answer);
      }),
      http.get(`${BASE}/site-entries/:id`, ({ params }) => {
        const denied = deps.guard('operator');
        if (denied) return denied;
        const e = find(String(params.id));
        return e
          ? HttpResponse.json(describe(e, true))
          : fail(404, 'not_found', `No site entry ${String(params.id)}`);
      }),
      http.post(`${BASE}/site-entries`, async ({ request }) => {
        const denied = deps.csrf(request) ?? deps.guard('configure');
        if (denied) return denied;
        let body = await bodyOf(request);
        if (!body) return fail(400, 'bad_request', 'The body must be a JSON object');
        let problem = '';
        if ('fromCase' in body) ({ body, problem } = fromCase(body));
        if (problem) return fail(400, 'bad_request', `The entry is not valid (CONTRACTS 6.8): ${problem}`);
        const id = `L${next + 1}`;
        const { content, problems, warnings } = normalise(body, id);
        if (problems.length)
          return fail(400, 'bad_request', `The entry is not valid (CONTRACTS 6.8): ${problems[0].text}`, {
            problems,
          });
        next += 1;
        const e: Entry = {
          id,
          state: 'draft',
          activeVersion: 0,
          draftVersion: 1,
          revision: 0,
          versions: [
            {
              version: 1,
              status: 'draft',
              content,
              digest: digestOf(content),
              writtenBy: deps.who(),
              writtenAt: stamp(),
            },
          ],
          proofs: [],
          events: [],
          createdBy: deps.who(),
          createdAt: stamp(),
          updatedAt: stamp(),
        };
        entries.push(e);
        record(e, 'created', `Draft made: ${content.title}`, 1);
        return HttpResponse.json({ ...describe(e, true), warnings }, { status: 201 });
      }),
      http.put(`${BASE}/site-entries/:id`, async ({ request, params }) => {
        const denied = deps.csrf(request) ?? deps.guard('configure');
        if (denied) return denied;
        const e = find(String(params.id));
        if (!e) return fail(404, 'not_found', 'No such site entry');
        const body = await bodyOf(request);
        if (!body) return fail(400, 'bad_request', 'The body must be a JSON object');
        if (e.state === 'retired')
          return fail(
            409,
            'wrong_state',
            `${e.id} is retired: its history is kept and it is not changed again`,
          );
        if (e.proposal?.action === 'activate')
          return fail(
            409,
            'wrong_state',
            `Version ${e.proposal.version} of ${e.id} waits for approval and is frozen until it is approved or rejected`,
          );
        const { expectedVersion, ...rest } = body;
        if (expectedVersion === undefined || Number(expectedVersion) !== e.revision)
          return fail(409, 'stale_version', "expectedVersion is not the entry's revision", {
            currentVersion: e.revision,
          });
        const { content, problems, warnings } = normalise(rest, e.id);
        if (problems.length)
          return fail(400, 'bad_request', `The entry is not valid (CONTRACTS 6.8): ${problems[0].text}`, {
            problems,
          });
        if (!e.draftVersion) e.draftVersion = Math.max(...e.versions.map((v) => v.version)) + 1;
        const v = {
          version: e.draftVersion,
          status: 'draft' as const,
          content,
          digest: digestOf(content),
          writtenBy: deps.who(),
          writtenAt: stamp(),
        };
        e.versions = [...e.versions.filter((x) => x.version !== v.version), v];
        record(e, 'edited', `Draft version ${v.version} changed`, v.version);
        return HttpResponse.json({ ...describe(e, true), warnings });
      }),
      http.post(`${BASE}/site-entries/:id/proof`, async ({ request, params }) => {
        const denied = deps.csrf(request) ?? deps.guard('configure');
        if (denied) return denied;
        const e = find(String(params.id));
        if (!e) return fail(404, 'not_found', 'No such site entry');
        const action = String((await bodyOf(request))?.action || 'activate');
        const v = versionFor(e, action);
        if (typeof v === 'string')
          return fail(
            v.startsWith('The action') ? 400 : 409,
            v.startsWith('The action') ? 'bad_request' : 'wrong_state',
            v,
          );
        const result = run(e.id, v.version, v.content, action);
        const proofId = keep(e, v.version, v.digest, action, result);
        record(e, 'proved', `Proof for ${action}: ${result.passed ? 'passed' : 'did not pass'}`, v.version);
        return HttpResponse.json({ ...result, proofId });
      }),
      http.post(`${BASE}/site-entries/:id/propose`, async ({ request, params }) => {
        const denied = deps.csrf(request) ?? deps.guard('configure');
        if (denied) return denied;
        const e = find(String(params.id));
        if (!e) return fail(404, 'not_found', 'No such site entry');
        const action = String((await bodyOf(request))?.action ?? '');
        if (e.proposal)
          return fail(
            409,
            'wrong_state',
            `A proposal to ${e.proposal.action} ${e.id} already waits for approval`,
          );
        const v = versionFor(e, action);
        if (typeof v === 'string')
          return fail(
            v.startsWith('The action') ? 400 : 409,
            v.startsWith('The action') ? 'bad_request' : 'wrong_state',
            v,
          );
        const proof = [...e.proofs]
          .reverse()
          .find((p) => p.digest === v.digest && p.action === action && p.origin === 'api');
        if (!proof)
          return fail(
            409,
            'no_proof',
            `No proof of this version's digest for ${action}: run the proof first`,
          );
        if (!proof.passed) return fail(409, 'no_proof', 'The latest proof of this digest did not pass');
        e.proposal = {
          action: action as 'activate',
          version: v.version,
          digest: v.digest,
          by: deps.who(),
          at: stamp(),
          proofId: proof.id,
        };
        record(e, 'proposed', `Proposed: ${action} version ${v.version}`, v.version);
        return HttpResponse.json(describe(e, true));
      }),
      http.post(`${BASE}/site-entries/:id/approvals`, async ({ request, params }) => {
        // The trial answers as a demo instance: an approval needs the configure right as well as the approve right (R16)
        const denied = deps.csrf(request) ?? deps.guard('approver') ?? deps.guard('configure');
        if (denied) return denied;
        const e = find(String(params.id));
        if (!e) return fail(404, 'not_found', 'No such site entry');
        const body = (await bodyOf(request)) ?? {};
        const reason = String(body.reason ?? '').trim();
        if (body.decision !== 'approve' && body.decision !== 'reject')
          return fail(400, 'bad_request', 'decision is approve or reject');
        if (!reason) return fail(400, 'bad_request', 'A reason is required');
        const p = e.proposal;
        if (!p) return fail(409, 'wrong_state', `No proposal waits for approval on ${e.id}`);
        if (body.action !== p.action || Number(body.version) !== p.version || body.digest !== p.digest)
          return fail(
            409,
            'digest_mismatch',
            `The proposal is to ${p.action} version ${p.version} with digest ${p.digest}: the action, version and digest sent are not all those`,
          );
        const v = e.versions.find((x) => x.version === p.version)!;
        if (body.decision === 'reject') {
          e.proposal = undefined;
          record(e, 'rejected', `Rejected (${p.action}): ${reason}`, v.version);
          return HttpResponse.json(describe(e, true));
        }
        const me = deps.who();
        // As the core (R6): neither the proposer nor the version's author, for every action, whatever the letter case
        if ([p.by, v.writtenBy].some((who) => who.toUpperCase() === me.toUpperCase()))
          return fail(
            409,
            'same_person',
            `A second person approves a site entry: ${me} proposed this or wrote the version`,
          );
        const again = run(e.id, v.version, v.content, p.action);
        const before = e.proofs.find((x) => x.id === p.proofId);
        if (!again.passed || canonical(again.fixtures) !== canonical(before?.result.fixtures))
          return fail(
            409,
            'proof_failed',
            "The proof run again at approval did not answer as the proposal's did",
            { proof: again },
          );
        if (p.action === 'activate') {
          Object.assign(v, {
            status: 'approved',
            approvedBy: me,
            approvedAt: stamp(),
            reason,
            safetyReference: String(body.safetyReference ?? '') || undefined,
          });
          e.activeVersion = v.version;
          e.draftVersion = 0;
          e.state = 'active';
        } else e.state = p.action === 'retire' ? 'retired' : 'active';
        e.suspended = undefined;
        e.proposal = undefined;
        generation += 1;
        keep(e, v.version, v.digest, p.action, again, 'approval');
        record(e, 'approved', `Approved (${p.action}): ${reason}`, v.version);
        return HttpResponse.json({
          ...describe(e, true),
          catalogueVersion: '',
          approver: me,
          waitingPlans: 0,
        });
      }),
      http.post(`${BASE}/site-entries/:id/suspend`, async ({ request, params }) => {
        const denied = deps.csrf(request) ?? deps.guard('approver') ?? deps.guard('configure');
        if (denied) return denied;
        const e = find(String(params.id));
        if (!e) return fail(404, 'not_found', 'No such site entry');
        const reason = String((await bodyOf(request))?.reason ?? '').trim();
        if (!reason) return fail(400, 'bad_request', 'A reason is required');
        if (e.state !== 'active')
          return fail(409, 'wrong_state', `${e.id} is ${e.state}: only an active entry is suspended`);
        e.state = 'suspended';
        e.suspended = { by: deps.who(), at: stamp(), reason };
        generation += 1;
        record(e, 'suspended', `Suspended: ${reason}`, e.activeVersion);
        return HttpResponse.json(describe(e, true));
      }),
    ],
  };
}
