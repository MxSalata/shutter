import { MantineProvider } from '@mantine/core';
import { Notifications, notifications } from '@mantine/notifications';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { MemoryRouter } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { theme } from '@/theme';
import { OFFERED_LABEL, OutageSection } from './OutageSection';
import type { Outage, OutageList, OutageRow, Resend } from './types';

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
beforeEach(() => {
  resetMock('approver');
  notifications.clean();
  server.events.removeAllListeners();
});

const NOW = new Date().toISOString();

/** An outage in the routes' shape (CONTRACTS 17), every field present, with the given changes. */
function outage(changes: Partial<Outage> = {}): Outage {
  return {
    id: '7',
    receiver: 'Results Out',
    namespace: 'LABSITE',
    item: 'Results Out',
    state: 'open',
    kind: 'down',
    openedAt: NOW,
    closedAt: null,
    pausedUntil: null,
    readings: null,
    alerts: [],
    lists: { queued: [], offered: [], reached: [], refused: [] },
    openCases: [],
    version: 3,
    set: {
      status: 'not_computed',
      reason: 'the queue holds 2 messages: nothing is listed while anything is being tried',
    },
    approvable: false,
    acts: ['pause', 'read_again', 'close'],
    outcome: null,
    words: {
      first: 'The listener has been unreachable since 03:12.',
      do: 'Do: start the listener.',
      call: 'Call: the lab on 01632 960998.',
      critical: null,
    },
    ...changes,
  };
}

function row(id: string, control: string, reason: string, more: Partial<OutageRow> = {}): OutageRow {
  return {
    headerId: id,
    controlId: control,
    timeCreated: '2026-11-09 03:12:00',
    status: 'Error',
    attempts: 'never_opened',
    reason,
    patient: { id: '9990000301', authority: 'NHS' },
    sibling: null,
    acts: [],
    closure: null,
    closedBy: null,
    closedAt: null,
    ...more,
  };
}

/** A ledger row in the routes' shape (CONTRACTS 17.8). */
function resend(
  position: number,
  control: string,
  state: string,
  closure: string | null,
  words = '',
): Resend {
  return {
    runId: 'R7-4',
    position,
    headerId: String(40 + position),
    controlId: control,
    newHeaderId: closure ? String(900 + position) : null,
    state,
    closure,
    words,
    by: 'approver',
    at: NOW,
    caseId: position === 1 ? 'C-000031' : null,
  };
}

/** An offered set of two at a receiver whose duplicates are unknown: the rows list Already handled by hand. */
function offeredAtUnknown(changes: Partial<Outage> = {}): Outage {
  const byHand = { acts: ['handled_by_hand'] };
  return outage({
    state: 'offered',
    approvable: true,
    set: { status: 'computed', reason: null, digest: 'sha256:set1' },
    acts: ['pause', 'read_again', 'close', 'handled_by_hand'],
    lists: {
      offered: [
        row('41', 'CA', 'Shutter tried at 03:20; the connection never opened', byHand),
        row('44', 'CF', '', byHand),
      ],
      queued: [],
      reached: [],
      refused: [],
      closed: [],
    },
    ...changes,
  });
}

/** Every changing request the section sends: its path, body and the two headers the contract asks for. */
function recordPosts() {
  const posts: { path: string; body: Record<string, unknown>; csrf: string | null; key: string | null }[] =
    [];
  server.events.on('request:start', async ({ request }) => {
    if (request.method === 'POST')
      posts.push({
        path: new URL(request.url).pathname,
        body: (await request.clone().json()) as Record<string, unknown>,
        csrf: request.headers.get('X-Requested-With'),
        key: request.headers.get('Idempotency-Key'),
      });
  });
  return posts;
}

function serve(list: OutageList | null, status = 200) {
  server.use(
    http.get('/api/shutter/outages', () =>
      list
        ? HttpResponse.json(list, { status })
        : HttpResponse.json({ error: 'not_in_trial', detail: 'x' }, { status: 501 }),
    ),
  );
}

function renderSection() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <MantineProvider theme={theme}>
      <Notifications />
      <QueryClientProvider client={client}>
        <MemoryRouter>
          <OutageSection />
        </MemoryRouter>
      </QueryClientProvider>
    </MantineProvider>,
  );
}

describe('OutageSection', () => {
  it('shows nothing when the server has no outage routes, as the trial answers', async () => {
    serve(null);
    const { container } = renderSection();
    await new Promise((r) => setTimeout(r, 50));
    expect(container.querySelector('[data-testid="outages"]')).toBeNull();
  });

  it("says why there is no list, in the set's own words, and lists only the row's acts", async () => {
    serve({ items: [outage()], receivers: [] });
    renderSection();
    const card = await screen.findByRole('region', { name: 'Outage 7, Results Out' });
    expect(within(card).getByText('The listener has been unreachable since 03:12.')).toBeInTheDocument();
    expect(within(card).getByText('Call: the lab on 01632 960998.')).toBeInTheDocument();
    expect(within(card).getByTestId('outage-no-lists')).toHaveTextContent(
      'No list of messages: the queue holds 2 messages: nothing is listed while anything is being tried.',
    );
    const acts = await within(card).findByTestId('outage-acts');
    expect(within(acts).getByRole('button', { name: 'Read again' })).toBeInTheDocument();
    expect(within(acts).getByRole('button', { name: 'Pause' })).toBeDisabled();
    expect(within(acts).getByRole('button', { name: 'Close' })).toBeDisabled();
  });

  it('shows no Read again when the row does not list it', async () => {
    serve({ items: [outage({ acts: ['pause', 'close'] })], receivers: [] });
    renderSection();
    const card = await screen.findByRole('region', { name: 'Outage 7, Results Out' });
    expect(within(card).queryByRole('button', { name: 'Read again' })).toBeNull();
  });

  it('lists an offered set under its label, with each reason, and never an approval control while approvable is false', async () => {
    serve({
      items: [
        outage({
          state: 'offered',
          set: { status: 'computed', reason: null, digest: 'abc' },
          lists: {
            offered: [
              row('41', 'CA', ''),
              row('44', 'CF', 'Shutter tried at 03:20; the connection never opened'),
            ],
            queued: [],
            reached: [row('42', 'CB', 'the receiver took it on an attempt')],
            refused: [row('43', 'CC', 'Suspended: set aside, not a delivery that failed')],
          },
        }),
      ],
      receivers: [],
    });
    renderSection();
    const lists = await screen.findByTestId('outage-lists');
    expect(lists).toHaveTextContent(`${OFFERED_LABEL} (2)`);
    expect(lists).toHaveTextContent(
      'Control id CF (header 44, Error): Shutter tried at 03:20; the connection never opened',
    );
    expect(lists).toHaveTextContent('Reached the receiver: check its screen (1)');
    expect(lists).toHaveTextContent('Not listed, with the reason (1)');
    expect(screen.queryByRole('button', { name: /approve/i })).toBeNull();
  });

  it('keeps a closed row with open cases, never green, listing them with their owners', async () => {
    serve({
      items: [
        outage({
          state: 'closed',
          acts: [],
          outcome: 'Transport outage closed. 1 delivery exception still needs review.',
          openCases: [{ caseId: 'C-000012', reason: 'Suspended AE', owner: 'the lab' }],
        }),
        outage({ id: '8', state: 'closed', acts: [], outcome: 'Delivery backlog drained.' }),
      ],
      receivers: [],
    });
    renderSection();
    const card = await screen.findByRole('region', { name: 'Outage 7, Results Out' });
    expect(within(card).getByTestId('outage-open-cases')).toHaveTextContent(
      'C-000012: Suspended AE (owner: the lab)',
    );
    expect(within(card).getByText('closed')).toBeInTheDocument();
    expect(screen.queryByRole('region', { name: 'Outage 8, Results Out' })).toBeNull();
    expect(within(card).queryByTestId('outage-acts')).toBeNull();
  });

  it("says a watcher's reading is stale when it has not answered for a minute", async () => {
    const old = new Date(Date.now() - 5 * 60_000).toISOString();
    serve({
      items: [],
      receivers: [
        {
          receiver: 'Results Out',
          namespace: 'LABSITE',
          item: 'Results Out',
          reading: 'healthy',
          checkedAt: NOW,
        },
        { receiver: 'LIMS Out', namespace: 'LABSITE', item: 'LIMS Out', reading: 'healthy', checkedAt: old },
      ],
    });
    renderSection();
    const readings = await screen.findByTestId('readings');
    const lines = readings.querySelectorAll('[data-stale]');
    expect(lines[0]?.getAttribute('data-stale')).toBe('false');
    expect(lines[1]?.getAttribute('data-stale')).toBe('true');
    expect(lines[1]).toHaveTextContent('what is shown may be out of date');
  });

  it('shows an operator no acts', async () => {
    resetMock('operator');
    serve({ items: [outage()], receivers: [] });
    renderSection();
    const card = await screen.findByRole('region', { name: 'Outage 7, Results Out' });
    expect(within(card).queryByTestId('outage-acts')).toBeNull();
  });
  it('offers an approver the approval at a receiver whose duplicates are unknown, asking for the receiver check first', async () => {
    const posts = recordPosts();
    serve({ items: [offeredAtUnknown()], receivers: [] });
    server.use(
      http.post('/api/shutter/outages/7/approvals', () =>
        HttpResponse.json(offeredAtUnknown({ state: 'sending' })),
      ),
    );
    renderSection();
    const card = await screen.findByRole('region', { name: 'Outage 7, Results Out' });
    await userEvent.click(await within(card).findByRole('button', { name: 'Approve the resend…' }));
    const dialog = await screen.findByRole('dialog', { name: 'Approve the resend' });
    expect(within(dialog).getByText('Live system')).toBeInTheDocument();
    expect(within(dialog).getByTestId('confirm-consequence')).toHaveTextContent(
      'This has the engine send these 2 messages to Results Out again, one at a time, in this order: each is the stored message, unchanged.',
    );
    const order = within(dialog).getByRole('list', { name: 'The messages to send, in order' });
    expect(
      within(order)
        .getAllByRole('listitem')
        .map((li) => li.textContent),
    ).toEqual(['Control id CA (header 41)', 'Control id CF (header 44)']);
    const approve = within(dialog).getByRole('button', { name: 'Approve and resend' });
    expect(approve).toBeDisabled();
    await userEvent.type(
      within(dialog).getByRole('textbox', { name: /What was checked, and with whom/ }),
      'Checked both in the lab system with the duty biomedical scientist',
    );
    // The note alone is not enough here: the approver says the receiver was checked
    expect(approve).toBeDisabled();
    const check = within(dialog).getByRole('checkbox', {
      name: 'I checked the receiver for each of these messages',
    });
    expect(check).toHaveAccessibleDescription(/could be filed twice/);
    await userEvent.click(check);
    expect(approve).toBeEnabled();
    await userEvent.click(approve);
    expect(await screen.findByText('Approved: 2 messages to send')).toBeInTheDocument();
    expect(posts).toEqual([
      {
        path: '/api/shutter/outages/7/approvals',
        body: {
          digest: 'sha256:set1',
          note: 'Checked both in the lab system with the duty biomedical scientist',
          version: 3,
          receiverChecked: true,
        },
        csrf: 'Shutter',
        key: expect.any(String),
      },
    ]);
  });

  it('asks for no receiver check where the receiver refuses duplicates, and offers no hand closure there', async () => {
    const posts = recordPosts();
    const refuses = offeredAtUnknown({
      acts: ['pause', 'read_again', 'close'],
      lists: { offered: [row('41', 'CA', '')], queued: [], reached: [], refused: [], closed: [] },
    });
    serve({ items: [refuses], receivers: [] });
    server.use(
      http.post('/api/shutter/outages/7/approvals', () =>
        HttpResponse.json({ ...refuses, state: 'sending' }),
      ),
    );
    renderSection();
    const card = await screen.findByRole('region', { name: 'Outage 7, Results Out' });
    expect(within(card).queryByRole('button', { name: /Already handled by hand/ })).toBeNull();
    await userEvent.click(await within(card).findByRole('button', { name: 'Approve the resend…' }));
    const dialog = await screen.findByRole('dialog', { name: 'Approve the resend' });
    expect(within(dialog).queryByRole('checkbox')).toBeNull();
    await userEvent.type(within(dialog).getByRole('textbox', { name: /What was checked/ }), 'Lab agreed');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Approve and resend' }));
    await waitFor(() => expect(posts).toHaveLength(1));
    expect(posts[0].body).toEqual({ digest: 'sha256:set1', note: 'Lab agreed', version: 3 });
  });

  it('says a refused approval in plain words in the dialog, and that nothing was sent', async () => {
    serve({ items: [offeredAtUnknown()], receivers: [] });
    server.use(
      http.post('/api/shutter/outages/7/approvals', () =>
        HttpResponse.json(
          {
            error: 'set_changed',
            detail: 'The set has changed since it was read: read it again and approve what it lists now',
            currentDigest: 'sha256:set2',
          },
          { status: 409 },
        ),
      ),
    );
    renderSection();
    const card = await screen.findByRole('region', { name: 'Outage 7, Results Out' });
    await userEvent.click(await within(card).findByRole('button', { name: 'Approve the resend…' }));
    const dialog = await screen.findByRole('dialog', { name: 'Approve the resend' });
    await userEvent.type(within(dialog).getByRole('textbox', { name: /What was checked/ }), 'Checked');
    await userEvent.click(within(dialog).getByRole('checkbox'));
    await userEvent.click(within(dialog).getByRole('button', { name: 'Approve and resend' }));
    expect(await within(dialog).findByRole('alert')).toHaveTextContent(
      'Nothing was sent: the list changed since you read it. Read the new list and approve what it lists now.',
    );
  });

  it.each([
    [
      'stopped',
      { mode: 'enabled', stopped: true, stoppedBy: 'appr2', stoppedAt: '2026-11-09T19:40:00Z' },
      "Shutter recovery is stopped, so this resend can't be approved",
    ],
    ['in shadow mode', { mode: 'shadow', stopped: false }, 'Shadow mode: recovery is off at this site'],
  ])(
    'holds the approval while Shutter recovery is %s, saying why, and still offers the hand closure',
    async (_, control, words) => {
      const posts = recordPosts();
      serve({ items: [offeredAtUnknown()], receivers: [] });
      server.use(
        http.get('/api/shutter/recovery-control', () =>
          HttpResponse.json({
            generation: 2,
            stoppedAt: '',
            stoppedBy: '',
            stopReason: '',
            outstanding: [],
            outstandingCount: 0,
            readable: true,
            covers: '',
            doesNotCover: '',
            ...control,
          }),
        ),
      );
      renderSection();
      const card = await screen.findByRole('region', { name: 'Outage 7, Results Out' });
      expect(await within(card).findByTestId('outage-approval-held')).toHaveTextContent(words);
      expect(within(card).queryByRole('button', { name: 'Approve the resend…' })).toBeNull();
      expect(within(card).getAllByRole('button', { name: /Already handled by hand/ })).toHaveLength(2);
      expect(posts).toHaveLength(0);
    },
  );

  it('says a refusal by the recovery control in its own words, and that nothing was sent', async () => {
    serve({ items: [offeredAtUnknown()], receivers: [] });
    server.use(
      http.post('/api/shutter/outages/7/approvals', () =>
        HttpResponse.json(
          {
            error: 'recovery_stopped',
            detail:
              "Shutter recovery is stopped, so this resend can't be approved, and nothing was recorded. The messages stay offered: approve them once an approver has cleared the stop in Settings.",
          },
          { status: 409 },
        ),
      ),
    );
    renderSection();
    const card = await screen.findByRole('region', { name: 'Outage 7, Results Out' });
    await userEvent.click(await within(card).findByRole('button', { name: 'Approve the resend…' }));
    const dialog = await screen.findByRole('dialog', { name: 'Approve the resend' });
    await userEvent.type(within(dialog).getByRole('textbox', { name: /What was checked/ }), 'Checked');
    await userEvent.click(within(dialog).getByRole('checkbox'));
    await userEvent.click(within(dialog).getByRole('button', { name: 'Approve and resend' }));
    expect(await within(dialog).findByRole('alert')).toHaveTextContent(
      "Nothing was sent. Shutter recovery is stopped, so this resend can't be approved, and nothing was recorded.",
    );
  });

  it('shows a run the recovery stop halted: the card says so first, and each message not sent says why', async () => {
    const halted = (n: number, c: string) => ({
      ...resend(
        n,
        c,
        'stopped',
        null,
        'not sent: Shutter recovery was stopped by appr2 at 2026-11-09T19:40:00Z, so the run halted before this message',
      ),
      halt: 'recovery_stopped',
    });
    serve({
      items: [
        outage({
          state: 'needs_person',
          words: {
            first:
              'The resend halted because Shutter recovery was stopped: 1 of 3 messages were sent and 2 not sent. The rest go only by a new approval once an approver has cleared the stop in Settings: read the set again, then approve it.',
            do: 'Do: start the listener.',
            call: 'Call: the lab on 01632 960998.',
            critical: null,
          },
          resends: [
            resend(1, 'CA', 'completed', 'sent', 'Resent by Shutter'),
            halted(2, 'CB'),
            halted(3, 'CC'),
          ],
        }),
      ],
      receivers: [],
    });
    renderSection();
    const card = await screen.findByRole('region', { name: 'Outage 7, Results Out' });
    expect(
      await within(card).findByText(/^The resend halted because Shutter recovery was stopped/),
    ).toBeInTheDocument();
    expect(within(card).queryByTestId('outage-failed-resend')).toBeNull();
    const items = within(within(card).getByTestId('outage-resends')).getAllByRole('listitem');
    expect(items[1]).toHaveTextContent('Not sent');
    expect(items[1]).toHaveTextContent(
      'Not sent: Shutter recovery was stopped by appr2 at 2026-11-09T19:40:00Z, so the run halted before this message.',
    );
    expect(within(card).getByText("Shutter's resends: 1 sent, 2 not sent.")).toBeInTheDocument();
  });

  it('closes one offered message as already handled by hand after a confirmation with a note, sending nothing', async () => {
    const posts = recordPosts();
    serve({ items: [offeredAtUnknown()], receivers: [] });
    server.use(
      http.post('/api/shutter/outages/7/acts', () => HttpResponse.json(offeredAtUnknown({ version: 4 }))),
    );
    renderSection();
    const card = await screen.findByRole('region', { name: 'Outage 7, Results Out' });
    await userEvent.click(
      await within(card).findByRole('button', { name: 'Already handled by hand: control id CF' }),
    );
    const dialog = await screen.findByRole('dialog', { name: 'Already handled by hand' });
    expect(within(dialog).getByTestId('confirm-consequence')).toHaveTextContent(
      'Shutter will send nothing for control id CF (header 44), take it off the list and close its cases as handled by hand.',
    );
    const confirm = within(dialog).getByRole('button', { name: 'Close it, send nothing' });
    expect(confirm).toBeDisabled();
    await userEvent.type(
      within(dialog).getByRole('textbox', { name: /What you checked at the receiver/ }),
      'Entered by hand at 03:40 by the lab, seen on its screen',
    );
    await userEvent.click(confirm);
    expect(await screen.findByText('Control id CF: handled by hand')).toBeInTheDocument();
    expect(posts).toEqual([
      {
        path: '/api/shutter/outages/7/acts',
        body: {
          act: 'handled_by_hand',
          headerId: '44',
          note: 'Entered by hand at 03:40 by the lab, seen on its screen',
          version: 3,
        },
        csrf: 'Shutter',
        key: expect.any(String),
      },
    ]);
    // No approval went with it
    expect(posts.some((p) => p.path.endsWith('/approvals'))).toBe(false);
  });

  it('shows an operator neither the approval nor the hand closure', async () => {
    resetMock('operator');
    serve({ items: [offeredAtUnknown()], receivers: [] });
    renderSection();
    const card = await screen.findByRole('region', { name: 'Outage 7, Results Out' });
    await within(card).findByTestId('outage-lists');
    expect(within(card).queryByRole('button', { name: /Approve/ })).toBeNull();
    expect(within(card).queryByRole('button', { name: /Already handled by hand/ })).toBeNull();
  });

  it("shows a run's progress while it sends, each message with how it stands, and no approval", async () => {
    serve({
      items: [
        offeredAtUnknown({
          state: 'sending',
          acts: ['pause', 'close'],
          approval: {
            id: 'R7-4',
            by: 'approver',
            givenAt: NOW,
            digest: 'sha256:set1',
            note: 'Checked with the lab',
          },
          resends: [
            resend(
              1,
              'CA',
              'completed',
              'sent',
              'Resent by Shutter at 03:41 under approval R7-4 by approver; new header 901 Completed.',
            ),
            resend(2, 'CF', 'sending', null),
            resend(3, 'CG', 'approved', null),
          ],
        }),
      ],
      receivers: [],
    });
    renderSection();
    const card = await screen.findByRole('region', { name: 'Outage 7, Results Out' });
    expect(await within(card).findByRole('status')).toHaveTextContent(
      'Sending 2 of 3, one at a time, in order.',
    );
    expect(within(card).getByRole('status')).toHaveTextContent('Approved by approver for 3 messages');
    expect(within(card).queryByRole('button', { name: /Approve/ })).toBeNull();
    const list = within(card).getByRole('list', { name: /Each message sent, in order/ });
    const items = within(list).getAllByRole('listitem');
    expect(items[0]).toHaveTextContent('Control id CA (header 41, sent as header 901)Sent');
    expect(within(items[0]).getByRole('link', { name: 'C-000031' })).toHaveAttribute(
      'href',
      '/cases/C-000031',
    );
    expect(items[1]).toHaveTextContent('Sending now');
    expect(items[2]).toHaveTextContent('Waiting to send');
  });

  it('shows a failed resend as failed, first on the card, with the rest not sent', async () => {
    serve({
      items: [
        outage({
          state: 'needs_person',
          set: { status: 'not_computed', reason: 'a resend failed: a person reads the trace' },
          resends: [
            resend(1, 'CA', 'completed', 'sent'),
            resend(
              2,
              'CF',
              'failed',
              'failed',
              'new header 902 ended Suspended (the receiver answered AE: Refused by the application)',
            ),
            resend(3, 'CG', 'stopped', null, 'not sent: the run stopped'),
          ],
        }),
      ],
      receivers: [],
    });
    renderSection();
    const card = await screen.findByRole('region', { name: 'Outage 7, Results Out' });
    const notice = await within(card).findByTestId('outage-failed-resend');
    expect(notice).toHaveTextContent(
      'Control id CF: New header 902 ended Suspended (the receiver answered AE: Refused by the application). Nothing more was sent; a person reads the trace.',
    );
    expect(notice.closest('[data-tone]')).toHaveAttribute('data-tone', 'blocking');
    const items = within(within(card).getByTestId('outage-resends')).getAllByRole('listitem');
    expect(items[1]).toHaveTextContent('Failed');
    expect(items[1].querySelector('[data-tone]')).toHaveAttribute('data-tone', 'blocking');
    expect(items[2]).toHaveTextContent('Not sent');
    expect(items[2]).toHaveTextContent('Not sent: the run stopped.');
    expect(within(card).getByTestId('outage-tally')).toHaveTextContent(
      "Shutter's resends: 1 sent, 1 failed, 1 not sent.",
    );
  });

  it('lists the messages closed as already delivered or handled by hand, apart from the offered ones', async () => {
    serve({
      items: [
        offeredAtUnknown({
          lists: {
            offered: [row('44', 'CF', '', { acts: ['handled_by_hand'] })],
            queued: [],
            reached: [],
            refused: [],
            closed: [
              row(
                '41',
                'CA',
                'Already delivered: the receiver reported it already holds this message (MSA-3: ALREADY HELD, entered by hand).',
                {
                  closure: 'already_delivered',
                },
              ),
              row(
                '42',
                'CB',
                'Handled by hand, recorded by approver at 03:40: entered by the lab. Shutter sent nothing for it.',
                {
                  closure: 'handled_by_hand',
                  closedBy: 'approver',
                  closedAt: NOW,
                },
              ),
            ],
          },
        }),
      ],
      receivers: [],
    });
    renderSection();
    const closed = await screen.findByTestId('outage-closed');
    expect(closed).toHaveTextContent('Closed: already at the receiver (2)');
    const items = within(closed).getAllByRole('listitem');
    expect(items[0]).toHaveTextContent('Control id CA (header 41)Already delivered');
    expect(items[0]).toHaveTextContent('MSA-3: ALREADY HELD, entered by hand');
    expect(items[1]).toHaveTextContent('Control id CB (header 42)Handled by hand');
    // Only the message still offered carries the hand closure
    expect(await screen.findAllByRole('button', { name: /Already handled by hand/ })).toHaveLength(1);
    expect(screen.getByTestId('outage-lists')).toHaveTextContent(`${OFFERED_LABEL} (1)`);
  });

  it("keeps a closed outage whose messages Shutter resent for a day, with the ledger's tally in place of older words", async () => {
    serve({
      items: [
        outage({
          state: 'closed',
          closedAt: NOW,
          acts: [],
          outcome: '2 messages failed and are listed for a person. Shutter will not send these messages.',
          resends: [
            resend(1, 'CA', 'completed', 'sent'),
            resend(2, 'CF', 'closed_as_present', 'already_delivered'),
          ],
        }),
      ],
      receivers: [],
    });
    renderSection();
    const card = await screen.findByRole('region', { name: 'Outage 7, Results Out' });
    expect(within(card).getByTestId('outage-tally')).toHaveTextContent(
      "Shutter's resends: 1 sent, 1 the receiver already held.",
    );
    expect(within(card).queryByText(/Shutter will not send these messages/)).toBeNull();
    expect(within(card).queryByTestId('outage-acts')).toBeNull();
  });
});
