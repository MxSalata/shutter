import { MantineProvider } from '@mantine/core';
import { Notifications, notifications } from '@mantine/notifications';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import fixtures from '@/mocks/fixtures.json';
import { server } from '@/mocks/node';
import { resetMock } from '@/mocks/handlers';
import { theme } from '@/theme';
import LibraryPage from './LibraryPage';

let patches: { path: string; body: Record<string, unknown> }[] = [];

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
beforeEach(() => {
  notifications.clean();
  patches = [];
  server.events.removeAllListeners();
  server.events.on('request:start', async ({ request }) => {
    if (request.method === 'PATCH')
      patches.push({
        path: new URL(request.url).pathname,
        body: (await request.clone().json()) as Record<string, unknown>,
      });
  });
});

function renderPage() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter([{ path: '/library', element: <LibraryPage /> }], {
    initialEntries: ['/library'],
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

const coordinator = fixtures.library.find((m) => m.role === 'coordinator')!;

describe('LibraryPage', () => {
  it('lets an operator read the board but not change it', async () => {
    resetMock('operator');
    renderPage();
    expect(
      await screen.findByText(/Changing which agents sit on the board needs the approver role/),
    ).toBeInTheDocument();
    const switches = screen.getAllByRole('switch');
    expect(switches.length).toBeGreaterThan(0);
    for (const sw of switches) expect(sw).toBeDisabled();
  });

  it('lets an approver change it', async () => {
    resetMock('approver');
    renderPage();
    const sw = await screen.findByRole('switch', { name: `${coordinator.name} enabled` });
    expect(sw).toBeEnabled();
    expect(screen.queryByText(/needs the approver role/)).not.toBeInTheDocument();
    const before = coordinator.enabled;
    await userEvent.click(sw);
    await waitFor(() => expect(patches).toHaveLength(1));
    expect(patches[0]).toEqual({
      path: `/api/shutter/library/${coordinator.code}`,
      body: { enabled: !before },
    });
    // Put the mock's library back for the other tests in this file
    await waitFor(() => expect(sw).toBeEnabled());
    await userEvent.click(sw);
    await waitFor(() => expect(patches).toHaveLength(2));
    await waitFor(() => expect(coordinator.enabled).toBe(before));
  });
});
