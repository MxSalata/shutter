import { MantineProvider } from '@mantine/core';
import { Notifications, notifications } from '@mantine/notifications';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { act, cleanup, render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { IncidentDetail, IncidentEvent, IncidentSummary } from '@/api/types';
import type { DetailLevel } from '@/env/mode';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { useAppearance } from '@/stores/appearance';
import { layer1Words } from '@/test/words';
import { theme } from '@/theme';
import IncidentPage from './IncidentPage';
import IncidentsPage from './IncidentsPage';
import recorded from './test-incident.json';
import { PLAIN_BUDGET, TECHNICAL_BUDGET } from './wordBudget';

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

/** The same incident with chain 4 stopped at its one operation, which a check blocked. */
function stopped(): IncidentDetail {
  const inc = structuredClone(closed);
  const chain = inc.chains.find((c) => c.seq === 4)!;
  chain.state = 'stopped';
  chain.stoppedAt = 1;
  chain.items = chain.items.map((i) => ({
    ...i,
    state: 'blocked',
    caseState: 'blocked',
    verifiedVersion: null,
  }));
  inc.progress = { ...inc.progress!, byState: { resolved: 5, stopped: 1 } };
  return inc;
}

/** The same incident while it still takes cases: five failures, no chains yet. */
function taking(): IncidentDetail {
  const inc = structuredClone(closed);
  inc.state = 'open';
  inc.closedAt = undefined;
  inc.intakeClosedAt = undefined;
  inc.chains = [];
  inc.approvals = [];
  inc.tasks = [];
  inc.planDigest = undefined;
  inc.progress = { chains: 0, cases: 5, byKind: {}, byState: {} };
  return inc;
}

let served: IncidentDetail = closed;
/** The plan's digest as the server holds it when a decision arrives. */
let digest = closed.planDigest;
let posted: { path: string; body: unknown } | null = null;

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => {
  server.resetHandlers();
  // A notice shown by one test would otherwise be in the next one's page
  notifications.clean();
});
afterAll(() => server.close());
beforeEach(() => {
  resetMock('approver');
  useAppearance.setState({ detail: 'plain' });
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

function renderAt(path: string, detail: DetailLevel = 'plain') {
  useAppearance.setState({ detail });
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

/** The words a reader sees; the shared count leaves out the endpoint's own JSON, which Technical opens. */
function words(container: HTMLElement = document.body): string[] {
  return layer1Words(container);
}

/** Waits for the parts of the page that load after the incident: its header, and the timeline's lines. */
async function loaded() {
  await screen.findByRole('heading', { name: 'Incident I-000001' });
  await screen.findByRole('button', { name: '5 cases joined' });
  // The approval waits for who is signed in
  await screen.findByRole('region', { name: 'Approval' });
}

describe('IncidentsPage', () => {
  it('lists each incident with its outcome, what it holds and the shape of its chains', async () => {
    renderAt('/incidents');
    const link = await screen.findByRole('link', { name: 'I-000001' });
    expect(link).toHaveAttribute('href', '/incidents/I-000001');
    const row = link.closest('tr')!;
    // The row's edge is in the incident outcome's tone, and the outcome is in words as well
    expect(row).toHaveAttribute('data-tone', 'positive');
    expect(within(row).getByText('All 6 chains verified')).toBeInTheDocument();
    expect(within(row).getByText('8 cases in 6 chains')).toBeInTheDocument();
    expect(within(row).getByText('4 single, 1 ordered, 1 interleaved')).toBeInTheDocument();
    expect(within(row).getByText('Downstream Out')).toBeInTheDocument();
    // One segment per chain, hidden from assistive technology: the words say the same
    const bar = row.querySelector('.chain-bar')!;
    expect(bar).toHaveAttribute('aria-hidden', 'true');
    expect(bar.querySelectorAll('span')).toHaveLength(6);
  });

  it('says how the policy chains are released once, on the run mode, not in a sentence on every row', async () => {
    renderAt('/incidents');
    await screen.findByRole('link', { name: 'I-000001' });
    // The sentence is a tooltip's: the row carries only the mode, and the keyboard reaches it
    expect(screen.queryByText(/The policy chains are released/)).not.toBeInTheDocument();
    const mode = screen.getByText('Site policy').closest('[tabindex="0"]') as HTMLElement;
    expect(mode).not.toBeNull();
    act(() => mode.focus());
    expect(await screen.findByText(/The policy chains are released/)).toBeInTheDocument();
  });

  it('puts the three figures that matter above the list', async () => {
    renderAt('/incidents');
    const tiles = await screen.findByRole('region', { name: 'Incidents at a glance' });
    expect(within(tiles).getByText('Open')).toBeInTheDocument();
    expect(within(tiles).getByText('Closed')).toBeInTheDocument();
    expect(within(tiles).getByText('6 of 6')).toBeInTheDocument();
    expect(within(tiles).getByText('All verified')).toBeInTheDocument();
  });

  it('filters by state and says so when none is in it', async () => {
    renderAt('/incidents');
    await screen.findByRole('link', { name: 'I-000001' });
    await userEvent.selectOptions(screen.getByLabelText('State'), 'open');
    expect(await screen.findByText('No incidents in this state.')).toBeInTheDocument();
    expect(screen.queryByRole('link', { name: 'I-000001' })).not.toBeInTheDocument();
  });

  it('says when one opens, from the site profile, when there is none yet', async () => {
    server.use(http.get(`${BASE}/incidents`, () => HttpResponse.json({ items: [], total: 0 })));
    renderAt('/incidents');
    expect(
      await screen.findByText(
        'No incidents yet. One opens when 5 deliveries to one receiver fail within 10 minutes.',
      ),
    ).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Site profile' })).toHaveAttribute('href', '/site-profile');
  });

  it('names the endpoint it read, for the engineer', async () => {
    renderAt('/incidents');
    await screen.findByRole('link', { name: 'I-000001' });
    expect(screen.getByRole('button', { name: 'As the API sends it' })).toBeInTheDocument();
    expect(screen.getByText('GET /api/shutter/incidents?limit=100')).toBeInTheDocument();
  });

  it('keeps the first layer short, in Plain and in Technical', async () => {
    renderAt('/incidents');
    await screen.findByRole('link', { name: 'I-000001' });
    const plain = words().length;
    expect(plain).toBeLessThanOrEqual(110);
    cleanup();
    renderAt('/incidents', 'technical');
    await screen.findByRole('link', { name: 'I-000001' });
    expect(words().length).toBeLessThanOrEqual(plain * 1.5);
  });
});

describe('IncidentPage', () => {
  it('leads with what a manager measures: how many failed, for how many patients, all verified, how fast', async () => {
    renderAt('/incidents/I-000001');
    await loaded();
    expect(
      screen.getByText(
        '8 failed deliveries to Downstream Out, grouped and released in order, one at a time.',
      ),
    ).toBeInTheDocument();
    const hero = screen.getByRole('region', { name: 'Outcome' });
    expect(hero).toHaveAttribute('data-tone', 'positive');
    expect(
      within(hero).getByText(
        '8 failed messages for 6 patient encounters, all closed and verified at the receiver, in 6 min 27 s.',
      ),
    ).toBeInTheDocument();
    // The four tiles, the time from opening to closing first
    const tiles = within(hero).getByRole('region', { name: 'The incident in figures' });
    const labels = within(tiles)
      .getAllByText(/^(Open to closed|Failures|Chains|Decided by)$/)
      .map((e) => e.textContent);
    expect(labels).toEqual(['Open to closed', 'Failures', 'Chains', 'Decided by']);
    expect(within(tiles).getByText('6 min 27 s')).toBeInTheDocument();
    expect(within(tiles).getByText('to Downstream Out')).toBeInTheDocument();
    expect(within(tiles).getByText('4 single, 1 ordered, 1 interleaved')).toBeInTheDocument();
    expect(within(tiles).getByText('5 of 6')).toBeInTheDocument();
    expect(within(tiles).getByText('by site policy')).toBeInTheDocument();
    expect(within(tiles).getByText('The board 1')).toBeInTheDocument();
    expect(within(tiles).getByText('1 approval')).toBeInTheDocument();
  });

  it('shows the state and the outcome in the header, with the IRIS row', async () => {
    renderAt('/incidents/I-000001');
    await loaded();
    const title = screen.getByRole('heading', { name: 'Incident I-000001' }).parentElement!;
    expect(within(title).getByText('Closed')).toBeInTheDocument();
    expect(within(title).getByText('All 6 chains verified')).toBeInTheDocument();
    expect(screen.getByText('In IRIS:')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /Workflow trace/ })).toHaveAttribute(
      'href',
      expect.stringContaining('SESSIONID=103'),
    );
    expect(screen.getByText('Times in')).toBeInTheDocument();
  });

  it('shows every chain in order, with each operation, its versions and who decides it', async () => {
    renderAt('/incidents/I-000001');
    expect(await screen.findByRole('heading', { name: 'Incident I-000001' })).toBeInTheDocument();
    const chains = await screen.findAllByRole('article');
    expect(chains).toHaveLength(6);
    const ordered = within(chains[1]);
    expect(ordered.getByText('Chain 2: ENC-1102')).toBeInTheDocument();
    // The newcomer's line says who decides; the long form is the expert's
    expect(ordered.getByText('Site policy, one approval')).toBeInTheDocument();
    expect(ordered.getByText('Ordered')).toBeInTheDocument();
    expect(ordered.getByText('Verified')).toBeInTheDocument();
    expect(ordered.getByRole('link', { name: 'C-000004' })).toHaveAttribute('href', '/cases/C-000004');
    expect(ordered.getByText('v1 → v2')).toBeInTheDocument();
    expect(ordered.getByText('v2 → v3')).toBeInTheDocument();
    expect(within(chains[0]).getByText('fresh evidence → v2')).toBeInTheDocument();
    expect(within(chains[2]).getByText('The board of agents decides')).toBeInTheDocument();
  });

  it("lists a chain's operations as an ordered list, oldest first, so the order is announced", async () => {
    renderAt('/incidents/I-000001');
    await loaded();
    const chains = await screen.findAllByRole('article');
    const ops = within(chains[1]).getByRole('list', { name: 'Chain 2 operations, oldest first' });
    expect(ops.tagName).toBe('OL');
    const items = within(ops).getAllByRole('listitem');
    expect(items.map((i) => within(i).getByRole('link').textContent)).toEqual(['C-000004', 'C-000009']);
    // Two operations run side by side with an arrow between them; one alone stands as it is
    expect(ops).toHaveAttribute('data-flow', 'row');
    expect(within(chains[0]).getByRole('list')).toHaveAttribute('data-flow', 'stack');
  });

  it("names each operation's outcome as a case's outcome, not as a recovery", async () => {
    renderAt('/incidents/I-000001');
    await loaded();
    const chains = await screen.findAllByRole('article');
    const all = chains.flatMap((c) =>
      within(c).queryAllByText(/^(Delivered, verified|Nothing to send, verified)$/),
    );
    // Five operations were resent and verified; chain 3's first, chain 4's (superseded at release) and chain 5's sent nothing
    expect(all.filter((e) => e.textContent === 'Delivered, verified')).toHaveLength(5);
    expect(all.filter((e) => e.textContent === 'Nothing to send, verified')).toHaveLength(3);
    expect(screen.queryByText(/recovered/i)).not.toBeInTheDocument();
  });

  it('shows the catalogue, the keys and the long form to the engineer, where the newcomer reads words', async () => {
    renderAt('/incidents/I-000001', 'technical');
    await loaded();
    const chains = await screen.findAllByRole('article');
    const ordered = within(chains[1]);
    expect(ordered.getByText('MRN1102')).toBeInTheDocument();
    expect(ordered.getByText('policy')).toBeInTheDocument();
    expect(ordered.getByText('approval')).toBeInTheDocument();
    expect(ordered.getAllByText('E4').length).toBeGreaterThanOrEqual(2);
    expect(ordered.getByText('PAS^HOSP^MRN1102^ENC-1102^transfer^2026-10-15T09:20:00Z')).toBeInTheDocument();
    // Chain 4 was matched as E2 when it formed, and its released case found the transfer superseded (E1)
    expect(within(chains[3]).getByText('At release: E1 · none')).toBeInTheDocument();
    expect(within(chains[3]).getByRole('button', { name: 'More about C-000006' })).toBeInTheDocument();
    // None of it is in the newcomer's page
    cleanup();
    renderAt('/incidents/I-000001');
    await loaded();
    expect(screen.queryByText('MRN1102')).not.toBeInTheDocument();
    expect(screen.queryByText('At release: E1 · none')).not.toBeInTheDocument();
  });

  it('keeps the operations as tables behind one disclosure, for the engineer who wants every column', async () => {
    renderAt('/incidents/I-000001');
    await loaded();
    const toggle = screen.getByRole('button', { name: 'Show the operations as tables' });
    expect(toggle).toHaveAttribute('aria-expanded', 'false');
    expect(screen.queryByRole('table', { name: 'Operations of chain 2' })).not.toBeInTheDocument();
    await userEvent.click(toggle);
    const table = await screen.findByRole('table', { name: 'Operations of chain 2' });
    expect(within(table).getByText('C-000009')).toBeInTheDocument();
    expect(within(table).getByText('v2 → v3')).toBeInTheDocument();
  });

  it('reads an incident with a chain stopped: blocking, in words, with the operation that stopped it', async () => {
    served = stopped();
    renderAt('/incidents/I-000001');
    await loaded();
    const hero = screen.getByRole('region', { name: 'Outcome' });
    expect(hero).toHaveAttribute('data-tone', 'blocking');
    expect(
      within(hero).getByText('8 failed messages for 6 patient encounters: 5 chains verified, 1 stopped.'),
    ).toBeInTheDocument();
    const chains = await screen.findAllByRole('article');
    expect(within(chains[3]).getByText('Stopped')).toBeInTheDocument();
    expect(within(chains[3]).getByText('Blocked')).toBeInTheDocument();
    expect(within(chains[3]).getByText('Stopped the chain')).toBeInTheDocument();
    // The header's outcome badge and the chains' own count say it too
    expect(screen.getAllByText('1 stopped')).toHaveLength(2);
  });

  it('reads an incident that still takes cases: so far, and still open', async () => {
    served = taking();
    renderAt('/incidents/I-000001');
    await screen.findByRole('heading', { name: 'Incident I-000001' });
    const hero = screen.getByRole('region', { name: 'Outcome' });
    expect(hero).toHaveAttribute('data-tone', 'info');
    expect(within(hero).getByText('5 failed messages so far, taking cases.')).toBeInTheDocument();
    expect(within(hero).getByText('Still open')).toBeInTheDocument();
    expect(screen.getByText(/No chains yet/)).toBeInTheDocument();
    expect(within(hero).queryByText('Decided by')).not.toBeInTheDocument();
  });

  it('records who approved the policy chains, in one sentence, and the timeline says so', async () => {
    renderAt('/incidents/I-000001');
    const approval = await screen.findByRole('region', { name: 'Approval' });
    expect(within(approval).getByText('Approved by approver')).toBeInTheDocument();
    expect(
      within(approval).getByText('One approval released the ordered chain: C-000004 then C-000009.'),
    ).toBeInTheDocument();
    expect(within(approval).getByText('Checked the order of the two operations')).toBeInTheDocument();
    expect(within(approval).queryByRole('button', { name: /Approve/ })).not.toBeInTheDocument();
    // What the approval binds is one click away
    expect(within(approval).getByRole('button', { name: 'What an approval binds' })).toHaveAttribute(
      'aria-expanded',
      'false',
    );
    expect(
      await screen.findByText(/Approved by approver \(task 148, plan digest sha256:f42f69be8a57\)/),
    ).toBeInTheDocument();
  });

  it('says in one line what the plan covers, with the digest behind "Everything the approval is bound to"', async () => {
    renderAt('/incidents/I-000001');
    const plan = await screen.findByRole('region', { name: 'The plan' });
    expect(within(plan).getByText('One plan, approved once, covers the ordered chain.')).toBeInTheDocument();
    expect(within(plan).getByRole('button', { name: 'Everything the approval is bound to' })).toHaveAttribute(
      'aria-expanded',
      'false',
    );
    await loaded();
    // The digest is not in the plain page
    expect(words().join(' ')).not.toContain('sha256');
    cleanup();
    renderAt('/incidents/I-000001', 'technical');
    await loaded();
    // In Technical the data opens: the digest, the epoch and the catalogue as chips
    const open = await screen.findByRole('region', { name: 'The plan' });
    expect(within(open).getByRole('button', { name: 'Everything the approval is bound to' })).toHaveAttribute(
      'aria-expanded',
      'true',
    );
    expect(within(open).getByLabelText(/incident plan digest: sha256:f42f69be8a57/)).toBeInTheDocument();
    expect(within(open).getByText('E10@1')).toBeInTheDocument();
  });

  it('collapses the runs of joined cases into lines with their dates, and opens one to its events', async () => {
    renderAt('/incidents/I-000001');
    await loaded();
    const timeline = screen.getByRole('region', { name: 'Timeline' });
    // Every line carries its date and time
    const stamps = within(timeline).getAllByText(/^\d{1,2} \w{3}, \d\d:\d\d:\d\d$/);
    expect(stamps.length).toBeGreaterThanOrEqual(10);
    expect(stamps[0]).toHaveTextContent('18 Oct, 12:04:27');
    expect(within(timeline).getByText('Opened: 5 failures within 10 minutes')).toBeInTheDocument();
    expect(within(timeline).getByRole('button', { name: '3 cases joined' })).toBeInTheDocument();
    expect(within(timeline).getByRole('button', { name: '20 release steps' })).toBeInTheDocument();
    expect(
      within(timeline).getByText('Closed: 6 chains: 6 resolved, 0 stopped, 0 escalated, 0 rejected'),
    ).toBeInTheDocument();
    const joined = within(timeline).getByRole('button', { name: '5 cases joined' });
    expect(joined).toHaveAttribute('aria-expanded', 'false');
    const region = document.getElementById(joined.getAttribute('aria-controls')!)!;
    expect(region).toHaveAttribute('data-tech-detail', 'closed');
    await userEvent.click(joined);
    expect(joined).toHaveAttribute('aria-expanded', 'true');
    expect(region).toHaveAttribute('data-tech-detail', 'open');
    expect(
      within(region).getByText(/Case C-000003 joined: transfer for ENC-1101 at 2026-10-15T09:20:00Z/),
    ).toBeInTheDocument();
  });

  it('never prints a plural as "(s)" in the words a reader sees', async () => {
    renderAt('/incidents/I-000001', 'technical');
    await loaded();
    const technical = words().join(' ');
    expect(technical).not.toMatch(/\w\(s\)/);
    expect(technical).toContain('6 chains');
    expect(technical).toContain('approve the release of 1 chain to Downstream Out');
    cleanup();
    renderAt('/incidents/I-000001');
    await loaded();
    expect(words().join(' ')).not.toMatch(/\w\(s\)/);
  });

  it('names the endpoint it read, for the engineer', async () => {
    renderAt('/incidents/I-000001');
    await loaded();
    expect(screen.getByRole('button', { name: 'As the API sends it' })).toBeInTheDocument();
    expect(screen.getByText('GET /api/shutter/incidents/I-000001')).toBeInTheDocument();
  });

  it("lets an approver release the waiting chains under the plan's digest", async () => {
    served = waiting();
    renderAt('/incidents/I-000001');
    const approval = await screen.findByRole('region', { name: 'Approval' });
    expect(within(approval).getByText('Waiting for approval')).toBeInTheDocument();
    expect(
      within(approval).getByText('One approval releases the ordered chain: C-000004 then C-000009.'),
    ).toBeInTheDocument();
    await userEvent.click(within(approval).getByRole('button', { name: /Approve/ }));
    const dialog = await screen.findByRole('dialog', { name: 'Approve the release of 1 chain' });
    // The consequence first, in plain words, with where it takes effect beside the title (not in the dialog's name)
    expect(
      within(dialog).getByText('This sends 2 fixes to Downstream Out, in this order, for real.'),
    ).toBeInTheDocument();
    expect(within(dialog).getByText('Live system')).toBeInTheDocument();
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
        "The incident's plan changed since you opened this: close this and review it again.",
      ),
    ).toBeInTheDocument();
  });

  it('stops a dialog left open when the plan changes under it, and posts nothing', async () => {
    served = waiting();
    renderAt('/incidents/I-000001');
    const approval = await screen.findByRole('region', { name: 'Approval' });
    await userEvent.click(within(approval).getByRole('button', { name: /Approve/ }));
    const dialog = await screen.findByRole('dialog');
    // The page's next read brings the new digest under the open dialog
    served = { ...served, planDigest: 'sha256:another' };
    const confirm = within(dialog).getByRole('button', { name: 'Approve the release' });
    await waitFor(() => expect(confirm).toBeDisabled(), { timeout: 10_000 });
    expect(within(dialog).getByRole('alert')).toHaveTextContent(
      "The incident's plan changed since you opened this: close this and review it again.",
    );
    expect(posted).toBeNull();
  });

  it('keeps the decision from someone without the approver role', async () => {
    resetMock('operator');
    served = waiting();
    renderAt('/incidents/I-000001');
    const approval = await screen.findByRole('region', { name: 'Approval' });
    expect(await within(approval).findByRole('button', { name: /Approve/ })).toBeDisabled();
    // The reason is written under the buttons, where a keyboard or a screen reader reaches it without a hover
    expect(
      within(approval).getByText('Deciding needs the approver role: sign in as approver'),
    ).toBeInTheDocument();
  });

  it('says plainly when there is no such incident', async () => {
    renderAt('/incidents/I-999999');
    expect(await screen.findByText('There is no incident I-999999')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'All incidents' })).toBeInTheDocument();
  });

  it('keeps the first layer within its word budget, in Plain and in Technical', async () => {
    renderAt('/incidents/I-000001');
    await loaded();
    const plain = words().length;
    expect(plain).toBeLessThanOrEqual(PLAIN_BUDGET);
    cleanup();
    renderAt('/incidents/I-000001', 'technical');
    await loaded();
    const technical = words().length;
    expect(technical).toBeLessThanOrEqual(TECHNICAL_BUDGET);
    expect(technical).toBeLessThanOrEqual(plain * 1.5);
  });
});
