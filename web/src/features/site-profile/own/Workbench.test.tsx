import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { MemoryRouter } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { resetMock, SITE_ENTRIES_EXAMPLE } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { useAppearance } from '@/stores/appearance';
import { theme } from '@/theme';
import { OwnScenarios } from '../OwnScenarios';

/**
 * The workbench of the site's own scenarios (CONTRACTS 6.8) on the trial's sample entries: starting from a closed case,
 * the chips and their count, the near miss the proof needs, the proof's table, sending for approval, a second person's
 * review, the author's own refused, the demo's locked saves and its Try it, and one approver's suspension. What the page
 * sends is checked too: never a field that decides.
 */

const BASE = '/api/shutter';

function page(at = '/site-profile') {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <MantineProvider theme={theme}>
        <MemoryRouter initialEntries={[at]}>
          <OwnScenarios />
        </MemoryRouter>
      </MantineProvider>
    </QueryClientProvider>,
  );
}

/** Every body the page sent to a site entry route, by its path. */
let sent: { path: string; body: Record<string, unknown> }[] = [];

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
beforeEach(() => {
  resetMock('approver');
  useAppearance.setState({ detail: 'plain' });
  sent = [];
  server.events.removeAllListeners();
  server.events.on('request:start', ({ request }) => {
    const url = new URL(request.url);
    if (request.method !== 'GET' && url.pathname.startsWith(`${BASE}/site-entries`))
      void request
        .clone()
        .json()
        .then((body: Record<string, unknown>) => sent.push({ path: url.pathname.slice(BASE.length), body }))
        .catch(() => undefined);
  });
});

const DECIDING = ['decides', 'preferred', 'alternatives', 'outcome', 'decision_by', 'checks'];

describe("the workbench of the site's own scenarios", () => {
  it('starts from a closed case: its conditions as ticked chips, a count that changes as one is unticked, and the near miss it asks for', async () => {
    const user = userEvent.setup();
    page('/site-profile?own=new&case=C-000028');
    const chips = await screen.findByTestId('own-chips', {}, { timeout: 5000 });
    const boxes = within(chips).getAllByRole('checkbox');
    expect(boxes.length).toBeGreaterThan(5);
    for (const b of boxes) expect(b).toBeChecked();
    expect(within(chips).getByText('it is a transfer')).toBeInTheDocument();
    const line = screen.getByTestId('own-live-impact');
    await waitFor(() => expect(line).toHaveTextContent(/Of the last 64 cases, it would catch \d+/), {
      timeout: 5000,
    });
    const before = Number(/catch (\d+)/.exec(line.textContent ?? '')?.[1]);
    // Untick "nothing later was applied": the pattern widens, so the count can only grow, and what is sent lacks it
    await user.click(within(chips).getByText('nothing later was applied'));
    await waitFor(
      () => {
        const last = sent.filter((x) => x.path === '/site-entries/preview').at(-1)?.body;
        expect(Object.keys((last?.pattern as object) ?? {})).not.toContain('later_applied');
        expect(Object.keys((last?.pattern as object) ?? {})).toContain('event');
      },
      { timeout: 5000 },
    );
    await waitFor(() => expect(line).toHaveTextContent(/it would catch/), { timeout: 5000 });
    expect(Number(/catch (\d+)/.exec(line.textContent ?? '')?.[1])).toBeGreaterThanOrEqual(before);
    await user.click(within(chips).getByText('nothing later was applied'));
    // The case is the first one it must catch, and it asks for a near miss, saying why
    expect(screen.getByTestId('own-fixtures')).toHaveTextContent('C-000028: it must catch this case');
    expect(screen.getByTestId('own-near-miss-ask')).toHaveTextContent(/Without one the proof cannot pass/);
    // Try it: the same table a proof gives, and it does not pass without a near miss
    await user.click(screen.getByTestId('own-try'));
    const tried = await screen.findByTestId('own-tried', {}, { timeout: 5000 });
    expect(tried).toHaveTextContent('The proof does not pass');
    expect(within(tried).getByTestId('own-tried-problems')).toHaveTextContent(/near miss/);
    // A near miss, the words, then Save and Prove
    await user.type(screen.getByLabelText('Another closed case'), 'C-000027');
    await user.click(screen.getByRole('button', { name: 'Add as a near miss' }));
    expect(screen.queryByTestId('own-near-miss-ask')).not.toBeInTheDocument();
    await user.type(screen.getByLabelText(/^Title/), 'A failed transfer into Ward B');
    await user.type(
      screen.getByLabelText(/^Why a person must decide/),
      'The ward places its patients by hand.',
    );
    await user.click(screen.getByRole('button', { name: 'Save the draft' }));
    expect(
      await screen.findByRole('heading', { name: 'L3: A failed transfer into Ward B' }, { timeout: 5000 }),
    ).toBeInTheDocument();
    await user.click(await screen.findByRole('button', { name: 'Prove it' }));
    const proof = await screen.findByTestId('own-proof', {}, { timeout: 5000 });
    expect(proof).toHaveTextContent('The proof passes');
    const rows = within(within(proof).getByTestId('own-proof-fixtures')).getAllByRole('row');
    expect(rows[1]).toHaveTextContent(/C-000028To catchYesL3/);
    expect(rows[2]).toHaveTextContent(/C-000027To leave aloneYesnot this entry/);
    // Send for approval: the summary, and a proposal
    await user.click(screen.getByRole('button', { name: 'Send for approval…' }));
    const dialog = await screen.findByRole('dialog', { name: /Send version 1 of L3 for approval/ });
    expect(within(dialog).getByTestId('own-summary')).toHaveTextContent(
      /When a transfer to Downstream Out.*a person decides/,
    );
    await waitFor(() =>
      expect(within(dialog).getByTestId('own-displaces')).toHaveTextContent(/Without it: E2/),
    );
    expect(within(dialog).getByTestId('own-digest')).toHaveTextContent(
      /action activate, version 1, digest sha256:/,
    );
    const shown = /digest (sha256:[0-9a-f]+)/.exec(
      within(dialog).getByTestId('own-digest').textContent ?? '',
    )?.[1];
    await user.click(within(dialog).getByRole('button', { name: 'Send for approval' }));
    expect(await screen.findByTestId('own-proposal', {}, { timeout: 5000 })).toHaveTextContent(
      /approver proposed to make version 1 active/,
    );
    // The proposal names the version and digest the dialog showed
    expect(sent.find((s) => s.path === '/site-entries/L3/propose')?.body).toEqual({
      action: 'activate',
      version: 1,
      digest: shown,
    });
    // The author reviews their own: why they cannot approve it, and Approve is locked
    await user.click(screen.getByRole('button', { name: 'Review the proposal…' }));
    const review = await screen.findByRole('dialog', { name: 'Approve or reject: L3 version 1' });
    expect(within(review).getByTestId('save-locked')).toHaveTextContent(
      /You proposed this: a second person approves it/,
    );
    expect(within(review).getByRole('button', { name: 'Approve' })).toHaveAttribute('aria-disabled', 'true');
    // Nothing the page sent says who decides or the outcome
    for (const s of sent) for (const k of DECIDING) expect(Object.keys(s.body), `${s.path}`).not.toContain(k);
    expect(sent.some((s) => s.path === '/site-entries' && Array.isArray(s.body.fixtures))).toBe(true);
  }, 60_000);

  it('lets a second person approve the waiting sample with a reason, showing the proof, what it displaces and the plans it stops', async () => {
    const user = userEvent.setup();
    page();
    await user.click(await screen.findByRole('button', { name: 'Review L2' }));
    const dialog = await screen.findByRole(
      'dialog',
      { name: 'Approve or reject: L2 version 1' },
      { timeout: 5000 },
    );
    expect(within(dialog).getByText('Proposed by sample-author.')).toBeInTheDocument();
    expect(within(dialog).getByTestId('own-approval-proof')).toHaveTextContent('The proof passes');
    expect(within(dialog).getByTestId('own-waiting')).toHaveTextContent(/0 open cases have plans/);
    await waitFor(() =>
      expect(within(dialog).getByTestId('own-displaces')).toHaveTextContent(/Without it: E2/),
    );
    // A reason is needed
    await user.click(within(dialog).getByRole('button', { name: 'Approve' }));
    expect(within(dialog).getByText('A reason is needed, for the record.')).toBeInTheDocument();
    await user.type(within(dialog).getByLabelText(/^Reason/), 'Agreed with the ward');
    await user.type(within(dialog).getByLabelText(/^Safety reference/), 'HAZ-12');
    await user.click(within(dialog).getByRole('button', { name: 'Approve' }));
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument(), { timeout: 5000 });
    const row = await screen.findByTestId('own-scenario-L2');
    await waitFor(() => expect(within(row).getByText('Active')).toBeInTheDocument());
    expect(within(row).getByText(/Version 1 approved by approver/)).toBeInTheDocument();
    const approval = sent.find((s) => s.path === '/site-entries/L2/approvals')!;
    expect(approval.body).toMatchObject({
      action: 'activate',
      version: 1,
      decision: 'approve',
      safetyReference: 'HAZ-12',
    });
    expect(String(approval.body.digest)).toMatch(/^sha256:/);
  }, 60_000);

  it("on the demo: the list is read and tried, and every save is locked with the site profile's explanation", async () => {
    resetMock('demo');
    const user = userEvent.setup();
    page();
    expect(screen.queryByTestId('own-new')).not.toBeInTheDocument();
    await user.click(await screen.findByRole('button', { name: 'Open L2' }));
    const bench = await screen.findByTestId('own-workbench', {}, { timeout: 5000 });
    expect(await within(bench).findByTestId('save-locked')).toHaveTextContent(
      "The online demo's settings are locked",
    );
    await user.click(await within(bench).findByTestId('own-try'));
    const tried = await within(bench).findByTestId('own-tried', {}, { timeout: 5000 });
    expect(tried).toHaveTextContent('The proof passes');
    await user.click(screen.getByRole('button', { name: 'Review the proposal…' }));
    const review = await screen.findByRole('dialog', { name: 'Approve or reject: L2 version 1' });
    expect(within(review).getByTestId('save-locked')).toHaveTextContent(
      "The online demo's settings are locked",
    );
    expect(within(review).getByRole('button', { name: 'Approve' })).toHaveAttribute('aria-disabled', 'true');
    expect(sent.every((s) => s.path === '/site-entries/preview' || s.path === '/site-entries/validate')).toBe(
      true,
    );
  }, 60_000);

  it('shows the demo its example where it has no entry of its own, tried on S2 and S1', async () => {
    resetMock('demo');
    server.use(
      http.get(`${BASE}/site-entries`, () =>
        HttpResponse.json({
          items: [],
          status: {
            active: 0,
            proposed: 0,
            generation: 0,
            limit: 50,
            suspended: [],
            needsReview: [],
            onePerson: null,
            warnings: [],
          },
          catalogueVersion: '',
        }),
      ),
    );
    const user = userEvent.setup();
    page();
    await user.click(await screen.findByTestId('own-open-example', {}, { timeout: 5000 }));
    expect(await screen.findByTestId('own-example-note')).toHaveTextContent(/not stored/);
    await waitFor(
      () => expect(screen.getByTestId('own-fixtures')).toHaveTextContent(/it must leave this case alone/),
      {
        timeout: 5000,
      },
    );
    await user.click(screen.getByTestId('own-try'));
    expect(await screen.findByTestId('own-tried', {}, { timeout: 5000 })).toHaveTextContent(
      'The proof passes',
    );
  }, 60_000);

  it('tells an operator only an approver approves, and lets an approver suspend an active entry with a reason', async () => {
    resetMock('operator');
    const user = userEvent.setup();
    const first = page();
    await user.click(await screen.findByRole('button', { name: 'Review L2' }));
    const review = await screen.findByRole(
      'dialog',
      { name: 'Approve or reject: L2 version 1' },
      { timeout: 5000 },
    );
    expect(within(review).getByTestId('save-locked')).toHaveTextContent(/Only an approver approves here/);
    first.unmount();
    resetMock('approver');
    page('/site-profile?own=L1');
    await user.click(await screen.findByRole('button', { name: 'Suspend it…' }, { timeout: 5000 }));
    const dialog = await screen.findByRole('dialog', { name: 'Suspend L1' });
    await user.type(within(dialog).getByLabelText(/^Reason/), 'It floods the on-call');
    await user.click(within(dialog).getByRole('button', { name: 'Suspend now' }));
    const banner = await screen.findByTestId('own-scenarios-warnings', {}, { timeout: 5000 });
    expect(banner).toHaveTextContent(/L1 is suspended/);
    expect(await screen.findByRole('button', { name: 'Propose resuming it…' })).toBeInTheDocument();
    // The suspension names the revision the page read
    expect(sent.find((s) => s.path === '/site-entries/L1/suspend')?.body).toEqual({
      reason: 'It floods the on-call',
      expectedVersion: 4,
    });
  }, 60_000);

  it("says someone changed the entry when a suspension names a revision that is no longer the entry's, and keeps the dialog open", async () => {
    server.use(
      http.post(`${BASE}/site-entries/:id/suspend`, () =>
        HttpResponse.json(
          {
            error: 'stale_version',
            detail: "expectedVersion is missing or not the entry's revision",
            currentVersion: 5,
          },
          { status: 409 },
        ),
      ),
    );
    const user = userEvent.setup();
    page('/site-profile?own=L1');
    await user.click(await screen.findByRole('button', { name: 'Suspend it…' }, { timeout: 5000 }));
    const dialog = await screen.findByRole('dialog', { name: 'Suspend L1' });
    await user.type(within(dialog).getByLabelText(/^Reason/), 'It floods the on-call');
    await user.click(within(dialog).getByRole('button', { name: 'Suspend now' }));
    expect(await within(dialog).findByRole('alert')).toHaveTextContent(
      'Someone changed this entry since you opened it: close and open it again.',
    );
    expect(screen.getByRole('dialog', { name: 'Suspend L1' })).toBeInTheDocument();
  }, 60_000);

  it("tells the version's author they cannot approve its retirement either, whatever the letter case of their name", async () => {
    const example = SITE_ENTRIES_EXAMPLE.items[0]!;
    server.use(
      http.get(`${BASE}/site-entries/L1`, () =>
        HttpResponse.json({
          ...example,
          proposal: {
            action: 'retire',
            version: 1,
            digest: example.digest,
            by: 'colleague',
            at: '2026-11-16T09:00:00Z',
          },
          versions: [
            {
              version: 1,
              status: 'approved',
              digest: example.digest,
              writtenBy: 'APPROVER',
              approvedBy: 'colleague',
            },
          ],
          proofs: [],
          events: [],
        }),
      ),
    );
    const user = userEvent.setup();
    page('/site-profile?own=L1');
    await user.click(await screen.findByRole('button', { name: 'Review the proposal…' }, { timeout: 5000 }));
    const review = await screen.findByRole('dialog', { name: 'Approve or reject: L1 version 1' });
    expect(within(review).getByTestId('save-locked')).toHaveTextContent(
      /You wrote this version: a second person/,
    );
    expect(within(review).getByRole('button', { name: 'Approve' })).toHaveAttribute('aria-disabled', 'true');
    // The author may still reject it
    expect(within(review).getByRole('button', { name: 'Reject' })).not.toHaveAttribute('aria-disabled');
  }, 60_000);
});
