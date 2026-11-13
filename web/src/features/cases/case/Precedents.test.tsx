import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import type { Precedent, PrecedentSummary } from '@/api/types';
import fixtures from '@/mocks/fixtures.json';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { useAppearance } from '@/stores/appearance';
import { theme } from '@/theme';
import CasePage from '../CasePage';

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => {
  server.resetHandlers();
  server.events.removeAllListeners();
});
afterAll(() => server.close());

function renderCase(caseId: string) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter([{ path: '/cases/:caseId', element: <CasePage /> }], {
    initialEntries: [`/cases/${caseId}`],
  });
  render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
  return router;
}

const HELD = 'C-000002';
const recorded = fixtures.cases[HELD];

/**
 * Precedents as a v1.35 server would give them for S2's conditions at Downstream Out: an approval and a rejection that
 * count, and an approval retired.
 */
function rows(): Precedent[] {
  return [
    {
      id: 12,
      caseId: 'C-000301',
      receiver: 'Downstream Out',
      approver: 'approver',
      decision: 'approved',
      policyVersion: '2026-11-01.1',
      siteProfileVersion: 4,
      createdAt: '2026-11-02T10:02:11Z',
      active: true,
    },
    {
      id: 11,
      caseId: 'C-000287',
      receiver: 'Downstream Out',
      approver: 'mx',
      decision: 'rejected',
      policyVersion: '2026-10-25.2',
      siteProfileVersion: 3,
      createdAt: '2026-11-01T16:40:00Z',
      active: true,
    },
    {
      id: 9,
      caseId: 'C-000250',
      receiver: 'Downstream Out',
      approver: 'approver',
      decision: 'approved',
      policyVersion: '2026-10-25.2',
      createdAt: '2026-10-30T09:00:00Z',
      active: false,
      retiredAt: '2026-11-01T08:00:00Z',
      retiredBy: 'mx',
      retiredReason: "the receiver's contract changed",
    },
  ];
}

const summaryOf = (list: Precedent[], samePolicy = false): PrecedentSummary => {
  const active = list.filter((p) => p.active);
  return {
    approved: active.filter((p) => p.decision === 'approved').length,
    rejected: active.filter((p) => p.decision === 'rejected').length,
    lastDecision: active[0]?.decision ?? '',
    lastApprover: active[0]?.approver ?? '',
    lastAt: active[0]?.createdAt ?? '',
    lastCaseId: active[0]?.caseId ?? '',
    samePolicy,
    windowDays: 180,
    signature: 'sha256:5e1c',
  };
};

/**
 * The held S2 case with precedents: its snapshot's summary carries them as collected, and the precedents route lists
 * them as they stand, retiring one as the server does. Returns what the retire route was sent.
 */
function withPrecedents(answer?: () => Response) {
  const list = rows();
  const sent: { id: string; body: unknown; csrf: string | null }[] = [];
  server.use(
    http.get(`/api/shutter/cases/${HELD}/snapshot`, () =>
      HttpResponse.json({
        ...recorded.snapshot,
        summary: { ...recorded.snapshot.summary, precedents: summaryOf(rows()) },
      }),
    ),
    http.get(`/api/shutter/cases/${HELD}/precedents`, () =>
      HttpResponse.json({
        receiver: 'Downstream Out',
        conditions: recorded.snapshot.summary.catalogue.conditions,
        summary: summaryOf(list),
        precedents: list,
      }),
    ),
    http.post('/api/shutter/precedents/:id/retire', async ({ request, params }) => {
      const body = (await request.json()) as { reason: string };
      sent.push({ id: String(params.id), body, csrf: request.headers.get('X-Requested-With') });
      if (answer) return answer();
      const p = list.find((x) => String(x.id) === params.id)!;
      Object.assign(p, {
        active: false,
        retiredAt: '2026-11-02T11:30:00Z',
        retiredBy: 'approver',
        retiredReason: body.reason,
      });
      return HttpResponse.json(p);
    }),
  );
  return sent;
}

/** An element's words as they read, without a term's definition kept hidden for its description. */
const visibleText = (el: HTMLElement) => {
  const copy = el.cloneNode(true) as HTMLElement;
  copy.querySelectorAll('[hidden]').forEach((h) => h.remove());
  return copy.textContent ?? '';
};

/** The precedents' line in a part of the page, as it reads. */
const line = (part: HTMLElement = document.body) => visibleText(within(part).getByTestId('precedents-line'));
const nextAction = () => screen.findByTestId('next-action-precedents');

async function openAuditTrail() {
  await userEvent.click(await screen.findByRole('tab', { name: 'Audit trail' }));
  return screen.findByRole('region', { name: 'Precedents' });
}

describe('precedents on the case page', () => {
  beforeEach(() => {
    resetMock('approver');
    useAppearance.setState({ detail: 'plain' });
    vi.useFakeTimers({ now: new Date('2026-11-02T12:00:00Z'), toFake: ['Date'] });
  });
  afterEach(() => vi.useRealTimers());

  it('say under the approval that no approver has seen these conditions here, defining the word', async () => {
    renderCase(HELD);
    const precedents = await nextAction();
    expect(line(precedents)).toContain(
      'Precedents: no approver has seen these conditions at this receiver in the last 180 days.',
    );
    const word = within(precedents).getByText('Precedents');
    expect(word).toHaveClass('term');
    expect(word).toHaveAccessibleDescription(/^What an approver decided before on the same evidence/);
    // Nothing to see, and nothing to press but the existing way to the decision
    expect(within(precedents).queryByRole('button')).not.toBeInTheDocument();
  });

  it('are in the Audit trail of every case, with the record a click away', async () => {
    renderCase('C-000008');
    const section = await openAuditTrail();
    expect(within(section).getByRole('heading', { level: 2, name: 'Precedents' })).toBeInTheDocument();
    expect(line(section)).toContain(
      'No approver has seen these conditions at this receiver in the last 180 days.',
    );
    expect(section).toHaveTextContent('It informs a decision and never releases anything.');
    // The word is defined here, the page's first use, since the case waits for nothing
    expect(within(section).getByText('Precedents', { selector: '.term' })).toBeInTheDocument();
    const record = within(section).getByRole('button', { name: 'See the record' });
    expect(record).toHaveAttribute('aria-expanded', 'false');
    await userEvent.click(record);
    const empty = await within(section).findByText(
      'No precedent is recorded for these conditions at this receiver.',
    );
    await waitFor(() => expect(empty).toBeVisible());
    expect(within(section).getByText('GET /api/shutter/cases/C-000008/precedents')).toBeInTheDocument();
  });

  it('name the recorded approval before a later case of the same conditions, and list it in the record', async () => {
    renderCase('C-000009');
    const section = await openAuditTrail();
    expect(line(section)).toContain(
      'Approved and verified 1 time, rejected 0 times here in the last 180 days; last approved by approver on 2 Nov (case C-000002).',
    );
    expect(within(section).getByRole('link', { name: 'C-000002' })).toHaveAttribute(
      'href',
      '/cases/C-000002',
    );
    await userEvent.click(within(section).getByRole('button', { name: 'See them' }));
    const table = await within(section).findByRole('table');
    const [, only, ...more] = within(table).getAllByRole('row');
    expect(more).toHaveLength(0);
    expect(only).toHaveTextContent('Approved, verified');
    expect(within(only).getByRole('link', { name: 'C-000002' })).toHaveAttribute('href', '/cases/C-000002');
    expect(only).toHaveTextContent('2026-11-01.1');
  });

  it('count the approvals and rejections, name the last decision and its case, and say when the policy was earlier', async () => {
    withPrecedents();
    renderCase(HELD);
    const precedents = await nextAction();
    await waitFor(() =>
      expect(line(precedents)).toContain(
        'Precedents: approved and verified 1 time, rejected 1 time here in the last 180 days; last approved by approver on 2 Nov (case C-000301), under an earlier policy.',
      ),
    );
    expect(within(precedents).getByRole('link', { name: 'C-000301' })).toHaveAttribute(
      'href',
      '/cases/C-000301',
    );
  });

  it('open their list in the Audit trail from "See them": date, decision, approver, case, policy and whether it counts', async () => {
    withPrecedents();
    renderCase(HELD);
    const precedents = await nextAction();
    await userEvent.click(
      await within(precedents).findByRole('button', { name: 'See them in the audit trail' }),
    );
    expect(screen.getByRole('tab', { name: 'Audit trail' })).toHaveAttribute('aria-selected', 'true');
    const section = await screen.findByRole('region', { name: 'Precedents' });
    // Focus follows the reader there, to the section's heading
    await waitFor(() => expect(within(section).getByRole('heading', { name: 'Precedents' })).toHaveFocus());
    // The word was defined above, under the approval: not twice
    expect(within(section).queryByText('Precedents', { selector: '.term' })).not.toBeInTheDocument();
    expect(within(section).getByRole('button', { name: 'See them' })).toHaveAttribute(
      'aria-expanded',
      'true',
    );
    const table = await within(section).findByRole('table');
    expect(
      within(table)
        .getAllByRole('columnheader')
        .map((h) => h.textContent),
    ).toEqual(['Date', 'Decision', 'Approver', 'Case', 'Policy version', 'Active', 'Retire']);
    const [, first, second, retired] = within(table).getAllByRole('row');
    expect(first).toHaveTextContent('Approved, verified');
    expect(first).toHaveTextContent('approver');
    expect(within(first).getByRole('link', { name: 'C-000301' })).toHaveAttribute('href', '/cases/C-000301');
    expect(first).toHaveTextContent('2026-11-01.1');
    expect(first).toHaveTextContent('site profile version 4');
    expect(first).toHaveTextContent('Active');
    expect(second).toHaveTextContent('Rejected');
    // A retired one is struck through and says who retired it, when and why, and cannot be retired again
    expect(retired).toHaveAttribute('data-retired', 'true');
    expect(retired).toHaveTextContent("Retired by mx on 1 Nov: the receiver's contract changed");
    expect(within(retired).getAllByRole('cell')[2]).toHaveStyle({ textDecoration: 'line-through' });
    expect(within(retired).queryByRole('button')).not.toBeInTheDocument();
    expect(within(table).getAllByRole('button', { name: /^Retire the precedent from / })).toHaveLength(2);
  });

  it('are retired by an approver only', async () => {
    resetMock('operator');
    renderCase('C-000008');
    const section = await openAuditTrail();
    expect(line(section)).toContain('No approver has seen');
    // The trial's store has none: the list is a stand-in for a server that has them
    server.use(
      http.get('/api/shutter/cases/C-000008/precedents', () =>
        HttpResponse.json({
          receiver: 'Downstream Out',
          conditions: null,
          summary: summaryOf(rows()),
          precedents: rows(),
        }),
      ),
    );
    await userEvent.click(within(section).getByRole('button', { name: 'See the record' }));
    const table = await within(section).findByRole('table');
    expect(within(table).getAllByRole('row')).toHaveLength(4);
    expect(within(table).queryByRole('button')).not.toBeInTheDocument();
    expect(within(table).queryByRole('columnheader', { name: 'Retire' })).not.toBeInTheDocument();
  });

  it('retire with a reason, which the line and the list then count for nothing', async () => {
    const sent = withPrecedents();
    renderCase(HELD);
    const precedents = await nextAction();
    await userEvent.click(
      await within(precedents).findByRole('button', { name: 'See them in the audit trail' }),
    );
    const section = await screen.findByRole('region', { name: 'Precedents' });
    await userEvent.click(
      await within(section).findByRole('button', { name: 'Retire the precedent from C-000301, 2 Nov' }),
    );
    const dialog = await screen.findByRole('dialog', { name: 'Retire a precedent' });
    expect(within(dialog).getByText('Live system')).toBeInTheDocument();
    expect(dialog).toHaveTextContent('Approved, verified by approver on 2 Nov, case C-000301.');
    const submit = within(dialog).getByRole('button', { name: 'Retire it' });
    expect(submit).toBeDisabled();
    await userEvent.type(within(dialog).getByRole('textbox', { name: /Why retire it/ }), 'a test approval');
    expect(submit).toBeEnabled();
    await userEvent.click(submit);
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
    expect(sent).toEqual([{ id: '12', body: { reason: 'a test approval' }, csrf: 'Shutter' }]);
    const table = within(section).getByRole('table');
    await waitFor(() =>
      expect(within(table).getAllByRole('row')[1]).toHaveTextContent(
        'Retired by approver on 2 Nov: a test approval',
      ),
    );
    // The line reads the count as it stands now, in both places
    await waitFor(() =>
      expect(line(section)).toContain(
        'Approved and verified 0 times, rejected 1 time here in the last 180 days; last rejected by mx on 1 Nov (case C-000287), under an earlier policy.',
      ),
    );
    expect(line(await nextAction())).toContain('Precedents: approved and verified 0 times, rejected 1 time');
  });

  it('say who retired one already, and when, and read the list again', async () => {
    let reads = 0;
    const sent = withPrecedents(() =>
      HttpResponse.json(
        { error: 'already_retired', detail: 'Precedent 12 was retired on 2026-11-02T10:00:00Z by mx' },
        { status: 409 },
      ),
    );
    server.events.on('request:start', ({ request }) => {
      if (request.method === 'GET' && request.url.endsWith(`/cases/${HELD}/precedents`)) reads++;
    });
    renderCase(HELD);
    await userEvent.click(
      await within(await nextAction()).findByRole('button', { name: 'See them in the audit trail' }),
    );
    const section = await screen.findByRole('region', { name: 'Precedents' });
    await userEvent.click(
      await within(section).findByRole('button', { name: 'Retire the precedent from C-000301, 2 Nov' }),
    );
    const dialog = await screen.findByRole('dialog', { name: 'Retire a precedent' });
    await userEvent.type(within(dialog).getByRole('textbox', { name: /Why retire it/ }), 'stale');
    const before = reads;
    await userEvent.click(within(dialog).getByRole('button', { name: 'Retire it' }));
    expect(await within(dialog).findByRole('alert')).toHaveTextContent(
      'Already retired by mx on 2 Nov, 10:00:00 GMT.',
    );
    expect(within(dialog).getByRole('button', { name: 'Retire it' })).toBeDisabled();
    expect(within(dialog).getByRole('button', { name: 'Done' })).toBeInTheDocument();
    expect(sent).toHaveLength(1);
    await waitFor(() => expect(reads).toBeGreaterThan(before));
  });

  it('never offer to approve, nor say what to do', async () => {
    withPrecedents();
    renderCase(HELD);
    const precedents = await nextAction();
    await userEvent.click(
      await within(precedents).findByRole('button', { name: 'See them in the audit trail' }),
    );
    const section = await screen.findByRole('region', { name: 'Precedents' });
    await within(section).findByRole('table');
    for (const part of [precedents, section]) {
      expect(within(part).queryByRole('button', { name: /approve/i })).not.toBeInTheDocument();
      expect(part.textContent).not.toMatch(/recommend|should approve|safe to approve/i);
    }
  });

  it('say nothing when the snapshot was collected before precedents were', async () => {
    // A snapshot from a server before v1.35: no precedents in its summary
    const { precedents: _none, ...before } = recorded.snapshot.summary;
    server.use(
      http.get(`/api/shutter/cases/${HELD}/snapshot`, () =>
        HttpResponse.json({ ...recorded.snapshot, summary: before }),
      ),
    );
    renderCase(HELD);
    await screen.findByRole('heading', { name: 'What needs you now' });
    await screen.findByText('Review the resend');
    expect(screen.queryByTestId('next-action-precedents')).not.toBeInTheDocument();
    await userEvent.click(await screen.findByRole('tab', { name: 'Audit trail' }));
    await screen.findByRole('region', { name: 'Timeline' });
    expect(screen.queryByRole('region', { name: 'Precedents' })).not.toBeInTheDocument();
  });
});
