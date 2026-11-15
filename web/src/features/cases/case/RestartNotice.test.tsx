import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { CaseDetail, CaseEvent } from '@/api/types';
import fixtures from '@/mocks/fixtures.json';
import { server } from '@/mocks/node';
import { resetMock } from '@/mocks/handlers';
import { formatZoned } from '@/lib/format';
import { theme } from '@/theme';
import CasePage from '../CasePage';

const ID = 'C-000008';
const recorded = (fixtures.cases as unknown as Record<string, { detail: CaseDetail; events: CaseEvent[] }>)[
  ID
];

/** The start sweep's note, as Shutter.Store.Case.MarkOpenAtStart writes it, at the given time. */
function startNote(at: string, state: string): CaseEvent {
  return {
    seq: recorded.events.length + 1,
    at,
    kind: 'error',
    fromState: '',
    toState: '',
    text: `The production started at ${at} while this case was ${state}. Work in flight resumes when the production was stopped cleanly; if the case does not move on within 15 minutes, an approver can abandon it (POST /cases/${ID}/abandon, or "Abandon the case" on the case page)`,
    actor: 'system',
    ref: `start:${at}`,
  };
}

/** The recorded case as a restart left it in the given state, the start note `minutesAgo` old and its newest event. */
function restartedIn(state: string, minutesAgo: number, after: CaseEvent[] = []) {
  const at = new Date(Date.now() - minutesAgo * 60_000).toISOString().replace(/\.\d+Z$/, 'Z');
  const events = [...recorded.events, startNote(at, state), ...after];
  const detail = { ...recorded.detail, state, disposition: '', closedAt: '' } as CaseDetail;
  server.use(
    http.get(`/api/shutter/cases/${ID}`, () => HttpResponse.json(detail)),
    http.get(`/api/shutter/cases/${ID}/events`, () => HttpResponse.json(events)),
  );
  return at;
}

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
beforeEach(() => resetMock('approver'));

function renderCase() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter([{ path: '/cases/:caseId', element: <CasePage /> }], {
    initialEntries: [`/cases/${ID}`],
  });
  return render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

/** The case's audit trail, once its events are read. */
async function auditTrail() {
  await userEvent.click(await screen.findByRole('tab', { name: 'Audit trail' }));
  const timeline = await screen.findByRole('region', { name: 'Timeline' });
  await waitFor(() => expect(within(timeline).queryByText('No events yet.')).toBeNull());
  return timeline;
}

describe('RestartNotice', () => {
  it('says under the progress strip when the production restarted and to wait, before abandoning is open', async () => {
    const at = restartedIn('investigating', 5);
    renderCase();
    const notice = await screen.findByTestId('case-restart');
    expect(within(notice).getByRole('note')).toHaveTextContent('The production restarted during this case');
    expect(notice).toHaveTextContent(
      `Shutter's production started at ${formatZoned(at)} while this case was investigating, and nothing has moved since. Work in flight resumes after a clean stop, so wait: if nothing moves by ${formatZoned(new Date(Date.parse(at) + 15 * 60_000).toISOString())}, an approver can abandon the case.`,
    );
    // Under the progress strip, before anything else of the case
    const strip = document.getElementById('case-lifecycle')!;
    expect(strip.compareDocumentPosition(notice) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(screen.queryByRole('region', { name: 'Still working' })).not.toBeInTheDocument();
    // The audit trail names the note for what it is, not as an error
    const timeline = await auditTrail();
    expect(within(timeline).getByText('Production started')).toBeInTheDocument();
    expect(within(timeline).queryByText('Error')).not.toBeInTheDocument();
  });

  it('points an approver to Still working once the quiet minutes are over', async () => {
    restartedIn('investigating', 20);
    renderCase();
    const notice = await screen.findByTestId('case-restart');
    expect(notice).toHaveTextContent(
      /nothing has moved for 15 minutes\. If the case's workflow has stopped for good, abandon it under Still working on the Summary tab/,
    );
    expect(await screen.findByRole('region', { name: 'Still working' })).toBeInTheDocument();
  });

  it('tells an operator an approver can abandon it, with no panel of its own', async () => {
    resetMock('operator');
    restartedIn('investigating', 20);
    renderCase();
    const notice = await screen.findByTestId('case-restart');
    expect(notice).toHaveTextContent(/an approver can abandon it: nothing more is sent/);
    expect(screen.queryByRole('region', { name: 'Still working' })).not.toBeInTheDocument();
  });

  it('asks for the decision as before on a case waiting for approval, however long ago', async () => {
    restartedIn('awaiting_approval', 90);
    renderCase();
    const notice = await screen.findByTestId('case-restart');
    expect(notice).toHaveTextContent(
      /while this case was waiting for approval, and nothing has moved since\. A clean stop keeps the approval task: decide on the plan as before\.$/,
    );
    expect(notice).not.toHaveTextContent(/abandon/);
  });

  it('is gone once the case moved on after the restart, and absent on a case never restarted', async () => {
    const moved: CaseEvent = {
      seq: recorded.events.length + 2,
      at: new Date().toISOString(),
      kind: 'state',
      fromState: 'investigating',
      toState: 'proposed',
      text: 'The board proposed a plan',
      actor: 'system',
      ref: '',
    };
    restartedIn('proposed', 5, [moved]);
    const { unmount } = renderCase();
    const timeline = await auditTrail();
    // The note stays in the audit trail as the record of the restart
    expect(within(timeline).getByText('Production started')).toBeInTheDocument();
    expect(screen.queryByTestId('case-restart')).not.toBeInTheDocument();
    unmount();

    server.resetHandlers();
    const detail = {
      ...recorded.detail,
      state: 'investigating',
      disposition: '',
      closedAt: '',
    } as CaseDetail;
    server.use(
      http.get(`/api/shutter/cases/${ID}`, () => HttpResponse.json(detail)),
      http.get(`/api/shutter/cases/${ID}/events`, () => HttpResponse.json(recorded.events)),
    );
    renderCase();
    await auditTrail();
    expect(screen.queryByTestId('case-restart')).not.toBeInTheDocument();
  });
});
