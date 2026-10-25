import { MantineProvider } from '@mantine/core';
import { Notifications } from '@mantine/notifications';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { ReviewDetail } from '@/api/types';
import fixtures from '@/mocks/fixtures.json';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { theme } from '@/theme';
import ReviewPage from './ReviewPage';
import ReviewsPage from './ReviewsPage';

const BASE = '/api/shutter';
const recorded = fixtures.productionReviews.reviews as unknown as Record<string, ReviewDetail>;

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => {
  server.resetHandlers();
  server.events.removeAllListeners();
});
afterAll(() => server.close());
beforeEach(() => resetMock('approver'));

function renderAt(path: string) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter(
    [
      { path: '/reviews', element: <ReviewsPage /> },
      { path: '/reviews/:reviewId', element: <ReviewPage /> },
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

const findings = () => within(screen.getByRole('region', { name: 'Findings' }));
/** The findings table's rows, header row left out. */
const rows = () => findings().getAllByRole('row').slice(1);

/** PR-000001 as the agent would leave it: ranked, explained, with its summary and unknowns. */
function ranked(): ReviewDetail {
  const r = structuredClone(recorded['PR-000001']);
  r.agent = {
    ...r.agent,
    state: 'ok',
    mode: 'replay',
    model: 'a-recorded-model',
    error: '',
    summary: 'The downstream errors outnumber the rest.',
    unknowns: ['Whether the ward was down for maintenance'],
  };
  r.agentState = 'ok';
  // Within the medium tier the agent puts MESSAGE_ERRORS on ADT to Downstream (F5) first
  const order = ['F5', 'F1', 'F2', 'F3', 'F4', 'F6', 'F7', 'F8', 'F9', 'F10', 'F11', 'F12', 'F13'];
  for (const f of r.findings) {
    f.rank = order.indexOf(f.id) + 1;
    f.explanation = `Consistent with the cases of ${f.item || 'the production'}.`;
  }
  return r;
}

describe('ReviewsPage', () => {
  it('lists the past reviews newest first, with their state, the agent and the findings by severity', async () => {
    renderAt('/reviews');
    expect(await screen.findByRole('link', { name: 'PR-000004' })).toHaveAttribute(
      'href',
      '/reviews/PR-000004',
    );
    const past = within(screen.getByRole('region', { name: 'Past reviews' }));
    const lines = past.getAllByRole('row').slice(1);
    expect(lines.map((r) => within(r).getAllByRole('link')[0].textContent)).toEqual([
      'PR-000004',
      'PR-000003',
      'PR-000002',
      'PR-000001',
    ]);
    expect(within(lines[1]).getByText('Hospital.Production')).toBeInTheDocument();
    expect(within(lines[1]).getByText('No recording')).toBeInTheDocument();
    expect(within(lines[1]).getByText('1 high')).toBeInTheDocument();
    expect(within(lines[0]).getByText('Agent not asked')).toBeInTheDocument();
    expect(screen.getByText(/The review never changes the production/)).toBeInTheDocument();
  });

  it("starts a review of the chosen production for an operator and follows it until it's done", async () => {
    resetMock('operator');
    let posted: { body: unknown; key: string | null; csrf: string | null } | null = null;
    server.events.on('request:start', ({ request }) => {
      if (request.method === 'POST' && new URL(request.url).pathname === `${BASE}/production-reviews`)
        void request
          .clone()
          .json()
          .then((body) => {
            posted = {
              body,
              key: request.headers.get('Idempotency-Key'),
              csrf: request.headers.get('X-Requested-With'),
            };
          });
    });
    renderAt('/reviews');
    const select = await screen.findByRole('combobox', { name: 'Production' });
    await userEvent.selectOptions(select, 'HOSPITAL|Hospital.Production');
    await userEvent.click(screen.getByRole('switch', { name: /Ask the agent/ }));
    await userEvent.click(screen.getByRole('button', { name: 'Start the review' }));
    expect(await screen.findByRole('heading', { name: 'Review PR-000005' })).toBeInTheDocument();
    expect(posted).toEqual({
      body: { namespace: 'HOSPITAL', production: 'Hospital.Production', windowDays: 7, agent: false },
      key: expect.stringMatching(/^[0-9a-f-]{36}$/),
      csrf: 'Shutter',
    });
    // The first read finds it sweeping; the page reads it again until it is done
    expect(await screen.findByText(/This page reads the review again every 2 seconds/)).toBeInTheDocument();
    expect(await findings().findByText('PURGE_MISSING', {}, { timeout: 5000 })).toBeInTheDocument();
  });

  it('keeps the start of a review from someone without the operator role', async () => {
    server.use(
      http.get(`${BASE}/me`, () =>
        HttpResponse.json({ username: 'viewer', operator: false, approver: false }),
      ),
    );
    renderAt('/reviews');
    expect(await screen.findByText('An operator starts a review.')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Start the review' })).not.toBeInTheDocument();
  });

  it('links to the review still running when the server refuses a second one', async () => {
    resetMock('operator');
    server.use(
      http.post(`${BASE}/production-reviews`, () =>
        HttpResponse.json(
          {
            error: 'wrong_state',
            detail: 'A review of Shutter.Production is ranking',
            reviewId: 'PR-000004',
            state: 'ranking',
          },
          { status: 409 },
        ),
      ),
    );
    renderAt('/reviews');
    await userEvent.click(await screen.findByRole('button', { name: 'Start the review' }));
    const alert = await screen.findByRole('alert');
    expect(within(alert).getByText(/A review of Shutter.Production is ranking/)).toBeInTheDocument();
    expect(within(alert).getByRole('link', { name: 'Follow review PR-000004' })).toHaveAttribute(
      'href',
      '/reviews/PR-000004',
    );
  });
});

describe('ReviewPage', () => {
  it('shows the review read only, in baseline order, with the agent plainly not recorded', async () => {
    renderAt('/reviews/PR-000001');
    expect(await screen.findByRole('heading', { name: 'Review PR-000001' })).toBeInTheDocument();
    expect(
      screen.getByText(/Shutter.Production in SHUTTER\. The review never changes the production/),
    ).toBeInTheDocument();
    const agent = within(screen.getByRole('region', { name: "The agent's ranking" }));
    expect(agent.getByText('No recorded explanation for this configuration')).toBeInTheDocument();
    expect(findings().getByText(/In the deterministic order/)).toBeInTheDocument();
    expect(rows().map((r) => within(r).getAllByText(/^F\d+$/)[0].textContent)).toEqual(
      recorded['PR-000001'].findings.map((f) => f.id),
    );
    const first = within(rows()[0]);
    expect(first.getByText('ERRORS_GROUPED')).toBeInTheDocument();
    expect(first.getByText('the production')).toBeInTheDocument();
    expect(first.getByText('Intended')).toBeInTheDocument();
    expect(first.getByRole('link', { name: 'C-000055' })).toHaveAttribute('href', '/cases/C-000055');
    expect(first.getByRole('link', { name: /Latest header 4342/ })).toHaveAttribute(
      'href',
      '/csp/shutter/EnsPortal.MessageContents.zen?HeaderId=4342',
    );
    const alerting = within(rows()[1]);
    expect(alerting.getByText("Source: the item's own setting")).toBeInTheDocument();
    expect(alerting.getAllByRole('listitem')).toHaveLength(4);
    expect(findings().getByText(/No HL7 TCP item in this production/)).toBeInTheDocument();
  });

  it("sorts by the agent's rank when it answered, with its explanation, summary and unknowns", async () => {
    server.use(http.get(`${BASE}/production-reviews/PR-000001`, () => HttpResponse.json(ranked())));
    renderAt('/reviews/PR-000001');
    expect(
      await screen.findByText("In the agent's order: within each severity tier, as it ranked them."),
    ).toBeInTheDocument();
    const first = within(rows()[0]);
    expect(first.getByText('F5')).toBeInTheDocument();
    expect(
      first.getByText('Agent, rank 1: Consistent with the cases of ADT to Downstream.'),
    ).toBeInTheDocument();
    const agent = within(screen.getByRole('region', { name: "The agent's ranking" }));
    expect(agent.getByText('Ranked and explained (recorded)')).toBeInTheDocument();
    expect(agent.getByText('The downstream errors outnumber the rest.')).toBeInTheDocument();
    expect(agent.getByText('Whether the ward was down for maintenance')).toBeInTheDocument();
  });

  it('lets an approver mark a finding intended with a reason and an expiry, and reads the review again', async () => {
    let posted: { body: unknown; key: string | null } | null = null;
    let served = recorded['PR-000001'];
    server.use(
      http.get(`${BASE}/production-reviews/PR-000001`, () => HttpResponse.json(served)),
      http.post(`${BASE}/production-reviews/PR-000001/annotations`, async ({ request }) => {
        posted = { body: await request.json(), key: request.headers.get('Idempotency-Key') };
        served = structuredClone(served);
        Object.assign(served.findings[1], { status: 'intended', annotationId: '17' });
        return HttpResponse.json({ annotationId: '17', status: 'intended' }, { status: 201 });
      }),
    );
    renderAt('/reviews/PR-000001');
    await screen.findByRole('heading', { name: 'Review PR-000001' });
    await userEvent.click(await within(rows()[1]).findByRole('button', { name: 'Annotate…' }));
    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText(/never a change to the production/)).toBeInTheDocument();
    const mark = within(dialog).getByRole('button', { name: 'Mark as intended' });
    expect(mark).toBeDisabled();
    await userEvent.type(
      within(dialog).getByRole('textbox', { name: /Reason/ }),
      'Alerts go to the night desk',
    );
    await userEvent.type(within(dialog).getByRole('textbox', { name: /Expires on/ }), '2099-01-31');
    await userEvent.click(mark);
    expect(await screen.findByText('Marked as intended')).toBeInTheDocument();
    expect(posted).toEqual({
      body: {
        findingId: 'F2',
        status: 'intended',
        reason: 'Alerts go to the night desk',
        expiresAt: '2099-01-31',
      },
      key: expect.stringMatching(/^[0-9a-f-]{36}$/),
    });
    expect(await within(rows()[1]).findByText('Annotation 17')).toBeInTheDocument();
  });

  it('lets an approver remove an annotation', async () => {
    let deleted = '';
    server.use(
      http.delete(`${BASE}/production-reviews/annotations/:id`, ({ params }) => {
        deleted = String(params.id);
        return new HttpResponse(null, { status: 204 });
      }),
    );
    renderAt('/reviews/PR-000001');
    await screen.findByRole('heading', { name: 'Review PR-000001' });
    await userEvent.click(await within(rows()[0]).findByRole('button', { name: 'Remove annotation' }));
    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Remove the annotation' }));
    expect(await screen.findByText('Annotation removed')).toBeInTheDocument();
    expect(deleted).toBe('16');
  });

  it("shows the server's refusal of an annotation in the dialog", async () => {
    renderAt('/reviews/PR-000003');
    await screen.findByRole('heading', { name: 'Review PR-000003' });
    await userEvent.click(await within(rows()[0]).findByRole('button', { name: 'Annotate…' }));
    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('radio', { name: /False positive/ }));
    await userEvent.type(
      within(dialog).getByRole('textbox', { name: /Reason/ }),
      'Purged by the site script',
    );
    await userEvent.click(within(dialog).getByRole('button', { name: 'Mark as false positive' }));
    expect(await within(dialog).findByRole('alert')).toHaveTextContent(
      /^The online demo keeps no annotations\./,
    );
  });

  it('hides the annotations from an operator', async () => {
    resetMock('operator');
    renderAt('/reviews/PR-000001');
    await screen.findByRole('heading', { name: 'Review PR-000001' });
    expect(within(rows()[0]).getByText('Intended')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /Annotate|Remove annotation/ })).not.toBeInTheDocument();
  });

  it('says plainly when there is no such review', async () => {
    renderAt('/reviews/PR-999999');
    expect(await screen.findByText('There is no review PR-999999')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'All reviews' })).toBeInTheDocument();
  });
});
