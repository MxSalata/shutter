import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { createMemoryRouter, RouterProvider, useNavigate, useParams } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { api } from '@/api/client';
import { CLOSED_STATES, type CaseList, type CaseSummary, type Health } from '@/api/types';
import { LOOK_ONLY_DEMO, resetMock, writesOf } from '@/mocks/handlers';
import recording from '@/mocks/fixtures.json';
import { server } from '@/mocks/node';
import { useAppearance } from '@/stores/appearance';
import { theme } from '@/theme';
import CasesPage from './CasesPage';
import { DEMO_INSTALL, SITE_AWAITING_SETUP, SITE_WITH_INTAKE } from './emptyCases.fixtures';

/** Whether the page is the trial: set per test. */
const env = vi.hoisted(() => ({ trial: false }));
vi.mock('@/env/mode', async (importOriginal) => {
  const mode = await importOriginal<typeof import('@/env/mode')>();
  return {
    ...mode,
    get TRIAL() {
      return env.trial;
    },
  };
});

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => {
  server.resetHandlers();
  env.trial = false;
});
afterAll(() => server.close());
beforeEach(() => resetMock('approver'));

/** A case page that only says which case it is and goes back, as the browser's Back does. */
function CaseStub() {
  const { caseId } = useParams();
  const navigate = useNavigate();
  return (
    <>
      <h1>Case {caseId}</h1>
      <button type="button" onClick={() => void navigate(-1)}>
        Back
      </button>
    </>
  );
}

/** The list at an address, in a router that has the case pages too; returns the router, for the address. */
function renderList(address = '/cases') {
  useAppearance.setState({ detail: 'plain' });
  const router = createMemoryRouter(
    [
      { path: '/cases', element: <CasesPage /> },
      { path: '/cases/:caseId', element: <CaseStub /> },
      { path: '*', element: <p>Another page</p> },
    ],
    { initialEntries: [address] },
  );
  render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
  return router;
}

/** The list's requests for a page of cases, as their query strings, in the order they were sent. */
function listRequests() {
  const asked: string[] = [];
  server.use(
    http.get('/api/shutter/cases', ({ request }) => {
      asked.push(new URL(request.url).search);
      return undefined;
    }),
  );
  return asked;
}

const hideClosed = () => screen.findByRole('switch', { name: 'Hide closed' });
const caseRows = () => screen.getAllByRole('row').slice(1);
const HIDING = 'Hiding closed cases: resolved, blocked, escalated and failed.';

describe('the closed states, one list for the app and the server', () => {
  const root = join(__dirname, '../../../..');
  const quoted = (list: string) => [...list.matchAll(/['"]([a-z_]+)['"]/g)].map((m) => m[1]);

  it("is the server's filter for open=1 (Shutter.API.Dispatch.CasesWhere)", () => {
    const source = readFileSync(join(root, 'src/Shutter/API/Dispatch.cls'), 'utf8');
    const method = /ClassMethod CasesWhere\([\s\S]*?\n}\n/.exec(source);
    const list = /State NOT IN \(([^)]*)\)/.exec(method![0]);
    expect(quoted(list![1])).toEqual([...CLOSED_STATES]);
  });

  it("is what the server calls closed (Shutter.Store.Case.IsClosed), which the filter's unit test checks there", () => {
    const source = readFileSync(join(root, 'src/Shutter/Store/Case.cls'), 'utf8');
    const method = /Method IsClosed\(\)[\s\S]*?\n}\n/.exec(source);
    const list = /\$LISTBUILD\(([^)]*)\)/.exec(method![0]);
    expect(quoted(list![1])).toEqual([...CLOSED_STATES]);
  });
});

describe("the trial's API, open=1", () => {
  it('leaves out the closed cases and counts what is left, as the server does', async () => {
    const all = await api.get<CaseList>('/cases');
    const open = await api.get<CaseList>('/cases?open=1');
    // The trial holds one recorded case at its approval: the only one not closed
    expect(all.total).toBe(64);
    expect(open.total).toBe(1);
    expect(open.items.map((c) => c.state)).toEqual(['awaiting_approval']);
    expect(open.total).toBe(all.items.filter((c) => !CLOSED_STATES.includes(c.state)).length);
  });

  it('counts and pages the same rows, beside a state and a scenario', async () => {
    const page = await api.get<CaseList>('/cases?open=1&limit=25&offset=25');
    expect(page).toEqual({ items: [], total: 1 });
    expect((await api.get<CaseList>('/cases?open=1&state=awaiting_approval')).total).toBe(1);
    expect((await api.get<CaseList>('/cases?open=1&state=resolved')).total).toBe(0);
    expect((await api.get<CaseList>('/cases?open=1&scenario=S2')).total).toBe(1);
    expect((await api.get<CaseList>('/cases?open=1&scenario=S3')).total).toBe(0);
  });

  it('filters nothing for any other value', async () => {
    for (const value of ['0', 'true', ''])
      expect((await api.get<CaseList>(`/cases?open=${value}`)).total).toBe(64);
  });
});

describe('Hide closed', () => {
  it('is off by default: the list, its count, its address and its requests are as they were', async () => {
    const asked = listRequests();
    const router = renderList();
    expect(await hideClosed()).not.toBeChecked();
    expect(await screen.findByText('64 cases')).toBeVisible();
    await waitFor(() => expect(caseRows()).toHaveLength(25));
    expect(router.state.location.search).toBe('');
    expect(screen.queryByText(HIDING)).not.toBeInTheDocument();
    expect(asked.length).toBeGreaterThan(0);
    expect(asked.filter((q) => q.includes('open'))).toEqual([]);
    expect(asked).toContain('?limit=25&offset=0');
  });

  it('turned on, asks the server for the open cases, keeps open=1 in the address and says what is hidden', async () => {
    const asked = listRequests();
    const router = renderList();
    await screen.findByText('64 cases');
    await userEvent.click(await hideClosed());
    expect(await screen.findByText('1 open case')).toBeVisible();
    expect(await hideClosed()).toBeChecked();
    expect(router.state.location.search).toBe('?open=1');
    expect(asked).toContain('?open=1&limit=25&offset=0');
    expect(screen.getByText(HIDING)).toBeVisible();
    await waitFor(() => expect(caseRows()).toHaveLength(1));
    expect(within(caseRows()[0]).getAllByText('Waiting for approval').length).toBeGreaterThan(0);
    // The tiles still count every case: they are the way to the closed ones
    expect(screen.getByRole('button', { name: /^15 Escalated Show these$/ })).toBeVisible();

    await userEvent.click(await hideClosed());
    expect(await screen.findByText('64 cases')).toBeVisible();
    expect(router.state.location.search).toBe('');
    expect(screen.queryByText(HIDING)).not.toBeInTheDocument();
  });

  it('starts on from an address that has open=1, on the first page of the open cases', async () => {
    const asked = listRequests();
    renderList('/cases?open=1');
    expect(await hideClosed()).toBeChecked();
    expect(await screen.findByText('1 open case')).toBeVisible();
    expect(asked).toContain('?open=1&limit=25&offset=0');
    expect(asked).not.toContain('?limit=25&offset=0');
  });

  it('is kept by Back from a case', async () => {
    const router = renderList();
    await screen.findByText('64 cases');
    await userEvent.click(await hideClosed());
    await screen.findByText('1 open case');
    await userEvent.click(await screen.findByRole('link', { name: 'C-000002' }));
    expect(await screen.findByRole('heading', { name: 'Case C-000002' })).toBeVisible();
    expect(router.state.location.pathname).toBe('/cases/C-000002');
    await userEvent.click(screen.getByRole('button', { name: 'Back' }));
    expect(await hideClosed()).toBeChecked();
    expect(router.state.location.pathname + router.state.location.search).toBe('/cases?open=1');
    expect(await screen.findByText('1 open case')).toBeVisible();
    expect(screen.getByRole('link', { name: 'C-000002' })).toBeVisible();
  });

  it('is turned off by a Closed tile, so the list shows the outcome just chosen', async () => {
    const router = renderList('/cases?open=1');
    await screen.findByText('1 open case');
    const tile = await screen.findByRole('button', { name: /^26 Delivered, verified Show these$/ });
    await userEvent.click(tile);
    expect(await screen.findByText('26 cases')).toBeVisible();
    expect(await hideClosed()).not.toBeChecked();
    expect(router.state.location.search).toBe('?outcome=delivered');
    expect(tile).toHaveAttribute('aria-pressed', 'true');
    expect(screen.queryByText(HIDING)).not.toBeInTheDocument();
  });

  it('is turned off by a closed State, from the select or a Needs a person tile, and kept by an open one', async () => {
    const router = renderList('/cases?open=1');
    await screen.findByText('1 open case');
    const state = screen.getByLabelText('State', { exact: true });
    // An open state: the switch stays on beside it
    await userEvent.selectOptions(state, 'Waiting for approval');
    await waitFor(() => expect(router.state.location.search).toBe('?open=1&state=awaiting_approval'));
    expect(await hideClosed()).toBeChecked();
    expect(await screen.findByText('1 open case')).toBeVisible();
    // A closed one from the select
    await userEvent.selectOptions(state, 'Resolved');
    expect(await screen.findByText('39 cases')).toBeVisible();
    expect(await hideClosed()).not.toBeChecked();
    expect(router.state.location.search).toBe('?state=resolved');
    // On again: the closed state gives way to the switch, the newer choice
    await userEvent.click(await hideClosed());
    expect(await screen.findByText('1 open case')).toBeVisible();
    expect(router.state.location.search).toBe('?open=1');
    expect(state).toHaveValue('');
    // An escalated case is closed too: its tile turns the switch off
    await userEvent.click(screen.getByRole('button', { name: /^15 Escalated Show these$/ }));
    expect(await screen.findByText('15 cases')).toBeVisible();
    expect(await hideClosed()).not.toBeChecked();
    expect(router.state.location.search).toBe('?state=escalated');
  });

  it('turned on over a Closed tile, clears the tile and keeps the scenario', async () => {
    const router = renderList('/cases?outcome=delivered&scenario=S2');
    const tile = await screen.findByRole('button', {
      name: /Delivered, verified Showing these; press to clear$/,
    });
    expect(await hideClosed()).not.toBeChecked();
    await userEvent.click(await hideClosed());
    expect(await screen.findByText('1 open case')).toBeVisible();
    expect(router.state.location.search).toBe('?scenario=S2&open=1');
    expect(tile).toHaveAttribute('aria-pressed', 'false');
    expect(screen.getByLabelText('Scenario', { exact: true })).toHaveValue('S2');
  });

  it('gives way to a closed choice in the same address: the list never shows nothing for it', async () => {
    const asked = listRequests();
    renderList('/cases?open=1&state=escalated');
    expect(await screen.findByText('15 cases')).toBeVisible();
    expect(await hideClosed()).not.toBeChecked();
    expect(asked).toContain('?state=escalated&limit=25&offset=0');
    expect(asked.filter((q) => q.includes('open'))).toEqual([]);
  });

  it('says so when no case is open, and Show every case turns it off', async () => {
    const closed = summaries.filter((c) => CLOSED_STATES.includes(c.state));
    serve(closed);
    const router = renderList('/cases?open=1');
    expect(await screen.findByText('No open cases. Closed cases are hidden.')).toBeVisible();
    expect(screen.getByText('0 open cases')).toBeVisible();
    await userEvent.click(screen.getByRole('button', { name: 'Show every case' }));
    expect(await screen.findByText(`${closed.length} cases`)).toBeVisible();
    expect(router.state.location.search).toBe('');
    expect(await hideClosed()).not.toBeChecked();
  });
});

// The list as the mock sends it: each summary with the writes and the verification counted from its attempts
const summaries = Object.values(recording.cases as unknown as Record<string, { summary: CaseSummary }>).map(
  (c) => ({ ...c.summary, ...writesOf(c as never) }),
);

/** Serves these cases as GET /cases does: newest first, with the state, scenario and open filters, a page and the total. */
function serve(cases: CaseSummary[]) {
  server.use(
    http.get('/api/shutter/cases', ({ request }) => {
      const q = new URL(request.url).searchParams;
      const state = q.get('state');
      const scenario = q.get('scenario');
      const rows = cases
        .filter((c) => (!state || c.state === state) && (!scenario || c.scenario === scenario))
        .filter((c) => q.get('open') !== '1' || !CLOSED_STATES.includes(c.state))
        .sort((a, b) => b.openedAt.localeCompare(a.openedAt));
      const offset = Number(q.get('offset') ?? 0);
      return HttpResponse.json({
        items: rows.slice(offset, offset + Number(q.get('limit') ?? 25)),
        total: rows.length,
      });
    }),
  );
}

describe('the scope of a closed outcome when there are more than 100 cases', () => {
  const delivered = summaries.find((c) => c.caseId === 'C-000058')!;
  const escalated = summaries.find((c) => c.state === 'escalated')!;
  /** Among the 100 most recent: seven deliveries. Older than those: two more deliveries and the only case closed by hand. */
  const RECENT_DELIVERIES = [3, 17, 29, 41, 58, 73, 99];
  const OLDER_DELIVERIES = [104, 120];
  const OLDER_BY_HAND = 110;
  const id = (i: number) => `C-${String(900 + i).padStart(6, '0')}`;
  const many: CaseSummary[] = Array.from({ length: 130 }, (_, i) => ({
    ...(RECENT_DELIVERIES.includes(i) || OLDER_DELIVERIES.includes(i)
      ? delivered
      : i === OLDER_BY_HAND
        ? { ...delivered, disposition: 'handled_by_hand' }
        : escalated),
    caseId: id(i),
    openedAt: new Date(Date.UTC(2026, 10, 1, 5, 0, 0) - i * 60_000).toISOString(),
  }));

  it('says how many match among the 100 most recent, and that older cases were not searched', async () => {
    serve(many);
    renderList();
    const closed = await screen.findByRole('region', { name: 'Closed, in the newest 100' });
    await userEvent.click(
      await within(closed).findByRole('button', { name: /^7 Delivered, verified Show these$/ }),
    );
    expect(
      await screen.findByText(
        '7 matches among the 100 most recent cases. Older cases have not been searched.',
      ),
    ).toBeVisible();
    await waitFor(() => expect(caseRows()).toHaveLength(7));
    // The older deliveries are real and are not in the list: the caption says why
    for (const i of OLDER_DELIVERIES)
      expect(screen.queryByRole('link', { name: id(i) })).not.toBeInTheDocument();
    for (const i of RECENT_DELIVERIES) expect(screen.getByRole('link', { name: id(i) })).toBeVisible();
    // One count, with its scope: no bare "7 cases" beside it, and nothing of the old caption
    expect(screen.queryByText('7 cases')).not.toBeInTheDocument();
    expect(screen.queryByText(/Showing the newest 100 cases/)).not.toBeInTheDocument();
  });

  it('says "no matches in the 100 most recent" where an older case matches, never that there are none', async () => {
    serve(many);
    renderList();
    const closed = await screen.findByRole('region', { name: 'Closed, in the newest 100' });
    await userEvent.click(await within(closed).findByRole('button', { name: /^0 By hand Show these$/ }));
    expect(
      await screen.findByText('No matches in the 100 most recent cases. Older cases have not been searched.'),
    ).toBeVisible();
    expect(screen.queryByText('No cases match these filters.')).not.toBeInTheDocument();
    expect(screen.queryByRole('link', { name: id(OLDER_BY_HAND) })).not.toBeInTheDocument();
    expect(screen.queryByText('0 cases')).not.toBeInTheDocument();
  });

  it('gives a State, which the server searches in every case, its whole count with no such caption', async () => {
    serve(many);
    renderList();
    await screen.findByText('130 cases');
    await userEvent.selectOptions(screen.getByLabelText('State', { exact: true }), 'Resolved');
    // The seven recent deliveries, the two older ones and the case closed by hand
    expect(await screen.findByText('10 cases')).toBeVisible();
    expect(screen.getByRole('link', { name: id(OLDER_BY_HAND) })).toBeVisible();
    expect(screen.queryByText(/most recent cases/)).not.toBeInTheDocument();
  });

  it('keeps a plain count and no caption while the 100 hold every case', async () => {
    renderList('/cases?outcome=delivered');
    expect(await screen.findByText('26 cases')).toBeVisible();
    expect(screen.queryByText(/most recent cases/)).not.toBeInTheDocument();
  });
});

describe('the failed count', () => {
  /** GET /cases?state=failed as a server with this many failed cases answers a read of 100. */
  const failedCases = (total: number, abandoned: number) =>
    server.use(
      http.get('/api/shutter/cases', ({ request }) => {
        if (new URL(request.url).searchParams.get('state') !== 'failed') return undefined;
        return HttpResponse.json({
          items: Array.from({ length: Math.min(total, 100) }, (_, i) => ({
            caseId: `C-F${i}`,
            state: 'failed',
            disposition: i < abandoned ? 'abandoned' : '',
          })),
          total,
        });
      }),
    );

  it('reads "at most" when more cases failed than were read, since older ones given up are still in it', async () => {
    failedCases(150, 3);
    renderList();
    const need = await screen.findByRole('region', { name: 'Needs a person' });
    const tile = await within(need).findByRole('button', { name: /^At most 147 Failed Show these$/ });
    expect(within(tile).getByText('Failed, at most')).toBeVisible();
    expect(
      screen.getByText(
        /Failed is at most its figure: cases a person gave up are taken off among the 100 newest/,
      ),
    ).toBeInTheDocument();
  });

  it('is exact, and says nothing more, when every failed case was read', async () => {
    failedCases(40, 3);
    renderList();
    const need = await screen.findByRole('region', { name: 'Needs a person' });
    const tile = await within(need).findByRole('button', { name: /^37 Failed Show these$/ });
    expect(within(tile).getByText('Failed')).toBeVisible();
    expect(screen.queryByText(/at most/i)).not.toBeInTheDocument();
  });
});

describe('the empty list, by what the install can do', () => {
  const noCases = () =>
    server.use(http.get('/api/shutter/cases', () => HttpResponse.json({ items: [], total: 0 })));
  const healthIs = (report: Health) =>
    server.use(http.get('/api/shutter/health', () => HttpResponse.json(report)));
  const guidance = async () => {
    const box = await screen.findByTestId('no-cases');
    await waitFor(() => expect(box).not.toHaveAttribute('data-install', 'unknown'));
    return box;
  };

  it('offers a recorded scenario in the trial', async () => {
    env.trial = true;
    noCases();
    renderList();
    const box = await guidance();
    expect(box).toHaveAttribute('data-install', 'trial');
    expect(box).toHaveTextContent('No cases yet. Play a recorded scenario to open one.');
    expect(within(box).getByRole('link', { name: 'Play a scenario' })).toHaveAttribute('href', '/scenarios');
  });

  it('offers a scenario on a demo install, as before', async () => {
    noCases();
    healthIs(DEMO_INSTALL);
    renderList();
    const box = await guidance();
    expect(box).toHaveAttribute('data-install', 'demo');
    expect(box).toHaveTextContent('No cases yet. Play a scenario to open one.');
    expect(within(box).getByRole('link', { name: 'Play a scenario' })).toHaveAttribute('href', '/scenarios');
  });

  it('tells a demo sign-in that may not run scenarios who can, with no button it cannot use', async () => {
    noCases();
    healthIs(DEMO_INSTALL);
    server.use(http.get('/api/shutter/me', () => HttpResponse.json(LOOK_ONLY_DEMO)));
    renderList();
    const box = await guidance();
    await waitFor(() =>
      expect(box).toHaveTextContent(
        'No cases yet. An operator, approver or judge opens one by playing a scenario.',
      ),
    );
    expect(within(box).queryByRole('link', { name: 'Play a scenario' })).not.toBeInTheDocument();
    expect(within(box).getByRole('link', { name: 'See the scenarios' })).toHaveAttribute(
      'href',
      '/scenarios',
    );
  });

  it('tells a site with an intake that nothing has failed yet, and never to play a scenario', async () => {
    noCases();
    healthIs(SITE_WITH_INTAKE);
    renderList();
    const box = await guidance();
    expect(box).toHaveAttribute('data-install', 'site-intake');
    expect(box).toHaveTextContent(
      'No failed delivery has reached Shutter yet. It watches PATHOLOGY and DOCUMENTS.',
    );
    expect(within(box).getByRole('link', { name: 'If one was expected, check Health' })).toHaveAttribute(
      'href',
      '/health',
    );
    expect(box).not.toHaveTextContent(/scenario/i);
  });

  it('names the missing step on a site awaiting set-up, with its page for someone who may configure', async () => {
    noCases();
    healthIs(SITE_AWAITING_SETUP);
    renderList();
    const box = await guidance();
    expect(box).toHaveAttribute('data-install', 'site-setup');
    await waitFor(() =>
      expect(box).toHaveTextContent('No cases yet. No watched namespace reports its failures here.'),
    );
    expect(within(box).getByRole('link', { name: 'Set up a watched namespace' })).toHaveAttribute(
      'href',
      '/settings/namespaces',
    );
    expect(box).not.toHaveTextContent(/scenario/i);
  });

  it('gives an operator there the reason and Health, not a set-up page that would refuse them', async () => {
    resetMock('operator');
    noCases();
    healthIs(SITE_AWAITING_SETUP);
    renderList();
    const box = await guidance();
    await waitFor(() =>
      expect(box).toHaveTextContent(
        'No cases yet. No watched namespace reports its failures here; someone who may configure Shutter sets one up.',
      ),
    );
    expect(within(box).queryByRole('link', { name: 'Set up a watched namespace' })).not.toBeInTheDocument();
    expect(within(box).getByRole('link', { name: 'See what Health reports' })).toHaveAttribute(
      'href',
      '/health',
    );
  });

  it('says only that there are none when the health report cannot be read', async () => {
    noCases();
    server.use(
      http.get('/api/shutter/health', () =>
        HttpResponse.json({ error: 'forbidden', detail: 'This needs Shutter_Operate' }, { status: 403 }),
      ),
    );
    renderList();
    const box = await screen.findByTestId('no-cases');
    expect(box).toHaveAttribute('data-install', 'unknown');
    expect(box).toHaveTextContent('No cases yet.');
    expect(within(box).getByRole('link', { name: 'Open Health' })).toHaveAttribute('href', '/health');
    expect(box).not.toHaveTextContent(/scenario/i);
  });

  it('asks for the health report only when the list is empty', async () => {
    let asked = 0;
    server.use(
      http.get('/api/shutter/health', () => {
        asked += 1;
        return undefined;
      }),
    );
    renderList();
    await screen.findByText('64 cases');
    await waitFor(() => expect(caseRows()).toHaveLength(25));
    expect(asked).toBe(0);
  });

  it('keeps the filtered words for a filter that matches nothing, whatever the install', async () => {
    healthIs(SITE_AWAITING_SETUP);
    renderList('/cases?state=failed');
    expect(await screen.findByText('No cases match these filters.')).toBeVisible();
    expect(screen.getByRole('button', { name: 'Show every case' })).toBeVisible();
    expect(screen.queryByTestId('no-cases')).not.toBeInTheDocument();
  });
});
