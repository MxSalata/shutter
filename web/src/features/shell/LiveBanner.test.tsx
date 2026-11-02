import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor, within } from '@testing-library/react';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { LiveStatus } from '@/api/types';
import fixtures from '@/mocks/fixtures.json';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { theme } from '@/theme';
import { LIVE_WELCOME_KEY } from '@/trial/LiveWelcome';
import { AppLayout } from './AppLayout';

const BASE = '/api/shutter';

beforeAll(() => {
  server.listen({ onUnhandledRequest: 'error' });
  // The frame restores the scroll on every page; jsdom has no scrolling
  window.scrollTo = () => {};
});
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

/** The real frame of the app, with two stand-in pages: the banner belongs to the frame, not to a page. */
function renderFrame(path = '/cases') {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter(
    [
      {
        element: <AppLayout />,
        children: [
          { path: '/cases', element: <h1>Cases page</h1> },
          { path: '/library', element: <h1>Library page</h1> },
        ],
      },
    ],
    { initialEntries: [path] },
  );
  const view = render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
  return { router, ...view };
}

/** The mock's settings with a `live` object (or none) laid over them. */
function settingsWith(live: Partial<LiveStatus> | undefined) {
  server.use(
    http.get(`${BASE}/settings`, () =>
      HttpResponse.json({
        ...fixtures.settings,
        ...(live ? { live } : {}),
      }),
    ),
  );
}

const minutesAgo = (n: number) => new Date(Date.now() - n * 60_000).toISOString();
const inMinutes = (n: number) => minutesAgo(-n);
const banner = () => screen.findByLabelText('Live hospital');
/** The banner's line alone: for a user who operates, the banner also carries "Break the feed" (features/storm). */
const line = async () => within(await banner()).getByTestId('live-line');
const noBanner = async () => {
  // The settings are read by the banner; wait for the page, then for a beat that the banner is not coming
  await screen.findByRole('heading', { name: /page$/ });
  await new Promise((r) => setTimeout(r, 150));
  expect(screen.queryByLabelText('Live hospital')).not.toBeInTheDocument();
};

describe('the live hospital banner', () => {
  beforeEach(() => {
    resetMock('approver');
    // The live first-run prompt would open over every page here; it has tests of its own
    localStorage.setItem(LIVE_WELCOME_KEY, 'seen');
  });

  it('tells how often a failure arrives and what played last, on every page', async () => {
    settingsWith({
      enabled: true,
      every_minutes: 7,
      last_played: { scenario: 'S23a', title: 'the bed is occupied', at: minutesAgo(4) },
    });
    const { router } = renderFrame('/cases');
    expect(await banner()).toHaveTextContent(
      'Live hospital: a new failure every 7 minutes. Last: S23a, 4 min ago.',
    );
    await router.navigate('/library');
    expect(await screen.findByRole('heading', { name: 'Library page' })).toBeInTheDocument();
    expect(await banner()).toHaveTextContent('Live hospital: a new failure every 7 minutes.');
  });

  it('shows for the public demo role of the mock, which is signed in to a live hospital', async () => {
    resetMock('demo');
    renderFrame();
    expect(await line()).toHaveTextContent(
      /^Live hospital: a new failure every 7 minutes\. Last: S2, 4 min ago\. Next: S8 at \d\d:\d\d (GMT|BST|UTC)\.$/,
    );
  });

  it("keeps the story's title for a tooltip on its code, so the line stays short", async () => {
    settingsWith({
      enabled: true,
      every_minutes: 7,
      last_played: { scenario: 'S23a', title: 'the bed is occupied', at: minutesAgo(4) },
    });
    renderFrame();
    const b = await banner();
    expect(b).not.toHaveTextContent('the bed is occupied');
    expect(within(b).getByText('S23a')).toHaveAttribute('tabindex', '0');
  });

  it('names the story due next and when, only while that time is still ahead', async () => {
    settingsWith({
      enabled: true,
      every_minutes: 7,
      last_played: { scenario: 'S2', title: 'a lost transfer', at: minutesAgo(4) },
      next: { scenario: 'S8', at: inMinutes(3) },
    });
    const first = renderFrame();
    expect(await line()).toHaveTextContent(/ Next: S8 at \d\d:\d\d (GMT|BST|UTC)\.$/);
    first.unmount();
    // A story that was due and has not played: the player is behind or stopped, so no time is promised
    settingsWith({
      enabled: true,
      every_minutes: 7,
      last_played: { scenario: 'S2', title: 'a lost transfer', at: minutesAgo(12) },
      next: { scenario: 'S8', at: minutesAgo(5) },
    });
    renderFrame();
    expect(await banner()).not.toHaveTextContent('Next:');
  });

  it('says every minute for a one-minute interval, and leaves out a last story that has not played', async () => {
    settingsWith({ enabled: true, every_minutes: 1, last_played: null });
    renderFrame();
    const text = await line();
    expect(text).toHaveTextContent(/^Live hospital: a new failure every minute\.$/);
    expect(text).not.toHaveTextContent('Last:');
  });

  it('does not say a number when the server gave none', async () => {
    settingsWith({ enabled: true });
    renderFrame();
    expect(await banner()).toHaveTextContent('Live hospital: a new failure every few minutes.');
  });

  it('is hidden when the settings carry no live object', async () => {
    settingsWith(undefined);
    renderFrame();
    await noBanner();
  });

  it('is hidden for the `{enabled: false}` an instance with no hospital reports', async () => {
    settingsWith({ enabled: false });
    renderFrame();
    await noBanner();
  });

  it('is hidden when the live hospital is not enabled', async () => {
    settingsWith({ enabled: false, every_minutes: 7 });
    renderFrame();
    await noBanner();
  });

  it('is hidden for whoever cannot read the settings', async () => {
    server.use(
      http.get(`${BASE}/settings`, () =>
        HttpResponse.json({ error: 'forbidden', message: 'Needs the operator role' }, { status: 403 }),
      ),
    );
    renderFrame();
    await noBanner();
  });

  it('is not shown by the mock to an approver, who is on the recorded demo', async () => {
    renderFrame();
    await noBanner();
    await waitFor(() => expect(screen.queryByLabelText('Live hospital')).toBeNull());
  });
});
