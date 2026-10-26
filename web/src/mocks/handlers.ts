import { delay, http, HttpResponse } from 'msw';
import fixtures from './fixtures.json';
import definitions from '../../../fixtures/scenarios.json';
import type {
  AgentRun,
  ApprovalDecision,
  AskQuestion,
  CaseQuestion,
  CaseState,
  Costs,
  Escalation,
  IncidentDetail,
  IncidentEvent,
  IncidentSummary,
  Me,
  ReviewAgent,
  ReviewDetail,
  ReviewListItem,
  ReviewTarget,
  ScenarioRun,
  SiteProfile,
  SiteProfileVersionEntry,
  SiteProfileView,
} from '@/api/types';
import {
  addressesProblem,
  closeNeedsApprover,
  controlProblem,
  validateProfile,
} from '@/features/site-profile/profile';
import { digest, draftEscalation, teamFor } from './escalation';
import { freshHolds, heldView, type CaseFixture, type Hold } from './hold';
import { recordedSiteProfile, recordedSiteProfileHistory } from './profile';
import { resetQuestionIds, sampleQuestion, startingQuestions, suggestedFor, whatIfFor } from './questions';

/**
 * An in-browser stand-in for Shutter's REST API (CONTRACTS 5), for the demo build, development
 * (`VITE_MOCK=1 npm run dev`) and the tests. It serves answers recorded from the real API (scripts/record-demo.mjs;
 * fixtures.json says when); playing a scenario only pretends. One recorded case is held at its approval (hold.ts), so
 * that a decision can be tried: approving it replays the recorded outcome.
 */
const BASE = '/api/shutter';
const cases = fixtures.cases as unknown as Record<string, CaseFixture>;
interface IncidentFixture {
  summary: IncidentSummary;
  detail: IncidentDetail;
  events: IncidentEvent[];
}
/** Recorded incidents (S11 and S12); a recording from before the incident routes has none. */
const incidents = (fixtures as unknown as { incidents?: Record<string, IncidentFixture> }).incidents ?? {};
interface ReviewFixtures {
  targets: ReviewTarget[];
  list: ReviewListItem[];
  reviews: Record<string, ReviewDetail>;
}
/** Recorded production reviews (CONTRACTS 13): the targets, the list and each review as GET returned it. */
const recordedReviews: ReviewFixtures = (fixtures as unknown as { productionReviews?: ReviewFixtures })
  .productionReviews ?? { targets: [], list: [], reviews: {} };

const USERS: Record<string, Me> = {
  operator: { username: 'operator', operator: true, approver: false },
  approver: { username: 'approver', operator: true, approver: true },
};

let session: Me | null = null;
let run: ScenarioRun | null = null;
/** The mode each scenario was last played in here: a real run opens a case in that mode, which its card then shows. */
let played: Record<string, string> = {};
/** The cases held at their approval, and what was decided on them here. */
let holds: Record<string, Hold> = freshHolds(cases);

/** A case as the demo shows it now: the recording, or the held case's view of it, with what was done to it here. */
const caseOf = (id: string): CaseFixture | undefined =>
  cases[id] ? doneHere(id, heldView(cases[id], holds[id])) : undefined;
const allCases = () => Object.keys(cases).map((id) => caseOf(id)!);
const stamp = () => new Date().toISOString().replace(/\.\d+Z$/, 'Z');

/** The recorded site profile and its versions; a save in the demo changes these until the page is reloaded. */
let siteProfile: SiteProfileView | null = null;
let siteProfileHistory: SiteProfileVersionEntry[] = [];
function resetSiteProfile() {
  siteProfile = recordedSiteProfile();
  siteProfileHistory = recordedSiteProfileHistory();
}
resetSiteProfile();

/** For tests: start signed in (or not), with no run playing. */
export function resetMock(signedInAs: keyof typeof USERS | null = 'approver') {
  session = signedInAs ? USERS[signedInAs] : null;
  run = null;
  played = {};
  holds = freshHolds(cases);
  resetSiteProfile();
  escalations = {};
  closed = {};
  abandoned = {};
  trail = {};
  startedReviews = {};
  asked = {};
  resetQuestionIds();
}

/**
 * The questions asked about each case here, read on first use: a showcase case starts with its example conversation.
 * The answers are sample data until the re-record (questions.ts).
 */
let asked: Record<string, CaseQuestion[]> = {};
const questionsOf = (id: string) => (asked[id] ??= startingQuestions(id, stamp()));

/** Cases a person closed as handled by hand in the demo, laid over the recorded case when it is read. */
let closed: Record<string, { reason: string; by: string; at: string; version: number }> = {};
/** Cases an approver abandoned in the demo (Case.Abandon), laid over the recorded case the same way. */
let abandoned: Record<string, { reason: string; by: string; at: string; version: number; from: string }> = {};
/** How long a case's workflow must have been quiet before it may be abandoned (abandonAfterMinutes). */
const ABANDON_AFTER_MINUTES = 15;

interface TrailEvent {
  at: string;
  kind: string;
  fromState: string;
  toState: string;
  text: string;
  actor: string;
  ref: string;
}
/** The lines the demo adds to a case's timeline, as the server writes them: escalations drafted and sent, a hand closure. */
let trail: Record<string, TrailEvent[]> = {};
const record = (id: string, line: Partial<TrailEvent> & Pick<TrailEvent, 'kind' | 'text' | 'actor'>) =>
  (trail[id] ??= []).push({ at: stamp(), fromState: '', toState: '', ref: '', ...line });

/**
 * The case with what was done to it in the demo: the trail's lines after the recorded events and, once it was closed
 * by hand, the case, its summary and its closure as the server leaves them (Case.CloseByHand).
 */
function doneHere(id: string, c: CaseFixture): CaseFixture {
  const lines = trail[id] ?? [];
  const close = closed[id];
  const gaveUp = abandoned[id];
  if (!lines.length && !close && !gaveUp) return c;
  const events = c.events as { seq: number }[];
  const last = events.at(-1)?.seq ?? 0;
  const out = { ...c, events: [...events, ...lines.map((e, i) => ({ ...e, seq: last + i + 1 }))] };
  if (gaveUp) {
    const failed = {
      state: 'failed',
      disposition: 'abandoned',
      outcome: `Abandoned, recorded by ${gaveUp.by}: ${gaveUp.reason}. The workflow stopped in ${gaveUp.from}; nothing more is sent`,
      headline: `Abandoned by ${gaveUp.by}. ${gaveUp.reason.slice(0, 200)}`,
      closedAt: gaveUp.at,
      updatedAt: gaveUp.at,
      version: gaveUp.version,
    };
    return {
      ...out,
      summary: { ...c.summary, ...failed },
      detail: { ...c.detail, ...failed },
    } as unknown as CaseFixture;
  }
  if (!close) return out as unknown as CaseFixture;
  const outcome = `Handled by hand, recorded by ${close.by}: ${close.reason}`;
  const handled = {
    state: 'resolved',
    disposition: 'handled_by_hand',
    outcome,
    // Cut at 200 characters as the server cuts it; the page shows a cut headline up to its last whole word
    headline: `Handled by the team. ${close.reason.slice(0, 200)}`,
    closedAt: close.at,
    updatedAt: close.at,
    version: close.version,
  };
  const closure = (c.closure ?? {}) as { actors?: unknown[] };
  return {
    ...out,
    summary: { ...c.summary, ...handled },
    detail: { ...c.detail, ...handled },
    closure: {
      ...closure,
      caseId: id,
      state: 'resolved',
      disposition: 'handled_by_hand',
      outcome,
      closedAt: close.at,
      verifiedEffects: [],
      actors: [...new Set([...(closure.actors ?? []).map(String), close.by])].sort(),
    },
  } as unknown as CaseFixture;
}

/**
 * Reviews started here: the newest recorded review of the same target (with the agent or without, as asked) under a
 * new id, read once as sweeping and then as done. The mock reads no production; the window stays the recording's.
 */
let startedReviews: Record<string, { review: ReviewDetail; reads: number }> = {};
const reviewOf = (id: string): ReviewDetail | undefined =>
  startedReviews[id]?.review ?? recordedReviews.reviews[id];
const allReviews = (): ReviewDetail[] => [
  ...Object.values(recordedReviews.reviews),
  ...Object.values(startedReviews).map((s) => s.review),
];
/** The list's line of a review: the recorded line when there is one (its summary as stored), else from the review. */
const listItemOf = (r: ReviewDetail): ReviewListItem =>
  recordedReviews.list.find((x) => x.reviewId === r.reviewId) ?? {
    reviewId: r.reviewId,
    namespace: r.namespace,
    production: r.production,
    productionState: r.productionState,
    startedAt: r.startedAt,
    finishedAt: r.finishedAt,
    state: r.state,
    agentState: r.agentState,
    summary: r.summary,
    requestedBy: r.requestedBy,
  };
/** What GET answers while the item is still sweeping: no findings yet, and the agent's part empty. */
function sweeping(r: ReviewDetail): ReviewDetail {
  const agent: ReviewAgent = {
    state: 'pending',
    mode: null,
    model: null,
    providerConfig: null,
    costUsd: null,
    promptTokens: null,
    completionTokens: null,
    cacheReadTokens: null,
    cacheCreationTokens: null,
    durationMs: null,
    recordKey: null,
    ensMessageId: null,
    error: '',
    summary: '',
    unknowns: [],
  };
  return {
    ...r,
    state: 'sweeping',
    agentState: 'pending',
    finishedAt: null,
    fingerprint: '',
    summary: {},
    findings: [],
    caseAggregates: {},
    agent,
  };
}
/** The online demo keeps no annotations: it says so, as the server words a refusal. */
const annotationsRefused = () =>
  error(
    403,
    'demo',
    "The online demo keeps no annotations. On an instance an approver's annotation is stored in Shutter, never in the production, and applies to every review of this production until the value changes, it expires or it is removed.",
  );
const ANNOTATION_STATUSES = ['intended', 'accepted_risk', 'false_positive'];
const EXPIRES_AT = /^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}(:\d{2})?Z)?$/;

/** Escalations drafted and sent in the demo, by case: nothing leaves the browser. */
let escalations: Record<string, Escalation[]> = {};

const error = (status: number, code: string, detail: string) =>
  HttpResponse.json({ error: code, detail }, { status });
const signedOut = () => error(401, 'unauthorized', 'Sign in first');
/** As the server answers a subject or a To or Cc it won't send (CONTRACTS 10): 422 naming the field. */
const escalationRefused = (e: Pick<Escalation, 'subject' | 'to' | 'cc'>) => {
  if (controlProblem(e.subject ?? ''))
    return HttpResponse.json(
      {
        error: 'subject_not_allowed',
        field: 'subject',
        detail: 'The subject must not contain line breaks or control characters',
      },
      { status: 422 },
    );
  const domains = siteProfile?.profile.mail?.allowed_domains ?? [];
  for (const field of ['to', 'cc'] as const) {
    const problem = addressesProblem(e[field] ?? '', domains);
    if (problem)
      return HttpResponse.json(
        { error: 'address_not_allowed', field, detail: `The ${field} address is not allowed: ${problem}` },
        { status: 422 },
      );
  }
  return null;
};
/** The case's state as the demo shows it, with a hand close or an abandon laid over the recording. */
const stateOf = (id: string) => caseOf(id)?.summary.state ?? '';
/** An escalation is edited or sent only while its case still stands with the team, as the server refuses it. */
const standsWithTeam = (id: string, verb: 'edited' | 'sent') => {
  const state = stateOf(id);
  return ['blocked', 'escalated', 'failed'].includes(state)
    ? null
    : error(
        409,
        'wrong_state',
        `The case is ${state}; an escalation is ${verb} only while the case is blocked, escalated or failed`,
      );
};
/** Cancel every draft or queued email of a case, as a hand close and an abandon do; how many were cancelled. */
const cancelPending = (id: string) => {
  const pending = (escalations[id] ?? []).filter((x) => x.state === 'draft' || x.state === 'queued');
  for (const x of pending) x.state = 'cancelled';
  return pending.length;
};
const guard = (role: 'operator' | 'approver') =>
  !session ? signedOut() : !session[role] ? error(403, 'forbidden', `Needs the ${role} role`) : null;
const csrf = (request: Request) =>
  request.headers.get('X-Requested-With') === 'Shutter'
    ? null
    : error(400, 'csrf', 'Missing X-Requested-With');

/**
 * The modes a scenario is defined for (expected.modes), from the scenario definitions themselves, so that a recording
 * made before a scenario named its modes still shows which ones it isn't defined for.
 */
const definedModes: Record<string, string[]> = Object.fromEntries(
  (definitions as { id: string; expected: { modes?: string[] } }[]).flatMap((d) =>
    d.expected.modes ? [[d.id, d.expected.modes]] : [],
  ),
);

/**
 * The costs, as the server sums them from the agent runs (CONTRACTS 5): the recorded answer, or, when the recording
 * has none, the same sums over the recorded cases' runs. A replay costs nothing; its tokens are the recorded run's.
 */
function costs(): Costs {
  const answer = fixtures.costs as unknown as Partial<Costs>;
  if (answer.byModel?.length) return answer.byReview ? (answer as Costs) : withReviews(answer as Costs);
  const runs = Object.values(cases).flatMap((c) =>
    ((c.runs ?? []) as unknown as AgentRun[]).map((r) => ({ ...r, caseId: c.summary.caseId })),
  );
  const cost = (r: AgentRun) => (r.mode === 'replay' ? 0 : Number(r.costUsd) || 0);
  const byModel = new Map<string, Costs['byModel'][number]>();
  const byDay = new Map<string, Costs['byDay'][number]>();
  const byCase = new Map<string, Costs['byCase'][number]>();
  for (const r of runs) {
    const replayed = r.mode === 'replay' ? 1 : 0;
    const m = byModel.get(`${r.model}|${r.mode}`) ?? {
      model: r.model,
      mode: r.mode,
      runs: 0,
      promptTokens: 0,
      completionTokens: 0,
      cacheReadTokens: 0,
      costUsd: 0,
    };
    m.runs += 1;
    m.promptTokens += Number(r.promptTokens) || 0;
    m.completionTokens += Number(r.completionTokens) || 0;
    m.cacheReadTokens += Number(r.cacheReadTokens) || 0;
    m.costUsd += cost(r);
    byModel.set(`${r.model}|${r.mode}`, m);
    const day = r.startedAt.slice(0, 10);
    const d = byDay.get(day) ?? { day, runs: 0, replayedRuns: 0, costUsd: 0 };
    d.runs += 1;
    d.replayedRuns = (d.replayedRuns ?? 0) + replayed;
    d.costUsd += cost(r);
    byDay.set(day, d);
    const k = byCase.get(r.caseId) ?? { caseId: r.caseId, runs: 0, replayedRuns: 0, costUsd: 0 };
    k.runs += 1;
    k.replayedRuns = (k.replayedRuns ?? 0) + replayed;
    k.costUsd += cost(r);
    byCase.set(r.caseId, k);
  }
  const replayedRuns = runs.filter((r) => r.mode === 'replay').length;
  return withReviews({
    totals: {
      spentUsd: runs.reduce((sum, r) => sum + cost(r), 0),
      liveRuns: runs.length - replayedRuns,
      replayedRuns,
    },
    byModel: [...byModel.values()].sort((a, b) =>
      `${a.model}|${a.mode}`.localeCompare(`${b.model}|${b.mode}`),
    ),
    byDay: [...byDay.values()].sort((a, b) => a.day.localeCompare(b.day)),
    byCase: [...byCase.values()].sort((a, b) => b.caseId.localeCompare(a.caseId)),
  });
}

/**
 * The reviews' agent runs added as the route adds them: the reviews whose agent answered, in any mode (a mode is set),
 * newest first; spentUsd includes their live cost, and a replay spends nothing.
 */
function withReviews(c: Costs): Costs {
  const answered = allReviews()
    .filter((r) => r.agent.mode)
    .sort((a, b) => b.startedAt.localeCompare(a.startedAt) || b.reviewId.localeCompare(a.reviewId));
  const byReview = answered.map((r) => ({
    reviewId: r.reviewId,
    production: r.production,
    model: r.agent.model ?? '',
    mode: r.agent.mode ?? '',
    costUsd: r.agent.mode === 'replay' ? 0 : Number(r.agent.costUsd) || 0,
    startedAt: r.startedAt,
  }));
  const spent = byReview.reduce((sum, r) => sum + r.costUsd, 0);
  const totals = c.totals ?? { spentUsd: 0, liveRuns: 0, replayedRuns: 0 };
  return {
    ...c,
    totals: { ...totals, spentUsd: totals.spentUsd + spent, reviewRuns: answered.length },
    byReview,
  };
}

/** Who made the case's current plan (its `createdBy`: run:<id>, policy:<entry>, rules or withheld), for the list's summary. */
function planOrigin(c: CaseFixture): { planCreatedBy?: string } {
  const by = (c.plan as { plan?: { createdBy?: string } } | null)?.plan?.createdBy;
  return by ? { planCreatedBy: by } : {};
}

/** The list's writes and latest verification, from the recorded attempts, as the API's summary counts them. */
function writesOf(c: CaseFixture): { writes: number; verification: string } {
  const rows = (c.attempts ?? []) as {
    attempt?: { outcome?: string } | null;
    verification?: { outcome?: string } | null;
  }[];
  const writes = rows.filter((r) =>
    ['applied', 'already_committed', 'uncertain'].includes(r.attempt?.outcome ?? ''),
  );
  const latest = [...rows].reverse().find((r) => r.verification)?.verification?.outcome ?? '';
  return { writes: writes.length, verification: latest };
}

/** The HL7 files a scenario delivers, in order, as its steps name them. */
function filesOf(scenario: string): string[] {
  const steps = fixtures.scenarios.find((s) => s.id === scenario)?.steps ?? [];
  return steps.flatMap((step) => ('file' in step && step.file ? [String(step.file)] : []));
}

/** The scenario's latest recorded case in the mode it was last played in (the board's until then), else any. */
function latestCase(scenario: string) {
  const mode = played[scenario] ?? 'board';
  const all = allCases()
    .filter((x) => x.summary.scenario === scenario)
    .sort((a, b) => b.summary.openedAt.localeCompare(a.summary.openedAt));
  const c = all.find((x) => x.summary.mode === mode) ?? all[0];
  return c
    ? {
        caseId: c.summary.caseId,
        state: c.summary.state as CaseState,
        disposition: c.summary.disposition,
        headline: c.summary.headline,
      }
    : null;
}

function part(caseId: string, pick: (c: CaseFixture) => unknown, missing: string) {
  const c = caseOf(caseId);
  if (!session) return signedOut();
  if (!c) return error(404, 'not_found', `No case ${caseId}`);
  const value = pick(c);
  return value === null || value === undefined
    ? error(404, missing, `No ${missing.replace('no_', '')} for ${caseId}`)
    : HttpResponse.json(value as object);
}

function incidentPart(id: string, pick: (i: IncidentFixture) => unknown) {
  if (!session) return signedOut();
  const i = incidents[id];
  return i ? HttpResponse.json(pick(i) as object) : error(404, 'not_found', `No incident ${id}`);
}

/** As the API decides (CONTRACTS 7.5): the plan's digest must match, and something must await this approval. */
async function decideIncident(request: Request, id: string, seq: number | null) {
  const denied = csrf(request) ?? guard('approver');
  if (denied) return denied;
  const i = incidents[id];
  if (!i) return error(404, 'not_found', `No incident ${id}`);
  const body = (await request.json()) as { decision?: string; planDigest?: string };
  if (body.decision !== 'approve' && body.decision !== 'reject')
    return error(400, 'bad_request', 'decision must be approve or reject');
  if (i.detail.state === 'closed') return error(409, 'wrong_state', 'The incident is closed');
  const waiting = i.detail.chains.filter((c) =>
    seq === null
      ? c.state === 'awaiting_approval' && c.policy === 'approval'
      : c.seq === seq && c.state === 'awaiting_approval' && c.policy === 'per_chain',
  );
  if (!waiting.length) return error(409, 'wrong_state', `Nothing of ${id} awaits this approval`);
  if (body.planDigest !== i.detail.planDigest)
    return error(409, 'plan_changed', "planDigest is not the incident plan's digest");
  return HttpResponse.json(
    {
      taskId: '1',
      decision: body.decision,
      incidentId: id,
      ...(seq === null ? {} : { chainSeq: seq }),
      approver: session!.username,
    },
    { status: 202 },
  );
}

export const handlers = [
  http.post(`${BASE}/session`, async ({ request }) => {
    const bad = csrf(request);
    if (bad) return bad;
    const body = (await request.json()) as { username?: string; password?: string };
    const user = USERS[body.username ?? ''];
    if (!user || body.password !== 'shutter')
      return error(401, 'unauthorized', 'Wrong user name or password');
    session = user;
    return HttpResponse.json(user);
  }),
  http.delete(`${BASE}/session`, () => {
    session = null;
    return new HttpResponse(null, { status: 204 });
  }),
  http.get(`${BASE}/me`, () => (session ? HttpResponse.json(session) : signedOut())),

  http.get(`${BASE}/scenarios`, () => {
    if (!session) return signedOut();
    if (run?.state === 'running' && Date.now() - Date.parse(run.startedAt) > 8_000)
      run = {
        ...run,
        state: 'done',
        finishedAt: new Date().toISOString(),
        step: undefined,
        files: filesOf(run.scenario),
      };
    return HttpResponse.json({
      scenarios: fixtures.scenarios.map((s) => ({
        ...s,
        expected: { ...s.expected, ...(definedModes[s.id] ? { modes: definedModes[s.id] } : {}) },
        latestCase: latestCase(s.id),
      })),
      run,
    });
  }),
  http.post(`${BASE}/scenarios/:id/run`, async ({ request, params }) => {
    const denied = csrf(request) ?? guard('operator');
    if (denied) return denied;
    if (run?.state === 'running')
      return error(409, 'wrong_state', `A run of ${run.scenario} is still playing`);
    const { mode } = (await request.json()) as { mode: ScenarioRun['mode'] };
    played[String(params.id)] = mode;
    // Playing it again opens the case again: a held case of the scenario in this mode waits for its approval anew
    for (const [id, hold] of Object.entries(freshHolds(cases)))
      if (cases[id].summary.scenario === params.id && cases[id].summary.mode === mode) {
        holds[id] = hold;
        delete closed[id];
        delete abandoned[id];
        delete escalations[id];
        delete trail[id];
      }
    run = {
      scenario: String(params.id),
      mode,
      startedAt: new Date().toISOString(),
      state: 'running',
      files: [],
      timeouts: [],
      step: 'delivering the first file',
    };
    await delay(300);
    return HttpResponse.json(
      { scenario: run.scenario, mode, startedAt: run.startedAt, files: [] },
      { status: 202 },
    );
  }),
  http.post(
    `${BASE}/scenarios/reset`,
    ({ request }) =>
      csrf(request) ??
      guard('operator') ??
      HttpResponse.json({ reset: true, resetAt: new Date().toISOString() }),
  ),

  http.get(`${BASE}/cases`, ({ request }) => {
    if (!session) return signedOut();
    const url = new URL(request.url);
    const state = url.searchParams.get('state');
    const scenario = url.searchParams.get('scenario');
    // The list names who made each case's current plan, from the recorded plan, as the API's summary does
    const items = allCases()
      .map((c) => ({ ...c.summary, ...planOrigin(c), ...writesOf(c) }))
      .filter((c) => (!state || c.state === state) && (!scenario || c.scenario === scenario))
      .sort((a, b) => b.openedAt.localeCompare(a.openedAt));
    return HttpResponse.json({ items, total: items.length });
  }),
  http.get(`${BASE}/cases/:id`, ({ params }) => part(String(params.id), (c) => c.detail, 'not_found')),
  http.get(`${BASE}/cases/:id/events`, ({ params }) => part(String(params.id), (c) => c.events, 'not_found')),
  http.get(`${BASE}/cases/:id/snapshot`, ({ params }) =>
    part(String(params.id), (c) => c.snapshot, 'no_snapshot'),
  ),
  http.get(`${BASE}/cases/:id/runs`, ({ params }) => part(String(params.id), (c) => c.runs, 'not_found')),
  http.get(`${BASE}/cases/:id/plan`, ({ params }) => part(String(params.id), (c) => c.plan, 'no_plan')),
  http.get(`${BASE}/cases/:id/approvals`, ({ params }) =>
    part(String(params.id), (c) => c.approvals, 'not_found'),
  ),
  http.get(`${BASE}/cases/:id/attempts`, ({ params }) =>
    part(String(params.id), (c) => c.attempts, 'not_found'),
  ),
  http.get(`${BASE}/cases/:id/closure`, ({ params }) =>
    part(String(params.id), (c) => c.closure, 'no_closure'),
  ),
  http.get(`${BASE}/cases/:id/blocked-reason`, ({ params }) =>
    part(String(params.id), (c) => c.blockedReason, 'no_blocked_reason'),
  ),
  // As the server decides (CONTRACTS 5.3): the plan's digest and the case's version must still match
  http.post(`${BASE}/cases/:id/approvals`, async ({ request, params }) => {
    const denied = csrf(request) ?? guard('approver');
    if (denied) return denied;
    const id = String(params.id);
    const c = caseOf(id);
    if (!c) return error(404, 'not_found', 'No such case');
    const body = (await request.json().catch(() => null)) as Partial<ApprovalDecision> | null;
    if (body?.decision !== 'approve' && body?.decision !== 'reject')
      return error(400, 'bad_request', 'decision must be approve or reject');
    if (c.summary.state !== 'awaiting_approval')
      return error(409, 'wrong_state', `The case is ${c.summary.state}, not awaiting approval`);
    const digest = (c.plan as { plan?: { digest?: string } } | null)?.plan?.digest;
    if (body.planDigest !== digest)
      return HttpResponse.json(
        {
          error: 'stale_version',
          detail: "planDigest is not the current plan's digest",
          currentDigest: digest,
        },
        { status: 409 },
      );
    if (Number(body.expectedVersion) !== c.detail.version)
      return HttpResponse.json(
        {
          error: 'stale_version',
          detail: "expectedVersion is not the case's version",
          currentVersion: c.detail.version,
        },
        { status: 409 },
      );
    holds[id] = {
      state: body.decision === 'approve' ? 'approved' : 'rejected',
      by: session!.username,
      at: stamp(),
      comment: body.comment ?? '',
    };
    const task = (c.approvals as { tasks?: { taskId?: string }[] }).tasks?.[0];
    return HttpResponse.json(
      { taskId: task?.taskId ?? '1', decision: body.decision, caseId: id, approver: session!.username },
      { status: 202 },
    );
  }),
  http.post(`${BASE}/cases/:id/reinvestigate`, ({ request, params }) => {
    const denied = csrf(request) ?? guard('operator');
    if (denied) return denied;
    const c = caseOf(String(params.id));
    if (!c) return error(404, 'not_found', 'No such case');
    if (!['blocked', 'escalated', 'failed'].includes(c.summary.state))
      return error(409, 'wrong_state', `The case is ${c.summary.state}`);
    return HttpResponse.json({ caseId: String(params.id), state: 'reopening' }, { status: 202 });
  }),
  // A case the team corrected by hand, closed with the reason (CONTRACTS 5.3, v1.14); an approver's step where the
  // site keeps the two-person rule (v1.17)
  http.post(`${BASE}/cases/:id/close`, async ({ request, params }) => {
    const denied = csrf(request) ?? guard('operator');
    if (denied) return denied;
    if (closeNeedsApprover(siteProfile?.profile) && !session!.approver)
      return error(
        403,
        'forbidden',
        "On this site closing a case by hand needs an approver (the site profile's approvers.close_needs_approver): ask an approver to mark it handled",
      );
    const id = String(params.id);
    const c = caseOf(id);
    if (!c) return error(404, 'not_found', 'No such case');
    const body = (await request.json().catch(() => null)) as {
      reason?: string;
      expectedVersion?: number;
    } | null;
    if (!body || typeof body !== 'object' || !body.reason?.trim())
      return error(400, 'bad_request', 'reason: say what the team did');
    if (closed[id] || !['blocked', 'escalated', 'failed'].includes(c.summary.state))
      return error(409, 'wrong_state', `The case is ${closed[id] ? 'resolved' : c.summary.state}`);
    const version = (c.detail as { version?: number }).version;
    if (body.expectedVersion !== undefined && body.expectedVersion !== version)
      return HttpResponse.json(
        { error: 'stale_version', detail: 'The case changed since it was read', currentVersion: version },
        { status: 409 },
      );
    // The latest email the team worked from is named, and every one not yet sent is cancelled: the team is not asked
    // to correct a case already handled
    const latest = (escalations[id] ?? []).at(-1);
    let followed = latest
      ? `; after escalation ${latest.seq}${latest.teamName ? ` to ${latest.teamName}` : ''} (${latest.state})`
      : '';
    const cancelled = cancelPending(id);
    if (cancelled) followed += `; ${cancelled} pending email${cancelled === 1 ? '' : 's'} cancelled`;
    const reason = body.reason.trim();
    closed[id] = { reason, by: session!.username, at: stamp(), version: (version ?? 0) + 1 };
    record(id, {
      kind: 'state',
      fromState: c.summary.state,
      toState: 'resolved',
      text: `Handled by hand: ${reason}${followed}`,
      actor: session!.username,
      ref: latest ? `escalation:${latest.seq}` : '',
    });
    return HttpResponse.json(
      { caseId: id, state: 'closing', requestedBy: session!.username, reason: body.reason },
      { status: 202 },
    );
  }),
  // Abandon a case its workflow left in a working state (CONTRACTS 5): approver only, refused while it is busy
  http.post(`${BASE}/cases/:id/abandon`, async ({ request, params }) => {
    const denied = csrf(request) ?? guard('approver');
    if (denied) return denied;
    const id = String(params.id);
    const c = caseOf(id);
    if (!c) return error(404, 'not_found', `No case ${id}`);
    const body = (await request.json().catch(() => null)) as {
      reason?: unknown;
      expectedVersion?: unknown;
    } | null;
    const reason = typeof body?.reason === 'string' ? body.reason.trim() : '';
    if (!reason) return error(400, 'bad_request', 'reason is required: why the case is given up');
    const version = (c.detail as { version?: number }).version ?? 0;
    if (body?.expectedVersion !== undefined && Number(body.expectedVersion) !== version)
      return HttpResponse.json(
        {
          error: 'stale_version',
          detail: "expectedVersion is not the case's version",
          currentVersion: version,
        },
        { status: 409 },
      );
    const state = c.summary.state;
    if (['resolved', 'blocked', 'escalated', 'failed'].includes(state))
      return error(
        409,
        'wrong_state',
        `The case is ${state}; a closed case is marked handled (POST /cases/${id}/close) or reopened (POST /cases/${id}/reinvestigate), not abandoned`,
      );
    const newestAt = (c.events as { at?: string }[]).reduce((a, e) => (e.at && e.at > a ? e.at : a), '');
    const quiet = newestAt && Date.now() - Date.parse(newestAt) >= ABANDON_AFTER_MINUTES * 60_000;
    // A case held at its approval waits for a person: its plan is rejected instead
    const deferred = state === 'awaiting_approval';
    if (deferred || !quiet)
      return HttpResponse.json(
        {
          error: 'busy',
          detail: deferred
            ? `The case waits for a person: an approval task is open, so reject the plan (POST /cases/${id}/approvals) instead of abandoning the case`
            : `The case's workflow has 1 message in flight (newest ${newestAt}); a case counts as left behind once nothing has moved for ${ABANDON_AFTER_MINUTES} minutes`,
          state,
          inFlight: 1,
          newestAt: newestAt || null,
          deferred,
        },
        { status: 409 },
      );
    const cancelled = cancelPending(id);
    abandoned[id] = { reason, by: session!.username, at: stamp(), version: version + 1, from: state };
    record(id, {
      kind: 'state',
      fromState: state,
      toState: 'failed',
      text: `Abandoned from ${state}: ${reason}${cancelled ? `; ${cancelled} pending email${cancelled === 1 ? '' : 's'} cancelled` : ''}`,
      actor: session!.username,
    });
    return HttpResponse.json(
      { caseId: id, state: 'abandoning', requestedBy: session!.username, reason },
      { status: 202 },
    );
  }),
  http.post(`${BASE}/cases/:id/preview-blind-resend`, ({ request, params }) => {
    const denied = csrf(request) ?? guard('operator');
    if (denied) return denied;
    const id = String(params.id);
    const c = caseOf(id);
    if (!c) return error(404, 'not_found', 'No such case');
    if (['resolved', 'blocked', 'escalated', 'failed'].includes(c.summary.state))
      return error(409, 'wrong_state', 'The case is closed');
    // A held case: what the recorded resend left at the receiver is what sending it again would leave
    type Encounter = { version?: number };
    const sent = (
      cases[id].attempts as {
        attempt?: { response?: { encounter?: Encounter; encounter_before?: Encounter } };
      }[]
    )[0];
    const after = sent?.attempt?.response?.encounter ?? null;
    // The version the dry run would be checked against: the one the recorded resend found
    const before = sent?.attempt?.response?.encounter_before?.version;
    const version =
      typeof before === 'number' ? before : typeof after?.version === 'number' ? after.version - 1 : null;
    return HttpResponse.json({
      wouldApply: true,
      outcome: 'would_apply',
      applied: false,
      reason: '',
      encounterAfter: after,
      checkedAgainst: { version, epoch: null },
      expectedVersion: null,
      note: after
        ? 'Recorded data: the encounter as the recorded resend left it. The demo has no downstream system to ask.'
        : 'Recorded data: no downstream system to ask.',
    });
  }),

  // Asking about a case (the case-chat design): reading needs a session, asking the operator role; nothing is written
  // to the case, the receiver or the profile. A question in the asker's own words runs live only, and the demo has no key.
  http.get(`${BASE}/cases/:id/whatif`, ({ params }) => {
    if (!session) return signedOut();
    const id = String(params.id);
    if (!caseOf(id)) return error(404, 'not_found', `No case ${id}`);
    const w = whatIfFor(id);
    return w ? HttpResponse.json(w) : error(404, 'no_whatif', `No what-if facts for ${id}`);
  }),
  http.get(`${BASE}/cases/:id/questions/suggested`, ({ params }) => {
    if (!session) return signedOut();
    const id = String(params.id);
    if (!caseOf(id)) return error(404, 'not_found', `No case ${id}`);
    const s = suggestedFor(id);
    return s
      ? HttpResponse.json(s)
      : error(404, 'no_questions', `No suggested questions for ${id}'s scenario`);
  }),
  http.get(`${BASE}/cases/:id/questions`, ({ params }) => {
    if (!session) return signedOut();
    const id = String(params.id);
    if (!caseOf(id)) return error(404, 'not_found', `No case ${id}`);
    return HttpResponse.json({ items: questionsOf(id) });
  }),
  http.get(`${BASE}/cases/:id/questions/:qid`, ({ params }) => {
    if (!session) return signedOut();
    const id = String(params.id);
    const q = caseOf(id) ? questionsOf(id).find((x) => x.questionId === params.qid) : undefined;
    return q ? HttpResponse.json(q) : error(404, 'not_found', `No question ${String(params.qid)}`);
  }),
  http.post(`${BASE}/cases/:id/questions`, async ({ request, params }) => {
    const denied = csrf(request) ?? guard('operator');
    if (denied) return denied;
    const id = String(params.id);
    if (!caseOf(id)) return error(404, 'not_found', `No case ${id}`);
    const body = (await request.json()) as Partial<AskQuestion>;
    if (body.tier !== 'explain' && body.tier !== 'board')
      return error(400, 'invalid_request', 'tier must be explain or board');
    if (!body.suggested)
      return error(
        409,
        'live_only',
        'A question in your own words runs live, and no model key is configured here',
      );
    const { conversation, turn } = body.suggested;
    // The turn's tier is the file's: a suggested turn asked in another tier has no recording
    const fileTurn = suggestedFor(id)
      ?.conversations.find((c) => c.id === conversation)
      ?.turns.find((t) => t.turn === turn);
    if (!fileTurn || fileTurn.tier !== body.tier)
      return error(404, 'no_recording', `No recorded answer for ${conversation} turn ${turn}`);
    const list = questionsOf(id);
    const done = list.find((q) => q.conversation === conversation && q.turn === turn);
    if (done) return HttpResponse.json({ questionId: done.questionId, conversation, turn }, { status: 202 });
    const q = sampleQuestion(id, conversation, turn, session!.username, stamp());
    if (!q) return error(404, 'no_recording', `No recorded answer for ${conversation} turn ${turn}`);
    await delay();
    list.push(q);
    return HttpResponse.json({ questionId: q.questionId, conversation, turn }, { status: 202 });
  }),

  http.get(`${BASE}/incidents`, ({ request }) => {
    if (!session) return signedOut();
    const state = new URL(request.url).searchParams.get('state');
    const items = Object.values(incidents)
      .map((i) => i.summary)
      .filter((i) => !state || i.state === state)
      .sort((a, b) => b.openedAt.localeCompare(a.openedAt));
    return HttpResponse.json({ items, total: items.length });
  }),
  http.get(`${BASE}/incidents/:id`, ({ params }) => incidentPart(String(params.id), (i) => i.detail)),
  http.get(`${BASE}/incidents/:id/events`, ({ params }) => incidentPart(String(params.id), (i) => i.events)),
  http.get(`${BASE}/incidents/:id/approvals`, ({ params }) =>
    incidentPart(String(params.id), (i) => i.detail.approvals),
  ),
  http.post(`${BASE}/incidents/:id/approvals`, ({ request, params }) =>
    decideIncident(request, String(params.id), null),
  ),
  http.post(`${BASE}/incidents/:id/chains/:seq/approvals`, ({ request, params }) =>
    decideIncident(request, String(params.id), Number(params.seq)),
  ),

  http.get(`${BASE}/cases/:id/escalations`, ({ params }) =>
    part(String(params.id), () => escalations[String(params.id)] ?? [], 'not_found'),
  ),
  http.post(`${BASE}/cases/:id/escalations`, async ({ request, params }) => {
    const denied = csrf(request) ?? guard('operator');
    if (denied) return denied;
    const id = String(params.id);
    const c = caseOf(id);
    if (!c) return error(404, 'not_found', `No case ${id}`);
    if (!['blocked', 'escalated', 'failed'].includes(c.summary.state))
      return error(
        409,
        'wrong_state',
        `The case is ${c.summary.state}: only a case Shutter stopped is escalated`,
      );
    const { teamId } = ((await request.json().catch(() => ({}))) ?? {}) as { teamId?: string };
    const team = teamFor(
      siteProfile?.profile,
      String((c.detail as { receiver?: string }).receiver ?? ''),
      teamId,
    );
    if (!team) return error(400, 'bad_request', `No team ${teamId} in the site profile`);
    const list = (escalations[id] ??= []);
    const e = draftEscalation(c as never, team, list.length + 1, session!.username);
    list.push(e);
    record(id, {
      kind: 'escalation',
      text: `Escalation ${e.seq} drafted for ${e.teamName || 'a person'} (${e.to ?? ''})`,
      actor: session!.username,
      ref: `escalation:${e.seq}`,
    });
    return HttpResponse.json(e, { status: 201 });
  }),
  http.patch(`${BASE}/cases/:id/escalations/:seq`, async ({ request, params }) => {
    const denied = csrf(request) ?? guard('operator');
    if (denied) return denied;
    const id = String(params.id);
    const e = escalations[id]?.find((x) => x.seq === Number(params.seq));
    if (!e) return error(404, 'not_found', 'No such escalation');
    const standing = standsWithTeam(id, 'edited');
    if (standing) return standing;
    if (e.purgedAt || !['draft', 'failed'].includes(e.state))
      return error(409, 'wrong_state', `The escalation is ${e.purgedAt ? 'purged' : e.state}`);
    const change = (await request.json()) as Record<string, unknown>;
    if (['subject', 'body', 'to', 'cc'].some((f) => f in change && typeof change[f] !== 'string'))
      return error(400, 'bad_request', 'subject, body, to and cc must be strings');
    const next = { ...e, ...(change as Partial<Pick<Escalation, 'subject' | 'body' | 'to' | 'cc'>>) };
    if (!next.to?.trim()) return error(400, 'bad_request', 'to: at least one address');
    const refused = escalationRefused(next);
    if (refused) return refused;
    Object.assign(e, change, { state: 'draft', editedBy: session!.username });
    e.bodyDigest = digest(e.to ?? '', e.cc ?? '', e.subject, e.body);
    return HttpResponse.json(e);
  }),
  http.post(`${BASE}/cases/:id/escalations/:seq/send`, async ({ request, params }) => {
    const denied = csrf(request) ?? guard('operator');
    if (denied) return denied;
    const e = escalations[String(params.id)]?.find((x) => x.seq === Number(params.seq));
    if (!e) return error(404, 'not_found', 'No such escalation');
    const standing = standsWithTeam(String(params.id), 'sent');
    if (standing) return standing;
    if (e.purgedAt) return error(409, 'wrong_state', 'The escalation is purged');
    const { bodyDigest } = (await request.json()) as { bodyDigest?: string };
    if (bodyDigest !== e.bodyDigest)
      return error(409, 'body_changed', "bodyDigest is not the digest of the escalation's current text");
    if (!e.to) return error(409, 'no_recipient', 'The escalation has no recipient');
    // Again at the send: the allowed domains may have changed since the edit
    const refused = escalationRefused(e);
    if (refused) return refused;
    Object.assign(e, {
      state: 'sent',
      sentBy: session!.username,
      sentAt: new Date().toISOString().replace(/\.\d+Z$/, 'Z'),
      transport: 'file',
      result: `Written as ${String(params.id)}-escalation-${e.seq}.eml (the demo sends no email)`,
    });
    record(String(params.id), {
      kind: 'escalation',
      text: `Escalation ${e.seq} sent by ${session!.username} to ${e.to}; digest of the text sent ${e.bodyDigest}`,
      actor: session!.username,
      ref: `escalation:${e.seq}`,
    });
    // The server's mail operation then records the delivery, as the system
    record(String(params.id), {
      kind: 'escalation',
      text: `Escalation ${e.seq} delivered (file): ${e.result}`,
      actor: 'system',
      ref: `escalation:${e.seq}`,
    });
    return HttpResponse.json(e, { status: 202 });
  }),

  http.get(`${BASE}/site-profile`, () =>
    !session
      ? signedOut()
      : siteProfile
        ? HttpResponse.json(siteProfile)
        : error(404, 'not_found', 'No site profile was recorded'),
  ),
  http.get(`${BASE}/site-profile/history`, ({ request }) => {
    if (!session) return signedOut();
    const limit = Number(new URL(request.url).searchParams.get('limit') ?? 50);
    return HttpResponse.json(siteProfileHistory.slice(0, limit));
  }),
  // As the server answers (CONTRACTS 6.4): the whole profile, expectedVersion taken out before the shape check
  http.put(`${BASE}/site-profile`, async ({ request }) => {
    const denied = csrf(request) ?? guard('approver');
    if (denied) return denied;
    if (!siteProfile) return error(404, 'not_found', 'No site profile was recorded');
    let body: unknown;
    try {
      body = await request.json();
    } catch {
      body = null;
    }
    if (!body || typeof body !== 'object' || Array.isArray(body))
      return error(400, 'bad_request', 'The body must be the profile as a JSON object');
    const { expectedVersion, ...profile } = body as SiteProfile & { expectedVersion?: number };
    if (expectedVersion !== undefined && Number(expectedVersion) !== siteProfile.version)
      return HttpResponse.json(
        {
          error: 'stale_version',
          detail: "expectedVersion is not the stored profile's version",
          currentVersion: siteProfile.version,
        },
        { status: 409 },
      );
    const problem = validateProfile(profile);
    if (problem) return error(400, 'bad_request', `The profile is not valid (CONTRACTS 6.4): ${problem}`);
    const version = siteProfile.version + 1;
    const updatedAt = new Date().toISOString().replace(/\.\d+Z$/, 'Z');
    const updatedBy = session?.username ?? '';
    siteProfile = {
      ...siteProfile,
      profile: { ...profile, version },
      version,
      source: 'api',
      updatedAt,
      updatedBy,
    };
    siteProfileHistory.unshift({ version, source: 'api', updatedAt, updatedBy, profile });
    return HttpResponse.json(siteProfile);
  }),

  http.get(`${BASE}/library`, () => (session ? HttpResponse.json(fixtures.library) : signedOut())),
  // Which agents sit on the board is an approver's change (CONTRACTS 5, v1.17)
  http.patch(`${BASE}/library/:code`, async ({ request, params }) => {
    const denied = csrf(request) ?? guard('approver');
    if (denied) return denied;
    const m = fixtures.library.find((x) => x.code === params.code);
    if (!m) return error(404, 'not_found', 'No such member');
    Object.assign(m, (await request.json()) as object);
    return HttpResponse.json(m);
  }),
  // A recording from before the API mimic was reported has no mock fields: the mimic was off
  http.get(`${BASE}/settings`, () =>
    session
      ? HttpResponse.json({ mock: false, mockConfig: '', mockModel: '', ...fixtures.settings })
      : signedOut(),
  ),
  http.get(`${BASE}/costs`, () => (session ? HttpResponse.json(costs()) : signedOut())),

  // The production review (CONTRACTS 13): the recorded reviews of both productions, read only
  http.get(`${BASE}/production-reviews/targets`, () =>
    session ? HttpResponse.json({ items: recordedReviews.targets }) : signedOut(),
  ),
  http.get(`${BASE}/production-reviews`, ({ request }) => {
    if (!session) return signedOut();
    const url = new URL(request.url);
    const namespace = url.searchParams.get('namespace');
    const production = url.searchParams.get('production');
    const limit = Number(url.searchParams.get('limit') ?? 50);
    if (!Number.isInteger(limit) || limit < 1 || limit > 500)
      return error(400, 'bad_request', 'limit must be from 1 to 500');
    const items = allReviews()
      .filter(
        (r) => (!namespace || r.namespace === namespace) && (!production || r.production === production),
      )
      .map((r) => (startedReviews[r.reviewId]?.reads === 0 ? listItemOf(sweeping(r)) : listItemOf(r)))
      .sort((a, b) => b.startedAt.localeCompare(a.startedAt) || b.reviewId.localeCompare(a.reviewId));
    return HttpResponse.json({ items: items.slice(0, limit), total: items.length });
  }),
  http.get(`${BASE}/production-reviews/:id`, ({ params }) => {
    if (!session) return signedOut();
    const id = String(params.id);
    const started = startedReviews[id];
    if (started) return HttpResponse.json(started.reads++ === 0 ? sweeping(started.review) : started.review);
    const r = recordedReviews.reviews[id];
    return r ? HttpResponse.json(r) : error(404, 'not_found', `No review ${id}`);
  }),
  http.post(`${BASE}/production-reviews`, async ({ request }) => {
    const denied = csrf(request) ?? guard('operator');
    if (denied) return denied;
    const body = (await request.json().catch(() => null)) as {
      namespace?: string;
      production?: string;
      windowDays?: number;
      agent?: boolean;
    } | null;
    if (!body || typeof body !== 'object' || Array.isArray(body))
      return error(400, 'bad_request', 'The body must be a JSON object');
    const own = recordedReviews.targets.find((t) => t.own);
    const namespace = body.namespace ?? own?.namespace;
    const production = body.production ?? own?.production;
    const target = recordedReviews.targets.find(
      (t) => t.namespace === namespace && t.production === production,
    );
    if (!target)
      return error(400, 'bad_request', `${production ?? ''} in ${namespace ?? ''} is not a review target`);
    const days = body.windowDays ?? 7;
    if (!Number.isInteger(days) || days < 1 || days > 90)
      return error(400, 'bad_request', 'windowDays must be a whole number from 1 to 90');
    const busy = allReviews().find(
      (r) =>
        r.namespace === namespace && r.production === production && startedReviews[r.reviewId]?.reads === 0,
    );
    if (busy)
      return HttpResponse.json(
        {
          error: 'wrong_state',
          detail: `Review ${busy.reviewId} of ${production} is still sweeping`,
          reviewId: busy.reviewId,
          state: 'sweeping',
        },
        { status: 409 },
      );
    const agent = body.agent ?? true;
    const ofTarget = Object.values(recordedReviews.reviews)
      .filter((r) => r.namespace === namespace && r.production === production)
      .sort((a, b) => b.startedAt.localeCompare(a.startedAt));
    const base = ofTarget.find((r) => (r.agent.state !== 'skipped') === agent) ?? ofTarget[0];
    if (!base) return error(503, 'not_queued', `The demo has no recorded review of ${production}`);
    const last = Math.max(0, ...allReviews().map((r) => Number(r.reviewId.slice(3)) || 0));
    const reviewId = `PR-${String(last + 1).padStart(6, '0')}`;
    const at = stamp();
    startedReviews[reviewId] = {
      review: {
        ...structuredClone(base),
        reviewId,
        startedAt: at,
        finishedAt: at,
        requestedBy: session!.username,
      },
      reads: 0,
    };
    return HttpResponse.json(
      { reviewId, state: 'sweeping', requestedBy: session!.username },
      { status: 202 },
    );
  }),
  http.post(`${BASE}/production-reviews/:id/annotations`, async ({ request, params }) => {
    const denied = csrf(request) ?? guard('approver');
    if (denied) return denied;
    const r = reviewOf(String(params.id));
    if (!r) return error(404, 'not_found', `No review ${String(params.id)}`);
    const body = (await request.json().catch(() => ({}))) as {
      findingId?: string;
      status?: string;
      reason?: string;
      expiresAt?: string;
    };
    if (!r.findings.some((f) => f.id === body.findingId))
      return error(404, 'not_found', `No finding ${body.findingId ?? ''} in ${r.reviewId}`);
    if (!ANNOTATION_STATUSES.includes(body.status ?? ''))
      return error(400, 'bad_request', 'status must be intended, accepted_risk or false_positive');
    if (!body.reason?.trim()) return error(400, 'bad_request', 'A reason is needed');
    if (body.expiresAt && !EXPIRES_AT.test(body.expiresAt))
      return error(400, 'bad_request', 'expiresAt must be an ISO UTC time');
    return annotationsRefused();
  }),
  http.delete(`${BASE}/production-reviews/annotations/:annotationId`, ({ request, params }) => {
    const denied = csrf(request) ?? guard('approver');
    if (denied) return denied;
    const id = String(params.annotationId);
    if (!allReviews().some((r) => r.findings.some((f) => f.annotationId === id)))
      return error(404, 'not_found', `No annotation ${id}`);
    return annotationsRefused();
  }),
  http.get(`${BASE}/health`, () =>
    session ? HttpResponse.json({ recorded: fixtures.source, ...fixtures.health }) : signedOut(),
  ),
];
