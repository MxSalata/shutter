import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { server } from '@/mocks/node';
import { resetMock } from '@/mocks/handlers';
import { theme } from '@/theme';
import CasePage from '@/features/cases/CasePage';
import ScenariosPage from '@/features/scenarios/ScenariosPage';
import SettingsPage from '@/features/settings/SettingsPage';

/** The screens as the demo build shows them: recorded data on the in-browser mock, with no IRIS behind it. */
vi.mock('@/demo', () => ({ DEMO: true, DEMO_USER: { username: 'approver', password: 'shutter' } }));

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

function renderAt(path: string) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter(
    [
      { path: '/scenarios', element: <ScenariosPage /> },
      { path: '/cases/:caseId', element: <CasePage /> },
      { path: '/settings', element: <SettingsPage /> },
    ],
    { initialEntries: [path] },
  );
  return render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

describe('the demo', () => {
  beforeEach(() => resetMock('approver'));

  it('leaves out the single investigator, which has no recordings', async () => {
    renderAt('/scenarios');
    expect(await screen.findByRole('radio', { name: 'Board' })).toBeInTheDocument();
    expect(screen.queryByRole('radio', { name: 'Single investigator' })).not.toBeInTheDocument();
    await userEvent.click(screen.getByRole('radio', { name: 'Site policy' }));
    expect(
      await screen.findByText('Not defined for Site policy mode. Its modes: Board, Rules only.'),
    ).toBeInTheDocument();
  });

  it('says the held case is a replay, and links nothing into a portal it does not have', async () => {
    const { container } = renderAt('/cases/C-000002');
    const approval = await screen.findByRole('region', { name: 'Approval' });
    expect(await within(approval).findByText('Demo replay')).toBeInTheDocument();
    expect(await screen.findByText('Message trace (on an instance)')).toBeInTheDocument();
    expect(screen.getByText('Workflow trace (on an instance)')).toBeInTheDocument();
    const board = await screen.findByRole('region', { name: 'The board' });
    expect(
      (await within(board).findAllByText("The run's message in the production (on an instance)")).length,
    ).toBe(4);
    expect(container.querySelectorAll('a[href*="/csp/"]')).toHaveLength(0);
  });
});

describe('Settings', () => {
  beforeEach(() => resetMock('approver'));

  it('leads with what is configured, not with what is missing', async () => {
    renderAt('/settings');
    expect(await screen.findByText('4 AI Hub agents, replaying 64 recorded live runs')).toBeInTheDocument();
    expect(
      screen.getByText(
        'Not on this instance: AI Hub, the live runner and a model provider. A replay needs none of them: the recorded runs answer.',
      ),
    ).toBeInTheDocument();
    expect(screen.queryByText(/^No AI Hub/)).not.toBeInTheDocument();
    expect(await screen.findByText(/64 replayed runs cost nothing/)).toBeInTheDocument();
  });
});
