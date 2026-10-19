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
      within(dialog).getByText('Ward Out, tier: from 2, operations to 3, clinical safety'),
    ).toBeInTheDocument();
    expect(within(dialog).getByText(/made under version 6 are refused at release/)).toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save version 7' }));
    expect(await screen.findByText('Version 7 saved')).toBeInTheDocument();
    expect(puts).toHaveLength(1);
    expect(puts[0].headers.get('X-Requested-With')).toBe('Shutter');
    const { version: _v, ...expected } = structuredClone(recorded.profile);
    expected.receivers[0].tier = 3;
    expect(puts[0].body).toEqual({ ...expected, expectedVersion: recorded.version });
    expect(await screen.findByText('Saved in Shutter')).toBeInTheDocument();
    expect(screen.queryByText('Shutter is running on the shipped answers')).not.toBeInTheDocument();
  });

  it('confirms the shipped answers with no change, which records who answered', async () => {
    renderPage();
    await userEvent.click(await screen.findByRole('button', { name: 'Confirm these answers…' }));
    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Confirm as version 7' }));
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
    const save = within(dialog).getByRole('button', { name: 'Save version 7' });
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
    // Someone else saves version 7 while this page holds version 6
    const theirs = structuredClone(recorded.profile);
    delete theirs.version;
    theirs.incident = { ...theirs.incident, threshold: 8 };
    const res = await fetch(`${BASE}/site-profile`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json', 'X-Requested-With': 'Shutter' },
      body: JSON.stringify({ ...theirs, expectedVersion: 6 }),
    });
    expect(res.status).toBe(200);
    await userEvent.click(screen.getByRole('button', { name: 'Review and save\u2026' }));
    let dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save version 7' }));
    expect(await within(dialog).findByText(/Version 7 was saved by someone else/)).toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole('button', { name: 'Keep editing' }));
    await userEvent.click(screen.getByRole('button', { name: 'Review and save\u2026' }));
    dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Incidents, failures: from 8 to 5')).toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save version 8' }));
    expect(await screen.findByText('Version 8 saved')).toBeInTheDocument();
    expect(puts.at(-1)?.body.expectedVersion).toBe(7);
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
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save version 7' }));
    expect(await screen.findByText('Version 7 saved')).toBeInTheDocument();
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
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save version 7' }));
    expect(await screen.findByText('Receiver 1, tier: must be 1, 2 or 3')).toBeInTheDocument();
    await waitFor(() => expect(screen.getByRole('radio', { name: /3, clinical safety/ })).toHaveFocus());
  });

  it('lists the versions with what each changed', async () => {
    renderPage();
    const versions = await screen.findByRole('region', { name: 'Versions' });
    expect(await within(versions).findByRole('button', { name: /Version 6/ })).toBeInTheDocument();
    await userEvent.click(within(versions).getByRole('button', { name: /Version 6/ }));
    expect(await within(versions).findByText('The first stored version.')).toBeInTheDocument();
  });
});
