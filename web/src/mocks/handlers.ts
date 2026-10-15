import { delay, http, HttpResponse } from 'msw';
import fixtures from './fixtures.json';
import type { CaseState, Me, ScenarioRun } from '@/api/types';

/**
 * An in-browser stand-in for Interlock's REST API (CONTRACTS 5), for development (`VITE_MOCK=1 npm run dev`) and the
 * component tests. Its data was recorded from the store (fixtures.json says from where); playing a scenario only
 * pretends, and a decision is accepted without changing the recorded case.
 */
const BASE = '/api/interlock';
type CaseFixture = (typeof fixtures.cases)[keyof typeof fixtures.cases];
const cases = fixtures.cases as unknown as Record<string, CaseFixture>;

const USERS: Record<string, Me> = {
  operator: { username: 'operator', operator: true, approver: false },
  approver: { username: 'approver', operator: true, approver: true },
};

let session: Me | null = null;
let run: ScenarioRun | null = null;

/** For tests: start signed in (or not), with no run playing. */
export function resetMock(signedInAs: keyof typeof USERS | null = 'approver') {
  session = signedInAs ? USERS[signedInAs] : null;
  run = null;
}

const error = (status: number, code: string, detail: string) =>
  HttpResponse.json({ error: code, detail }, { status });
const signedOut = () => error(401, 'unauthorized', 'Sign in first');
const guard = (role: 'operator' | 'approver') =>
  !session ? signedOut() : !session[role] ? error(403, 'forbidden', `Needs the ${role} role`) : null;
const csrf = (request: Request) =>
  request.headers.get('X-Requested-With') === 'Interlock'
    ? null
    : error(400, 'csrf', 'Missing X-Requested-With');

function latestCase(scenario: string) {
  const c = Object.values(cases).find((x) => x.summary.scenario === scenario);
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

export const handlers = [
  http.post(`${BASE}/session`, async ({ request }) => {
    const bad = csrf(request);
    if (bad) return bad;
    const body = (await request.json()) as { username?: string; password?: string };
    const user = USERS[body.username ?? ''];
    if (!user || body.password !== 'interlock')
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
      note: 'Recorded data: no ward to ask.',
    });
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
  http.get(`${BASE}/settings`, () =>
    session
      ? HttpResponse.json({
          mode: 'board',
          scenario: 'S2',
          resetAt: '2026-10-15T19:37:59Z',
          demo: true,
          agentItems: fixtures.library.map((m) => ({
            name: m.configItem,
            agentClass: m.agentClass,
            mode: 'replay',
            model: 'fixture',
            providerConfig: '',
            maxIterations: 8,
            tokenBudget: 20000,
          })),
          prices: fixtures.prices,
          aiHubPresent: false,
          liveRunnerPresent: false,
        })
      : signedOut(),
  ),
  http.get(`${BASE}/costs`, () =>
    session
      ? HttpResponse.json({
          byModel: [
            {
              model: 'fixture',
              runs: 16,
              promptTokens: 0,
              completionTokens: 0,
              cacheReadTokens: 0,
              costUsd: 0,
            },
          ],
          byDay: [],
          byCase: [],
        })
      : signedOut(),
  ),
  http.get(`${BASE}/health`, () =>
    session ? HttpResponse.json({ source: fixtures.source, ok: true }) : signedOut(),
  ),
];
