import { MantineProvider } from '@mantine/core';
import { Notifications, notifications } from '@mantine/notifications';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { recordedSiteProfile } from '@/mocks/profile';
import { server } from '@/mocks/node';
import { resetMock } from '@/mocks/handlers';
import { theme } from '@/theme';
import SiteProfilePage from './SiteProfilePage';
import { suggestionHref } from './suggestion';

const BASE = '/api/shutter';
const recorded = recordedSiteProfile()!;
let puts: { body: Record<string, unknown>; headers: Headers }[] = [];
let lastRouter: ReturnType<typeof createMemoryRouter> | undefined;

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
beforeEach(() => {
  resetMock('approver');
  // The notifications store is global: a toast from the test before would still be on screen
  notifications.clean();
  puts = [];
  server.events.removeAllListeners();
  server.events.on('request:start', async ({ request }) => {
    if (request.method === 'PUT')
      puts.push({
        body: (await request.clone().json()) as Record<string, unknown>,
        headers: request.headers,
      });
  });
});

function renderPage(query = '') {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter([{ path: '/site-profile', element: <SiteProfilePage /> }], {
    initialEntries: [`/site-profile${query}`],
  });
  lastRouter = router;
  return render(
    <MantineProvider theme={theme}>
      <Notifications />
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

/** The first receiver's questions: the seed lists two receivers, each asked the same ones. */
const receiver1 = () => within(screen.getByRole('group', { name: 'Receiver 1: Downstream Out' }));
const inReceiver1 = async () =>
  within(await screen.findByRole('group', { name: 'Receiver 1: Downstream Out' }));

describe('SiteProfilePage', () => {
  it('shows the answers in force, where they came from, and asks for the induction', async () => {
    renderPage();
    expect(await screen.findByText('Seeded from knowledge/site/profile.json')).toBeInTheDocument();
    expect(screen.getByText('Shutter is running on the shipped answers')).toBeInTheDocument();
    expect((await inReceiver1()).getByRole('radio', { name: /2, operations/ })).toBeChecked();
    expect((await inReceiver1()).getByRole('radio', { name: 'In arrival order' })).toBeChecked();
    expect(screen.getByRole('switch', { name: /Downstream Out accepts cancels/ })).not.toBeChecked();
    expect(screen.getByRole('combobox', { name: 'Tier 2, ordered chains' })).toHaveValue('approval');
    expect(screen.getByRole('textbox', { name: 'Failures' })).toHaveValue('5');
    const matrix = screen.getByRole('table', { name: 'Who releases each write' });
    expect(within(matrix).getAllByText("The site's written policy").length).toBeGreaterThan(0);
  });

  it('shows each receiver as a card with its category in plain words, and the kind no receiver has', async () => {
    renderPage();
    const cards = await screen.findByRole('list', { name: 'The receivers and what each needs' });
    const beds = within(cards).getByRole('listitem', { name: 'Downstream Out' });
    expect(within(beds).getByText('Current state')).toBeInTheDocument();
    expect(within(beds).getByText('Tier 2, operations')).toBeInTheDocument();
    expect(within(beds).getByText("Only today's placement matters.")).toBeInTheDocument();
    expect(within(beds).getByText('Overtaken failure: closes, no write.')).toBeInTheDocument();
    // The whole sentence the case page reads stays in the card's second layer
    expect(within(beds).getByText(/An overtaken failure closes with no write/)).toBeInTheDocument();
    const records = within(cards).getByRole('listitem', { name: 'Records Out' });
    expect(within(records).getByText('History of record')).toBeInTheDocument();
    expect(
      within(records).getByText('Overtaken failure: asks a person to correct by hand.'),
    ).toBeInTheDocument();
    expect(within(records).getByText(/asks for a correction by hand/)).toBeInTheDocument();
    expect(within(cards).getByText('Orders and results')).toBeInTheDocument();
    expect(within(cards).getByText('Not modelled yet')).toBeInTheDocument();
  });

  it('says where a receiver with no category answered takes its history policy from', async () => {
    const legacy = structuredClone(recorded);
    const { category: _c, history_policy: _h, ...beds } = legacy.profile.receivers[0];
    legacy.profile = { ...legacy.profile, receivers: [beds], history_policy: 'correct' };
    server.use(http.get(`${BASE}/site-profile`, () => HttpResponse.json(legacy)));
    renderPage();
    const cards = await screen.findByRole('list', { name: 'The receivers and what each needs' });
    const card = within(cards).getByRole('listitem', { name: 'Downstream Out' });
    expect(within(card).getByText('Not answered: read as current state')).toBeInTheDocument();
    expect(within(card).getByText(/asks for a correction by hand/)).toBeInTheDocument();
    expect(
      within(card).getByText(
        'Read from the site-wide history policy (correct the history), since no category is answered for this receiver.',
      ),
    ).toBeInTheDocument();
  });

  it("asks each receiver's category, explains it, and sends it with the profile", async () => {
    renderPage();
    const select = (await inReceiver1()).getByRole('combobox', { name: 'Category of Downstream Out' });
    expect(select).toHaveValue('current_state');
    await userEvent.selectOptions(select, 'history_of_record');
    expect(receiver1().getByText(/A PAS, an electronic patient record/)).toBeInTheDocument();
    await userEvent.click(receiver1().getByRole('button', { name: 'Advanced: its history policy' }));
    expect(
      receiver1().getByRole('combobox', { name: /When a failure at it has been overtaken/ }),
    ).toHaveValue('');
    await userEvent.click(screen.getByRole('button', { name: 'Review and save…' }));
    const dialog = await screen.findByRole('dialog');
    expect(
      within(dialog).getByText('Downstream Out, category: from current state to history of record'),
    ).toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save version 8' }));
    expect(await screen.findByText('Version 8 saved')).toBeInTheDocument();
    const sent = puts[0].body.receivers as { category?: string; history_policy?: string }[];
    expect(sent.map((r) => r.category)).toEqual(['history_of_record', 'history_of_record']);
    expect(sent[0].history_policy).toBeUndefined();
  });

  it("shows the validator's message for a category the server would refuse, at its field", async () => {
    server.use(
      http.put(`${BASE}/site-profile`, () =>
        HttpResponse.json(
          {
            error: 'bad_request',
            detail:
              'The profile is not valid (CONTRACTS 6.4): receivers[1].category: must be current_state, history_of_record or orders_results',
          },
          { status: 400 },
        ),
      ),
    );
    renderPage();
    await userEvent.click(await screen.findByRole('button', { name: 'Confirm these answers…' }));
    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Confirm as version 8' }));
    expect(
      await screen.findByText(
        'Receiver 2, category: must be current_state, history_of_record or orders_results',
      ),
    ).toBeInTheDocument();
    await waitFor(() =>
      expect(screen.getByRole('combobox', { name: 'Category of Records Out' })).toHaveFocus(),
    );
  });

  it('asks whether closing a case by hand needs an approver, and sends the answer with the profile', async () => {
    renderPage();
    const rule = await screen.findByRole('switch', { name: /^Closing a case by hand needs an approver/ });
    expect(rule).not.toBeChecked();
    expect(screen.getByText(/is marked handled by an operator or an approver/)).toBeInTheDocument();
    await userEvent.click(rule);
    expect(
      screen.getByText(/is marked handled by an approver only \(the two-person rule\)/),
    ).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Review and save…' }));
    const dialog = await screen.findByRole('dialog');
    expect(
      within(dialog).getByText('Closing a case by hand: only an approver, from now on'),
    ).toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save version 8' }));
    expect(await screen.findByText('Version 8 saved')).toBeInTheDocument();
    expect(puts[0].body.approvers).toEqual({ ...recorded.profile.approvers, close_needs_approver: true });
  });

  it('lets an operator read the answers but not change them', async () => {
    resetMock('operator');
    renderPage();
    expect(await screen.findByText(/Changing the answers needs the approver role/)).toBeInTheDocument();
    expect((await inReceiver1()).getByRole('radio', { name: /2, operations/ })).toBeDisabled();
    expect(screen.getByRole('switch', { name: /^Closing a case by hand needs an approver/ })).toBeDisabled();
    expect(
      screen.queryByRole('button', { name: /Review and save|Confirm these answers/ }),
    ).not.toBeInTheDocument();
  });

  it('saves a change as the next version, sending the whole profile with expectedVersion', async () => {
    renderPage();
    await userEvent.click((await inReceiver1()).getByRole('radio', { name: /3, clinical safety/ }));
    await userEvent.click(screen.getByRole('button', { name: 'Review and save…' }));
    const dialog = await screen.findByRole('dialog');
    expect(
      within(dialog).getByText('Downstream Out, tier: from 2, operations to 3, clinical safety'),
    ).toBeInTheDocument();
    expect(within(dialog).getByText(/made under version 7 are refused at release/)).toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save version 8' }));
    expect(await screen.findByText('Version 8 saved')).toBeInTheDocument();
    expect(puts).toHaveLength(1);
    expect(puts[0].headers.get('X-Requested-With')).toBe('Shutter');
    const { version: _v, ...expected } = structuredClone(recorded.profile);
    expected.receivers[0].tier = 3;
    expect(puts[0].body).toEqual({ ...expected, expectedVersion: recorded.version });
    expect(await screen.findByText('Saved in Shutter')).toBeInTheDocument();
    expect(screen.queryByText('Shutter is running on the shipped answers')).not.toBeInTheDocument();
  });

  // It fills a whole team form: about 3 s alone, 10 s on a busy machine, and 30 s when the suites run side by side.
  it('adds a team that corrects a receiver by hand, and sends it with the profile', async () => {
    renderPage();
    await userEvent.click(await screen.findByRole('button', { name: 'Add a team' }));
    const team = screen.getByRole('group', { name: 'Team 3: new' });
    await userEvent.type(within(team).getByRole('textbox', { name: 'Short id' }), 'beds');
    await userEvent.type(within(team).getByRole('textbox', { name: 'Team' }), 'Bed management');
    await userEvent.type(within(team).getByRole('textbox', { name: 'Mailbox' }), 'beds@example.nhs.uk');
    const copies = within(team).getByRole('textbox', { name: 'Copies' });
    await userEvent.type(copies, 'oncall@example.nhs.uk, ');
    // A trailing comma survives while typing the next address
    expect(copies).toHaveValue('oncall@example.nhs.uk, ');
    await userEvent.click(within(team).getByRole('checkbox', { name: 'Downstream Out' }));
    await userEvent.click(screen.getByRole('button', { name: 'Review and save…' }));
    const dialog = await screen.findByRole('dialog');
    expect(
      within(dialog).getByText(
        'Team added: Bed management <beds@example.nhs.uk>, copies oncall@example.nhs.uk, for Downstream Out',
      ),
    ).toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save version 8' }));
    expect(await screen.findByText('Version 8 saved')).toBeInTheDocument();
    // The seed's two teams first, as stored, then the new one
    const teams = puts[0].body.teams as { id: string }[];
    expect(teams.map((t) => t.id)).toEqual(['integration', 'pas', 'beds']);
    expect(teams.slice(2)).toEqual([
      {
        id: 'beds',
        name: 'Bed management',
        mailbox: 'beds@example.nhs.uk',
        cc: ['oncall@example.nhs.uk'],
        receivers: ['Downstream Out'],
        sources: [],
      },
    ]);
  }, 60_000);

  // It fills a team form too, about 4.5 s alone, so it gets the same allowance as the team test.
  it('refuses a team mailbox outside the allowed domains before sending, and points at it', async () => {
    // The profile allows example.nhs.uk, the seed's domain
    renderPage();
    await userEvent.click(await screen.findByRole('button', { name: 'Add a team' }));
    const team = screen.getByRole('group', { name: 'Team 3: new' });
    await userEvent.type(within(team).getByRole('textbox', { name: 'Short id' }), 'beds');
    await userEvent.type(within(team).getByRole('textbox', { name: 'Team' }), 'Bed management');
    await userEvent.type(within(team).getByRole('textbox', { name: 'Mailbox' }), 'beds@example.com');
    await userEvent.click(screen.getByRole('button', { name: 'Review and save…' }));
    expect(
      await screen.findByRole('button', { name: 'Team 3, mailbox: not in the allowed domains' }),
    ).toBeInTheDocument();
    await waitFor(() => expect(within(team).getByRole('textbox', { name: 'Mailbox' })).toHaveFocus());
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    expect(puts).toHaveLength(0);
  }, 60_000);

  it("sets the feed's zone to a fixed offset, and the review says every key changes", async () => {
    renderPage();
    expect(await screen.findByRole('radio', { name: /UK time/ })).toBeChecked();
    await userEvent.click(screen.getByRole('radio', { name: /A fixed offset from UTC/ }));
    const offset = screen.getByRole('textbox', { name: 'Offset' });
    await userEvent.clear(offset);
    await userEvent.type(offset, '-03:30');
    await userEvent.click(screen.getByRole('button', { name: 'Review and save…' }));
    const dialog = await screen.findByRole('dialog');
    expect(
      within(dialog).getByText(/Feed time zone: from Europe\/London to -03:30\. Every operation key/),
    ).toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save version 8' }));
    expect(await screen.findByText('Version 8 saved')).toBeInTheDocument();
    expect(puts[0].body.feed).toEqual({ time_zone: '-03:30' });
  });

  it('shows the offset as the draft holds it after Discard, and points a cleared offset at its field', async () => {
    renderPage();
    await userEvent.click(await screen.findByRole('radio', { name: /A fixed offset from UTC/ }));
    const offset = screen.getByRole('textbox', { name: 'Offset' });
    expect(offset).toHaveValue('+01:00');
    await userEvent.clear(offset);
    expect(offset).toHaveAccessibleDescription(/Write it as \+01:00 or -03:30/);
    await userEvent.click(screen.getByRole('button', { name: 'Review and save…' }));
    expect(
      await screen.findByRole('button', {
        name: /^Feed, time zone: must be UTC, Europe\/London, a fixed offset/,
      }),
    ).toBeInTheDocument();
    await waitFor(() => expect(offset).toHaveFocus());
    await userEvent.type(offset, '+02:00');
    await userEvent.click(screen.getByRole('button', { name: 'Discard changes' }));
    expect(screen.getByRole('radio', { name: /UK time/ })).toBeChecked();
    expect(screen.queryByRole('textbox', { name: 'Offset' })).not.toBeInTheDocument();
  });

  it('shows a stored IANA zone as kept, and saves a change elsewhere without refusing the zone', async () => {
    const view = recordedSiteProfile()!;
    view.profile.feed = { time_zone: 'Europe/Paris' };
    server.use(http.get(`${BASE}/site-profile`, () => HttpResponse.json(view)));
    renderPage();
    const kept = await screen.findByRole('radio', { name: 'Kept as stored: Europe/Paris' });
    expect(kept).toBeChecked();
    expect(kept).toBeDisabled();
    expect(screen.queryByRole('textbox', { name: 'Offset' })).not.toBeInTheDocument();
    await userEvent.click(screen.getByRole('switch', { name: /Downstream Out accepts cancels/ }));
    await userEvent.click(screen.getByRole('button', { name: 'Review and save…' }));
    const dialog = await screen.findByRole('dialog');
    expect(screen.queryByRole('button', { name: /^Feed, time zone/ })).not.toBeInTheDocument();
    expect(within(dialog).queryByText(/Feed time zone/)).not.toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save version 8' }));
    expect(await screen.findByText('Version 8 saved')).toBeInTheDocument();
    expect(puts[0].body.feed).toEqual({ time_zone: 'Europe/Paris' });
  });

  it('sends note text to the model only when the site says so', async () => {
    renderPage();
    const sw = await screen.findByRole('switch', { name: /^Send note text to the model/ });
    expect(sw).not.toBeChecked();
    await userEvent.click(sw);
    await userEvent.click(screen.getByRole('button', { name: 'Review and save…' }));
    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Note text: sent to the model from now on')).toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save version 8' }));
    expect(await screen.findByText('Version 8 saved')).toBeInTheDocument();
    expect(puts[0].body.model_content).toEqual({ free_text: true });
  });

  it('asks question 13 and holds the feed while a schema is missing only when the site says so', async () => {
    renderPage();
    expect(
      await screen.findByText(
        /^Should Shutter hold the feed when a message arrives whose HL7 schema is not loaded here/,
      ),
    ).toBeInTheDocument();
    const sw = screen.getByRole('switch', { name: /^Hold messages whose schema is not loaded/ });
    expect(sw).not.toBeChecked();
    await userEvent.click(sw);
    await userEvent.click(screen.getByRole('button', { name: 'Review and save…' }));
    const dialog = await screen.findByRole('dialog');
    expect(
      within(dialog).getByText(
        "Prevent failures: from now on, a message whose HL7 schema isn't loaded here is held as a case, and nothing is sent until the schema is imported",
      ),
    ).toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save version 8' }));
    expect(await screen.findByText('Version 8 saved')).toBeInTheDocument();
    expect(puts[0].body.feed).toMatchObject({ prevent_failures: true });
  });

  it('confirms the shipped answers with no change, which records who answered', async () => {
    renderPage();
    await userEvent.click(await screen.findByRole('button', { name: 'Confirm these answers…' }));
    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Confirm as version 8' }));
    expect(await screen.findByText('Saved in Shutter')).toBeInTheDocument();
    const { version: _v, ...expected } = structuredClone(recorded.profile);
    expect(puts[0].body).toEqual({ ...expected, expectedVersion: recorded.version });
  });

  it('asks the approver to acknowledge tier 3 released with no person', async () => {
    renderPage();
    await userEvent.selectOptions(
      await screen.findByRole('combobox', { name: 'Tier 3, single failures' }),
      'automatic',
    );
    await userEvent.click(screen.getByRole('button', { name: 'Review and save…' }));
    const dialog = await screen.findByRole('dialog');
    const save = within(dialog).getByRole('button', { name: 'Save version 8' });
    expect(save).toBeDisabled();
    expect(within(dialog).getByText('Fewer releases wait for a person')).toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole('checkbox', { name: /I mean it/ }));
    expect(save).toBeEnabled();
  });

  it('checks an answer before anything is sent, and points at the field', async () => {
    renderPage();
    const name = (await inReceiver1()).getByRole('textbox', { name: /Production item/ });
    await userEvent.clear(name);
    await userEvent.click(screen.getByRole('button', { name: 'Review and save…' }));
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    expect(await screen.findByText('Receiver 1, name: required')).toBeInTheDocument();
    await waitFor(() => expect(name).toHaveFocus());
    expect(puts).toHaveLength(0);
  });

  it('keeps the edits when someone else saved meanwhile, and saves them against the newer version', async () => {
    renderPage();
    await userEvent.click((await inReceiver1()).getByRole('radio', { name: /3, clinical safety/ }));
    // Someone else saves version 8 while this page holds version 7
    const theirs = structuredClone(recorded.profile);
    delete theirs.version;
    theirs.incident = { ...theirs.incident, threshold: 8 };
    const res = await fetch(`${BASE}/site-profile`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json', 'X-Requested-With': 'Shutter' },
      body: JSON.stringify({ ...theirs, expectedVersion: 7 }),
    });
    expect(res.status).toBe(200);
    await userEvent.click(screen.getByRole('button', { name: 'Review and save\u2026' }));
    let dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save version 8' }));
    expect(await within(dialog).findByText(/Version 8 was saved by someone else/)).toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole('button', { name: 'Keep editing' }));
    await userEvent.click(screen.getByRole('button', { name: 'Review and save\u2026' }));
    dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Incidents, failures: from 8 to 5')).toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save version 9' }));
    expect(await screen.findByText('Version 9 saved')).toBeInTheDocument();
    expect(puts.at(-1)?.body.expectedVersion).toBe(8);
  });

  it('counts a save whose answer was lost as saved when the stored profile is ours', async () => {
    let first = true;
    server.use(
      http.put(`${BASE}/site-profile`, async ({ request }) => {
        if (!first) return undefined;
        first = false;
        // The save goes through, then the answer is lost
        await fetch(request.url, { method: 'PUT', headers: request.headers, body: await request.text() });
        return HttpResponse.error();
      }),
    );
    renderPage();
    await userEvent.click((await inReceiver1()).getByRole('radio', { name: /3, clinical safety/ }));
    await userEvent.click(screen.getByRole('button', { name: 'Review and save\u2026' }));
    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save version 8' }));
    expect(await screen.findByText('Version 8 saved')).toBeInTheDocument();
  });

  it('marks the field a server refusal names, and focuses its chosen radio', async () => {
    server.use(
      http.put(`${BASE}/site-profile`, () =>
        HttpResponse.json(
          {
            error: 'bad_request',
            detail: 'The profile is not valid (CONTRACTS 6.4): receivers[0].tier: must be 1, 2 or 3',
          },
          { status: 400 },
        ),
      ),
    );
    renderPage();
    await userEvent.click((await inReceiver1()).getByRole('radio', { name: /3, clinical safety/ }));
    await userEvent.click(screen.getByRole('button', { name: 'Review and save\u2026' }));
    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save version 8' }));
    expect(await screen.findByText('Receiver 1, tier: must be 1, 2 or 3')).toBeInTheDocument();
    await waitFor(() => expect(receiver1().getByRole('radio', { name: /3, clinical safety/ })).toHaveFocus());
  });

  it('lists the versions with what each changed', async () => {
    renderPage();
    const versions = await screen.findByRole('region', { name: 'Versions' });
    expect(await within(versions).findByRole('button', { name: /Version 1\b/ })).toBeInTheDocument();
    await userEvent.click(within(versions).getByRole('button', { name: /Version 1\b/ }));
    expect(await within(versions).findByText('The first stored version.')).toBeInTheDocument();
  });

  it('names the engine resend on a version that turned it on, not "no changes"', async () => {
    const before = recorded.profile;
    const after = structuredClone(before);
    after.receivers[0].engine_resend = true;
    after.receivers[0].ack_level = 'application';
    const entry = (version: number, profile: typeof before) => ({
      version,
      profile,
      source: 'api',
      updatedAt: '2026-11-07T10:00:00Z',
      updatedBy: 'approver',
    });
    server.use(
      http.get(`${BASE}/site-profile/history`, () => HttpResponse.json([entry(2, after), entry(1, before)])),
    );
    renderPage();
    const versions = await screen.findByRole('region', { name: 'Versions' });
    await userEvent.click(await within(versions).findByRole('button', { name: /Version 2\b/ }));
    expect(await within(versions).findByText('Downstream Out, the engine resend: on')).toBeInTheDocument();
    expect(within(versions).queryByText(/Saved with no changes/)).not.toBeInTheDocument();
  });
});

describe('SiteProfilePage, a change a case suggested', () => {
  const suggestion = suggestionHref({ caseId: 'C-000008', fact: 'W1' }).replace('/site-profile', '');

  it('opens as a pre-filled draft with the change as a diff, and saves only through the review', async () => {
    renderPage(suggestion);
    const heading = await screen.findByRole('heading', { name: 'A suggested change from case C-000008' });
    await waitFor(() => expect(heading).toHaveFocus());
    const card = screen.getByRole('region', { name: 'A suggested change from case C-000008' });
    const table = within(card).getByRole('table', { name: 'The change in this draft' });
    expect(within(table).getByRole('columnheader', { name: 'Now, version 7' })).toBeInTheDocument();
    const row = within(table)
      .getByRole('rowheader', { name: /Authoritative source/ })
      .closest('tr')!;
    expect(row).toHaveTextContent('none named');
    expect(row).toHaveTextContent('BEDMGR');
    expect(
      within(card).getByText(/every failure where another source system applied a movement/),
    ).toBeInTheDocument();
    expect(within(card).getByRole('link', { name: 'Back to case C-000008' })).toHaveAttribute(
      'href',
      '/cases/C-000008?ask=1',
    );
    // Nothing is saved by opening it
    expect(puts).toEqual([]);
    await userEvent.click(within(card).getByRole('button', { name: 'Review and save…' }));
    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText(/Authoritative source: from .* to BEDMGR/)).toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save version 8' }));
    expect(await screen.findByText('Version 8 saved')).toBeInTheDocument();
    expect(puts).toHaveLength(1);
    expect(puts[0].body).toMatchObject({ authoritative_source: 'BEDMGR', expectedVersion: 7 });
    // Saved: the suggestion leaves the page and the address
    await waitFor(() =>
      expect(screen.queryByRole('region', { name: /A suggested change/ })).not.toBeInTheDocument(),
    );
    expect(lastRouter!.state.location.search).toBe('');
  });

  it('discards the suggestion, putting the stored answers back', async () => {
    renderPage(suggestion);
    const card = await screen.findByRole('region', { name: 'A suggested change from case C-000008' });
    await userEvent.click(within(card).getByRole('button', { name: 'Discard the suggestion' }));
    await waitFor(() => expect(screen.queryByRole('region', { name: /A suggested change/ })).toBeNull());
    expect(screen.getByRole('button', { name: 'Confirm these answers…' })).toBeInTheDocument();
    expect(lastRouter!.state.location.search).toBe('');
  });

  it('discards only the suggested change, keeping the other edits in the draft', async () => {
    renderPage(suggestion);
    const card = await screen.findByRole('region', { name: 'A suggested change from case C-000008' });
    const cancels = screen.getByRole('switch', { name: /Downstream Out accepts cancels/ });
    await userEvent.click(cancels);
    await userEvent.click(within(card).getByRole('button', { name: 'Discard the suggestion' }));
    await waitFor(() => expect(screen.queryByRole('region', { name: /A suggested change/ })).toBeNull());
    expect(screen.getByRole('switch', { name: /Downstream Out accepts cancels/ })).toBeChecked();
    await userEvent.click(screen.getByRole('button', { name: 'Review and save…' }));
    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).queryByText(/Authoritative source: from/)).not.toBeInTheDocument();
    expect(within(dialog).getAllByText(/cancels/i).length).toBeGreaterThan(0);
  });

  it("takes the change and its wording from the case's facts, never from the address", async () => {
    // An address with words of its own: only the case and the fact are read from it
    renderPage(
      `?suggest=C-000008&fact=W1&why=${encodeURIComponent('Trust this link')}&to=PAS&affects=everything`,
    );
    const card = await screen.findByRole('region', { name: 'A suggested change from case C-000008' });
    expect(card).not.toHaveTextContent(/Trust this link/);
    const row = within(within(card).getByRole('table', { name: 'The change in this draft' }))
      .getByRole('rowheader', { name: /Authoritative source/ })
      .closest('tr')!;
    expect(row).toHaveTextContent('BEDMGR');
    expect(row).not.toHaveTextContent('PAS');
    expect(
      within(card).getByText(/every failure where another source system applied a movement/),
    ).toBeInTheDocument();
  });

  it('pre-fills nothing for a fact the case does not have, or facts that cannot be read', async () => {
    renderPage('?suggest=C-000008&fact=W9');
    const card = await screen.findByRole('region', { name: 'A suggested change' });
    expect(within(card).getByText(/Case C-000008 has no such What-if fact now/)).toBeInTheDocument();
    expect(within(card).queryByRole('table')).not.toBeInTheDocument();
    expect(within(card).queryByRole('button', { name: 'Review and save…' })).not.toBeInTheDocument();
  });

  it('says so when the case facts cannot be read', async () => {
    server.use(
      http.get(`${BASE}/cases/:id/whatif`, () => HttpResponse.json({ error: 'boom' }, { status: 500 })),
    );
    renderPage(suggestion);
    const card = await screen.findByRole('region', { name: 'A suggested change' });
    expect(within(card).getByText(/could not be read, so nothing was pre-filled/)).toBeInTheDocument();
  });

  it('pre-fills nothing when the profile changed since the facts were read', async () => {
    const stored = recordedSiteProfile()!;
    stored.profile.authoritative_source = 'PAS';
    server.use(http.get(`${BASE}/site-profile`, () => HttpResponse.json(stored)));
    renderPage(suggestion);
    const card = await screen.findByRole('region', { name: 'A suggested change from case C-000008' });
    expect(within(card).getByText('Not pre-filled')).toBeInTheDocument();
    expect(within(card).getByText(/authoritative source is now PAS, not none named/)).toBeInTheDocument();
    expect(within(card).queryByRole('button', { name: 'Review and save…' })).not.toBeInTheDocument();
  });

  it('shows an operator the draft, and that an approver saves it', async () => {
    resetMock('operator');
    renderPage(suggestion);
    const card = await screen.findByRole('region', { name: 'A suggested change from case C-000008' });
    expect(within(card).getByText(/Saving it needs the approver role/)).toBeInTheDocument();
    expect(within(card).queryByRole('button', { name: 'Review and save…' })).not.toBeInTheDocument();
  });
});

describe("SiteProfilePage, as the public demo's role reads it", () => {
  const suggestion = suggestionHref({ caseId: 'C-000008', fact: 'W1' }).replace('/site-profile', '');
  const saves = () =>
    screen.queryByRole('button', { name: /Review and save|Confirm these answers|Save version/ });

  beforeEach(() => resetMock('demo'));

  it('keeps the answers for reading and puts a note where Save would be', async () => {
    renderPage();
    expect(await screen.findByTestId('demo-read-only')).toHaveTextContent(
      "On the online demo you can approve or reject plans; a site's approver saves changes here",
    );
    expect((await inReceiver1()).getByRole('radio', { name: /2, operations/ })).toBeDisabled();
    expect(saves()).not.toBeInTheDocument();
    expect(screen.queryByText(/Changing the answers needs the approver role/)).not.toBeInTheDocument();
    expect(screen.queryByText(/a save lasts until the page is reloaded/)).not.toBeInTheDocument();
    // The shipped answers are listed, as for everyone
    expect(screen.getByText('Shutter is running on the shipped answers')).toBeInTheDocument();
    // Beside that notice it says who saves, and never tells this role to do it
    const notice = screen.getByText('Shutter is running on the shipped answers').closest('[role]')!;
    expect(within(notice as HTMLElement).getByTestId('demo-read-only')).toBeInTheDocument();
    expect(screen.queryByText(/confirm or change them and save/)).not.toBeInTheDocument();
  });

  it('keeps the pre-filled draft and its review for reading, with the note instead of Save', async () => {
    renderPage(suggestion);
    const card = await screen.findByRole('region', { name: 'A suggested change from case C-000008' });
    expect(within(card).getByText('BEDMGR')).toBeInTheDocument();
    expect(within(card).queryByRole('button', { name: 'Review and save…' })).not.toBeInTheDocument();
    expect(within(card).getByText(/On the online demo you can approve or reject plans/)).toBeInTheDocument();
    await userEvent.click(within(card).getByRole('button', { name: 'Review the change…' }));
    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText(/Authoritative source: from .* to BEDMGR/)).toBeInTheDocument();
    expect(within(dialog).getByTestId('demo-read-only')).toHaveTextContent(
      'On the online demo you can approve or reject plans',
    );
    expect(within(dialog).queryByRole('button', { name: /Save version/ })).not.toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole('button', { name: 'Done' }));
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
    // The page itself offers the review of the draft too, and still no save
    expect(screen.getByRole('button', { name: 'Review the changes…' })).toBeInTheDocument();
    expect(saves()).not.toBeInTheDocument();
    expect(puts).toEqual([]);
  });
});

describe('SiteProfilePage, which server it asks', () => {
  const asServer = (me: object) =>
    server.use(http.get(`${BASE}/me`, () => HttpResponse.json({ username: 'approver', ...me })));

  it('saves as before for an approver whose server sends no `can`', async () => {
    asServer({ operator: true, approver: true });
    renderPage();
    expect(await screen.findByRole('button', { name: 'Confirm these answers…' })).toBeEnabled();
    expect(screen.queryByTestId('demo-read-only')).not.toBeInTheDocument();
  });

  it('offers Save to whoever the server says may configure', async () => {
    asServer({
      operator: true,
      approver: true,
      can: { operate: true, approve: true, configure: true, scenarios: true },
    });
    renderPage();
    expect(await screen.findByRole('button', { name: 'Confirm these answers…' })).toBeEnabled();
  });

  it('withholds Save from an approver the server says may not configure, and says the demo is read-only', async () => {
    asServer({
      operator: true,
      approver: true,
      can: { operate: true, approve: true, configure: false, scenarios: true },
    });
    renderPage();
    expect(await screen.findByTestId('demo-read-only')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /Review and save|Confirm these answers/ })).toBeNull();
  });
});
