import { delay, http, HttpResponse } from 'msw';
import fixtures from './fixtures.json';
import type {
  CaseState,
  Escalation,
  IncidentDetail,
  IncidentEvent,
  IncidentSummary,
  Me,
  ScenarioRun,
  SiteProfile,
  SiteProfileVersionEntry,
  SiteProfileView,
} from '@/api/types';
import { addressesProblem, validateProfile } from '@/features/site-profile/profile';
import { digest, draftEscalation, teamFor } from './escalation';

/**
 * An in-browser stand-in for Shutter's REST API (CONTRACTS 5), for the demo build, development
 * (`VITE_MOCK=1 npm run dev`) and the tests. It serves answers recorded from the real API (scripts/record-demo.mjs;
 * fixtures.json says when); playing a scenario only pretends, and a decision is accepted without changing the
 * recorded case.
 */
const BASE = '/api/shutter';
type CaseFixture = (typeof fixtures.cases)[keyof typeof fixtures.cases];
const cases = fixtures.cases as unknown as Record<string, CaseFixture>;
interface IncidentFixture {
  summary: IncidentSummary;
  detail: IncidentDetail;
  events: IncidentEvent[];
}
/** Recorded incidents (S11 and S12); a recording from before the incident routes has none. */
const incidents = (fixtures as unknown as { incidents?: Record<string, IncidentFixture> }).incidents ?? {};

const USERS: Record<string, Me> = {
  operator: { username: 'operator', operator: true, approver: false },
  approver: { username: 'approver', operator: true, approver: true },
};

let session: Me | null = null;
let run: ScenarioRun | null = null;
/** The mode each scenario was last played in here: a real run opens a case in that mode, which its card then shows. */
let played: Record<string, string> = {};

/** The recorded site profile and its versions; a save in the demo changes these until the page is reloaded. */
const recorded = fixtures as unknown as {
  siteProfile?: SiteProfileView | null;
  siteProfileHistory?: SiteProfileVersionEntry[] | null;
};
let siteProfile: SiteProfileView | null = null;
let siteProfileHistory: SiteProfileVersionEntry[] = [];
function resetSiteProfile() {
  siteProfile = recorded.siteProfile ? structuredClone(recorded.siteProfile) : null;
  siteProfileHistory = structuredClone(recorded.siteProfileHistory ?? []);
}
resetSiteProfile();

/** For tests: start signed in (or not), with no run playing. */
export function resetMock(signedInAs: keyof typeof USERS | null = 'approver') {
  session = signedInAs ? USERS[signedInAs] : null;
  run = null;
  played = {};
  resetSiteProfile();
  escalations = {};
}

/** Escalations drafted and sent in the demo, by case: nothing leaves the browser. */
let escalations: Record<string, Escalation[]> = {};

const error = (status: number, code: string, detail: string) =>
  HttpResponse.json({ error: code, detail }, { status });
const signedOut = () => error(401, 'unauthorized', 'Sign in first');
/** As the server answers a To or Cc it won't send to (CONTRACTS 10): 422 naming the field. */
const addressRefused = (e: Pick<Escalation, 'to' | 'cc'>) => {
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
const guard = (role: 'operator' | 'approver') =>
  !session ? signedOut() : !session[role] ? error(403, 'forbidden', `Needs the ${role} role`) : null;
const csrf = (request: Request) =>
  request.headers.get('X-Requested-With') === 'Shutter'
    ? null
    : error(400, 'csrf', 'Missing X-Requested-With');

/** The scenario's latest recorded case in the mode it was last played in (the board's until then), else any. */
function latestCase(scenario: string) {
  const mode = played[scenario] ?? 'board';
  const all = Object.values(cases)
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
  const c = cases[caseId];
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
    { taskId: '1', decision: body.decision, incidentId: id, ...(seq === null ? {} : { chainSeq: seq }) },
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
        files: [`${run.scenario}-01-A01.hl7`, `${run.scenario}-02-A02.hl7`],
      };
    return HttpResponse.json({
      scenarios: fixtures.scenarios.map((s) => ({ ...s, latestCase: latestCase(s.id) })),
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
    const items = Object.values(cases)
      .map((c) => c.summary)
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
  http.post(`${BASE}/cases/:id/approvals`, ({ request, params }) => {
    const denied = csrf(request) ?? guard('approver');
    if (denied) return denied;
    const c = cases[String(params.id)];
    if (!c) return error(404, 'not_found', 'No such case');
    if (c.summary.state !== 'awaiting_approval')
      return error(409, 'wrong_state', `The case is ${c.summary.state}`);
    return HttpResponse.json({ taskId: '1', decision: 'approve' }, { status: 202 });
  }),
  http.post(`${BASE}/cases/:id/reinvestigate`, ({ request, params }) => {
    const denied = csrf(request) ?? guard('operator');
    if (denied) return denied;
    const c = cases[String(params.id)];
    if (!c) return error(404, 'not_found', 'No such case');
    if (!['blocked', 'escalated', 'failed'].includes(c.summary.state))
      return error(409, 'wrong_state', `The case is ${c.summary.state}`);
    return HttpResponse.json({ caseId: String(params.id), state: 'reopening' }, { status: 202 });
  }),
  http.post(`${BASE}/cases/:id/preview-blind-resend`, ({ request, params }) => {
    const denied = csrf(request) ?? guard('operator');
    if (denied) return denied;
    const c = cases[String(params.id)];
    if (!c) return error(404, 'not_found', 'No such case');
    if (['resolved', 'blocked', 'escalated', 'failed'].includes(c.summary.state))
      return error(409, 'wrong_state', 'The case is closed');
    return HttpResponse.json({
      wouldApply: true,
      reason: '',
      encounterAfter: null,
      note: 'Recorded data: no downstream system to ask.',
    });
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
    const c = cases[id];
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
    return HttpResponse.json(e, { status: 201 });
  }),
  http.patch(`${BASE}/cases/:id/escalations/:seq`, async ({ request, params }) => {
    const denied = csrf(request) ?? guard('operator');
    if (denied) return denied;
    const e = escalations[String(params.id)]?.find((x) => x.seq === Number(params.seq));
    if (!e) return error(404, 'not_found', 'No such escalation');
    if (!['draft', 'failed'].includes(e.state))
      return error(409, 'wrong_state', `The escalation is ${e.state}`);
    const change = (await request.json()) as Pick<Escalation, 'subject' | 'body' | 'to' | 'cc'>;
    if (!change.to?.trim()) return error(400, 'bad_request', 'to: at least one address');
    const refused = addressRefused({ to: change.to, cc: change.cc });
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
    const { bodyDigest } = (await request.json()) as { bodyDigest?: string };
    if (bodyDigest !== e.bodyDigest)
      return error(409, 'body_changed', "bodyDigest is not the digest of the escalation's current text");
    if (!e.to) return error(409, 'no_recipient', 'The escalation has no recipient');
    // Again at the send: the allowed domains may have changed since the edit
    const refused = addressRefused(e);
    if (refused) return refused;
    Object.assign(e, {
      state: 'sent',
      sentBy: session!.username,
      sentAt: new Date().toISOString().replace(/\.\d+Z$/, 'Z'),
      transport: 'file',
      result: `Written as ${String(params.id)}-escalation-${e.seq}.eml (the demo sends no email)`,
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
  http.patch(`${BASE}/library/:code`, async ({ request, params }) => {
    const denied = csrf(request) ?? guard('operator');
    if (denied) return denied;
    const m = fixtures.library.find((x) => x.code === params.code);
    if (!m) return error(404, 'not_found', 'No such member');
    Object.assign(m, (await request.json()) as object);
    return HttpResponse.json(m);
  }),
  http.get(`${BASE}/settings`, () => (session ? HttpResponse.json(fixtures.settings) : signedOut())),
  http.get(`${BASE}/costs`, () => (session ? HttpResponse.json(fixtures.costs) : signedOut())),
  http.get(`${BASE}/health`, () =>
    session ? HttpResponse.json({ recorded: fixtures.source, ...fixtures.health }) : signedOut(),
  ),
];
