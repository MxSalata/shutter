import { MantineProvider } from '@mantine/core';
import { render, screen } from '@testing-library/react';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import { api } from '@/api/client';
import { chooseTransport, resetTransportForTests } from '@/api/transport';
import type {
  CaseDetail,
  CaseEvent,
  Escalation,
  Me,
  PlanView,
  SiteProfileView,
  SuggestedQuestions,
} from '@/api/types';
import { EnvChip } from '@/components/EnvChip';
import { resetMock } from '@/mocks/handlers';
import { theme } from '@/theme';
import { journal } from './journal';
import { createTrialTransport } from './transport';

/**
 * The full trial walk (trial-architecture.md 7, test 6): every action the trial offers, in the order a judge would
 * try them, made through the app's own `request()` exactly as the pages' hooks make it, with `fetch` a spy that
 * fails the walk if it is ever called. The confirms' "Trial only" chip is the shared EnvChip; each page's own confirm
 * wording is its page's test.
 */
vi.mock('@/env/mode', async (importOriginal) => {
  const mode = await importOriginal<typeof import('@/env/mode')>();
  return { ...mode, TRIAL: true, ENV: mode.envFrom('?trial', false) };
});

const sent = vi.fn(() => Promise.reject(new Error('fetch was called from the trial')));
beforeAll(() => {
  vi.stubGlobal('fetch', sent);
  resetTransportForTests();
  chooseTransport(createTrialTransport('approver'));
  journal.clear();
});
afterAll(() => {
  vi.unstubAllGlobals();
  resetTransportForTests();
});

const HELD = 'C-000002';
const WITHHELD = 'C-000012';

async function decide(decision: 'approve' | 'reject') {
  const c = await api.get<CaseDetail>(`/cases/${HELD}`);
  const view = await api.get<PlanView>(`/cases/${HELD}/plan`);
  return api.post<{ decision: string; approver: string }>(
    `/cases/${HELD}/approvals`,
    { decision, planDigest: view.plan.digest, expectedVersion: c.version, comment: 'Tried in the trial' },
    { idempotencyKey: `walk-${decision}` },
  );
}

describe('the trial, walked end to end', () => {
  it('lets a judge do every action it offers, and sends nothing anywhere', async () => {
    // Opens signed in as the approver
    expect(await api.get<Me>('/me')).toMatchObject({ username: 'approver' });

    // Approve the held S2 case: the recording plays forward, each replayed event marked
    expect(await decide('approve')).toMatchObject({ decision: 'approve', approver: 'approver' });
    expect((await api.get<CaseDetail>(`/cases/${HELD}`)).state).toBe('resolved');
    const events = await api.get<CaseEvent[]>(`/cases/${HELD}/events`);
    expect(events.some((e) => e.replayed)).toBe(true);
    expect(events.at(-1)?.text).toMatch(/^Replayed from the recording in the trial/);

    // Reject it instead, on a fresh trial
    resetMock('approver');
    await decide('reject');
    expect((await api.get<CaseDetail>(`/cases/${HELD}`)).state).toBe('blocked');

    // Run S2
    expect(await api.post('/scenarios/S2/run', { mode: 'board' })).toBeTruthy();

    // Save the site profile
    const view = await api.get<SiteProfileView>('/site-profile');
    const { version: _inner, ...profile } = view.profile;
    await api.put('/site-profile', { ...profile, expectedVersion: view.version });
    expect((await api.get<SiteProfileView>('/site-profile')).version).toBe(view.version + 1);

    // Draft and send an escalation
    const draft = await api.post<Escalation>(`/cases/${WITHHELD}/escalations`, {});
    const sentMail = await api.post<Escalation>(`/cases/${WITHHELD}/escalations/${draft.seq}/send`, {
      bodyDigest: draft.bodyDigest,
    });
    // Saved as an email file, as on an instance with no mail server: nobody is emailed (v1.53)
    expect(sentMail.state).toBe('saved');

    // Start a production review
    expect(
      await api.post<{ state: string }>('/production-reviews', {
        namespace: 'HOSPITAL',
        production: 'Hospital.Production',
        windowDays: 7,
        agent: false,
      }),
    ).toMatchObject({ state: 'sweeping' });

    // Ask a suggested question
    const suggested = await api.get<SuggestedQuestions>('/cases/C-000008/questions/suggested');
    const first = suggested.conversations[0];
    expect(
      await api.post<{ state: string }>('/cases/C-000008/questions', {
        suggested: { conversation: first.id, turn: first.turns[0].turn },
      }),
    ).toBeTruthy();

    // Switch role, sign out and in again
    await api.post('/session', { username: 'operator', password: 'shutter' });
    expect((await api.get<Me>('/me')).username).toBe('operator');
    await api.del('/session');
    await expect(api.get('/me')).rejects.toMatchObject({ status: 401 });
    await api.post('/session', { username: 'approver', password: 'shutter' });
    expect((await api.get<Me>('/me')).username).toBe('approver');

    // Nothing reached the network; the journal holds every call, the actions among them
    expect(sent).not.toHaveBeenCalled();
    expect(journal.counts().actions).toBeGreaterThanOrEqual(10);
    expect(journal.counts()).toMatchObject({ refused: 0, violations: 0 });
  });

  it("says beside a write's confirm that it is trial only", () => {
    render(
      <MantineProvider theme={theme}>
        <EnvChip />
      </MantineProvider>,
    );
    expect(screen.getByText('Trial only')).toBeInTheDocument();
    expect(screen.queryByText('Live system')).not.toBeInTheDocument();
  });
});
