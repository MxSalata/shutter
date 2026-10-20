import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { api } from '@/api/client';
import type {
  ApprovalsView,
  CaseDetail,
  CaseEvent,
  CaseList,
  Closure,
  Costs,
  PlanView,
  ScenarioList,
} from '@/api/types';
import { isApiError } from '@/lib/errors';
import fixtures from './fixtures.json';
import definitions from '../../../fixtures/scenarios.json';
import { resetMock } from './handlers';
import { server } from './node';

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

const HELD = 'C-000002';
const recorded = fixtures.cases[HELD];

async function decide(
  decision: 'approve' | 'reject',
  change: Partial<{ planDigest: string; expectedVersion: number }> = {},
) {
  const c = await api.get<CaseDetail>(`/cases/${HELD}`);
  const view = await api.get<PlanView>(`/cases/${HELD}/plan`);
  return api.post<{ decision: string }>(`/cases/${HELD}/approvals`, {
    decision,
    planDigest: view.plan.digest,
    expectedVersion: c.version,
    comment: 'tried in the demo',
    ...change,
  });
}

async function refusal(p: Promise<unknown>) {
  try {
    await p;
  } catch (e) {
    if (isApiError(e)) return e;
  }
  throw new Error('expected the mock to refuse');
}

describe('the held case', () => {
  beforeEach(() => resetMock('approver'));

  it('waits for an approver, with its plan and rehearsal and none of what came after', async () => {
    const c = await api.get<CaseDetail>(`/cases/${HELD}`);
    expect(c.state).toBe('awaiting_approval');
    expect(c.closedAt).toBe('');
    const events = await api.get<CaseEvent[]>(`/cases/${HELD}/events`);
    expect(events.some((e) => e.toState === 'approved')).toBe(false);
    expect(events.some((e) => e.toState === 'awaiting_approval')).toBe(true);
    expect(events.at(-1)?.text).toMatch(/^Demo replay: /);
    // One version per state change, as the store counts them
    expect(c.version).toBe(events.filter((e) => e.kind === 'state').length);
    const approvals = await api.get<ApprovalsView>(`/cases/${HELD}/approvals`);
    expect(approvals.approvals).toEqual([]);
    expect(approvals.tasks.map((t) => t.complete)).toEqual([false]);
    expect(await api.get<unknown[]>(`/cases/${HELD}/attempts`)).toEqual([]);
    expect((await refusal(api.get(`/cases/${HELD}/closure`))).status).toBe(404);
    // The gate's check at dispatch came after the approval
    const plan = await api.get<PlanView>(`/cases/${HELD}/plan`);
    expect(recorded.plan.gateDecisions.map((g) => g.stage)).toContain('dispatch');
    expect(plan.gateDecisions.map((g) => g.stage)).toEqual(['proposal']);
    const list = await api.get<CaseList>('/cases?state=awaiting_approval');
    expect(list.items.map((x) => x.caseId)).toEqual([HELD]);
  });

  it('answers the blind-resend preview from the recorded resend', async () => {
    const r = await api.post<{ wouldApply: boolean; encounterAfter: { ward?: string } | null }>(
      `/cases/${HELD}/preview-blind-resend`,
    );
    expect(r.wouldApply).toBe(true);
    expect(r.encounterAfter?.ward).toBe('WARD-B');
  });

  it('replays the recorded outcome once approved, labelled as a replay', async () => {
    expect((await decide('approve')).decision).toBe('approve');
    const c = await api.get<CaseDetail>(`/cases/${HELD}`);
    expect(c.state).toBe('resolved');
    expect(c.outcome).toBe(recorded.summary.outcome);
    const events = await api.get<CaseEvent[]>(`/cases/${HELD}/events`);
    expect(events).toHaveLength(recorded.events.length + 1);
    expect(events.at(-1)?.text).toMatch(/^Demo replay: approved in the browser by approver/);
    expect(await api.get<unknown[]>(`/cases/${HELD}/attempts`)).toHaveLength(recorded.attempts.length);
    expect((await refusal(decide('approve'))).status).toBe(409);
  });

  it('closes it as blocked when rejected', async () => {
    await decide('reject');
    const c = await api.get<CaseDetail>(`/cases/${HELD}`);
    expect(c.state).toBe('blocked');
    expect(c.headline).toMatch(/^Rejected by approver: /);
    const approvals = await api.get<ApprovalsView>(`/cases/${HELD}/approvals`);
    expect(approvals.approvals.map((a) => [a.decision, a.comment])).toEqual([
      ['rejected', 'tried in the demo'],
    ]);
    expect(await api.get<unknown[]>(`/cases/${HELD}/attempts`)).toEqual([]);
    const plan = await api.get<PlanView>(`/cases/${HELD}/plan`);
    expect(plan.gateDecisions.map((g) => g.stage)).toEqual(['proposal']);
    // As the server answers: the approver's rejection from the catalogue, and a closure with no verification
    const reason = await api.get<{ code: string; catalogue: { title: string }; failingChecks: unknown[] }>(
      `/cases/${HELD}/blocked-reason`,
    );
    expect(reason.code).toBe('REJECTED_BY_APPROVER');
    expect(reason.catalogue.title).toBe('The approver rejected the plan');
    expect(reason.failingChecks).toEqual([]);
    const closure = await api.get<Closure & { state: string }>(`/cases/${HELD}/closure`);
    expect([closure.state, closure.disposition, closure.verification]).toEqual(['blocked', 'resend', null]);
    expect(closure.actors).toContain('approver');
    expect(closure.unverified).toHaveLength(1);
  });

  it('binds the decision to the plan digest and the case version', async () => {
    const digest = await refusal(decide('approve', { planDigest: 'sha256:0000' }));
    expect([digest.status, (digest.body as { error: string }).error]).toEqual([409, 'stale_version']);
    const version = await refusal(decide('approve', { expectedVersion: 1 }));
    expect([version.status, (version.body as { error: string }).error]).toEqual([409, 'stale_version']);
    expect((await api.get<CaseDetail>(`/cases/${HELD}`)).state).toBe('awaiting_approval');
  });

  it('needs the approver role', async () => {
    resetMock('operator');
    expect((await refusal(decide('approve'))).status).toBe(403);
  });

  it('waits again when its scenario is played again in its mode', async () => {
    await decide('approve');
    await api.post('/scenarios/S2/run', { mode: 'rules' });
    expect((await api.get<CaseDetail>(`/cases/${HELD}`)).state).toBe('resolved');
    resetMock('approver');
    await decide('approve');
    await api.post('/scenarios/S2/run', { mode: 'board' });
    expect((await api.get<CaseDetail>(`/cases/${HELD}`)).state).toBe('awaiting_approval');
  });

  it('forgets a hand closure and its emails when it waits again', async () => {
    await decide('reject');
    await api.post(`/cases/${HELD}/close`, { reason: 'corrected at the ward' });
    expect((await api.get<CaseDetail>(`/cases/${HELD}`)).disposition).toBe('handled_by_hand');
    await api.post('/scenarios/S2/run', { mode: 'board' });
    const c = await api.get<CaseDetail>(`/cases/${HELD}`);
    expect([c.state, c.disposition]).toEqual(['awaiting_approval', recorded.summary.disposition]);
    expect(await api.get<unknown[]>(`/cases/${HELD}/escalations`)).toEqual([]);
    expect((await decide('approve')).decision).toBe('approve');
  });

  it('leaves the other recorded cases as they were recorded', async () => {
    const c = await api.get<CaseDetail>('/cases/C-000009');
    expect(c).toEqual(fixtures.cases['C-000009'].detail);
  });
});

describe('the scenarios', () => {
  beforeEach(() => resetMock('approver'));

  it('name the modes the scenario definitions restrict them to', async () => {
    const { scenarios } = await api.get<ScenarioList>('/scenarios');
    const s7 = scenarios.find((s) => s.id === 'S7');
    expect(s7?.expected.modes).toEqual(definitions.find((d) => d.id === 'S7')?.expected.modes);
    expect(s7?.expected.modes).not.toContain('policy');
    expect(scenarios.find((s) => s.id === 'S2')?.expected.modes).toBeUndefined();
  });

  it("report the files the scenario's steps deliver once a run is done", async () => {
    const realNow = Date.now;
    await api.post('/scenarios/S15/run', { mode: 'board' });
    try {
      Date.now = () => realNow() + 60_000;
      const { run } = await api.get<ScenarioList>('/scenarios');
      const steps = fixtures.scenarios.find((s) => s.id === 'S15')!.steps as { file?: string }[];
      expect(run?.state).toBe('done');
      expect(run?.files).toEqual(steps.flatMap((s) => (s.file ? [s.file] : [])));
      expect(run?.files.some((f) => f.includes('A40'))).toBe(true);
    } finally {
      Date.now = realNow;
    }
  });
});

describe('the costs', () => {
  beforeEach(() => resetMock('approver'));

  it('are summed from the recorded runs when the recording has none, a replay at no cost', async () => {
    const costs = await api.get<Costs>('/costs');
    const runs = Object.values(fixtures.cases).flatMap((c) => (c.runs ?? []) as unknown[]);
    expect(costs.totals).toEqual({ spentUsd: 0, liveRuns: 0, replayedRuns: runs.length });
    expect(costs.byModel.reduce((n, m) => n + m.runs, 0)).toBe(runs.length);
    expect(costs.byModel.every((m) => m.costUsd === 0)).toBe(true);
    expect(costs.byCase.find((c) => c.caseId === HELD)?.runs).toBe(recorded.runs.length);
  });
});
