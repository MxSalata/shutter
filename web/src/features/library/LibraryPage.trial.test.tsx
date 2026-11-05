import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import type { LibraryMember } from '@/api/types';
import fixtures from '@/mocks/fixtures.json';
import { server } from '@/mocks/node';
import { resetMock } from '@/mocks/handlers';
import { theme } from '@/theme';
import LibraryPage from './LibraryPage';

// This file reads the library in the trial; LibraryPage.test.tsx reads it live
const mode = vi.hoisted(() => ({ trial: true }));
vi.mock('@/env/mode', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/env/mode')>()),
  get TRIAL() {
    return mode.trial;
  },
}));

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

const library = fixtures.library as unknown as LibraryMember[];

function renderPage() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter([{ path: '/library', element: <LibraryPage /> }], {
    initialEntries: ['/library'],
  });
  return render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

describe('LibraryPage in the trial', () => {
  it('says under a card that a change lasts only in the trial, and only under the card that changed', async () => {
    resetMock('approver');
    renderPage();
    const impact = library.find((m) => m.code === 'impact')!;
    const sw = await screen.findByRole('switch', { name: `${impact.name} on the default board` });
    expect(screen.queryByText('Changed in the trial only.')).not.toBeInTheDocument();
    expect(screen.getByText('On the default board: 4 of 4')).toBeInTheDocument();

    await userEvent.click(sw);
    const card = within(screen.getByRole('article', { name: impact.name }));
    expect(await card.findByText('Changed in the trial only.')).toBeInTheDocument();
    // Under its own card only, and the recorded runs are not what it changes
    expect(card.getByText('The recorded runs stay as they were.')).toBeInTheDocument();
    expect(screen.getAllByText('Changed in the trial only.')).toHaveLength(1);
    // The board's count follows the change
    expect(await screen.findByText('On the default board: 3 of 4')).toBeInTheDocument();

    // Put the mock's library back for the other tests in this file
    await waitFor(() => expect(sw).toBeEnabled());
    await userEvent.click(sw);
    expect(await screen.findByText('On the default board: 4 of 4')).toBeInTheDocument();
    expect(impact.inDefaultBoard).toBe(true);
  });

  it("keeps the public demo's role to reading, with no mention of a change", async () => {
    resetMock('demo');
    renderPage();
    expect(await screen.findByTestId('demo-read-only')).toBeInTheDocument();
    expect(screen.queryByRole('switch')).not.toBeInTheDocument();
    expect(screen.queryByText('Changed in the trial only.')).not.toBeInTheDocument();
  });
});
