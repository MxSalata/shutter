import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, Outlet, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import type { LiveStatus, LiveStorm } from '@/api/types';
import IncidentsPage from '@/features/incidents/IncidentsPage';
import { LiveBanner } from '@/features/shell/LiveBanner';
import { STORM_IN_TRIAL } from '@/lib/storm';
import fixtures from '@/mocks/fixtures.json';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { useAppearance } from '@/stores/appearance';
import { axeViolations } from '@/test/axe';
import { theme } from '@/theme';
import { BREAK_THE_FEED, STORM_CONFIRM } from './BreakTheFeed';
import { refusalWords } from './view';

// The banner reads the page's TRIAL flag when it renders: switched here per test (live unless a test says so)
const mode = vi.hoisted(() => ({ trial: false }));
vi.mock('@/env/mode', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/env/mode')>()),
  get TRIAL() {
    return mode.trial;
  },
}));

const BASE = '/api/shutter';

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
beforeEach(() => {
  resetMock('approver');
  useAppearance.setState({ detail: 'plain' });
});
afterEach(() => {
  server.resetHandlers();
  mode.trial = false;
});
afterAll(() => server.close());

const at = (seconds: number) => new Date(Date.now() + seconds * 1000).toISOString();

const PATIENTS = [
  { mrn: 'MRN500101', encounterId: 'ENC-500101', ward: 'WARD-A', toWard: 'WARD-C', movements: 2 },
  { mrn: 'MRN500102', encounterId: 'ENC-500102', ward: 'WARD-B', toWard: 'WARD-D', movements: 2 },
  { mrn: 'MRN500103', encounterId: 'ENC-500103', ward: 'WARD-C', toWard: 'WARD-A', movements: 2 },
  { mrn: 'MRN500104', encounterId: 'ENC-500104', ward: 'WARD-D', toWard: 'WARD-B', movements: 2 },
];

/** A storm as `GET /settings` carries it: the player's record with Shutter's counts. */
const storm = (s: Partial<LiveStorm>): LiveStorm => ({
  stormId: 'ST-000003',
  state: 'sending',
  startedAt: at(-60),
  requestedBy: 'demo',
  receiverDownUntil: at(30),
  endsAt: at(540),
  movements: 8,
  sent: 0,
  patients: PATIENTS,
  cases: 0,
  resolved: 0,
  incidentId: null,
  cooldownUntil: at(540),
  ...s,
});

/** The strip's states, in the order a storm plays them. */
const STATES: Record<string, LiveStorm> = {
  requested: storm({ state: 'requested', patients: 4, receiverDownUntil: undefined }),
  sending: storm({ state: 'sending', sent: 3, cases: 2 }),
  cases: storm({ state: 'waiting_receiver', sent: 8, cases: 8 }),
  incident: storm({
    state: 'waiting_receiver',
    sent: 8,
    cases: 8,
    incidentId: 'I-000016',
    incidentState: 'open',
  }),
  releasing: storm({
    state: 'releasing',
    sent: 8,
    cases: 8,
    resolved: 5,
    incidentId: 'I-000016',
    incidentState: 'releasing',
    receiverUpAt: at(-5),
  }),
  done: storm({
    state: 'done',
    sent: 8,
    cases: 8,
    resolved: 8,
    incidentId: 'I-000016',
    incidentState: 'closed',
    receiverUpAt: at(-120),
    endedAt: at(-10),
  }),
  failed: storm({
    state: 'failed',
    sent: 3,
    cases: 2,
    error: "The hospital's inbound folder is not recorded",
  }),
};

const LIVE: LiveStatus = {
  enabled: true,
  every_minutes: 7,
  last_played: { scenario: 'S2', title: 'a lost transfer', at: at(-240) },
};

/** The settings with the live hospital laid over them, counting each read. */
function settingsWith(live: Partial<LiveStatus> | undefined) {
  const reads = { n: 0 };
  server.use(
    http.get(`${BASE}/settings`, () => {
      reads.n += 1;
      return HttpResponse.json({
        mock: false,
        mockConfig: '',
        mockModel: '',
        ...fixtures.settings,
        ...(live ? { live } : {}),
      });
    }),
  );
  return reads;
}

/** A signed-in user whose `can` says they may not operate. */
function cannotOperate() {
  server.use(
    http.get(`${BASE}/me`, () =>
      HttpResponse.json({
        username: 'viewer',
        operator: false,
        approver: false,
        can: { operate: false, approve: false, configure: false, scenarios: false, liveAgents: false },
      }),
    ),
  );
}

/** The presses the server received: their headers, and the answer to give each. */
function storms(...answers: { status: number; body: unknown }[]) {
  const presses: { requested: string | null; key: string | null }[] = [];
  server.use(
    http.post(`${BASE}/live/storm`, ({ request }) => {
      presses.push({
        requested: request.headers.get('X-Requested-With'),
        key: request.headers.get('Idempotency-Key'),
      });
      const a = answers[Math.min(presses.length - 1, answers.length - 1)];
      return HttpResponse.json(a.body as Record<string, unknown>, { status: a.status });
    }),
  );
  return presses;
}

/** The banner as the frame draws it, over a stand-in page, the Incidents page and an incident's page. */
function renderFrame(path = '/cases') {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter(
    [
      {
        element: (
          <>
            <LiveBanner />
            <Outlet />
          </>
        ),
        children: [
          { path: '/cases', element: <h1>Cases page</h1> },
          { path: '/incidents', element: <IncidentsPage /> },
          { path: '/incidents/:id', element: <h1>Incident page</h1> },
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
  return { router, client, unmount: view.unmount };
}

const banner = () => screen.findByRole('region', { name: 'Live hospital' });
const button = async () => within(await banner()).findByRole('button', { name: BREAK_THE_FEED });
/** The banner's line has drawn and /me has answered: a missing button is then missing for good. */
const settled = async () => {
  await banner();
  await new Promise((r) => setTimeout(r, 150));
};

describe('Break the feed: who sees it', () => {
  it('is on the live banner for a user who operates', async () => {
    settingsWith(LIVE);
    renderFrame();
    expect(await button()).toBeVisible();
    expect(screen.queryByText(STORM_IN_TRIAL)).not.toBeInTheDocument();
  });

  it('is not offered to a user who may not operate; the banner stays', async () => {
    settingsWith(LIVE);
    cannotOperate();
    renderFrame();
    await settled();
    expect(within(await banner()).queryByRole('button', { name: BREAK_THE_FEED })).not.toBeInTheDocument();
  });

  it('is not anywhere while the live hospital is off', async () => {
    settingsWith({ enabled: false, storm: STATES.sending });
    renderFrame();
    expect(await screen.findByRole('heading', { name: 'Cases page' })).toBeInTheDocument();
    await new Promise((r) => setTimeout(r, 150));
    expect(screen.queryByRole('button', { name: BREAK_THE_FEED })).not.toBeInTheDocument();
    expect(screen.queryByTestId('storm-strip')).not.toBeInTheDocument();
  });

  it('is not in the trial, whose banner says where the storm plays, in plain text, with no strip', async () => {
    mode.trial = true;
    settingsWith({ ...LIVE, storm: STATES.sending });
    renderFrame();
    const feed = await screen.findByRole('region', { name: 'Hospital feed (replayed)' });
    expect(await within(feed).findByText(STORM_IN_TRIAL)).toBeVisible();
    expect(within(feed).queryByRole('button')).not.toBeInTheDocument();
    // No address to the demo in the app yet, so no link
    expect(within(feed).queryByRole('link')).not.toBeInTheDocument();
    expect(screen.queryByTestId('storm-strip')).not.toBeInTheDocument();
    // A trial page says "live" only in "live system"
    expect(feed.textContent).not.toMatch(/\blive\b/i);
  });
});

describe('Break the feed: the press', () => {
  it('asks first, in the live voice, and Cancel sends nothing', async () => {
    settingsWith(LIVE);
    const presses = storms({ status: 202, body: STATES.requested });
    renderFrame();
    await userEvent.click(await button());
    const dialog = await screen.findByRole('dialog', { name: BREAK_THE_FEED });
    expect(dialog).toHaveTextContent(STORM_CONFIRM);
    expect(within(dialog).getByText('Live system')).toBeInTheDocument();
    expect(within(dialog).getByRole('button', { name: BREAK_THE_FEED })).toBeInTheDocument();
    expect(await axeViolations(dialog)).toEqual([]);
    await userEvent.click(within(dialog).getByRole('button', { name: 'Cancel' }));
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
    expect(presses).toEqual([]);
  });

  it('sends the press with the CSRF header and its own key, then follows the storm on the strip', async () => {
    const reads = settingsWith(LIVE);
    const presses = storms({ status: 202, body: STATES.requested });
    renderFrame();
    await userEvent.click(await button());
    const dialog = await screen.findByRole('dialog', { name: BREAK_THE_FEED });
    // The settings now carry the press the player has not picked up yet
    settingsWith({ ...LIVE, storm: STATES.requested });
    await userEvent.click(within(dialog).getByRole('button', { name: BREAK_THE_FEED }));
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
    expect(presses).toHaveLength(1);
    expect(presses[0].requested).toBe('Shutter');
    expect(presses[0].key).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
    const strip = await within(await banner()).findByTestId('storm-strip');
    expect(within(strip).getByTestId('storm-line')).toHaveTextContent('Step 1 of 5: The bed manager is down');
    expect(reads.n).toBeGreaterThanOrEqual(1);
  });

  it('takes a fresh key for each press, and the same key when one confirm is sent again after an error', async () => {
    settingsWith(LIVE);
    const presses = storms(
      { status: 500, body: { error: 'internal', detail: 'The hospital namespace could not be read' } },
      { status: 409, body: { error: 'cooldown', until: at(300), retryAfterSeconds: 300 } },
      { status: 409, body: { error: 'cooldown', until: at(300), retryAfterSeconds: 300 } },
    );
    renderFrame();
    await userEvent.click(await button());
    let dialog = await screen.findByRole('dialog', { name: BREAK_THE_FEED });
    await userEvent.click(within(dialog).getByRole('button', { name: BREAK_THE_FEED }));
    // An error that is not a refusal stays in the dialog, as an error, for a second try of the same press
    expect(await within(dialog).findByRole('alert')).toHaveTextContent('The storm could not be asked for');
    await userEvent.click(within(dialog).getByRole('button', { name: BREAK_THE_FEED }));
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
    await userEvent.click(await button());
    dialog = await screen.findByRole('dialog', { name: BREAK_THE_FEED });
    await userEvent.click(within(dialog).getByRole('button', { name: BREAK_THE_FEED }));
    await waitFor(() => expect(presses).toHaveLength(3));
    expect(presses[1].key).toBe(presses[0].key);
    expect(presses[2].key).not.toBe(presses[0].key);
  });
});

describe('Break the feed: the refusals, as calm notices', () => {
  /** Presses once against an answer and returns the notice the banner then shows. */
  async function refusedWith(status: number, body: unknown) {
    storms({ status, body });
    renderFrame();
    await userEvent.click(await button());
    const dialog = await screen.findByRole('dialog', { name: BREAK_THE_FEED });
    await userEvent.click(within(dialog).getByRole('button', { name: BREAK_THE_FEED }));
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
    const notice = await within(await banner()).findByRole('status');
    // A notice, not an error
    expect(screen.queryByRole('alert')).not.toBeInTheDocument();
    return notice;
  }

  it('says the live hospital is off', async () => {
    settingsWith(LIVE);
    const notice = await refusedWith(409, { error: 'live_off', detail: 'The live hospital is off' });
    expect(notice).toHaveTextContent(/^The live hospital is off\.$/);
    expect(notice).toHaveAttribute('data-tone', 'neutral');
    await userEvent.click(within(notice).getByRole('button', { name: 'Dismiss' }));
    await waitFor(() => expect(screen.queryByTestId('storm-notice')).not.toBeInTheDocument());
  });

  it('shows the storm already playing, on its strip', async () => {
    settingsWith(LIVE);
    storms({ status: 409, body: { error: 'storm_in_progress', stormId: 'ST-000002', state: 'sending' } });
    renderFrame();
    await userEvent.click(await button());
    const dialog = await screen.findByRole('dialog', { name: BREAK_THE_FEED });
    // The other visitor's storm, as the settings now carry it
    settingsWith({ ...LIVE, storm: { ...STATES.sending, stormId: 'ST-000002' } });
    await userEvent.click(within(dialog).getByRole('button', { name: BREAK_THE_FEED }));
    const notice = await within(await banner()).findByRole('status');
    expect(notice).toHaveTextContent(/^A storm is already playing; watch it here\.$/);
    expect(notice).toHaveAttribute('data-tone', 'info');
    const strip = await within(await banner()).findByTestId('storm-strip');
    expect(within(strip).getByTestId('storm-line')).toHaveTextContent('Step 1 of 5: The bed manager is down');
  });

  it('says when the next storm can start, in the time the app shows', async () => {
    settingsWith(LIVE);
    const until = at(252);
    const notice = await refusedWith(409, { error: 'cooldown', until, retryAfterSeconds: 252 });
    expect(notice).toHaveTextContent(refusalWords({ code: 'cooldown', until }));
    expect(notice).toHaveTextContent(/^The next storm can start at \d\d:\d\d (GMT|BST|UTC)\.$/);
  });

  it("says the demo hospital isn't installed", async () => {
    settingsWith(LIVE);
    const notice = await refusedWith(503, { error: 'no_service', detail: 'No live hospital' });
    expect(notice).toHaveTextContent(/^The demo hospital isn't installed here\.$/);
  });
});

describe('Break the feed: the strip', () => {
  const strip = async () => within(await banner()).findByTestId('storm-strip');
  const steps = (s: HTMLElement) => within(s).getAllByRole('listitem').slice(0, 5);

  it('follows each state in five steps, the current one marked and named in the step line', async () => {
    const expected: Record<string, { line: string; current: number; statuses: string[] }> = {
      requested: {
        line: 'Step 1 of 5: The bed manager is down',
        current: 0,
        statuses: ['current', 'pending', 'pending', 'pending', 'pending'],
      },
      sending: {
        line: 'Step 1 of 5: The bed manager is down',
        current: 0,
        statuses: ['current', 'pending', 'pending', 'pending', 'pending'],
      },
      cases: {
        line: 'Step 2 of 5: 8 deliveries failed; Shutter opened 8 cases',
        current: 1,
        statuses: ['done', 'current', 'pending', 'pending', 'pending'],
      },
      incident: {
        line: 'Step 3 of 5: Grouped into incident I-000016',
        current: 2,
        statuses: ['done', 'done', 'current', 'pending', 'pending'],
      },
      releasing: {
        line: 'Step 4 of 5: The bed manager is back; releasing in order',
        current: 3,
        statuses: ['done', 'done', 'done', 'current', 'pending'],
      },
      done: {
        line: 'Step 5 of 5: Done: 8 cases, 8 resolved',
        current: 4,
        statuses: ['done', 'done', 'done', 'done', 'finished'],
      },
      failed: {
        line: "Step 5 of 5: Stopped: The hospital's inbound folder is not recorded",
        current: 4,
        statuses: ['done', 'done', 'skipped', 'skipped', 'stopped'],
      },
    };
    for (const [name, want] of Object.entries(expected)) {
      settingsWith({ ...LIVE, storm: STATES[name] });
      const view = renderFrame();
      const s = await strip();
      expect(within(s).getByTestId('storm-line'), name).toHaveTextContent(want.line);
      const items = steps(s);
      expect(
        items.map((li) => li.getAttribute('data-status')),
        name,
      ).toEqual(want.statuses);
      expect(
        items.map((li) => li.getAttribute('aria-current')),
        name,
      ).toEqual(items.map((_, i) => (i === want.current ? 'step' : null)));
      // The step line is the only part a screen reader hears change
      const live = s.querySelectorAll('[aria-live]');
      expect(live, name).toHaveLength(1);
      expect(live[0]).toHaveAttribute('aria-live', 'polite');
      expect(live[0]).toBe(within(s).getByTestId('storm-line'));
      expect(await axeViolations(await banner()), name).toEqual([]);
      view.unmount();
    }
  });

  it('says the progress inside the current step: the movements sent, then the cases resolved', async () => {
    settingsWith({ ...LIVE, storm: STATES.sending });
    const first = renderFrame();
    expect(steps(await strip())[0]).toHaveTextContent('3 of 8 movements sent');
    first.unmount();
    settingsWith({ ...LIVE, storm: STATES.releasing });
    renderFrame();
    expect(steps(await strip())[3]).toHaveTextContent('5 of 8 resolved');
  });

  it("tells a screen reader each step's place, and marks the status in words", async () => {
    settingsWith({ ...LIVE, storm: STATES.releasing });
    renderFrame();
    const s = await strip();
    expect(within(s).getByText('Playing')).toBeInTheDocument();
    const items = steps(s);
    expect(items[0]).toHaveTextContent(/^Passed: The bed manager is down/);
    expect(items[3]).toHaveTextContent(/^Now: The bed manager is back; releasing in order/);
    expect(items[4]).toHaveTextContent(/^Not yet: Done$/);
  });

  it('links to the incident and gives its state', async () => {
    settingsWith({ ...LIVE, storm: STATES.releasing });
    const { router } = renderFrame();
    const s = await strip();
    const link = within(s).getByRole('link', { name: 'I-000016' });
    expect(link).toHaveAttribute('href', '/incidents/I-000016');
    expect(steps(s)[2]).toHaveTextContent('Grouped into incident I-000016 Releasing');
    await userEvent.click(link);
    expect(await screen.findByRole('heading', { name: 'Incident page' })).toBeInTheDocument();
    expect(router.state.location.pathname).toBe('/incidents/I-000016');
  });

  it('shows the four patients as tokens with their wards and no names; Technical adds the encounters', async () => {
    settingsWith({ ...LIVE, storm: STATES.cases });
    renderFrame();
    const s = await strip();
    const patients = within(s).getByRole('list', { name: "The storm's patients" });
    expect(
      within(patients)
        .getAllByRole('listitem')
        .map((li) => li.textContent),
    ).toEqual(['Ward A to Ward C', 'Ward B to Ward D', 'Ward C to Ward A', 'Ward D to Ward B']);
    expect(s).not.toHaveTextContent('MRN500101');
    expect(s).not.toHaveTextContent('ENC-500101');
    useAppearance.setState({ detail: 'technical' });
    expect(await within(patients).findByText('ENC-500101')).toBeInTheDocument();
    expect(s).toHaveTextContent('ST-000003');
    expect(s).not.toHaveTextContent('MRN500101');
  });

  it('has no patients to show while the press waits for the player', async () => {
    settingsWith({ ...LIVE, storm: STATES.requested });
    renderFrame();
    const s = await strip();
    expect(within(s).queryByRole('list', { name: "The storm's patients" })).not.toBeInTheDocument();
  });

  it('stays ten minutes after the storm ended, then goes', async () => {
    settingsWith({ ...LIVE, storm: { ...STATES.done, endedAt: at(-20 * 60), startedAt: at(-30 * 60) } });
    renderFrame();
    await settled();
    expect(screen.queryByTestId('storm-strip')).not.toBeInTheDocument();
  });

  it('pulses the current dot when the step changes, and never under reduced motion', async () => {
    const reads = settingsWith({ ...LIVE, storm: STATES.sending });
    const { client } = renderFrame();
    const s = await strip();
    const dot = () => s.querySelector('[aria-current="step"] .storm-dot');
    // Not on arrival: only a change of step moves
    expect(dot()).not.toHaveAttribute('data-pulse');
    settingsWith({ ...LIVE, storm: STATES.cases });
    await client.refetchQueries({ queryKey: ['settings'] });
    await waitFor(() => expect(within(s).getByTestId('storm-line')).toHaveTextContent('Step 2 of 5'));
    await waitFor(() => expect(dot()).toHaveAttribute('data-pulse'));
    expect(reads.n).toBeGreaterThanOrEqual(1);
  });

  it('keeps every dot still for a reader who asks for reduced motion', async () => {
    const matchMedia = window.matchMedia;
    window.matchMedia = ((query: string) => ({
      ...matchMedia(query),
      matches: query.includes('prefers-reduced-motion'),
    })) as typeof window.matchMedia;
    try {
      settingsWith({ ...LIVE, storm: STATES.sending });
      const { client } = renderFrame();
      const s = await strip();
      settingsWith({ ...LIVE, storm: STATES.cases });
      await client.refetchQueries({ queryKey: ['settings'] });
      await waitFor(() => expect(within(s).getByTestId('storm-line')).toHaveTextContent('Step 2 of 5'));
      expect(s.querySelectorAll('[data-pulse]')).toHaveLength(0);
    } finally {
      window.matchMedia = matchMedia;
    }
  });
});

describe('Break the feed: polling', () => {
  it('reads the settings again within 3 s while a storm plays', async () => {
    const reads = settingsWith({ ...LIVE, storm: STATES.sending });
    renderFrame();
    await banner();
    await waitFor(() => expect(reads.n).toBeGreaterThanOrEqual(2), { timeout: 4_500 });
  });

  it('waits half a minute once the storm is done', async () => {
    const reads = settingsWith({ ...LIVE, storm: STATES.done });
    renderFrame();
    await banner();
    const first = reads.n;
    await new Promise((r) => setTimeout(r, 3_600));
    expect(reads.n).toBe(first);
  });
});

describe('Break the feed: the Incidents page', () => {
  it('shows the strip above the incidents, and the banner leaves its own out there', async () => {
    settingsWith({ ...LIVE, storm: STATES.incident });
    renderFrame('/incidents');
    const card = await screen.findByTestId('incidents-storm');
    expect(within(card).getByRole('heading', { name: 'Break the feed', level: 2 })).toBeInTheDocument();
    expect(within(card).getByTestId('storm-line')).toHaveTextContent(
      'Step 3 of 5: Grouped into incident I-000016',
    );
    expect(within(card).getByRole('link', { name: 'I-000016' })).toHaveAttribute(
      'href',
      '/incidents/I-000016',
    );
    // One strip, one step line on the page
    expect(within(await banner()).queryByTestId('storm-strip')).not.toBeInTheDocument();
    expect(screen.getAllByTestId('storm-strip')).toHaveLength(1);
    expect(await axeViolations(card)).toEqual([]);
  });

  it('shows no strip when no storm plays', async () => {
    settingsWith(LIVE);
    renderFrame('/incidents');
    expect(await screen.findByRole('heading', { name: 'Incidents', level: 1 })).toBeInTheDocument();
    expect(screen.queryByTestId('incidents-storm')).not.toBeInTheDocument();
  });

  it('shows no strip in the trial', async () => {
    mode.trial = true;
    settingsWith({ ...LIVE, storm: STATES.incident });
    renderFrame('/incidents');
    expect(await screen.findByRole('heading', { name: 'Incidents', level: 1 })).toBeInTheDocument();
    await new Promise((r) => setTimeout(r, 150));
    expect(screen.queryByTestId('incidents-storm')).not.toBeInTheDocument();
  });
});
