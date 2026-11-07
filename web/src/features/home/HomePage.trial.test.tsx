import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen } from '@testing-library/react';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { server } from '@/mocks/node';
import { resetMock } from '@/mocks/handlers';
import { theme } from '@/theme';
import HomePage from './HomePage';

/** Home as the trial shows it: the health it reads is the recording's. */
vi.mock('@/env/mode', async (importOriginal) => {
  const mode = await importOriginal<typeof import('@/env/mode')>();
  return { ...mode, TRIAL: true, ENV: mode.envFrom('', true) };
});

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

describe('HomePage in the trial', () => {
  it('says the production ran when recorded, in a neutral colour, not that it runs now', async () => {
    resetMock('approver');
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    const router = createMemoryRouter([{ path: '/home', element: <HomePage /> }], {
      initialEntries: ['/home'],
    });
    render(
      <MantineProvider theme={theme}>
        <QueryClientProvider client={client}>
          <RouterProvider router={router} />
        </QueryClientProvider>
      </MantineProvider>,
    );
    const badge = await screen.findByText('Running when recorded');
    expect(badge.closest('.mantine-Badge-root')).toHaveStyle(
      '--badge-color: var(--mantine-color-gray-light-color)',
    );
    expect(screen.queryByText('Production running')).not.toBeInTheDocument();
  });
});
