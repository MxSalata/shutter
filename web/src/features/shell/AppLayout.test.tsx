import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, within } from '@testing-library/react';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { theme } from '@/theme';
import { LIVE_WELCOME_KEY } from '@/trial/LiveWelcome';
import { AppLayout } from './AppLayout';

beforeAll(() => {
  server.listen({ onUnhandledRequest: 'error' });
  window.scrollTo = () => {};
});
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

function renderFrame(path = '/cases/C-000002') {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter(
    [{ element: <AppLayout />, children: [{ path: '*', element: <h1>A page</h1> }] }],
    { initialEntries: [path] },
  );
  render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

describe('the shell', () => {
  beforeEach(() => {
    resetMock('approver');
    localStorage.setItem(LIVE_WELCOME_KEY, 'seen');
  });

  it('groups the navigation as Operate, Results and Configure, each icon in its section hue', async () => {
    renderFrame();
    const nav = await screen.findByRole('navigation', { name: 'Main' });
    const groups = within(nav).getAllByRole('group');
    expect(groups.map((g) => within(g).getAllByText(/./)[0].textContent)).toEqual([
      'Operate',
      'Results',
      'Configure',
    ]);
    expect(
      within(groups[1])
        .getAllByRole('link')
        .map((a) => a.textContent),
    ).toEqual(['Evaluation', 'Health']);
    const hues = Object.fromEntries(
      within(nav)
        .getAllByRole('link')
        .map((a) => [a.textContent?.replace(/\d+$/, ''), a.style.getPropertyValue('--nav-icon')]),
    );
    expect(hues).toMatchObject({
      Scenarios: 'var(--shutter-hue-cyan)',
      Cases: 'var(--shutter-hue-indigo)',
      Incidents: 'var(--shutter-hue-pink)',
      'Production review': 'var(--shutter-hue-violet)',
      Evaluation: 'var(--shutter-hue-teal)',
      Health: 'var(--shutter-hue-indigo)',
      'Site profile': 'var(--shutter-hue-teal)',
      'Agent library': 'var(--shutter-hue-violet)',
      'Settings and costs': 'var(--shutter-hue-cyan)',
    });
    // A case's page is under Cases: its entry is the active one
    expect(within(nav).getByRole('link', { name: /^Cases/ })).toHaveAttribute('data-active');
    expect(within(nav).getByRole('link', { name: 'Scenarios' })).not.toHaveAttribute('data-active');
  });

  it('counts the cases that need a person beside Cases, in words for a screen reader', async () => {
    renderFrame();
    // The recording holds one case waiting for an approval, and its escalated and blocked cases
    const cases = await screen.findByRole('link', { name: /^Cases \d+ cases? needs? a person$/ });
    expect(within(cases).getByText(/^\d+$/)).toBeInTheDocument();
  });

  it('shows no count when no case needs a person', async () => {
    server.use(http.get('/api/shutter/cases', () => HttpResponse.json({ items: [], total: 0 })));
    renderFrame();
    expect(await screen.findByRole('heading', { name: 'A page' })).toBeInTheDocument();
    await new Promise((r) => setTimeout(r, 200));
    expect(screen.getByRole('link', { name: 'Cases' })).toBeInTheDocument();
    expect(screen.queryByText(/needs? a person/)).not.toBeInTheDocument();
  });

  it('carries the Detail switch in the header, and offers the trial from Help on a live page', async () => {
    renderFrame();
    const header = (await screen.findByRole('heading', { name: 'A page' })).ownerDocument.querySelector(
      'header',
    )!;
    expect(within(header).getByRole('radiogroup', { name: 'Detail' })).toBeInTheDocument();
    expect(within(header).getByRole('button', { name: 'Help' })).toBeInTheDocument();
    // A live page has no trial chrome: no banner, no pill
    expect(screen.queryByRole('region', { name: 'Trial environment' })).not.toBeInTheDocument();
    expect(header.querySelector('.trial-pill')).toBeNull();
    expect(within(header).queryByText('DEMO')).not.toBeInTheDocument();
  });
});
