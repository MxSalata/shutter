import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, within } from '@testing-library/react';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import fixtures from '@/mocks/fixtures.json';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { theme } from '@/theme';
import IncidentsPage from './IncidentsPage';

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
beforeEach(() => resetMock('approver'));

function renderPage() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter([{ path: '/incidents', element: <IncidentsPage /> }], {
    initialEntries: ['/incidents'],
  });
  render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

describe('IncidentsPage', () => {
  it('lists the interfaces held for a schema not loaded here, by category, above the incidents', async () => {
    server.use(
      http.get('/api/shutter/settings', () =>
        HttpResponse.json({
          ...fixtures.settings,
          preventFailures: true,
          heldMessages: {
            count: 3,
            categories: [
              { category: 'MYSITE_2.5.1', namespace: 'HOSPITAL', count: 3, oldest: '2026-11-01T09:20:00Z' },
            ],
          },
        }),
      ),
    );
    renderPage();
    const held = await screen.findByTestId('held-interfaces');
    expect(within(held).getByRole('heading', { name: 'Held: a schema not loaded here' })).toBeInTheDocument();
    expect(within(held).getByText('MYSITE_2.5.1')).toBeInTheDocument();
    expect(within(held).getByRole('cell', { name: 'HOSPITAL' })).toBeInTheDocument();
    expect(within(held).getByRole('cell', { name: '3' })).toBeInTheDocument();
    expect(
      within(held).getByText(/Import the schema where it is missing and set the inbound item's category/),
    ).toBeInTheDocument();
    // An attention notice: the fact in a sentence, the instruction one click away
    expect(held.querySelector('[data-tone="attention"]')).not.toBeNull();
    expect(within(held).getByRole('button', { name: 'How to release them' })).toHaveAttribute(
      'aria-expanded',
      'false',
    );
  });

  it('shows no such list while nothing is held, as on a site that does not prevent failures', async () => {
    renderPage();
    expect(await screen.findByRole('heading', { name: 'Incidents' })).toBeInTheDocument();
    expect(screen.queryByTestId('held-interfaces')).not.toBeInTheDocument();
  });
});
