import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, within } from '@testing-library/react';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { SECTIONS } from '@/features/shell/sections';
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

function renderHome(can: Record<string, boolean> = ALL) {
  server.use(http.get('/api/shutter/me', () => HttpResponse.json(me(can))));
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
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

  it('starts someone new at the scenarios', async () => {
    renderHome();
    const start = await screen.findByRole('link', { name: 'Open the scenarios' });
    expect(start).toHaveAttribute('href', '/scenarios');
    expect(screen.getByText(/Start with S8/)).toBeInTheDocument();
  });

  it('starts the public demo, who cannot run scenarios, at the cases', async () => {
    renderHome({ ...ALL, configure: false, scenarios: false });
    const start = await screen.findByRole('link', { name: 'Open the cases' });
    expect(start).toHaveAttribute('href', '/cases');
    expect(screen.queryByText(/Start with S8/)).not.toBeInTheDocument();
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

  it('stays within its word budget', async () => {
    const { container } = renderHome();
    await screen.findByRole('heading', { level: 1, name: 'Home' });
    expect(layer1Words(container).length).toBeLessThanOrEqual(205);
  });
});
