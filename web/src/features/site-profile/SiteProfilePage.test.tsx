import { MantineProvider } from '@mantine/core';
import { Notifications, notifications } from '@mantine/notifications';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { SiteProfile } from '@/api/types';
import fixtures from '@/mocks/fixtures.json';
import { server } from '@/mocks/node';
import { resetMock } from '@/mocks/handlers';
import { theme } from '@/theme';
import SiteProfilePage from './SiteProfilePage';

const BASE = '/api/shutter';
const recorded = (fixtures as unknown as { siteProfile: { profile: SiteProfile; version: number } })
  .siteProfile;
let puts: { body: Record<string, unknown>; headers: Headers }[] = [];

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

function renderPage() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter([{ path: '/site-profile', element: <SiteProfilePage /> }], {
    initialEntries: ['/site-profile'],
  });
  return render(
    <MantineProvider theme={theme}>
      <Notifications />
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

describe('SiteProfilePage', () => {
  it('shows the answers in force, where they came from, and asks for the induction', async () => {
    renderPage();
    expect(await screen.findByText('Seeded from knowledge/site/profile.json')).toBeInTheDocument();
    expect(screen.getByText('Shutter is running on the shipped answers')).toBeInTheDocument();
    expect(screen.getByRole('radio', { name: /2, operations/ })).toBeChecked();
    expect(screen.getByRole('radio', { name: 'In arrival order' })).toBeChecked();
    expect(screen.getByRole('switch', { name: /accepts cancels/ })).not.toBeChecked();
    expect(screen.getByRole('combobox', { name: 'Tier 2, ordered chains' })).toHaveValue('approval');
    expect(screen.getByRole('textbox', { name: 'Failures' })).toHaveValue('5');
    const summary = screen.getByRole('list', { name: 'Who approves what' });
    expect(within(summary).getAllByText('automatic').length).toBeGreaterThan(0);
  });

  it('lets an operator read the answers but not change them', async () => {
    resetMock('operator');
    renderPage();
    expect(await screen.findByText(/Changing the answers needs the approver role/)).toBeInTheDocument();
    expect(screen.getByRole('radio', { name: /2, operations/ })).toBeDisabled();
    expect(
      screen.queryByRole('button', { name: /Review and save|Confirm these answers/ }),
    ).not.toBeInTheDocument();
  });

  it('saves a change as the next version, sending the whole profile with expectedVersion', async () => {
    renderPage();
    await userEvent.click(await screen.findByRole('radio', { name: /3, clinical safety/ }));
    await userEvent.click(screen.getByRole('button', { name: 'Review and save…' }));
    const dialog = await screen.findByRole('dialog');
    expect(
      within(dialog).getByText('Downstream Out, tier: from 2, operations to 3, clinical safety'),
    ).toBeInTheDocument();
    expect(within(dialog).getByText(/made under version 8 are refused at release/)).toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save version 9' }));
    expect(await screen.findByText('Version 9 saved')).toBeInTheDocument();
    expect(puts).toHaveLength(1);
    expect(puts[0].headers.get('X-Requested-With')).toBe('Shutter');
    const { version: _v, ...expected } = structuredClone(recorded.profile);
    expected.receivers[0].tier = 3;
    expect(puts[0].body).toEqual({ ...expected, expectedVersion: recorded.version });
    expect(await screen.findByText('Saved in Shutter')).toBeInTheDocument();
    expect(screen.queryByText('Shutter is running on the shipped answers')).not.toBeInTheDocument();
  });

  it('adds a team that corrects a receiver by hand, and sends it with the profile', async () => {
    renderPage();
    await userEvent.click(await screen.findByRole('button', { name: 'Add a team' }));
    const team = screen.getByRole('group', { name: 'Team 3: new' });
    await userEvent.type(within(team).getByRole('textbox', { name: 'Short id' }), 'beds');
    await userEvent.type(within(team).getByRole('textbox', { name: 'Team' }), 'Bed management');
    await userEvent.type(within(team).getByRole('textbox', { name: 'Mailbox' }), 'beds@trust.nhs.net');
    const copies = within(team).getByRole('textbox', { name: 'Copies' });
    await userEvent.type(copies, 'oncall@trust.nhs.net, ');
    // A trailing comma survives while typing the next address
    expect(copies).toHaveValue('oncall@trust.nhs.net, ');
    await userEvent.click(within(team).getByRole('checkbox', { name: 'Downstream Out' }));
    await userEvent.click(screen.getByRole('button', { name: 'Review and save…' }));
    const dialog = await screen.findByRole('dialog');
    expect(
      within(dialog).getByText(
        'Team added: Bed management <beds@trust.nhs.net>, copies oncall@trust.nhs.net, for Downstream Out',
      ),
    ).toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save version 9' }));
    expect(await screen.findByText('Version 9 saved')).toBeInTheDocument();
    // The seed's two teams first, as stored, then the new one
    const teams = puts[0].body.teams as { id: string }[];
    expect(teams.map((t) => t.id)).toEqual(['integration', 'pas', 'beds']);
    expect(teams.slice(2)).toEqual([
      {
        id: 'beds',
        name: 'Bed management',
        mailbox: 'beds@trust.nhs.net',
        cc: ['oncall@trust.nhs.net'],
        receivers: ['Downstream Out'],
        sources: [],
      },
    ]);
  });

  it('refuses a team mailbox outside the allowed domains before sending, and points at it', async () => {
    renderPage();
    await userEvent.type(
      await screen.findByRole('textbox', { name: 'Mail domains allowed for the teams' }),
      'example.nhs.uk',
    );
    await userEvent.click(screen.getByRole('button', { name: 'Add a team' }));
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
  });

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
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save version 9' }));
    expect(await screen.findByText('Version 9 saved')).toBeInTheDocument();
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
        name: /^Feed, time zone: must be UTC, Europe\/London or a fixed offset/,
      }),
    ).toBeInTheDocument();
    await waitFor(() => expect(offset).toHaveFocus());
    await userEvent.type(offset, '+02:00');
    await userEvent.click(screen.getByRole('button', { name: 'Discard changes' }));
    expect(screen.getByRole('radio', { name: /UK time/ })).toBeChecked();
    expect(screen.queryByRole('textbox', { name: 'Offset' })).not.toBeInTheDocument();
  });

  it('sends note text to the model only when the site says so', async () => {
    renderPage();
    const sw = await screen.findByRole('switch', { name: /^Send note text to the model/ });
    expect(sw).not.toBeChecked();
    await userEvent.click(sw);
    await userEvent.click(screen.getByRole('button', { name: 'Review and save…' }));
    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Note text: sent to the model from now on')).toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save version 9' }));
    expect(await screen.findByText('Version 9 saved')).toBeInTheDocument();
    expect(puts[0].body.model_content).toEqual({ free_text: true });
  });

  it('confirms the shipped answers with no change, which records who answered', async () => {
    renderPage();
    await userEvent.click(await screen.findByRole('button', { name: 'Confirm these answers…' }));
    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Confirm as version 9' }));
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
    const save = within(dialog).getByRole('button', { name: 'Save version 9' });
    expect(save).toBeDisabled();
    expect(within(dialog).getByText('Fewer releases wait for a person')).toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole('checkbox', { name: /I mean it/ }));
    expect(save).toBeEnabled();
  });

  it('checks an answer before anything is sent, and points at the field', async () => {
    renderPage();
    const name = await screen.findByRole('textbox', { name: /Production item/ });
    await userEvent.clear(name);
    await userEvent.click(screen.getByRole('button', { name: 'Review and save…' }));
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    expect(await screen.findByText('Receiver 1, name: required')).toBeInTheDocument();
    await waitFor(() => expect(name).toHaveFocus());
    expect(puts).toHaveLength(0);
  });

  it('keeps the edits when someone else saved meanwhile, and saves them against the newer version', async () => {
    renderPage();
    await userEvent.click(await screen.findByRole('radio', { name: /3, clinical safety/ }));
    // Someone else saves version 9 while this page holds version 8
    const theirs = structuredClone(recorded.profile);
    delete theirs.version;
    theirs.incident = { ...theirs.incident, threshold: 8 };
    const res = await fetch(`${BASE}/site-profile`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json', 'X-Requested-With': 'Shutter' },
      body: JSON.stringify({ ...theirs, expectedVersion: 8 }),
    });
    expect(res.status).toBe(200);
    await userEvent.click(screen.getByRole('button', { name: 'Review and save\u2026' }));
    let dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save version 9' }));
    expect(await within(dialog).findByText(/Version 9 was saved by someone else/)).toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole('button', { name: 'Keep editing' }));
    await userEvent.click(screen.getByRole('button', { name: 'Review and save\u2026' }));
    dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Incidents, failures: from 8 to 5')).toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save version 10' }));
    expect(await screen.findByText('Version 10 saved')).toBeInTheDocument();
    expect(puts.at(-1)?.body.expectedVersion).toBe(9);
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
    await userEvent.click(await screen.findByRole('radio', { name: /3, clinical safety/ }));
    await userEvent.click(screen.getByRole('button', { name: 'Review and save\u2026' }));
    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save version 9' }));
    expect(await screen.findByText('Version 9 saved')).toBeInTheDocument();
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
    await userEvent.click(await screen.findByRole('radio', { name: /3, clinical safety/ }));
    await userEvent.click(screen.getByRole('button', { name: 'Review and save\u2026' }));
    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save version 9' }));
    expect(await screen.findByText('Receiver 1, tier: must be 1, 2 or 3')).toBeInTheDocument();
    await waitFor(() => expect(screen.getByRole('radio', { name: /3, clinical safety/ })).toHaveFocus());
  });

  it('lists the versions with what each changed', async () => {
    renderPage();
    const versions = await screen.findByRole('region', { name: 'Versions' });
    expect(await within(versions).findByRole('button', { name: /Version 8/ })).toBeInTheDocument();
    await userEvent.click(within(versions).getByRole('button', { name: /Version 8/ }));
    expect(await within(versions).findByText('The first stored version.')).toBeInTheDocument();
  });
});
