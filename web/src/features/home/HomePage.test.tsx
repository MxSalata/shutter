import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor, within } from '@testing-library/react';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { PORTAL_PAGE, SECTIONS } from '@/features/shell/sections';
import { server } from '@/mocks/node';
import { resetMock } from '@/mocks/handlers';
import { layer1Words } from '@/test/words';
import { theme } from '@/theme';
import HomePage from './HomePage';

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

const me = (can: Record<string, boolean>) => ({ username: 'someone', operator: true, approver: true, can });
const ALL = { operate: true, approve: true, configure: true, scenarios: true, liveAgents: false };

let client: QueryClient | undefined;

function renderHome(can: Record<string, boolean> = ALL) {
  server.use(http.get('/api/shutter/me', () => HttpResponse.json(me(can))));
  client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter([{ path: '/home', element: <HomePage /> }], {
    initialEntries: ['/home'],
  });
  return render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

describe('HomePage', () => {
  beforeEach(() => resetMock(null));

  it('has one h1, Home', async () => {
    renderHome();
    expect(await screen.findByRole('heading', { level: 1, name: 'Home' })).toBeInTheDocument();
    expect(screen.getAllByRole('heading', { level: 1 })).toHaveLength(1);
  });

  it('starts a site install from its cases, since it plays no scenarios', async () => {
    server.use(http.get('/api/shutter/health', () => HttpResponse.json({ ok: true, demo: false })));
    renderHome();
    expect(await screen.findByRole('link', { name: 'Open the cases' })).toHaveAttribute('href', '/cases');
    expect(screen.queryByText(/Start with S2/)).not.toBeInTheDocument();
  });

  it('tells a role that may not run scenarios to follow the recovery, not to run it', async () => {
    renderHome({ ...ALL, configure: false, scenarios: false });
    expect(await screen.findByText('Follow the recovery and who decided.')).toBeInTheDocument();
    expect(screen.queryByText('Run the recovery and follow it.')).not.toBeInTheDocument();
  });

  it('links to every section of the navigation and says what it is for', async () => {
    renderHome();
    await screen.findByRole('heading', { level: 1, name: 'Home' });
    for (const { group, items } of SECTIONS) {
      const region = screen.getByRole('region', { name: group });
      for (const item of items) {
        const link = within(region).getByRole('link', { name: new RegExp(`^${item.label}`) });
        expect(link).toHaveAttribute('href', item.to);
        expect(link).toHaveTextContent(item.about);
        expect(item.about.split(/\s+/).length).toBeLessThanOrEqual(15);
      }
    }
  });

  it('opens by saying what Shutter does', async () => {
    renderHome();
    const heading = await screen.findByRole('heading', { level: 1, name: 'Home' });
    const page = heading.closest('main') ?? document.body;
    // The term's definition sits inside the sentence's text, so the words are read either side of it
    expect(page.textContent).toMatch(/Shutter fixes a failed HL7 transfer/);
    expect(page.textContent).toMatch(
      /only when its checks pass\. Otherwise it stops and names the patient\./,
    );
  });

  it('starts someone new at the scenarios', async () => {
    renderHome();
    const start = await screen.findByRole('link', { name: 'Open the scenarios' });
    expect(start).toHaveAttribute('href', '/scenarios');
    expect(
      screen.getByText(
        /Start with S2, then S8, where a plain resend would write over the bed manager's ward with every check passed\./,
      ),
    ).toBeInTheDocument();
  });

  it('offers the public demo the case where the agents disagree and one to approve', async () => {
    server.use(
      http.get('/api/shutter/cases', ({ request }) => {
        const q = new URL(request.url).searchParams;
        if (q.get('scenario') === 'S8')
          return HttpResponse.json({ items: [{ caseId: 'C-000002', scenario: 'S8' }], total: 1 });
        if (q.get('scenario') === 'S2')
          return HttpResponse.json({ items: [{ caseId: 'C-000034', scenario: 'S2' }], total: 1 });
        return HttpResponse.json({ items: [{ caseId: 'C-000036', scenario: 'S23a' }], total: 2 });
      }),
    );
    renderHome({ ...ALL, configure: false, scenarios: false });
    expect(await screen.findByRole('link', { name: 'See the agents disagree: C-000002' })).toHaveAttribute(
      'href',
      '/cases/C-000002',
    );
    // S2's waiting plan, the plainest, before the newer one that waits on another case
    expect(await screen.findByRole('link', { name: 'Approve a fix yourself: C-000034' })).toHaveAttribute(
      'href',
      '/cases/C-000034',
    );
  });

  it('offers another waiting plan when S2 has none', async () => {
    server.use(
      http.get('/api/shutter/cases', ({ request }) => {
        const q = new URL(request.url).searchParams;
        if (q.get('scenario')) return HttpResponse.json({ items: [], total: 0 });
        return HttpResponse.json({ items: [{ caseId: 'C-000036', scenario: 'S23a' }], total: 1 });
      }),
    );
    renderHome({ ...ALL, configure: false, scenarios: false });
    expect(await screen.findByRole('link', { name: 'Approve a fix yourself: C-000036' })).toBeInTheDocument();
  });

  it('offers the public demo no such links while the cases do not exist', async () => {
    server.use(http.get('/api/shutter/cases', () => HttpResponse.json({ items: [], total: 0 })));
    renderHome({ ...ALL, configure: false, scenarios: false });
    await screen.findByRole('link', { name: 'Open the cases' });
    await waitFor(() => expect(client!.isFetching()).toBe(0));
    expect(screen.queryByTestId('home-cases-to-open')).not.toBeInTheDocument();
  });

  it('offers neither to someone who can run the scenarios', async () => {
    renderHome();
    await screen.findByRole('link', { name: 'Open the scenarios' });
    expect(screen.queryByTestId('home-cases-to-open')).not.toBeInTheDocument();
  });

  it('starts the public demo, who cannot run scenarios, at the cases', async () => {
    renderHome({ ...ALL, configure: false, scenarios: false });
    const start = await screen.findByRole('link', { name: 'Open the cases' });
    expect(start).toHaveAttribute('href', '/cases');
    expect(screen.queryByText(/Start with S2, then S8/)).not.toBeInTheDocument();
  });

  it('counts the cases that need a person, in words', async () => {
    server.use(
      http.get('/api/shutter/cases', ({ request }) => {
        const state = new URL(request.url).searchParams.get('state');
        return HttpResponse.json({ items: [], total: state === 'blocked' ? 2 : 0 });
      }),
    );
    renderHome();
    expect(await screen.findByText('2 need a person')).toBeInTheDocument();
  });

  it('says nothing beside Cases when no case needs a person', async () => {
    server.use(http.get('/api/shutter/cases', () => HttpResponse.json({ items: [], total: 0 })));
    renderHome();
    await screen.findByRole('heading', { level: 1, name: 'Home' });
    expect(screen.queryByText(/a person$/)).not.toBeInTheDocument();
  });

  it('says whether the production runs', async () => {
    server.use(
      http.get('/api/shutter/health', () => HttpResponse.json({ ok: false, production_state: 'stopped' })),
    );
    renderHome();
    expect(await screen.findByText('Production not running')).toBeInTheDocument();
  });

  it('points to the page inside IRIS on a demo instance, saying what the online demo asks first', async () => {
    server.use(http.get('/api/shutter/health', () => HttpResponse.json({ ok: true, demo: true })));
    renderHome();
    const link = await screen.findByRole('link', { name: /^Shutter in IRIS/ });
    expect(link).toHaveAttribute('href', PORTAL_PAGE.href);
    expect(link).toHaveAttribute('target', '_blank');
    expect(link).toHaveTextContent("What is running, and the board's case in the Visual Trace.");
    expect(link).toHaveTextContent('Online demo: Cloudflare sign-in first (GitHub or an emailed code).');
  });

  it('does not point to it on a site install, where the page answers 404', async () => {
    server.use(http.get('/api/shutter/health', () => HttpResponse.json({ ok: true, demo: false })));
    renderHome();
    await screen.findByRole('link', { name: 'Open the scenarios' });
    await waitFor(() => expect(client?.isFetching()).toBe(0));
    expect(screen.queryByRole('link', { name: /^Shutter in IRIS/ })).not.toBeInTheDocument();
  });

  it('stays within its word budget, the card to IRIS included', async () => {
    server.use(http.get('/api/shutter/health', () => HttpResponse.json({ ok: true, demo: true })));
    const { container } = renderHome();
    await screen.findByRole('heading', { level: 1, name: 'Home' });
    await screen.findByRole('link', { name: /^Shutter in IRIS/ });
    expect(layer1Words(container).length).toBeLessThanOrEqual(210);
  });
});
