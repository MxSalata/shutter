import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { api } from '@/api/client';
import type {
  ApprovalsView,
  BlindResendPreview,
  CaseDetail,
  CaseEvent,
  CaseList,
  Closure,
  Costs,
  Escalation,
  LibraryMember,
  Me,
  PlanView,
  PrecedentSummary,
  PrecedentsView,
  ReviewDetail,
  ReviewList,
  ReviewTarget,
  ScenarioList,
  Settings,
  SiteProfileView,
  Snapshot,
} from '@/api/types';
import { isApiError } from '@/lib/errors';
import fixtures from './fixtures.json';
import definitions from '../../../fixtures/scenarios.json';
import { resetMock } from './handlers';
import { HELD_NOTE, REPLAYED_NOTE } from './hold';
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
    expect(events.at(-1)?.text).toBe(HELD_NOTE);
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
    // What the dry run was checked against: the version the recorded resend found; a preview is conditional on none
    const p = r as unknown as BlindResendPreview;
    expect([p.outcome, p.applied, p.expectedVersion]).toEqual(['would_apply', false, null]);
    expect(p.checkedAgainst).toEqual({
      version: (recorded.attempts[0].attempt.response.encounter.version as number) - 1,
      epoch: null,
    });
  });

  it('is abandoned by no one while it waits for its approval: its plan is rejected instead', async () => {
    const busy = await refusal(api.post(`/cases/${HELD}/abandon`, { reason: 'stuck' }));
    expect([busy.status, busy.code]).toEqual([409, 'busy']);
    expect(busy.body).toMatchObject({ state: 'awaiting_approval', inFlight: 1, deferred: true });
    expect((await api.get<CaseDetail>(`/cases/${HELD}`)).state).toBe('awaiting_approval');
    expect((await refusal(api.post(`/cases/${HELD}/abandon`, {}))).status).toBe(400);
    resetMock('operator');
    expect((await refusal(api.post(`/cases/${HELD}/abandon`, { reason: 'stuck' }))).status).toBe(403);
  });

  it('replays the recorded outcome once approved, labelled as a replay', async () => {
    expect(await decide('approve')).toMatchObject({ decision: 'approve', approver: 'approver' });
    const c = await api.get<CaseDetail>(`/cases/${HELD}`);
    expect(c.state).toBe('resolved');
    expect(c.outcome).toBe(recorded.summary.outcome);
    const events = await api.get<CaseEvent[]>(`/cases/${HELD}/events`);
    expect(events).toHaveLength(recorded.events.length + 1);
    expect(events.at(-1)?.text).toBe(`${REPLAYED_NOTE} Approved in the trial by approver.`);
    // The recorded events after the approval request are marked as replayed; the ones before it and the note are not
    const asked = events.findIndex((e) => e.kind === 'state' && e.fromState === 'awaiting_approval');
    expect(asked).toBeGreaterThan(0);
    expect(events.slice(0, asked).some((e) => e.replayed)).toBe(false);
    expect(events.slice(asked, -1).every((e) => e.replayed === true)).toBe(true);
    expect(events.at(-1)?.replayed).toBeUndefined();
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

  it('advance a run file by file while it plays, the step naming the next file', async () => {
    const realNow = Date.now;
    const files = (fixtures.scenarios.find((s) => s.id === 'S15')!.steps as { file?: string }[]).flatMap(
      (s) => (s.file ? [s.file] : []),
    );
    expect(files.length).toBe(3);
    await api.post('/scenarios/S15/run', { mode: 'board' });
    try {
      const each = 8_000 / files.length;
      // Nothing yet: the first file is going out
      let { run } = await api.get<ScenarioList>('/scenarios');
      expect(run).toMatchObject({ state: 'running', files: [], step: `delivering ${files[0]}` });
      // Past the first interval: one file delivered, the second on its way
      Date.now = () => realNow() + each + 100;
      ({ run } = await api.get<ScenarioList>('/scenarios'));
      expect(run).toMatchObject({ state: 'running', files: [files[0]], step: `delivering ${files[1]}` });
      // Past the second: two
      Date.now = () => realNow() + 2 * each + 100;
      ({ run } = await api.get<ScenarioList>('/scenarios'));
      expect(run).toMatchObject({
        state: 'running',
        files: files.slice(0, 2),
        step: `delivering ${files[2]}`,
      });
      // Past the whole run: done, with every file and no step
      Date.now = () => realNow() + 8_000;
      ({ run } = await api.get<ScenarioList>('/scenarios'));
      expect(run).toMatchObject({ state: 'done', files });
      expect(run?.step).toBeUndefined();
    } finally {
      Date.now = realNow;
    }
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
    expect(costs.totals).toEqual({ spentUsd: 0, liveRuns: 0, replayedRuns: runs.length, reviewRuns: 2 });
    expect(costs.byModel.reduce((n, m) => n + m.runs, 0)).toBe(runs.length);
    expect(costs.byModel.every((m) => m.costUsd === 0)).toBe(true);
    expect(costs.byCase.find((c) => c.caseId === HELD)?.runs).toBe(recorded.runs.length);
  });

  it("list the reviews whose agent answered apart from the board's runs, newest first, a replay at no cost", async () => {
    const costs = await api.get<Costs>('/costs');
    expect(costs.byReview).toEqual([
      {
        reviewId: 'PR-000004',
        production: 'Shutter.Production',
        model: 'claude-opus-5-5',
        mode: 'replay',
        costUsd: 0,
        startedAt: '2026-11-02T14:36:56Z',
      },
      {
        reviewId: 'PR-000003',
        production: 'Hospital.Production',
        model: 'claude-opus-5-5',
        mode: 'replay',
        costUsd: 0,
        startedAt: '2026-11-02T14:36:56Z',
      },
    ]);
  });
});

describe('the production reviews', () => {
  beforeEach(() => resetMock('approver'));
  const signIn = (username: string) => api.post('/session', { username, password: 'shutter' });

  it('offer both recorded productions as targets and list their reviews newest first', async () => {
    const { items } = await api.get<{ items: ReviewTarget[] }>('/production-reviews/targets');
    expect(items.map((t) => [t.production, t.own, t.watched])).toEqual([
      ['Shutter.Production', true, false],
      ['Hospital.Production', false, true],
    ]);
    const list = await api.get<ReviewList>('/production-reviews');
    expect(list.items.map((r) => r.reviewId)).toEqual(['PR-000004', 'PR-000003', 'PR-000002', 'PR-000001']);
    const hospital = await api.get<ReviewList>('/production-reviews?namespace=HOSPITAL&limit=1');
    expect(hospital).toEqual({ items: [expect.objectContaining({ reviewId: 'PR-000003' })], total: 2 });
  });

  it('serve a finished review of each production, in baseline order', async () => {
    for (const id of ['PR-000001', 'PR-000003']) {
      const r = await api.get<ReviewDetail>(`/production-reviews/${id}`);
      expect(r.state).toBe('done');
      expect(r.findings.map((f) => f.id)).toEqual(r.findings.map((_, i) => `F${i + 1}`));
    }
    expect((await refusal(api.get('/production-reviews/PR-999999'))).status).toBe(404);
  });

  it('start a review for an operator: sweeping on the first read, then the recorded review under its new id', async () => {
    await signIn('operator');
    const started = await api.post<{ reviewId: string; state: string; requestedBy: string }>(
      '/production-reviews',
      { namespace: 'HOSPITAL', production: 'Hospital.Production', windowDays: 7, agent: false },
    );
    expect(started).toEqual({ reviewId: 'PR-000005', state: 'sweeping', requestedBy: 'operator' });
    const again = await refusal(
      api.post('/production-reviews', { namespace: 'HOSPITAL', production: 'Hospital.Production' }),
    );
    expect([again.status, again.code, (again.body as { reviewId: string }).reviewId]).toEqual([
      409,
      'wrong_state',
      'PR-000005',
    ]);
    const first = await api.get<ReviewDetail>('/production-reviews/PR-000005');
    expect([first.state, first.findings, first.agent.state]).toEqual(['sweeping', [], 'pending']);
    const done = await api.get<ReviewDetail>('/production-reviews/PR-000005');
    expect([done.state, done.agentState, done.findings.length]).toEqual(['done', 'skipped', 7]);
  });

  it('refuse a target the server does not know and a window outside 1 to 90 days', async () => {
    const other = await refusal(
      api.post('/production-reviews', { namespace: 'USER', production: 'Demo.Production' }),
    );
    expect([other.status, other.code]).toEqual([400, 'bad_request']);
    const wide = await refusal(api.post('/production-reviews', { windowDays: 91 }));
    expect([wide.status, wide.code]).toEqual([400, 'bad_request']);
  });

  it('keep annotations to approvers, and the demo refuses them politely', async () => {
    const body = { findingId: 'F2', status: 'intended', reason: 'The feed is watched by hand' };
    const demo = await refusal(api.post('/production-reviews/PR-000001/annotations', body));
    expect([demo.status, demo.code]).toEqual([403, 'demo']);
    expect(demo.detail).toMatch(/^The online demo keeps no annotations\./);
    const unknown = await refusal(
      api.post('/production-reviews/PR-000001/annotations', { ...body, findingId: 'F99' }),
    );
    expect(unknown.status).toBe(404);
    // The recording marks no finding, so there is no annotation to remove
    const removed = await refusal(api.del('/production-reviews/annotations/16'));
    expect([removed.status, removed.code]).toEqual([404, 'not_found']);
    await signIn('operator');
    const operator = await refusal(api.post('/production-reviews/PR-000001/annotations', body));
    expect([operator.status, operator.code]).toEqual([403, 'forbidden']);
  });
});

describe('the roles', () => {
  beforeEach(() => resetMock('approver'));
  const WITHHELD = 'C-000012';

  const signIn = (username: string) => api.post('/session', { username, password: 'shutter' });

  async function twoPersonRule() {
    const view = await api.get<SiteProfileView>('/site-profile');
    const { version: _inner, ...profile } = view.profile;
    await api.put('/site-profile', {
      ...profile,
      approvers: { ...profile.approvers, close_needs_approver: true },
      expectedVersion: view.version,
    });
  }

  it('keep changes to the agent library to an approver', async () => {
    const member = fixtures.library[0];
    resetMock('operator');
    const refused = await refusal(api.patch(`/library/${member.code}`, { sort: member.sort }));
    expect([refused.status, (refused.body as { error: string }).error]).toEqual([403, 'forbidden']);
    resetMock('approver');
    const changed = await api.patch<LibraryMember>(`/library/${member.code}`, { sort: member.sort });
    expect(changed.code).toBe(member.code);
  });

  it('puts the recorded library back on a reset, after a change made here', async () => {
    const member = fixtures.library[0];
    const before = structuredClone(await api.get<LibraryMember[]>('/library'));
    await api.patch<LibraryMember>(`/library/${member.code}`, { enabled: !member.enabled, sort: 99 });
    const changed = (await api.get<LibraryMember[]>('/library')).find((m) => m.code === member.code);
    expect(changed).toMatchObject({ enabled: !before[0].enabled, sort: 99 });
    resetMock('approver');
    expect(await api.get<LibraryMember[]>('/library')).toEqual(before);
  });

  it('let an operator close a case by hand by default, on the record with the reason', async () => {
    resetMock('operator');
    const r = await api.post<{ state: string; requestedBy: string }>(`/cases/${WITHHELD}/close`, {
      reason: 'The PAS team merged the records by hand',
    });
    expect([r.state, r.requestedBy]).toEqual(['closing', 'operator']);
    const c = await api.get<CaseDetail>(`/cases/${WITHHELD}`);
    expect([c.state, c.disposition]).toEqual(['resolved', 'handled_by_hand']);
    expect(c.outcome).toBe('Handled by hand, recorded by operator: The PAS team merged the records by hand');
    const last = (await api.get<CaseEvent[]>(`/cases/${WITHHELD}/events`)).at(-1);
    expect([last?.kind, last?.toState, last?.actor, last?.text]).toEqual([
      'state',
      'resolved',
      'operator',
      'Handled by hand: The PAS team merged the records by hand',
    ]);
    const closure = await api.get<Closure>(`/cases/${WITHHELD}/closure`);
    expect([closure.disposition, closure.actors.includes('operator')]).toEqual(['handled_by_hand', true]);
    expect((await api.get<CaseList>('/cases?state=resolved')).items.map((x) => x.caseId)).toContain(WITHHELD);
  });

  it("need an approver to close a case by hand where the site's two-person rule says so", async () => {
    await twoPersonRule();
    // Signing in again keeps the saved profile, as the demo keeps it until the page is reloaded
    await signIn('operator');
    const refused = await refusal(api.post(`/cases/${WITHHELD}/close`, { reason: 'merged by hand' }));
    expect([refused.status, (refused.body as { error: string }).error]).toEqual([403, 'forbidden']);
    expect((refused.body as { detail: string }).detail).toMatch(/needs an approver/);
    expect((await api.get<CaseDetail>(`/cases/${WITHHELD}`)).state).toBe('escalated');
    await signIn('approver');
    const r = await api.post<{ requestedBy: string }>(`/cases/${WITHHELD}/close`, {
      reason: 'merged by hand',
    });
    expect(r.requestedBy).toBe('approver');
  });

  it('record who queued an escalation, the digest of the text queued, and that it was saved, not delivered', async () => {
    const draft = await api.post<Escalation>(`/cases/${WITHHELD}/escalations`, {});
    const sent = await api.post<Escalation>(`/cases/${WITHHELD}/escalations/${draft.seq}/send`, {
      bodyDigest: draft.bodyDigest,
    });
    // As on an instance with no mail server (v1.53): saved with savedAt, no sentAt
    expect(sent.state).toBe('saved');
    expect(sent.savedAt).toMatch(/Z$/);
    expect(sent.sentAt).toBe('');
    expect(sent.transport).toBe('file');
    const lines = (await api.get<CaseEvent[]>(`/cases/${WITHHELD}/events`))
      .slice(-3)
      .map((e) => [e.actor, e.ref, e.text]);
    expect(lines).toEqual([
      ['approver', 'escalation:1', `Escalation 1 drafted for ${draft.teamName} (${draft.to})`],
      [
        'approver',
        'escalation:1',
        `Escalation 1 queued by approver for ${draft.to}; digest of the text queued ${draft.bodyDigest}`,
      ],
      [
        'system',
        'escalation:1',
        `Escalation 1 saved as an email file, not delivered: ${sent.result}. No mail server is set, so nobody was emailed.`,
      ],
    ]);
    // A saved one can go again, as the server's Queue takes it; a queued or cancelled one can't
    const again = await api.post<Escalation>(`/cases/${WITHHELD}/escalations/${draft.seq}/send`, {
      bodyDigest: draft.bodyDigest,
    });
    expect(again.state).toBe('saved');
  });

  it('refuse a subject with a control character and a field that is not a string', async () => {
    const draft = await api.post<Escalation>(`/cases/${WITHHELD}/escalations`, {});
    const subject = await refusal(
      api.patch(`/cases/${WITHHELD}/escalations/${draft.seq}`, { subject: 'x\r\nBcc: e@evil.com' }),
    );
    expect([subject.status, subject.code, (subject.body as { field: string }).field]).toEqual([
      422,
      'subject_not_allowed',
      'subject',
    ]);
    const twoAts = await refusal(
      api.patch(`/cases/${WITHHELD}/escalations/${draft.seq}`, { to: 'pas@example.nhs.uk@evil.com' }),
    );
    expect([twoAts.status, twoAts.code]).toEqual([422, 'address_not_allowed']);
    const list = await refusal(api.patch(`/cases/${WITHHELD}/escalations/${draft.seq}`, { to: ['x'] }));
    expect([list.status, list.code]).toEqual([400, 'bad_request']);
  });

  it('cancel every pending email at a hand close, and then neither edit nor send one', async () => {
    const a = await api.post<Escalation>(`/cases/${WITHHELD}/escalations`, {});
    await api.post<Escalation>(`/cases/${WITHHELD}/escalations`, {});
    await api.post(`/cases/${WITHHELD}/close`, { reason: 'merged by hand' });
    const emails = await api.get<Escalation[]>(`/cases/${WITHHELD}/escalations`);
    expect(emails.map((e) => e.state)).toEqual(['cancelled', 'cancelled']);
    const last = (await api.get<CaseEvent[]>(`/cases/${WITHHELD}/events`)).at(-1);
    expect(last?.text).toBe(
      'Handled by hand: merged by hand; after escalation 2 to Integration team (draft); 2 pending emails cancelled',
    );
    const edit = await refusal(api.patch(`/cases/${WITHHELD}/escalations/${a.seq}`, { subject: 'x' }));
    expect([edit.status, edit.code]).toEqual([409, 'wrong_state']);
    expect(edit.detail).toMatch(/^The case is resolved; an escalation is edited only while/);
    const send = await refusal(
      api.post(`/cases/${WITHHELD}/escalations/${a.seq}/send`, { bodyDigest: a.bodyDigest }),
    );
    expect([send.status, send.code]).toEqual([409, 'wrong_state']);
    expect(send.detail).toMatch(/^The case is resolved; an escalation is sent only while/);
  });

  it('keep abandoning to cases still in a working state', async () => {
    const closed = await refusal(api.post(`/cases/${WITHHELD}/abandon`, { reason: 'stuck' }));
    expect([closed.status, closed.code]).toEqual([409, 'wrong_state']);
  });
});

describe("the public demo's role", () => {
  const code = async (p: Promise<unknown>) => {
    const e = await refusal(p);
    return [e.status, (e.body as { error: string }).error];
  };

  it('answers /me with what each role may do', async () => {
    const can = async (as: string) => {
      resetMock(as);
      return (await api.get<Me>('/me')).can;
    };
    expect(await can('approver')).toEqual({
      operate: true,
      approve: true,
      configure: true,
      scenarios: true,
      reset: true,
      stopRecovery: true,
      liveAgents: true,
    });
    expect(await can('operator')).toEqual({
      operate: true,
      approve: false,
      configure: false,
      scenarios: true,
      reset: true,
      stopRecovery: true,
      liveAgents: true,
    });
    // The public demo's own user replays, and since 1.4.4 runs the scenarios from their recordings; a judge spends the
    // day's model budget (v1.34) and runs the scenarios, never resetting them (1.4.3)
    expect(await can('demo')).toEqual({
      operate: true,
      approve: true,
      configure: false,
      scenarios: true,
      reset: false,
      liveAgents: false,
    });
    expect(await can('judge')).toEqual({
      operate: true,
      approve: true,
      configure: false,
      scenarios: true,
      reset: false,
      liveAgents: true,
    });
  });

  it('runs a scenario from its recordings, refuses the reset and every change to the site, and still approves', async () => {
    resetMock('demo');
    // Its runs replay the recorded agents (1.4.4): the single investigator has none, so that mode is refused
    const started = await api.post<{ scenario: string; replay: boolean }>('/scenarios/S2/run', {
      mode: 'board',
    });
    expect(started).toMatchObject({ scenario: 'S2', replay: true });
    resetMock('demo');
    expect(await code(api.post('/scenarios/S8/run', { mode: 'single' }))).toEqual([409, 'not_recorded']);
    expect(await code(api.post('/scenarios/reset'))).toEqual([403, 'forbidden']);
    expect(await code(api.patch(`/library/${fixtures.library[0].code}`, { sort: 1 }))).toEqual([
      403,
      'forbidden',
    ]);
    const view = await api.get<SiteProfileView>('/site-profile');
    expect(await code(api.put('/site-profile', { ...view.profile, expectedVersion: view.version }))).toEqual([
      403,
      'forbidden',
    ]);
    const body = { findingId: 'F2', status: 'intended', reason: 'The feed is watched by hand' };
    expect(await code(api.post('/production-reviews/PR-000001/annotations', body))).toEqual([
      403,
      'forbidden',
    ]);
    expect(await code(api.del('/production-reviews/annotations/16'))).toEqual([403, 'forbidden']);
    // It approves, as the approver does
    expect((await decide('approve')).decision).toBe('approve');
  });

  it('lets a judge run a scenario and refuses the judge the reset (1.4.3)', async () => {
    resetMock('judge');
    const started = await api.post<{ scenario: string; replay: boolean }>('/scenarios/S2/run', {
      mode: 'board',
    });
    expect(started).toMatchObject({ scenario: 'S2', replay: false });
    expect(await code(api.post('/scenarios/reset'))).toEqual([403, 'forbidden']);
    resetMock('approver');
  });

  it("keeps today's demo, the approver with every power, for whoever signs in the usual way", async () => {
    resetMock('approver');
    const started = await api.post<{ scenario: string }>('/scenarios/S2/run', { mode: 'board' });
    expect(started.scenario).toBe('S2');
    await api.post('/scenarios/reset');
  });

  it('reports a live hospital in the settings to the demo role alone', async () => {
    resetMock('demo');
    const live = (await api.get<Settings>('/settings')).live;
    expect(live).toMatchObject({ enabled: true, every_minutes: 7 });
    expect(live?.scenarios?.split(',')).toHaveLength(8);
    expect(live?.last_played).toMatchObject({ scenario: 'S2' });
    expect(Date.parse(live?.last_played?.at ?? '')).toBeLessThan(Date.now());
    expect(live?.next?.scenario).toBe('S8');
    expect(Date.parse(live?.next?.at ?? '')).toBeGreaterThan(Date.now());
    // Anyone else reads the recording's: the live hospital off
    resetMock('approver');
    expect((await api.get<Settings>('/settings')).live).toEqual({ enabled: false });
  });
});

describe('the settings', () => {
  beforeEach(() => resetMock('approver'));

  it('say the API mimic is off when the recording does not say', async () => {
    const s = await api.get<Settings>('/settings');
    expect([s.mock, s.mockConfig, s.mockModel]).toEqual([false, '', '']);
    expect(s.agentItems.some((a) => a.answeredBy)).toBe(false);
  });
});

describe('the cases list', () => {
  beforeEach(() => resetMock('approver'));

  it("names who made each case's plan, from the recorded plan", async () => {
    const list = await api.get<CaseList>('/cases');
    const by = Object.fromEntries(list.items.map((c) => [c.caseId, c.planCreatedBy]));
    expect(by['C-000002']).toMatch(/^run:/);
    expect(by['C-000021']).toBe('rules');
    expect(by['C-000028']).toBe('policy:E2');
    // In site-policy mode the catalogue left S8 to the board
    expect(by['C-000033']).toMatch(/^run:/);
    // A withheld merge is the policy's in board mode too
    expect(by['C-000012']).toBe('policy:E14');
  });

  it('serves a page at a time, newest first, with the total of every match', async () => {
    const all = await api.get<CaseList>('/cases');
    expect(all.items).toHaveLength(all.total);
    expect(all.total).toBeGreaterThan(25);
    const first = await api.get<CaseList>('/cases?limit=25');
    expect(first.total).toBe(all.total);
    expect(first.items.map((c) => c.caseId)).toEqual(all.items.slice(0, 25).map((c) => c.caseId));
    const second = await api.get<CaseList>('/cases?limit=25&offset=25');
    expect(second.items.map((c) => c.caseId)).toEqual(all.items.slice(25, 50).map((c) => c.caseId));
    const resolved = await api.get<CaseList>('/cases?state=resolved&limit=1');
    expect(resolved.items).toHaveLength(1);
    expect(resolved.total).toBe(all.items.filter((c) => c.state === 'resolved').length);
  });
});

describe('the precedents', () => {
  beforeEach(() => resetMock('approver'));

  it("are as recorded: the held case's snapshot found none before it, a later case's names the approvals before it", async () => {
    const held = await api.get<Snapshot>(`/cases/${HELD}/snapshot`);
    const none = (held.summary as { precedents: PrecedentSummary }).precedents;
    expect([none.approved, none.rejected, none.lastCaseId, none.windowDays]).toEqual([0, 0, '', 180]);
    expect(none).toEqual((recorded.snapshot.summary as { precedents: unknown }).precedents);
    const later = await api.get<Snapshot>('/cases/C-000009/snapshot');
    expect((later.summary as { precedents: PrecedentSummary }).precedents).toMatchObject({
      approved: 1,
      rejected: 0,
      lastDecision: 'approved',
      lastApprover: 'approver',
      lastCaseId: 'C-000002',
      signature: none.signature,
    });
  });

  it('list for a case the precedents on record when its evidence was collected, never its own or a later one', async () => {
    const view = await api.get<PrecedentsView>(`/cases/${HELD}/precedents`);
    expect(view.receiver).toBe('Downstream Out');
    expect(view.conditions).toMatchObject({ delivery: 'failed', receiver_answer: 'unavailable' });
    expect(view.summary.approved + view.summary.rejected).toBe(0);
    expect(view.precedents).toEqual([]);
    const later = await api.get<PrecedentsView>('/cases/C-000022/precedents');
    expect(later.precedents.map((p) => p.caseId)).toEqual(['C-000015', 'C-000009', 'C-000002']);
    expect(later.summary).toMatchObject({ approved: 3, lastCaseId: 'C-000015' });
    // Every case's list agrees with the summary its snapshot carries
    for (const id of Object.keys(fixtures.cases)) {
      const v = await api.get<PrecedentsView>(`/cases/${id}/precedents`);
      const active = v.precedents.filter((p) => p.active);
      expect([active.filter((p) => p.decision === 'approved').length, active[0]?.caseId ?? ''], id).toEqual([
        v.summary.approved,
        v.summary.lastCaseId,
      ]);
      expect(
        v.precedents.every((p) => p.caseId !== id),
        id,
      ).toBe(true);
    }
    expect((await refusal(api.get('/cases/C-999999/precedents'))).status).toBe(404);
  });

  it('are retired by an approver only, with a reason, and the trial refuses politely to change the record', async () => {
    const none = await refusal(api.post('/precedents/999/retire', { reason: 'tried' }));
    expect([none.status, none.code]).toEqual([404, 'not_found']);
    const kept = await refusal(api.post('/precedents/1/retire', { reason: 'tried' }));
    expect([kept.status, kept.code]).toEqual([403, 'demo']);
    expect(kept.detail).toMatch(/^The trial keeps the recorded precedents as they were\./);
    const why = await refusal(api.post('/precedents/1/retire', { reason: ' ' }));
    expect([why.status, why.code]).toEqual([400, 'bad_request']);
    resetMock('operator');
    const operator = await refusal(api.post('/precedents/1/retire', { reason: 'tried' }));
    expect(operator.status).toBe(403);
    resetMock('approver');
    const forged = await fetch(new URL('/api/shutter/precedents/1/retire', window.location.origin), {
      method: 'POST',
      body: '{}',
    });
    expect(forged.status).toBe(400);
  });
});
