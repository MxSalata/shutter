import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, within } from '@testing-library/react';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { server } from '@/mocks/node';
import { resetMock } from '@/mocks/handlers';
import { theme } from '@/theme';
import CasePage from './CasePage';

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

function renderCase(caseId: string) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter([{ path: '/cases/:caseId', element: <CasePage /> }], {
    initialEntries: [`/cases/${caseId}`],
  });
  return render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

describe('CasePage', () => {
  beforeEach(() => resetMock('approver'));

  it('tells the story of a resolved case, with the verification apart from the acknowledgement', async () => {
    renderCase('C-000010');
    expect(await screen.findByRole('heading', { name: 'Case C-000010' })).toBeInTheDocument();
    expect(await screen.findByText('Closed: verified')).toBeInTheDocument();
    const board = await screen.findByRole('region', { name: 'The board' });
    expect(await within(board).findByText('Conformance')).toBeInTheDocument();
    expect(await within(board).findByText('Encounter Integrity')).toBeInTheDocument();
    expect(await within(board).findByText('Impact Analysis')).toBeInTheDocument();
    const dispatch = await screen.findByRole('region', { name: 'Dispatch and verification' });
    expect(await within(dispatch).findByText(/Acknowledged/)).toBeInTheDocument();
    expect(await within(dispatch).findByText('Verified at the receiver')).toBeInTheDocument();
  });

  it('says why an escalated case stopped and what comes next', async () => {
    renderCase('C-000002');
    expect(await screen.findByText('Closed: handed to a person')).toBeInTheDocument();
    expect(await screen.findByText('Stopped before any write')).toBeInTheDocument();
    expect(
      await screen.findByText(
        "Read the case's last events for the reason, then investigate again or escalate.",
      ),
    ).toBeInTheDocument();
  });

  it('marks the steps a superseded case did not need', async () => {
    renderCase('C-000008');
    expect(await screen.findByText('Closed: verified')).toBeInTheDocument();
    expect((await screen.findAllByText('not needed')).length).toBe(3);
  });

  it('says so when there is no such case', async () => {
    renderCase('C-999999');
    expect(await screen.findByText('There is no case C-999999')).toBeInTheDocument();
  });
});
