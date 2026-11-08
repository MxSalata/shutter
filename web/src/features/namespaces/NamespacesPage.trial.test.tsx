import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import recorded from '@/mocks/onboarding.json';
import { useAppearance } from '@/stores/appearance';
import { layer1Words } from '@/test/words';
import { theme } from '@/theme';
import NamespacesPage from './NamespacesPage';

/** The page as the trial shows it: the recorded onboarding, answered in the browser. */
vi.mock('@/env/mode', async (importOriginal) => {
  const mode = await importOriginal<typeof import('@/env/mode')>();
  return { ...mode, TRIAL: true, ENV: mode.envFrom('', true) };
});

const PATHOLOGY = recorded.namespaces.PATHOLOGY;

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
beforeEach(() => {
  resetMock('approver');
  useAppearance.setState({ detail: 'plain' });
});

function renderTrial() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter([{ path: '/settings/namespaces', element: <NamespacesPage /> }], {
    initialEntries: ['/settings/namespaces'],
  });
  return render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

async function applyPathology(user: ReturnType<typeof userEvent.setup>) {
  await user.selectOptions(await screen.findByLabelText('Namespace'), 'PATHOLOGY');
  await user.click(screen.getByRole('button', { name: 'Read the plan' }));
  const plan = await screen.findByRole('region', { name: 'The plan for PATHOLOGY' });
  await user.click(within(plan).getByRole('button', { name: 'Apply this plan…' }));
  const dialog = await screen.findByRole('dialog', { name: /Apply this plan/ });
  expect(within(dialog).getByText('Trial only')).toBeInTheDocument();
  await user.click(within(dialog).getByRole('button', { name: 'Apply the plan' }));
  return screen.findByRole('region', { name: 'What changed in PATHOLOGY' });
}

describe('NamespacesPage in the trial', () => {
  it('says the answers are a replay, and offers no options, which have no recording', async () => {
    renderTrial();
    await screen.findByLabelText('Namespace');
    expect(screen.getByText(/Replayed from a recording/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Options' })).not.toBeInTheDocument();
    expect(layer1Words(document.body).join(' ')).not.toMatch(/\blive\b/i);
  });

  it('replays the plan, the apply and the test, and a reload of the mock starts again', async () => {
    const user = userEvent.setup();
    renderTrial();
    const done = await applyPathology(user);
    expect(within(done).getByText(PATHOLOGY.apply.changed[0])).toBeInTheDocument();
    const row = await screen.findByRole('row', { name: /PATHOLOGY/ });
    await user.click(within(row).getByRole('button', { name: 'Send a test failure' }));
    // The recorded case is not one of the trial's, so it is named and not linked
    const ok = await screen.findByText(/A test case opened/);
    expect(ok).toHaveTextContent(PATHOLOGY.test.case);
    expect(within(ok).queryByRole('link')).toBeNull();
    resetMock('approver');
  });

  it('replays the removal, and the namespace is offered again', async () => {
    const user = userEvent.setup();
    renderTrial();
    await applyPathology(user);
    const row = await screen.findByRole('row', { name: /PATHOLOGY/ });
    await user.click(within(row).getByRole('button', { name: 'Take off…' }));
    const dialog = await screen.findByRole('dialog', { name: /Take PATHOLOGY off/ });
    await user.click(await within(dialog).findByRole('button', { name: 'Take it off' }));
    const result = await screen.findByRole('region', { name: 'Taken off PATHOLOGY' });
    expect(within(result).getByText(PATHOLOGY.remove.removed[0])).toBeInTheDocument();
    const select = await screen.findByLabelText('Namespace');
    expect(await within(select).findByRole('option', { name: 'PATHOLOGY' })).toBeInTheDocument();
  });

  it('refuses the online demo role, as the server does', async () => {
    resetMock('demo');
    renderTrial();
    expect(await screen.findByText(/An approver who may change the site/)).toBeInTheDocument();
  });
});
