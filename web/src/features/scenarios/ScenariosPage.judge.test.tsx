import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor, within } from '@testing-library/react';
import { createMemoryRouter, Outlet, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { server } from '@/mocks/node';
import { resetMock } from '@/mocks/handlers';
import { theme } from '@/theme';
import { Guide } from '@/features/guide/Guide';
import { forgetProgress, welcomeSnoozed } from '@/features/guide/storage';
import { useGuide } from '@/features/guide/store';
import { INITIAL } from '@/features/guide/controller';
import ScenariosPage from './ScenariosPage';

/** The trial reached by the judges' path, `?trial=judge`, which has already put the page on Scenarios in Rules only. */
vi.mock('@/env/mode', async (importOriginal) => {
  const mode = await importOriginal<typeof import('@/env/mode')>();
  return { ...mode, TRIAL: true, ENV: mode.envFrom('?trial=judge', true) };
});

const scrolled = vi.fn();
beforeAll(() => {
  server.listen({ onUnhandledRequest: 'error' });
  window.scrollTo = scrolled as unknown as typeof window.scrollTo;
});
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

function renderJudge() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter(
    [
      {
        element: (
          <>
            <Outlet />
            <Guide />
          </>
        ),
        children: [{ path: '/scenarios', element: <ScenariosPage /> }],
      },
    ],
    { initialEntries: ['/scenarios?mode=rules'] },
  );
  render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

describe("the judges' path", () => {
  beforeEach(() => {
    resetMock('approver');
    localStorage.clear();
    forgetProgress();
    useGuide.setState({ progress: INITIAL, phase: 'closed', snoozed: false, pointAt: null });
  });

  it('lands on the S8 card in Rules only, its Run focused, with no welcome now or on a reload', async () => {
    renderJudge();
    const first = await screen.findByRole('region', { name: 'Try these three first' });
    const run = await within(first).findByRole('button', { name: 'Run S8 in Rules only mode' });
    await waitFor(() => expect(run).toHaveFocus());
    expect(scrolled).toHaveBeenCalled();
    expect(screen.getByRole('radio', { name: /^Rules only/ })).toBeChecked();
    expect(screen.queryByRole('dialog', { name: 'Welcome to the Shutter trial' })).not.toBeInTheDocument();
    // Put off for the visit, so the reload (an ordinary trial page) does not welcome either
    expect(useGuide.getState().snoozed).toBe(true);
    expect(welcomeSnoozed()).toBe(true);
  });
});
