import { MantineProvider } from '@mantine/core';
import { Notifications } from '@mantine/notifications';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { IncidentDetail, IncidentEvent, IncidentSummary } from '@/api/types';
import { server } from '@/mocks/node';
import { resetMock } from '@/mocks/handlers';
import { theme } from '@/theme';
import recorded from './test-incident.json';
import IncidentPage from './IncidentPage';
import IncidentsPage from './IncidentsPage';

const BASE = '/api/shutter';
const closed = recorded.detail as unknown as IncidentDetail;

/** The same incident while its ordered chain waits for the incident's approval and the rest are released. */
function waiting(): IncidentDetail {
  const inc = structuredClone(closed);
  inc.state = 'releasing';
  inc.closedAt = undefined;
  inc.approvals = [];
  inc.approvedBy = inc.approvalDecision = inc.approvedAt = undefined;
  inc.tasks = inc.tasks.map((t) => ({ ...t, complete: false, action: '', userName: '', timeCompleted: '' }));
  const ordered = inc.chains.find((c) => c.seq === 2)!;
  ordered.state = 'awaiting_approval';
  ordered.outcome = '';
  ordered.items = ordered.items.map((i) => ({
    ...i,
    state: 'pending',
    verifiedVersion: null,
    caseState: 'grouped',
  }));
  return inc;
}

let served: IncidentDetail = closed;
/** The plan's digest as the server holds it when a decision arrives. */
let digest = closed.planDigest;
let posted: { path: string; body: unknown } | null = null;

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
beforeEach(() => {
  resetMock('approver');
  served = closed;
  digest = closed.planDigest;
  posted = null;
  server.use(
    http.get(`${BASE}/incidents`, () =>
      HttpResponse.json({ items: [recorded.summary as unknown as IncidentSummary], total: 1 }),
    ),
    http.get(`${BASE}/incidents/:id`, ({ params }) =>
      params.id === served.incidentId
        ? HttpResponse.json(served)
        : HttpResponse.json(
            { error: 'not_found', detail: `No incident ${String(params.id)}` },
            { status: 404 },
          ),
    ),
    http.get(`${BASE}/incidents/:id/events`, () => HttpResponse.json(recorded.events as IncidentEvent[])),
    http.post(`${BASE}/incidents/:id/approvals`, async ({ request }) => {
      const body = (await request.json()) as { planDigest: string; decision: string };
      posted = { path: new URL(request.url).pathname, body };
      if (body.planDigest !== digest)
        return HttpResponse.json({ error: 'plan_changed', detail: 'The plan moved' }, { status: 409 });
      return HttpResponse.json(
        { taskId: '148', decision: body.decision, incidentId: served.incidentId },
        { status: 202 },
      );
    }),
  );
});

function renderAt(path: string) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter(
    [
      { path: '/incidents', element: <IncidentsPage /> },
      { path: '/incidents/:incidentId', element: <IncidentPage /> },
      { path: '/cases/:caseId', element: <p>case page</p> },
    ],
    { initialEntries: [path] },
  );
  return render(
    <MantineProvider theme={theme}>
      <Notifications />
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

describe('IncidentsPage', () => {
  it('lists each incident with what it holds and how its chains ended', async () => {
    renderAt('/incidents');
    const link = await screen.findByRole('link', { name: 'I-000001' });
    expect(link).toHaveAttribute('href', '/incidents/I-000001');
    expect(screen.getByText('8 cases in 6 chains: 4 single, 1 ordered, 1 interleaved')).toBeInTheDocument();
    expect(screen.getByText('6 resolved')).toBeInTheDocument();
    expect(screen.getByText('Downstream Out')).toBeInTheDocument();
    expect(
      screen.getByText("The policy chains are released under one approval of the incident's plan"),
    ).toBeInTheDocument();
  });
});

describe('IncidentPage', () => {
  it('shows every chain in order, with each operation, its catalogue match and its versions', async () => {
    renderAt('/incidents/I-000001');
    expect(await screen.findByRole('heading', { name: 'Incident I-000001' })).toBeInTheDocument();
    const chains = await screen.findAllByRole('article');
    expect(chains).toHaveLength(6);
    const ordered = within(chains[1]);
    expect(ordered.getByText('Chain 2: ENC-1102')).toBeInTheDocument();
    expect(
      ordered.getByText(/Ordered, decided by site policy, released under the incident's approval/),
    ).toBeInTheDocument();
    expect(ordered.getByRole('link', { name: 'C-000004' })).toHaveAttribute('href', '/cases/C-000004');
    expect(ordered.getByText('v1 → v2')).toBeInTheDocument();
    expect(ordered.getByText('v2 → v3')).toBeInTheDocument();
    // Chain 4 was matched as E2 when it formed, and its released case found the transfer superseded (E1)
    expect(within(chains[3]).getByText('At release: E1 · none')).toBeInTheDocument();
    expect(within(chains[0]).getByText('fresh evidence → v2')).toBeInTheDocument();
  });

  it("records who approved the policy chains, under the plan's digest, and the timeline says so", async () => {
    renderAt('/incidents/I-000001');
    const approval = await screen.findByRole('region', { name: 'Approval' });
    expect(within(approval).getByText('Approved by approver')).toBeInTheDocument();
    expect(within(approval).getByText('Checked the order of the two operations')).toBeInTheDocument();
    expect(within(approval).queryByRole('button', { name: /Approve/ })).not.toBeInTheDocument();
    expect(
      await screen.findByText(/Approved by approver \(task 148, plan digest sha256:f42f69be8a57\)/),
    ).toBeInTheDocument();
  });

  it("lets an approver release the waiting chains under the plan's digest", async () => {
    served = waiting();
    renderAt('/incidents/I-000001');
    const approval = await screen.findByRole('region', { name: 'Approval' });
    expect(within(approval).getByText('Waiting for an approver')).toBeInTheDocument();
    await userEvent.click(within(approval).getByRole('button', { name: /Approve/ }));
    const dialog = await screen.findByRole('dialog');
    expect(
      within(dialog).getByText(/resend these 2 operations to Downstream Out, in this order/),
    ).toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole('button', { name: 'Approve the release' }));
    expect(await screen.findByText('Approved')).toBeInTheDocument();
    expect(posted).toEqual({
      path: '/api/shutter/incidents/I-000001/approvals',
      body: expect.objectContaining({ decision: 'approve', planDigest: closed.planDigest }),
    });
  });

  it("says so when the incident's plan moved since the page loaded", async () => {
    served = waiting();
    renderAt('/incidents/I-000001');
    const approval = await screen.findByRole('region', { name: 'Approval' });
    // The plan moves on the server after the page has read it
    digest = 'sha256:another';
    await userEvent.click(within(approval).getByRole('button', { name: /Approve/ }));
    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Approve the release' }));
    expect(
      await within(dialog).findByText(
        "The incident's plan changed since this page loaded: close this and review it again.",
      ),
    ).toBeInTheDocument();
  });

  it('keeps the decision from someone without the approver role', async () => {
    resetMock('operator');
    served = waiting();
    renderAt('/incidents/I-000001');
    const approval = await screen.findByRole('region', { name: 'Approval' });
    expect(await within(approval).findByRole('button', { name: /Approve/ })).toBeDisabled();
  });

  it('says plainly when there is no such incident', async () => {
    renderAt('/incidents/I-999999');
    expect(await screen.findByText('There is no incident I-999999')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'All incidents' })).toBeInTheDocument();
  });
});
