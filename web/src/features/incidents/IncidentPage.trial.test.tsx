import { MantineProvider } from '@mantine/core';
import { Notifications, notifications } from '@mantine/notifications';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import type { IncidentDetail, IncidentEvent } from '@/api/types';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { useAppearance } from '@/stores/appearance';
import { layer1Words } from '@/test/words';
import { theme } from '@/theme';
import IncidentPage from './IncidentPage';
import recorded from './test-incident.json';

/** The page as the trial shows it: the recorded incident, answered in the browser. */
vi.mock('@/env/mode', async (importOriginal) => {
  const mode = await importOriginal<typeof import('@/env/mode')>();
  return { ...mode, TRIAL: true, ENV: mode.envFrom('', true) };
});

const BASE = '/api/shutter';

/** The recorded incident while its ordered chain waits for the incident's approval. */
function waiting(): IncidentDetail {
  const inc = structuredClone(recorded.detail) as unknown as IncidentDetail;
  inc.state = 'releasing';
  inc.closedAt = undefined;
  inc.approvals = [];
  const ordered = inc.chains.find((c) => c.seq === 2)!;
  ordered.state = 'awaiting_approval';
  ordered.items = ordered.items.map((i) => ({
    ...i,
    state: 'pending',
    verifiedVersion: null,
    caseState: 'grouped',
  }));
  return inc;
}

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => {
  server.resetHandlers();
  notifications.clean();
});
afterAll(() => server.close());
beforeEach(() => {
  resetMock('approver');
  useAppearance.setState({ detail: 'plain' });
  server.use(
    http.get(`${BASE}/incidents/:id`, () => HttpResponse.json(waiting())),
    http.get(`${BASE}/incidents/:id/events`, () => HttpResponse.json(recorded.events as IncidentEvent[])),
  );
});

function renderTrial() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter([{ path: '/incidents/:incidentId', element: <IncidentPage /> }], {
    initialEntries: ['/incidents/I-000001'],
  });
  render(
    <MantineProvider theme={theme}>
      <Notifications />
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

describe('IncidentPage in the trial', () => {
  it('invites the approval, says what you will see and that nothing leaves the browser', async () => {
    renderTrial();
    const approval = await screen.findByRole('region', { name: 'Approval' });
    await userEvent.click(await within(approval).findByRole('button', { name: /Approve/ }));
    // The dialog's name is its title alone: the chip beside it is not part of it
    const dialog = await screen.findByRole('dialog', { name: /^Approve the release of \d+ chains?$/ });
    expect(
      within(dialog).getByText(
        'Go ahead. You will see the recorded chain go out in order. Nothing leaves this browser, and a reload starts the recording afresh.',
      ),
    ).toBeInTheDocument();
    expect(within(dialog).getByText('Trial only')).toBeInTheDocument();
    // The live system's consequence is not said here
    expect(within(dialog).queryByText(/for real/)).not.toBeInTheDocument();
    expect(within(dialog).queryByText('Live system')).not.toBeInTheDocument();
  });

  it('keeps the word "live" out of the first layer', async () => {
    renderTrial();
    await screen.findByRole('region', { name: 'Approval' });
    expect(layer1Words(document.body).join(' ')).not.toMatch(/\blive\b/i);
  });
});
