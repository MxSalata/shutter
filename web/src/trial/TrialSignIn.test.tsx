import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { api } from '@/api/client';
import { keys } from '@/api/hooks';
import { chooseTransport, resetTransportForTests } from '@/api/transport';
import type { Me } from '@/api/types';
import { resetMock } from '@/mocks/handlers';
import { theme } from '@/theme';
import { LiveBanner } from '@/features/shell/LiveBanner';
import { createTrialTransport } from './transport';
import TrialSignIn from './TrialSignIn';

/** A trial page of a build IRIS serves (Leave trial offered), its calls answered by the trial's own transport. */
vi.mock('@/env/mode', async (importOriginal) => {
  const mode = await importOriginal<typeof import('@/env/mode')>();
  return { ...mode, TRIAL: true, ENV: mode.envFrom('?trial', false) };
});

const sent = vi.fn(() => Promise.reject(new Error('fetch was called from the trial')));
beforeAll(() => {
  vi.stubGlobal('fetch', sent);
  resetTransportForTests();
  chooseTransport(createTrialTransport('approver'));
});
afterEach(() => {
  expect(sent).not.toHaveBeenCalled();
});
afterAll(() => {
  vi.unstubAllGlobals();
  resetTransportForTests();
});

function renderSignIn() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter(
    [
      { path: '/login', element: <TrialSignIn /> },
      {
        path: '/scenarios',
        element: (
          <>
            <LiveBanner />
            <h1>Scenarios</h1>
          </>
        ),
      },
    ],
    { initialEntries: ['/login'] },
  );
  render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
  return client;
}

describe("the trial's sign-in page", () => {
  beforeEach(() => {
    resetMock(null);
    sessionStorage.clear();
  });

  it('offers the trial roles and no password field', async () => {
    renderSignIn();
    expect(
      await screen.findByRole('heading', { name: 'Choose who you are in the trial', level: 1 }),
    ).toBeVisible();
    expect(screen.getByText("No password: these are the trial's own roles.")).toBeInTheDocument();
    for (const name of ['approver', 'operator', 'public demo role', 'judge'])
      expect(screen.getByRole('button', { name: `Continue as ${name}` })).toBeInTheDocument();
    expect(screen.queryByLabelText(/Password/)).not.toBeInTheDocument();
    expect(document.querySelector('input[type="password"]')).toBeNull();
    expect(screen.getByRole('button', { name: 'Leave trial' })).toBeInTheDocument();
  });

  it("signs the public demo's role in, which cannot configure or run, and sees the replayed hospital feed", async () => {
    const client = renderSignIn();
    expect(screen.getByText(/sees the replayed hospital feed/)).toBeInTheDocument();
    await userEvent.click(await screen.findByRole('button', { name: 'Continue as public demo role' }));
    expect(await screen.findByRole('heading', { name: 'Scenarios' })).toBeInTheDocument();
    await waitFor(() => expect(client.getQueryData<Me>(keys.me)?.username).toBe('demo'));
    expect(client.getQueryData<Me>(keys.me)?.can).toEqual({
      operate: true,
      approve: true,
      configure: false,
      scenarios: false,
      liveAgents: false,
    });
    // The tab keeps the role for its reloads
    expect(sessionStorage.getItem('shutter:trial:as')).toBe('demo');
    // In the trial the feed is the recording replayed, never "live"
    const feed = await screen.findByRole('region', { name: 'Hospital feed (replayed)' });
    expect(feed).toHaveTextContent(/^Hospital feed \(replayed\): a new failure every 7 minutes\. Last: S2, /);
    expect(feed.textContent).not.toMatch(/\blive\b/i);
  });

  it('opens signed in: the trial transport starts with its role signed in', async () => {
    resetTransportForTests();
    chooseTransport(createTrialTransport('operator'));
    expect(await api.get<Me>('/me')).toMatchObject({ username: 'operator', approver: false });
  });
});
