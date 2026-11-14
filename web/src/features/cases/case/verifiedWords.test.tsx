import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { AttemptView, CaseDetail, Snapshot } from '@/api/types';
import fixtures from '@/mocks/fixtures.json';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { caseOutcome } from '@/lib/status';
import { useAppearance } from '@/stores/appearance';
import { theme } from '@/theme';
import CasePage from '../CasePage';
import { failureMapOf } from './failureMapModel';
import { deliveredByEngineWords, notCheckedAtReceiver } from './receiver';
import { kindOfAttempts, receiverKind } from './derive';
import { FHIR_DISPATCH_NOTE, FHIR_VERIFIED_NOTE } from './DispatchPanel';
import { evidenceSummary } from './outcome';

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => {
  server.resetHandlers();
  cleanup();
});
afterAll(() => server.close());
beforeEach(() => {
  resetMock('approver');
  useAppearance.setState({ detail: 'plain' });
});

const ID = 'C-000008';
const recorded = fixtures.cases[ID];
const DELIVERED =
  'delivered by the engine at 03:13 (header 17), after the outage; accepted on the connection; nothing was resent by Shutter';
const delivered = (words: string) =>
  `delivered by the engine at 03:13 (header 17), after the outage; ${words}; nothing was resent by Shutter`;
const COMMIT = "accepted by the receiver's transport; processing not confirmed";
const APPLICATION = "accepted by the receiver's application, as declared in the site profile";

/** The recorded snapshot with its route item changed: a level, a category. */
function snapshotWith(route: Record<string, unknown>): Snapshot {
  const s = structuredClone(recorded.snapshot) as unknown as Snapshot;
  s.items = s.items.map((i) =>
    i.kind === 'route' ? { ...i, data: { ...(i.data as object), ...route } } : i,
  );
  return s;
}

const resolvedDetail = (outcome: string) =>
  ({ ...recorded.detail, state: 'resolved', disposition: 'resend', outcome }) as unknown as CaseDetail;

const orderText =
  'This message is ORU, not ADT: Shutter resends only ADT, so it sends nothing and a person decides.';

const receiptAttempt = fixtures.cases['C-000002'].attempts as unknown as AttemptView[];

/** A case as the page reads it, from its detail, its route, its attempts and its closure. */
function serve(detail: unknown, route: Record<string, unknown>, attempts: unknown[], closure?: unknown) {
  server.use(
    http.get(`/api/shutter/cases/${ID}`, () => HttpResponse.json(detail as object)),
    http.get(`/api/shutter/cases/${ID}/snapshot`, () => HttpResponse.json(snapshotWith(route))),
    http.get(`/api/shutter/cases/${ID}/attempts`, () => HttpResponse.json(attempts as object[])),
    http.get(`/api/shutter/cases/${ID}/closure`, () =>
      HttpResponse.json(
        (closure ?? {
          disposition: 'resend',
          outcome: (detail as { outcome?: string }).outcome ?? '',
          verification: null,
          verifiedEffects: [],
          unverified: [
            "Consumers beyond the downstream system are outside the production's view and are not verified",
          ],
          actors: ['system'],
          policyVersion: '2026-11-07.1',
          closedAt: '2026-11-07T03:13:00Z',
        }) as object,
      ),
    ),
  );
}

function renderCase() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter([{ path: '/cases/:caseId', element: <CasePage /> }], {
    initialEntries: [`/cases/${ID}`],
  });
  render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

const openStep = async (title: string) => {
  const step = await screen.findByRole('button', { name: new RegExp(`^(\\d\\. )?${title}`) });
  if (step.getAttribute('aria-expanded') !== 'true') await userEvent.click(step);
  return step;
};

describe('the words of a case with no receipt', () => {
  const none: AttemptView[] = [];

  it('leaves every recorded case to its own words, each new branch dead there', () => {
    for (const [id, x] of Object.entries(fixtures.cases)) {
      const c = x.detail as unknown as CaseDetail;
      const snapshot = x.snapshot as unknown as Snapshot;
      expect(notCheckedAtReceiver(c, snapshot, x.attempts as unknown as AttemptView[]), id).toBeNull();
      expect(deliveredByEngineWords(c, snapshot), id).toBe('');
    }
  });

  it('reads a delivered case from its sentence, with and without a level', () => {
    const c = resolvedDetail(DELIVERED);
    expect(notCheckedAtReceiver(c, snapshotWith({}), none)).toEqual({ outcome: DELIVERED, accepted: '' });
    expect(notCheckedAtReceiver(c, snapshotWith({ ack_level: 'connection' }), none)).toEqual({
      outcome: DELIVERED,
      accepted: 'accepted on the connection',
    });
  });

  it.each([
    ['connection', 'accepted on the connection', 'accepted on the connection'],
    ['commit', COMMIT, COMMIT],
    ['application', APPLICATION, APPLICATION],
  ])('at %s, the words that level allows', (ack_level, words, accepted) => {
    const n = notCheckedAtReceiver(resolvedDetail(delivered(words)), snapshotWith({ ack_level }), none);
    expect(n?.accepted).toBe(accepted);
    expect(n?.accepted).not.toMatch(/verified/i);
  });

  it('never rounds a level up: the sentence written at the delivery can be the lower', () => {
    const n = notCheckedAtReceiver(
      resolvedDetail(DELIVERED),
      snapshotWith({ ack_level: 'application' }),
      none,
    );
    expect(n?.accepted).toBe('accepted on the connection');
    const m = notCheckedAtReceiver(
      resolvedDetail('delivered by the engine at 03:13 (header 17)'),
      snapshotWith({ ack_level: 'commit' }),
      none,
    );
    expect(m?.accepted).toBe(COMMIT);
  });

  it('claims no acceptance where the engine has not delivered it, or the word is no level', () => {
    const open = recorded.detail as unknown as CaseDetail;
    expect(notCheckedAtReceiver(open, snapshotWith({ ack_level: 'application' }), none)?.accepted).toBe('');
    const unestablished = resolvedDetail(
      'IRIS marked this delivery Completed. Receiver acceptance has not been established.',
    );
    const blocked: CaseDetail = { ...unestablished, state: 'blocked' };
    expect(notCheckedAtReceiver(blocked, snapshotWith({}), none)?.accepted).toBe('');
    expect(
      notCheckedAtReceiver(resolvedDetail(DELIVERED), snapshotWith({ ack_level: 'not_established' }), none)
        ?.accepted,
    ).toBe('');
    // Closed by another route: a level is no evidence of this message
    const other = resolvedDetail("Nothing was resent; the receiver's history shows the later event");
    expect(notCheckedAtReceiver(other, snapshotWith({ ack_level: 'application' }), none)?.accepted).toBe('');
  });

  it("keeps today's words where a receipt exists, level or none, and while the attempts are unread", () => {
    const c = resolvedDetail(DELIVERED);
    expect(notCheckedAtReceiver(c, snapshotWith({ ack_level: 'application' }), receiptAttempt)).toBeNull();
    expect(notCheckedAtReceiver(c, snapshotWith({}), undefined)).toBeNull();
  });

  it('says an order or a result was not checked, by its text or by its route', () => {
    const open = recorded.detail as unknown as CaseDetail;
    expect(notCheckedAtReceiver(open, snapshotWith({ category: 'orders_results' }), none)).not.toBeNull();
    const order = { ...open, failureKind: 'unmappable', failureText: orderText, failureOutcome: 'error' };
    expect(notCheckedAtReceiver(order, snapshotWith({}), none)).not.toBeNull();
  });
});

describe('the failure map of a case the engine delivered', () => {
  const outcome = caseOutcome({ state: 'resolved', disposition: 'resend' });

  it('has it delivered, not checked, with the level, and verified nowhere', () => {
    const m = failureMapOf(resolvedDetail(DELIVERED), snapshotWith({ ack_level: 'connection' }), outcome);
    expect(m.hop).toMatchObject({ label: 'Delivered by the engine', broken: false });
    expect(m.receiver.now).toBe('Not checked at the receiver; accepted on the connection');
    expect(m.sentence).toContain('delivered by the engine');
    expect(m.sentence).toContain('Not checked at the receiver');
    expect(`${m.sentence} ${m.steps.join(' ')}`).not.toMatch(/verified/i);
  });

  it('keeps the verified words for a resend the verifier found', () => {
    const m = failureMapOf(resolvedDetail('Committed'), snapshotWith({}), outcome, { delivered: true });
    expect(m.receiver.now).toContain('verified there');
  });
});

describe('the case page', () => {
  const noVerified = () => {
    // The trial's and the app's chrome are outside the case: the case's own regions are read
    for (const name of ['Outcome', 'The closing record', 'At the receiver', 'Dispatch'])
      expect(screen.getByRole('region', { name }).textContent).not.toMatch(/verif/i);
  };

  const opened = async () => {
    renderCase();
    await waitFor(() => expect(screen.getByTestId('outcome-line')).toBeInTheDocument());
    await openStep('At the receiver');
    await openStep('What was written');
    await screen.findByRole('region', { name: 'The closing record' });
    await screen.findByRole('region', { name: 'Dispatch' });
  };

  it('reads a delivered case with no level: its Outcome, not checked, verified nowhere', async () => {
    serve(resolvedDetail(DELIVERED), {}, []);
    await opened();
    const at = screen.getByRole('region', { name: 'At the receiver' });
    expect(within(at).getByText(`D${DELIVERED.slice(1)}`)).toBeInTheDocument();
    expect(within(at).getByText('Not checked at the receiver')).toBeInTheDocument();
    const closure = screen.getByRole('region', { name: 'The closing record' });
    expect(within(closure).getByText('Not checked at the receiver')).toBeInTheDocument();
    expect(within(closure).getByText(DELIVERED)).toBeInTheDocument();
    expect(
      await within(screen.getByRole('region', { name: 'Dispatch' })).findByText(/Nothing was sent/),
    ).toBeInTheDocument();
    await waitFor(() =>
      expect(screen.getByRole('region', { name: 'Outcome' })).toHaveTextContent(
        'Not checked at the receiver',
      ),
    );
    noVerified();
  });

  it.each([
    ['connection', 'Accepted on the connection', 'accepted on the connection'],
    ['commit', "Accepted by the receiver's transport; processing not confirmed", COMMIT],
    ['application', "Accepted by the receiver's application, as declared in the site profile", APPLICATION],
  ])('shows an ADT case at a %s receiver the declared words', async (ack_level, shown, words) => {
    serve(resolvedDetail(delivered(words)), { ack_level }, []);
    await opened();
    expect(
      within(screen.getByRole('region', { name: 'At the receiver' })).getByText(shown),
    ).toBeInTheDocument();
    await waitFor(() => expect(screen.getByRole('region', { name: 'Outcome' })).toHaveTextContent(shown));
    noVerified();
  });

  it('shows the same ADT case with a receipt as today', async () => {
    const x = fixtures.cases['C-000002'];
    const verified = { ...x.detail, caseId: ID };
    serve(verified, { ack_level: 'application' }, x.attempts, x.closure);
    renderCase();
    await waitFor(() =>
      expect(screen.getByTestId('outcome-line')).toHaveTextContent('Delivered: verified at the receiver'),
    );
    await openStep('What was verified');
    expect(await screen.findByRole('region', { name: 'Verification' })).toBeInTheDocument();
    const closure = await screen.findByRole('region', { name: 'The closing record' });
    expect(within(closure).getByText('Verified at the receiver')).toBeInTheDocument();
    expect(within(closure).getByText('Not verified')).toBeInTheDocument();
    expect(document.body).not.toHaveTextContent(/Not checked at the receiver/);
  });

  it('never gives an order case a closure that reads verified', async () => {
    const order = {
      ...recorded.detail,
      state: 'escalated',
      failureKind: 'unmappable',
      failureOutcome: 'error',
      failureText: orderText,
    };
    serve(order, { category: 'orders_results' }, []);
    renderCase();
    await waitFor(() => expect(screen.getByTestId('outcome-line')).toBeInTheDocument());
    await openStep('At the receiver');
    const closure = await screen.findByRole('region', { name: 'The closing record' });
    expect(closure.textContent).not.toMatch(/verif/i);
    expect(within(closure).getByText('Not checked at the receiver')).toBeInTheDocument();
    expect(screen.getByRole('region', { name: 'At the receiver' }).textContent).not.toMatch(/verif/i);
  });
});

describe('the words of a FHIR case', () => {
  const FHIR_HEADLINE =
    "Updated the Encounter's location once, by another route than the original HL7 delivery";

  it('leaves every recorded case to its own words, each new branch dead there', () => {
    for (const [id, x] of Object.entries(fixtures.cases)) {
      const snapshot = x.snapshot as unknown as Snapshot;
      expect(receiverKind(snapshot), id).toBeUndefined();
      expect(kindOfAttempts(x.attempts as unknown as AttemptView[]), id).toBeUndefined();
      expect(evidenceSummary(snapshot), id).not.toMatch(/marker/);
    }
  });

  it('shows the one update with If-Match, its answer and its verification, and never a resend', async () => {
    const x = fixtures.cases['C-000002'];
    const [view] = structuredClone(x.attempts) as unknown as AttemptView[];
    const attempts = [
      {
        attempt: {
          ...view.attempt,
          expectedVersion: '',
          httpStatus: 200,
          outcome: 'applied',
          receipt: {
            kind: 'fhir',
            encounter: 'Encounter/enc-1',
            expected_etag: 'W/"1"',
            response_etag: 'W/"2"',
            response_location: '',
            body_digest: 'sha256:abc123',
            operation_id: 'op-1',
            marker_system: 'urn:shutter',
          },
        },
        verification: {
          ...view.verification,
          outcome: 'verified',
          summary: 'Verified in Encounter version "2", which carries Shutter\'s marker.',
          detail: { kind: 'fhir', judge_outcome: 'verified', disposition: 'resend', case_code: '' },
        },
      },
    ];
    serve({ ...x.detail, caseId: ID }, { kind: 'fhir_r4' }, attempts, x.closure);
    renderCase();
    await waitFor(() =>
      expect(screen.getByRole('region', { name: 'Outcome' })).toHaveTextContent(FHIR_HEADLINE),
    );
    expect(document.body).not.toHaveTextContent(/Sent the transfer again/);
    await openStep('What was written');
    const dispatch = await screen.findByRole('region', { name: 'Dispatch' });
    expect(await within(dispatch).findByText('Sent with If-Match')).toBeInTheDocument();
    expect(within(dispatch).getByText('W/"1"')).toBeInTheDocument();
    expect(within(dispatch).getByText('HTTP 200, ETag W/"2"')).toBeInTheDocument();
    expect(within(dispatch).getByText('Body digest')).toBeInTheDocument();
    expect(dispatch).toHaveTextContent(FHIR_DISPATCH_NOTE);
    expect(within(dispatch).queryByText('Conditional on version')).not.toBeInTheDocument();
    expect(dispatch.textContent).not.toMatch(/version \S* to /);
    await openStep('What was verified');
    const verification = await screen.findByRole('region', { name: 'Verification' });
    expect(verification).toHaveTextContent(FHIR_VERIFIED_NOTE);
    expect(within(verification).getByText(/^Verified in Encounter version "2"/)).toBeInTheDocument();
  });

  /** A FHIR attempt of the recorded case's shape: its outcome, its answer and its response. */
  const fhirAttempt = (outcome: string, httpStatus: number, response: Record<string, unknown>) => {
    const [view] = structuredClone(fixtures.cases['C-000002'].attempts) as unknown as AttemptView[];
    return {
      ...view.attempt,
      expectedVersion: '',
      httpStatus,
      outcome,
      receipt: {
        kind: 'fhir',
        encounter: 'Encounter/enc-1',
        expected_etag: 'W/"3"',
        response_etag: '',
        response_location: '',
        body_digest: 'sha256:abc123',
        operation_id: 'op-1',
        marker_system: 'urn:shutter',
      },
      response: { kind: 'fhir', diagnostics: '', ...response },
    };
  };

  it("shows an update Shutter's last check stopped as not sent, never as sent or refused by the server", async () => {
    const x = fixtures.cases['C-000002'];
    const attempts = [
      {
        attempt: fhirAttempt('refused', 0, { sent: false, reason_code: 'fhir_endpoint_differs' }),
        verification: null,
      },
    ];
    serve(
      { ...x.detail, caseId: ID, state: 'blocked', disposition: 'resend', outcome: '' },
      { kind: 'fhir_r4' },
      attempts,
      x.closure,
    );
    renderCase();
    await openStep('What was written');
    const dispatch = await screen.findByRole('region', { name: 'Dispatch' });
    expect(
      await within(dispatch).findByText("Not sent: Shutter's last check stopped it"),
    ).toBeInTheDocument();
    expect(within(dispatch).getByText('fhir_endpoint_differs')).toBeInTheDocument();
    expect(within(dispatch).queryByText('Sent with If-Match')).not.toBeInTheDocument();
    expect(within(dispatch).queryByText('Sent')).not.toBeInTheDocument();
    expect(dispatch.textContent).not.toMatch(/FHIR server refused/);
    expect(document.body.textContent).not.toMatch(/did not take/);
  });

  it('says a FHIR write the history read did not show was not found there, never that it was not committed', async () => {
    const x = fixtures.cases['C-000002'];
    const [view] = structuredClone(x.attempts) as unknown as AttemptView[];
    const attempts = [
      {
        attempt: fhirAttempt('uncertain', 500, { sent: true, reason_code: '' }),
        verification: {
          ...view.verification,
          outcome: 'not_committed',
          summary: "No version in the history read carries this case's marker.",
          detail: {
            kind: 'fhir',
            judge_outcome: 'not_found',
            disposition: 'resend',
            case_code: 'FHIR_WRITE_NOT_FOUND',
          },
        },
      },
    ];
    serve(
      { ...x.detail, caseId: ID, state: 'escalated', disposition: 'resend', outcome: '' },
      { kind: 'fhir_r4' },
      attempts,
      x.closure,
    );
    renderCase();
    await waitFor(() =>
      expect(screen.getByRole('region', { name: 'Outcome' })).toHaveTextContent(
        "Sent one update of the Encounter's location",
      ),
    );
    expect(document.body.textContent).not.toMatch(/Updated the Encounter's location/);
    await openStep('What was verified');
    const verification = await screen.findByRole('region', { name: 'Verification' });
    expect(within(verification).getByText('Not found in the history read')).toBeInTheDocument();
    expect(document.body.textContent).not.toMatch(/Not committed/);
  });

  it('badges a FHIR plan as one FHIR update, never as a resend after rehearsal', async () => {
    const x = fixtures.cases['C-000002'];
    serve(
      { ...x.detail, caseId: ID, state: 'awaiting_approval', disposition: 'resend', outcome: '' },
      { kind: 'fhir_r4' },
      [],
      x.closure,
    );
    // No board plans a FHIR case: the recorded case's board runs are left out
    server.use(http.get(`/api/shutter/cases/${ID}/runs`, () => HttpResponse.json([])));
    renderCase();
    expect(await screen.findByText('Proposed: One FHIR update')).toBeInTheDocument();
    expect(screen.queryAllByText(/^(Proposed: )?Resend$/)).toHaveLength(0);
  });
});
