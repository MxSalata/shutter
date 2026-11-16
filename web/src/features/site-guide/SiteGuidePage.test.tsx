import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { catalogueView, resetMock, SITE_ENTRIES_EXAMPLE } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { useAppearance } from '@/stores/appearance';
import { theme } from '@/theme';
import SiteGuidePage from './SiteGuidePage';

/** This site's guide on a live page: every part from the install's answers, the stamp, the site's own entries, rights. */

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => {
  server.resetHandlers();
  useAppearance.setState({ detail: 'plain' });
});
afterAll(() => server.close());
beforeEach(() => resetMock('operator'));

function renderGuide() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter(
    [
      { path: '/site-guide', element: <SiteGuidePage /> },
      { path: '/site-profile', element: <p>Site profile</p> },
    ],
    { initialEntries: ['/site-guide'] },
  );
  return render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

const PARTS = [
  'Your receivers',
  'Site-wide settings',
  'The gate',
  'Every scenario and what Shutter does with it here',
  'Limits',
];

describe("This site's guide", () => {
  it('has the cover and the five parts in order, with the stamp at the foot of each', async () => {
    renderGuide();
    expect(await screen.findByRole('heading', { level: 1, name: "This site's guide" })).toBeInTheDocument();
    expect(screen.getAllByRole('heading', { level: 2 }).map((h) => h.textContent)).toEqual(PARTS);
    const feet = screen.getAllByTestId('site-guide-foot');
    expect(feet).toHaveLength(6);
    const view = catalogueView();
    for (const f of feet) {
      expect(f.textContent).toContain('Site profile version 7');
      expect(f.textContent).toContain(`catalogue ${view.version}`);
      expect(f.textContent).toContain('gate policy 2026-11-01.1');
      expect(f.textContent).toContain('release 1.4.8');
      expect(f.textContent).toMatch(/exported \d+ \w+ \d{4}/);
      expect(f.textContent).not.toContain('Trial');
    }
    const stamp = screen.getByTestId('site-guide-stamp');
    expect(stamp).toHaveTextContent('Version 7, saved 26 Oct 2026');
    expect(stamp).toHaveTextContent("by Setup (the demo's answers)");
    expect(stamp).toHaveTextContent('This guide describes these versions only.');
  });

  it('describes every receiver of the profile, and the gate’s twelve checks with when each decides', async () => {
    renderGuide();
    const beds = await screen.findByTestId('site-guide-receiver-Downstream Out');
    expect(within(beds).getByText('What Shutter may do here')).toBeInTheDocument();
    expect(beds).toHaveTextContent('Overtaken failure: closes, no write.');
    expect(beds).toHaveTextContent('Shutter never sends it a cancel');
    expect(beds).toHaveTextContent('Shutter Approvers approve its writes');
    expect(screen.getByTestId('site-guide-receiver-Records Out')).toHaveTextContent(
      'Overtaken failure: asks a person to correct by hand.',
    );
    const checks = screen.getByRole('table', { name: "The gate's twelve checks" });
    expect(within(checks).getAllByRole('row')).toHaveLength(13);
    expect(checks).toHaveTextContent('Decides at the approval and at the dispatch');
    expect(screen.getByText('An unknown answer blocks a write, as a block does.')).toBeInTheDocument();
  });

  it('lists every shipped entry with who decides here, the outcome at each receiver and its scenario', async () => {
    renderGuide();
    await screen.findByRole('heading', { level: 1 });
    for (const e of catalogueView().shipped)
      expect(screen.getByTestId(`site-guide-entry-${e.id}`)).toBeInTheDocument();
    const e1 = screen.getByTestId('site-guide-entry-E1');
    expect(e1).toHaveTextContent('Who decides here: by site policy.');
    expect(e1).toHaveTextContent('At Downstream Out');
    expect(e1).toHaveTextContent('a correction of the history by a person (its alternative 1)');
    expect(e1).toHaveTextContent('Shown in the scenarios S1 (');
    expect(screen.queryByText("This site's own entries")).toBeNull();
  });

  it("marks the site's own entries, with their instructions and who approved each and when", async () => {
    const example = SITE_ENTRIES_EXAMPLE.items[0];
    server.use(
      http.get('/api/shutter/catalogue', () =>
        HttpResponse.json({
          ...catalogueView(),
          version: `${catalogueView().version};g1:L1@1`,
          site: [
            {
              ...example.content,
              version: 1,
              origin: 'site',
              decides: 'person',
              preferred: { outcome: 'escalate', why: example.content!.why },
              alternatives: [],
              sentence: example.sentence,
            },
          ],
        }),
      ),
      http.get('/api/shutter/site-entries', () => HttpResponse.json(SITE_ENTRIES_EXAMPLE)),
    );
    renderGuide();
    const own = await screen.findByTestId('site-guide-entry-L1');
    expect(within(own).getByText("This site's own")).toBeInTheDocument();
    expect(own).toHaveTextContent(
      "Ring the ward's nurse in charge before anything is entered. Do not resend.",
    );
    expect(own).toHaveTextContent('Version 1, approved by approver, 15 Nov 2026');
    expect(own).toHaveTextContent('Who decides here: decided by a person.');
    expect(screen.getAllByTestId('site-guide-foot')[0]).toHaveTextContent(';g1:L1@1');
  });

  it('shows the Technical names beside the plain words only in Technical', async () => {
    renderGuide();
    await screen.findByRole('heading', { level: 1 });
    expect(screen.queryByText('state_transition')).toBeNull();
    await userEvent.click(screen.getByRole('radio', { name: 'Technical' }));
    expect(screen.getByText('state_transition')).toBeInTheDocument();
    expect(screen.getAllByText('decides: policy').length).toBeGreaterThan(0);
  });

  it('prints from the toolbar and goes back to the Site profile', async () => {
    const print = vi.spyOn(window, 'print').mockImplementation(() => {});
    renderGuide();
    await screen.findByRole('heading', { level: 1 });
    await userEvent.click(screen.getByRole('button', { name: 'Print or save as PDF' }));
    expect(print).toHaveBeenCalledOnce();
    print.mockRestore();
    expect(screen.getByRole('link', { name: 'Site profile' })).toHaveAttribute('href', '/site-profile');
  });

  it('says what is missing when a reader may not read the profile, and writes nothing', async () => {
    const writes: string[] = [];
    server.events.on('request:start', ({ request }) => {
      if (request.method !== 'GET') writes.push(`${request.method} ${request.url}`);
    });
    server.use(
      http.get('/api/shutter/site-profile', () =>
        HttpResponse.json({ error: 'forbidden', detail: 'This needs Shutter_Operate' }, { status: 403 }),
      ),
    );
    renderGuide();
    expect(await screen.findByText('This guide needs the operator or approver role')).toBeInTheDocument();
    expect(writes).toEqual([]);
    server.events.removeAllListeners();
  });
});
