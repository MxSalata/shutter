import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor, within } from '@testing-library/react';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { Budget, LiveStatus } from '@/api/types';
import fixtures from '@/mocks/fixtures.json';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { formatTime, zoneLabel } from '@/lib/format';
import { INSTALL_URL } from '@/lib/liveAgents';
import { axeViolations } from '@/test/axe';
import { layer1Words } from '@/test/words';
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
const banner = () => screen.findByLabelText("Mikolaj's Fictional Hospital, live");
/** The banner's line alone: for a user who operates, the banner also carries "Break the feed" (features/storm). */
const line = async () => within(await banner()).getByTestId('live-line');
const noBanner = async () => {
  // The settings are read by the banner; wait for the page, then for a beat that the banner is not coming
  await screen.findByRole('heading', { name: /page$/ });
  await new Promise((r) => setTimeout(r, 150));
  expect(screen.queryByLabelText("Mikolaj's Fictional Hospital, live")).not.toBeInTheDocument();
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
      "Mikolaj's Fictional Hospital, live: a new failure every 7 minutes. Last: S23a, 4 min ago.",
    );
    await router.navigate('/library');
    expect(await screen.findByRole('heading', { name: 'Library page' })).toBeInTheDocument();
    expect(await banner()).toHaveTextContent(
      "Mikolaj's Fictional Hospital, live: a new failure every 7 minutes.",
    );
  });

  it('shows for the public demo role of the mock, which is signed in to a live hospital', async () => {
    resetMock('demo');
    renderFrame();
    expect(await line()).toHaveTextContent(
      /^Mikolaj's Fictional Hospital, live: a new failure every 7 minutes\. Last: S2, 4 min ago\. Next: S8 at \d\d:\d\d (GMT|BST|UTC)\.$/,
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
    expect(text).toHaveTextContent(/^Mikolaj's Fictional Hospital, live: a new failure every minute\.$/);
    expect(text).not.toHaveTextContent('Last:');
  });

  it('does not say a number when the server gave none', async () => {
    settingsWith({ enabled: true });
    renderFrame();
    expect(await banner()).toHaveTextContent(
      "Mikolaj's Fictional Hospital, live: a new failure every few minutes.",
    );
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
    await waitFor(() => expect(screen.queryByLabelText("Mikolaj's Fictional Hospital, live")).toBeNull());
  });
});

/** The public demo's settings: the live hospital on, its budget and live.agents (v1.37) as a test gives them. */
function liveWith(live: Partial<LiveStatus>, budget?: Partial<Budget>) {
  server.use(
    http.get(`${BASE}/settings`, () =>
      HttpResponse.json({
        ...fixtures.settings,
        live: { enabled: true, every_minutes: 7, ...live },
        budget: { ...fixtures.settings.budget, ...budget },
      }),
    ),
  );
}

/** "20:00 GMT": a time as the banner says it. */
const clock = (iso: string) => `${formatTime(iso).slice(0, 5)} ${zoneLabel(iso)}`;
const budgetLine = async () => within(await banner()).findByTestId('live-budget-line');
const notice = async () => within(await banner()).findByRole('note');

describe('the live budget on the banner', () => {
  beforeEach(() => {
    resetMock('approver');
    localStorage.setItem(LIVE_WELCOME_KEY, 'seen');
  });

  it("says what the author pays, figure first, from the instance's own cap per hour, with the spend so far", async () => {
    liveWith({}, { dailyUsd: 2, spentTodayUsd: 0.4, exhausted: false });
    renderFrame();
    expect(await budgetLine()).toHaveTextContent(
      /^\$2 an hour, paid by the author, runs the live agents \(so far: \$0\.40\)\.$/,
    );
    expect(within(await banner()).queryByRole('note')).not.toBeInTheDocument();
    expect(within(await banner()).getByTestId('live-line')).toHaveTextContent(
      /^Mikolaj's Fictional Hospital, live: a new failure/,
    );
  });

  it("says the demo build's own figure alone when the server sends it", async () => {
    liveWith({ budgetNote: { amountUsd: 15, period: 'day' } }, { dailyUsd: 2, spentTodayUsd: 0.4 });
    renderFrame();
    expect(await budgetLine()).toHaveTextContent(/^\$15 a day, paid by the author, runs the live agents\.$/);
    expect(await budgetLine()).not.toHaveTextContent('so far');
  });

  it('says nothing about the budget when neither gives a positive figure', async () => {
    liveWith({ budgetNote: { amountUsd: 0, period: 'day' } }, { dailyUsd: 0 });
    renderFrame();
    expect(await line()).toBeInTheDocument();
    expect(within(await banner()).queryByTestId('live-budget-line')).not.toBeInTheDocument();
  });

  it('adds the notice under the line at the cap, with the hourly reset and the install link, and passes axe', async () => {
    const resets = inMinutes(40);
    liveWith({}, { dailyUsd: 2, spentTodayUsd: 2.05, exhausted: true, resetsAt: resets });
    renderFrame();
    const n = await notice();
    expect(layer1Words(n).join(' ')).toBe(
      `The live AI budget for this demo is used up until ${clock(resets)}, when the demo resets. Open cases, recorded runs and the trial still work. To run the live agents yourself, install Shutter with your own API key: how to install`,
    );
    expect(within(n).getByRole('link', { name: 'how to install' })).toHaveAttribute('href', INSTALL_URL);
    // The line stays: the notice follows it
    expect(await budgetLine()).toHaveTextContent(
      '$2 an hour, paid by the author, runs the live agents (so far: $2.05).',
    );
    // Plain words: the code is for Technical
    expect(await banner()).not.toHaveTextContent(/budget_exhausted|exhausted/);
    // Not a live region: it stands on every page
    expect(within(await banner()).queryByRole('status')).not.toBeInTheDocument();
    expect(await axeViolations(await banner())).toEqual([]);
  });

  it("says the user's own share apart from the cap", async () => {
    liveWith(
      {},
      // The server's next 00:00 UTC, hours away: the demo's own reset comes first
      {
        dailyUsd: 2,
        spentTodayUsd: 1,
        exhausted: true,
        perUserUsd: 1,
        spentByMeUsd: 1,
        shareExhausted: true,
        resetsAt: inMinutes(300),
      },
    );
    renderFrame();
    expect(await notice()).toHaveTextContent(
      "Your share of the live budget is used up until the demo's next reset, within the hour.",
    );
  });

  it('says the provider is refusing the key until the time live.agents gives, never the hourly reset', async () => {
    const until = inMinutes(200);
    liveWith(
      { agents: { available: false, reason: 'provider_auth', until, detail: 'refused (provider_auth)' } },
      { dailyUsd: 2, spentTodayUsd: 0.4 },
    );
    renderFrame();
    const n = await notice();
    expect(n).toHaveTextContent(`The live AI service for this demo is unavailable until ${clock(until)}.`);
    expect(n).not.toHaveTextContent(/reset|provider_auth/);
    expect(within(n).getByRole('link', { name: 'how to install' })).toHaveAttribute('href', INSTALL_URL);
    expect(await axeViolations(await banner())).toEqual([]);
  });

  it('says "for now" when live.agents gives no time', async () => {
    liveWith({ agents: { available: false, reason: 'provider_auth', until: null } });
    renderFrame();
    expect(await notice()).toHaveTextContent('The live AI service for this demo is unavailable for now.');
  });

  it('follows live.agents when the server sends it, and the budget when it does not', async () => {
    liveWith(
      { agents: { available: true, reason: null, until: null } },
      { dailyUsd: 2, spentTodayUsd: 2.05, exhausted: true },
    );
    const first = renderFrame();
    expect(await budgetLine()).toBeInTheDocument();
    expect(within(await banner()).queryByRole('note')).not.toBeInTheDocument();
    first.unmount();
    liveWith({}, { dailyUsd: 2, spentTodayUsd: 2.05, exhausted: true });
    renderFrame();
    expect(await notice()).toHaveTextContent('The live AI budget for this demo is used up');
  });
});
