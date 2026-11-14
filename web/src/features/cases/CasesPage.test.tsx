import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { server } from '@/mocks/node';
import { resetMock, writesOf } from '@/mocks/handlers';
import recording from '@/mocks/fixtures.json';
import { ToneLegend } from '@/components/ToneLegend';
import type { CaseSummary, FhirReceiverSettings, Scenario, SiteProfile, SiteReceiver } from '@/api/types';
import { recordedSiteProfile } from '@/mocks/profile';
import { layer1WordCount } from '@/test/words';
import { renderUi } from '@/test/render';
import { theme } from '@/theme';
import { MemoryRouter } from 'react-router';
import CasesPage, {
  AttentionTile,
  casesOfGroup,
  CasesTable,
  closedCounts,
  fhirReceiversOf,
  ForwardedBadge,
  InvestigatedBy,
  investigatedBy,
  proposalNote,
  whatHappened,
} from './CasesPage';

// The list's tag on its own: the page's filters (two Selects) take tens of seconds to render under jsdom, and so
// does opening the tag's tooltip; forwardedFrom's tests cover what the tooltip says.
const base = { caseId: 'C-000123', state: 'resolved', event: 'transfer', ward: 'WARD-B' } as CaseSummary;

function renderBadge(c: CaseSummary) {
  return render(
    <MantineProvider theme={theme}>
      <ForwardedBadge c={c} />
    </MantineProvider>,
  );
}

describe('ForwardedBadge', () => {
  it('tags a case another production forwarded', () => {
    renderBadge({
      ...base,
      sourceHeaderId: '13111',
      sourceNamespace: 'HOSPITAL',
      sourceProduction: 'Hospital.Production',
      sourceRoute: 'PAS In',
      originHeaderId: '4243',
    });
    expect(screen.getByText('Forwarded')).toBeInTheDocument();
  });

  it("tags no case the feed in Shutter's own production opened", () => {
    renderBadge({ ...base, sourceHeaderId: '11961', sourceNamespace: '' });
    expect(screen.queryByText('Forwarded')).not.toBeInTheDocument();
    renderBadge(base);
    expect(screen.queryByText('Forwarded')).not.toBeInTheDocument();
  });
});

describe('investigatedBy', () => {
  it("names the leader's board for a follower's plan", () => {
    expect(investigatedBy({ ...base, mode: 'board', planCreatedBy: 'lead:C-000007' }).who).toBe(
      'Board of C-000007',
    );
  });

  const at = (mode: CaseSummary['mode'], more: Partial<CaseSummary> = {}) =>
    investigatedBy({ ...base, mode, ...more });

  it("reads the plan's origin: an agent run is the board's, or the single investigator's", () => {
    expect(at('board', { planCreatedBy: 'run:8' })).toEqual({ who: 'Board' });
    expect(at('single', { planCreatedBy: 'run:3' })).toEqual({ who: 'Single investigator' });
    // In site-policy mode the catalogue left this case to the board
    expect(at('policy', { planCreatedBy: 'run:56' })).toEqual({ who: 'Board' });
  });

  it('names the catalogue entry the site policy settled a case with', () => {
    expect(at('policy', { planCreatedBy: 'policy:E2' })).toEqual({
      who: 'Site policy (no agents)',
      entry: 'E2',
    });
    // A withheld merge is the policy's whatever the mode
    expect(at('board', { planCreatedBy: 'policy:E14', failureKind: 'withheld' })).toEqual({
      who: 'Site policy (no agents)',
      entry: 'E14',
    });
  });

  it('names rules alone', () => {
    expect(at('rules', { planCreatedBy: 'rules' })).toEqual({ who: 'Rules only' });
  });

  it('says a person decides a withheld operation no single catalogue entry matched', () => {
    expect(at('rules', { planCreatedBy: 'withheld', failureKind: 'withheld' })).toEqual({
      who: 'Withheld: a person decides',
    });
    expect(at('policy', { planCreatedBy: 'withheld', failureKind: 'withheld' })).toEqual({
      who: 'Withheld: a person decides',
    });
  });

  it('says not yet while the case is on its way to a plan', () => {
    for (const state of ['detected', 'collecting', 'investigating', 'grouped'] as const) {
      expect(at('board', { state })).toEqual({ who: 'Not yet' });
      expect(at('policy', { state })).toEqual({ who: 'Not yet' });
    }
  });

  it('reads the mode for a case with no plan origin, without claiming the policy settled it', () => {
    const escalated = { state: 'escalated' } as const;
    expect(at('board', escalated)).toEqual({ who: 'Board' });
    expect(at('single', escalated)).toEqual({ who: 'Single investigator' });
    expect(at('rules', escalated)).toEqual({ who: 'Rules only' });
    // In site-policy mode the catalogue may have settled it or left it to the board
    expect(at('policy', escalated)).toEqual({ who: 'Site policy or board' });
    expect(at('board', { ...escalated, failureKind: 'withheld' })).toEqual({
      who: 'Withheld: a person decides',
    });
  });

  it('names no one for a plan origin it does not know', () => {
    expect(at('board', { planCreatedBy: 'user:approver' })).toEqual({ who: '-' });
  });

  it('shows the entry under the name in the list', () => {
    render(
      <MantineProvider theme={theme}>
        <InvestigatedBy c={{ ...base, mode: 'policy', planCreatedBy: 'policy:E2' }} />
      </MantineProvider>,
    );
    expect(screen.getByText('Site policy (no agents)')).toBeInTheDocument();
    expect(screen.getByText('entry E2')).toBeInTheDocument();
  });
});

describe('CasesTable', () => {
  it('names each cell after its column for the stacked layout, and keeps the table announced as one', () => {
    render(
      <MantineProvider theme={theme}>
        <MemoryRouter>
          <CasesTable
            items={[
              {
                ...base,
                encounterId: 'ENC-1',
                disposition: 'resend',
                scenario: 'S2',
                mode: 'board',
                openedAt: '2026-10-25T08:00:00Z',
                writes: 1,
                verification: 'verified',
              } as CaseSummary,
            ]}
          />
        </MemoryRouter>
      </MantineProvider>,
    );
    const table = screen.getByRole('table');
    expect(table).toHaveAttribute('role', 'table');
    expect(
      within(table)
        .getAllByRole('columnheader')
        .map((h) => h.textContent),
    ).toEqual([
      'Case',
      'Outcome',
      'Proposed action',
      'At the receiver',
      'What happened',
      'Scenario',
      'Investigated by',
    ]);
    const row = within(table).getByRole('link', { name: 'C-000123' }).closest('tr')!;
    expect(row).toHaveAttribute('role', 'row');
    const cells = within(row).getAllByRole('cell');
    // The first cell is the case id, the card's title on a phone; every other one carries its column's name
    expect(cells[0]).not.toHaveAttribute('data-label');
    expect(cells.slice(1).map((c) => c.getAttribute('data-label'))).toEqual([
      'Outcome',
      'Proposed action',
      'At the receiver',
      'What happened',
      'Scenario',
      'Investigated by',
    ]);
    // What was written and what the verifier found
    expect(cells[3]).toHaveTextContent('1 write');
    expect(cells[3]).toHaveTextContent('Effect verified at the receiver');
    // When it was opened sits under the case id
    expect(within(cells[0]).getByRole('time')).toHaveAttribute('datetime', '2026-10-25T08:00:00Z');
  });
});

describe("a FHIR receiver's case in the list", () => {
  const fhir = { base: '/fhir/r4' } as FhirReceiverSettings;
  const profile = (receivers: SiteReceiver[]) => ({ receivers, policy: {} }) as unknown as SiteProfile;
  const proposed = (caseId: string, receiver?: string) =>
    ({ ...base, caseId, receiver, state: 'awaiting_approval', disposition: 'resend' }) as CaseSummary;

  it('names the receivers whose site profile entry carries a fhir object, and none while the profile is not read', () => {
    const names = fhirReceiversOf(
      profile([
        { name: 'FHIR Encounters', tier: 1, fhir },
        { name: 'Bed Manager', tier: 2 },
      ]),
    );
    expect([...names]).toEqual(['FHIR Encounters']);
    expect(fhirReceiversOf(undefined).size).toBe(0);
  });

  it('badges it as one FHIR update, never as a resend after rehearsal; any other case is unchanged', () => {
    renderUi(
      <CasesTable
        items={[proposed('C-F1', 'FHIR Encounters'), proposed('C-B1', 'Bed Manager'), proposed('C-N1')]}
        fhirReceivers={new Set(['FHIR Encounters'])}
      />,
    );
    const row = (id: string) => screen.getByRole('link', { name: id }).closest('tr')!;
    expect(within(row('C-F1')).getByText('One FHIR update')).toBeInTheDocument();
    expect(within(row('C-F1')).queryByText('Resend')).not.toBeInTheDocument();
    expect(within(row('C-B1')).getByText('Resend')).toBeInTheDocument();
    expect(within(row('C-N1')).getByText('Resend')).toBeInTheDocument();
  });

  it('shows what it shows today while it has no FHIR receivers to go by', () => {
    renderUi(<CasesTable items={[proposed('C-F1', 'FHIR Encounters')]} />);
    expect(within(screen.getByRole('table')).getByText('Resend')).toBeInTheDocument();
    expect(screen.queryByText('One FHIR update')).not.toBeInTheDocument();
  });
});

describe('CasesTable tab stops', () => {
  it("keeps one tab stop per row, the case link: no stop on the row's time, badges or action", () => {
    render(
      <MantineProvider theme={theme}>
        <MemoryRouter>
          <CasesTable
            items={[
              {
                ...base,
                encounterId: 'ENC-1',
                disposition: 'resend',
                scenario: 'S2',
                mode: 'board',
                openedAt: '2026-10-25T08:00:00Z',
                writes: 1,
                verification: 'verified',
              } as CaseSummary,
            ]}
          />
        </MemoryRouter>
      </MantineProvider>,
    );
    const row = screen.getAllByRole('row')[1];
    const stops = [...row.querySelectorAll<HTMLElement>('a[href], button, [tabindex="0"]')];
    expect(stops.map((e) => e.textContent)).toEqual([base.caseId]);
  });

  it("leaves the row's time and badges no control of their own, so on a phone a tap on them reaches the card's link", () => {
    render(
      <MantineProvider theme={theme}>
        <MemoryRouter>
          <CasesTable
            items={[
              {
                ...base,
                encounterId: 'ENC-1',
                disposition: 'resend',
                scenario: 'S2',
                mode: 'board',
                openedAt: '2026-10-25T08:00:00Z',
                writes: 1,
                verification: 'verified',
              } as CaseSummary,
            ]}
          />
        </MemoryRouter>
      </MantineProvider>,
    );
    const row = screen.getAllByRole('row')[1];
    expect(row.querySelector('a.case-open')).toHaveTextContent(base.caseId);
    // What cases-list.css raises above the card's link on a phone: anything else lies under it
    const raised = "a:not(.case-open), button, [data-tech-detail='open']";
    const parts = [
      row.querySelector("td[data-label='Outcome'] [data-tone]"),
      row.querySelector("td[data-label='Proposed action'] [data-tone]"),
      row.querySelector('time'),
    ];
    for (const part of parts) {
      expect(part).not.toBeNull();
      expect(part!.closest(raised)).toBeNull();
      expect(part).not.toHaveAttribute('tabindex');
    }
  });
});

describe('proposalNote', () => {
  it('says what a stopped, held or escalated state means for the proposal beside it, and nothing otherwise', () => {
    expect(proposalNote({ state: 'blocked', disposition: 'resend' })).toBe('Stopped: nothing more is sent');
    expect(proposalNote({ state: 'awaiting_approval', disposition: 'resend' })).toBe(
      'Waiting for a person to release it',
    );
    expect(proposalNote({ state: 'escalated', disposition: 'escalate' })).toBe('A person decides');
    expect(proposalNote({ state: 'resolved', disposition: 'resend' })).toBe('');
    expect(proposalNote({ state: 'blocked', disposition: '' })).toBe('');
  });
});

describe('AttentionTile', () => {
  beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
  afterEach(() => server.resetHandlers());
  afterAll(() => server.close());
  beforeEach(() => resetMock('approver'));

  const summaries = Object.values(recording.cases as unknown as Record<string, { summary: CaseSummary }>).map(
    (c) => c.summary,
  );

  it("counts the cases in its state from the API's total, and filters the list when pressed", async () => {
    const choose = vi.fn();
    render(
      <MantineProvider theme={theme}>
        <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
          <AttentionTile state="blocked" chosen={false} onChoose={choose} />
        </QueryClientProvider>
      </MantineProvider>,
    );
    const blocked = summaries.filter((c) => c.state === 'blocked').length;
    const tile = await screen.findByRole('button', { name: new RegExp(`^${blocked}\\s*Blocked`) });
    expect(tile).toHaveAttribute('aria-pressed', 'false');
    await userEvent.click(tile);
    expect(choose).toHaveBeenCalledOnce();
  });
});

describe('ToneLegend', () => {
  it('says once what each of the five tones means, in words beside each badge', () => {
    render(
      <MantineProvider theme={theme}>
        <ToneLegend />
      </MantineProvider>,
    );
    const legend = screen.getByRole('list', { name: 'What the colours mean' });
    expect(within(legend).getAllByRole('listitem')).toHaveLength(5);
    expect(legend).toHaveTextContent('Attentiona person is needed');
    expect(legend).toHaveTextContent('closed, or a decision; nothing waiting');
    expect(legend).toHaveTextContent('verified at the receiver, a passed check, or a result as expected');
    expect(legend).toHaveTextContent('refused, failed or contradicted at the receiver');
  });
});

describe('the list from the mock', () => {
  beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
  afterAll(() => server.close());
  beforeEach(() => resetMock('approver'));

  it('counts writes and the latest verification from the recorded attempts, as the API does', async () => {
    const res = await fetch(`${location.origin}/api/shutter/cases?limit=500`);
    expect(res.status).toBe(200);
    const body = (await res.json()) as { items: CaseSummary[] };
    const resolved = body.items.find((c) => c.caseId === 'C-000015');
    const blocked = body.items.find((c) => c.caseId === 'C-000014');
    expect(resolved).toMatchObject({ writes: 1, verification: 'verified' });
    expect(blocked).toMatchObject({ writes: 0, verification: '' });
  });
});

const scenarios = recording.scenarios as unknown as Scenario[];
// The list as the mock sends it: each summary with the writes and the verification counted from its attempts
const summaries = Object.values(recording.cases as unknown as Record<string, { summary: CaseSummary }>).map(
  (c) => ({ ...c.summary, ...writesOf(c as never) }),
);
const scenarioOf = (c: CaseSummary) => scenarios.find((s) => s.id === c.scenario);

describe('whatHappened', () => {
  const at = (headline: string) =>
    whatHappened({ headline, event: 'transfer', ward: 'WARD-B', encounterId: 'ENC-1' });

  it('gives the first sentence in full and keeps the rest for the disclosure', () => {
    const w = at(
      'Resend the transfer to WARD-B unchanged, after rehearsal and approval. Catalogue E16, The destination bed is held by a patient who is leaving.',
    );
    expect(w.first).toBe('Resend the transfer to WARD-B unchanged, after rehearsal and approval.');
    expect(w.rest).toBe('Catalogue E16, The destination bed is held by a patient who is leaving.');
  });

  it('takes the next sentence with one of under six words, so the cell says what happened', () => {
    expect(
      at('Valid message. Do not resend: a later event moved the encounter on. Catalogue E1, Superseded.'),
    ).toEqual({
      first: 'Valid message. Do not resend: a later event moved the encounter on.',
      rest: 'Catalogue E1, Superseded.',
    });
    const escalated = at(
      'Escalated to a person. PAS transfer MSG00802 failed with HTTP 503 ward_unavailable, and there is no receipt (404). The receiver is at v2.',
    );
    expect(escalated.first).toMatch(/^Escalated to a person\. PAS transfer MSG00802 failed/);
    expect(escalated.rest).toBe('The receiver is at v2.');
  });

  it("reads the gate's headline as the checks that failed, and a summary with no headline as its own fields", () => {
    expect(
      at('Blocked by the gate: Blocked: conformance PARSE_FAILED (policy 2026-11-01.1, stage proposal)'),
    ).toEqual({
      first: "Blocked by the gate: the message couldn't be read or mapped to an operation.",
      rest: '',
    });
    expect(at('')).toEqual({ first: 'Transfer to WARD-B for ENC-1', rest: '' });
  });

  it("stops an escalation the server cut at its catalogue entry's title, and keeps the cut text for the disclosure", () => {
    expect(
      at(
        'Escalated to a person. Catalogue E17, Two patients are allocated to one bed: The receiver refused the movement because another encounter holds the destination bed, and no movement out of the bed is known for it (or it…',
      ),
    ).toEqual({
      first: 'Escalated to a person. Catalogue E17, Two patients are allocated to one bed.',
      rest: 'The receiver refused the movement because another encounter holds the destination bed, and no movement out of the bed is known for it (or it…',
    });
    // One the server did not cut reads whole
    const whole =
      'Escalated to a person. Catalogue E14, A patient merge: A merge changes which record a patient belongs to, and only the PAS team may decide it.';
    expect(at(whole).first).toBe(whole);
  });

  it('leaves no first line ending mid-clause on an escalation of the recorded hospital', () => {
    for (const c of summaries)
      if (c.state === 'escalated' && /Catalogue E/.test(c.headline ?? ''))
        expect(whatHappened(c).first).not.toMatch(/…$/);
  });

  it('leaves no first sentence cut with an ellipsis of the page', () => {
    for (const c of summaries) expect(whatHappened(c).first).not.toMatch(/\.\.\.$/);
  });
});

describe('the closed outcomes', () => {
  it('count the recorded cases by outcome, each against its own scenario: the rules-only S8 resend is not a delivery', () => {
    const counts = closedCounts(summaries, scenarioOf);
    const delivered = casesOfGroup(summaries, 'delivered', scenarioOf);
    expect(delivered.map((c) => c.caseId)).not.toContain('C-000021');
    expect(delivered.length).toBe(counts.delivered);
    // Without its scenario the same case would be a verified delivery
    expect(casesOfGroup(summaries, 'delivered', () => undefined).map((c) => c.caseId)).toContain('C-000021');
    expect(counts.delivered).toBeGreaterThan(20);
    expect(counts.nothing).toBeGreaterThan(5);
    expect(counts['by-hand']).toBe(0);
    // S8's wrong write has its own tile: every closed case is in one
    expect(casesOfGroup(summaries, 'unexpected', scenarioOf).map((c) => c.caseId)).toEqual(['C-000021']);
    expect(counts.unexpected).toBe(1);
  });

  it('put a hand fix and an abandoned case in "By hand", and both kinds of nothing to send in one', () => {
    const base = { state: 'resolved', scenario: '' } as CaseSummary;
    const items = [
      { ...base, caseId: 'a', disposition: 'handled_by_hand' },
      { ...base, caseId: 'b', disposition: 'abandoned' },
      { ...base, caseId: 'c', disposition: 'superseded', writes: 0, verification: 'verified' },
      { ...base, caseId: 'd', disposition: 'superseded', writes: 0, verification: '' },
      { ...base, caseId: 'e', disposition: 'resend', writes: 1, verification: 'verified' },
    ] as CaseSummary[];
    expect(closedCounts(items, () => undefined)).toEqual({
      unexpected: 0,
      delivered: 1,
      nothing: 2,
      'by-hand': 2,
    });
  });
});

describe('the technical chips', () => {
  const c = {
    ...base,
    encounterId: 'ENC-1232',
    disposition: 'resend',
    mode: 'policy',
    scenario: 'S23a',
    openedAt: '2026-11-01T05:46:06Z',
    failureKind: 'delivery_failed',
    sourceHeaderId: '31947',
    planCreatedBy: 'policy:E16',
    headline: 'Resend the transfer to WARD-B unchanged, after rehearsal and approval.',
  } as CaseSummary;

  it("show a row's event, failure kind, source header and catalogue entry in Technical only", () => {
    const { unmount } = renderUi(<CasesTable items={[c]} />);
    expect(screen.queryByText('delivery_failed')).not.toBeInTheDocument();
    expect(screen.queryByText('header 31947')).not.toBeInTheDocument();
    expect(screen.getByText('entry E16')).toBeInTheDocument();
    unmount();
    renderUi(<CasesTable items={[c]} />, { detail: 'technical' });
    expect(screen.getByText('transfer')).toBeInTheDocument();
    expect(screen.getByText('delivery_failed')).toBeInTheDocument();
    expect(screen.getByText('header 31947')).toBeInTheDocument();
    expect(screen.getByText('catalogue E16')).toBeInTheDocument();
  });

  it('say nothing for a field the summary does not send', () => {
    renderUi(<CasesTable items={[{ ...c, sourceHeaderId: undefined, planCreatedBy: 'rules' }]} />, {
      detail: 'technical',
    });
    expect(screen.queryByText(/^header /)).not.toBeInTheDocument();
    expect(screen.queryByText(/^catalogue /)).not.toBeInTheDocument();
  });
});

describe('the Technical line: the message, where it came in, the trace and the plan', () => {
  // C-000058 as the trial records it, with the fields the API sends for Technical
  const recorded = recording.cases['C-000058'].summary as unknown as CaseSummary;
  const words = [
    'ADT^A02',
    'MSG02304',
    '409 bed_occupied',
    '14:34:44.605Z',
    'ADT In',
    'Shutter.Production',
    'Shutter.Operation.Ward',
    'session 9625',
    'v1 f1171ecfa9a8',
  ];

  it('adds none of it in Plain', () => {
    const { container } = renderUi(<CasesTable items={[recorded]} />);
    for (const w of words) expect(container).not.toHaveTextContent(w);
    expect(screen.queryByTestId('case-tech')).not.toBeInTheDocument();
    expect(screen.queryByTestId('case-receiver-class')).not.toBeInTheDocument();
  });

  it('shows each fact the server sent in Technical, the session and the header opening their pages in the portal', () => {
    renderUi(<CasesTable items={[recorded]} />, { detail: 'technical' });
    const line = screen.getByTestId('case-tech');
    const message = within(line).getByTestId('case-tech-message');
    // MSH-9 in place of Shutter's event word, then MSH-10, the failure kind, the receiver's answer and when it failed
    expect(message).toHaveTextContent(/^ADT\^A02MSG02304rejected409 bed_occupied14:34:44\.605Z$/);
    expect(within(message).getByText('14:34:44.605Z').closest('time')).toHaveAttribute(
      'dateTime',
      '2026-11-02T14:34:44.605Z',
    );
    expect(within(line).getByTestId('case-tech-source')).toHaveTextContent(/^ADT InShutter\.Production$/);
    const trace = within(line).getByTestId('case-tech-trace');
    expect(trace).toHaveTextContent(/^session 9625 ?header 9625 ?catalogue E16v1 f1171ecfa9a8$/);
    expect(within(trace).getByRole('link', { name: 'session 9625' })).toHaveAttribute(
      'href',
      '/csp/healthshare/shutter/EnsPortal.VisualTrace.zen?SESSIONID=9625',
    );
    expect(within(trace).getByRole('link', { name: 'header 9625' })).toHaveAttribute(
      'href',
      '/csp/healthshare/shutter/EnsPortal.MessageContents.zen?HeaderClass=Ens.MessageHeader&HeaderId=9625',
    );
    expect(screen.getByTestId('case-receiver-class')).toHaveTextContent('Shutter.Operation.Ward');
  });

  it("names a forwarded case's production and route, and guesses no class for a receiver in another production", () => {
    const forwarded = recording.cases['C-000052'].summary as unknown as CaseSummary;
    renderUi(<CasesTable items={[forwarded]} />, { detail: 'technical' });
    expect(screen.getByTestId('case-tech-source')).toHaveTextContent(/^PAS InHospital\.Production$/);
    expect(screen.queryByTestId('case-receiver-class')).not.toBeInTheDocument();
  });

  it('keeps the event word, unlinked ids and no plan for a case the server sent no more of', () => {
    renderUi(
      <CasesTable
        items={[{ ...base, ensSessionId: '77', sourceHeaderId: '78', failureKind: 'delivery_failed' }]}
      />,
      { detail: 'technical' },
    );
    expect(screen.getByTestId('case-tech-message')).toHaveTextContent(/^transferdelivery_failed$/);
    expect(screen.queryByTestId('case-tech-source')).not.toBeInTheDocument();
    const trace = screen.getByTestId('case-tech-trace');
    expect(trace).toHaveTextContent(/^session 77header 78$/);
    expect(within(trace).queryByRole('link')).not.toBeInTheDocument();
  });

  it('leaves out the trace line of a case with no session, header or plan', () => {
    renderUi(<CasesTable items={[{ ...base, ensSessionId: '', sourceHeaderId: '' }]} />, {
      detail: 'technical',
    });
    expect(screen.getByTestId('case-tech')).toBeInTheDocument();
    expect(screen.queryByTestId('case-tech-trace')).not.toBeInTheDocument();
  });

  it("adds nothing of the patient: not the hospital number, the authority or the message's patient fields", () => {
    renderUi(<CasesTable items={[recorded]} />, { detail: 'technical' });
    const line = screen.getByTestId('case-tech');
    for (const w of ['MRN1232', 'HOSP', 'SYNTH', 'BAY2-02']) expect(line).not.toHaveTextContent(w);
  });
});

describe('the rows', () => {
  it('colour each row by what came of the case, and keep the rest of a long headline behind its own button', async () => {
    renderUi(
      <CasesTable
        items={[
          {
            ...base,
            caseId: 'C-000058',
            disposition: 'resend',
            scenario: 'S23a',
            mode: 'policy',
            writes: 1,
            verification: 'verified',
            openedAt: '2026-11-01T05:46:06Z',
            headline:
              'Resend the transfer to WARD-B unchanged, after rehearsal and approval. Catalogue E16, The destination bed is held by a patient who is leaving.',
          } as CaseSummary,
          {
            ...base,
            caseId: 'C-000021',
            disposition: 'resend',
            scenario: 'S8',
            mode: 'rules',
            writes: 1,
            verification: 'verified',
            openedAt: '2026-10-20T17:31:00Z',
          } as CaseSummary,
          {
            ...base,
            caseId: 'C-000099',
            state: 'escalated',
            disposition: 'escalate',
            mode: 'board',
            openedAt: '2026-10-20T17:31:00Z',
          } as CaseSummary,
        ]}
        scenarios={scenarios}
      />,
    );
    const row = (id: string) => screen.getByRole('link', { name: id }).closest('tr')!;
    expect(row('C-000058')).toHaveAttribute('data-tone', 'positive');
    expect(within(row('C-000058')).getByText('Delivered, verified')).toBeInTheDocument();
    // The rules-only S8 resend was verified too, but it is not what S8 expects
    expect(row('C-000021')).toHaveAttribute('data-tone', 'blocking');
    expect(within(row('C-000021')).getByText('Not as expected')).toBeInTheDocument();
    expect(row('C-000099')).toHaveAttribute('data-tone', 'attention');

    const first = within(row('C-000058'));
    const more = first.getByRole('button', { name: 'More about C-000058' });
    expect(more).toHaveAttribute('aria-expanded', 'false');
    expect(
      first.getByText('Resend the transfer to WARD-B unchanged, after rehearsal and approval.'),
    ).toBeVisible();
    await userEvent.click(more);
    expect(more).toHaveAttribute('aria-expanded', 'true');
    await waitFor(() => expect(first.getByText(/^Catalogue E16, The destination bed is held/)).toBeVisible());
    // A case whose headline is one short sentence has no disclosure
    expect(within(row('C-000021')).queryByRole('button', { name: /^More about/ })).not.toBeInTheDocument();
  });

  it('carry the phone card hooks: the sentence and the facts are cells of their own', () => {
    renderUi(<CasesTable items={[{ ...base, disposition: 'resend', mode: 'board' } as CaseSummary]} />);
    const row = screen.getByRole('link', { name: 'C-000123' }).closest('tr')!;
    const cells = within(row).getAllByRole('cell');
    expect(cells[4]).toHaveClass('case-line');
    expect(cells.filter((c) => c.classList.contains('case-meta'))).toHaveLength(3);
    expect(cells[2]).toHaveClass('case-last');
  });
});

describe('the page', () => {
  beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
  afterEach(() => server.resetHandlers());
  afterAll(() => server.close());
  beforeEach(() => resetMock('approver'));

  const renderPage = (options: Parameters<typeof renderUi>[1] = {}) =>
    renderUi(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <CasesPage />
      </QueryClientProvider>,
      options,
    );

  const closedTile = (name: RegExp) => screen.findByRole('button', { name });

  it('counts the closed cases by outcome over the newest 100, and says nothing of a base when it holds them all', async () => {
    renderPage();
    const closed = await screen.findByRole('region', { name: 'Closed' });
    // The trial holds C-000002 at its approval, so one fewer delivery than the 27 that wrote and were verified
    expect(
      await within(closed).findByRole('button', { name: /^26 Delivered, verified Show these$/ }),
    ).toBeVisible();
    expect(within(closed).getByRole('button', { name: /^12 Nothing to send Show these$/ })).toBeVisible();
    expect(within(closed).getByRole('button', { name: /^0 By hand Show these$/ })).toBeVisible();
    expect(screen.queryByText(/in the newest 100/)).not.toBeInTheDocument();
    // Needs a person: the API's own totals
    const need = screen.getByRole('region', { name: 'Needs a person' });
    expect(
      await within(need).findByRole('button', { name: /^1 Waiting for approval Show these$/ }),
    ).toBeVisible();
    expect(within(need).getByRole('button', { name: /^15 Escalated Show these$/ })).toBeVisible();
    expect(within(need).getByRole('button', { name: /^9 Blocked Show these$/ })).toBeVisible();
  });

  it('counts a failed case under Needs a person, and not one a person gave up', async () => {
    server.use(
      http.get('/api/shutter/cases', ({ request }) => {
        if (new URL(request.url).searchParams.get('state') !== 'failed') return undefined;
        return HttpResponse.json({
          items: [
            { caseId: 'C-1', state: 'failed', disposition: '' },
            { caseId: 'C-2', state: 'failed', disposition: 'abandoned' },
          ],
          total: 2,
        });
      }),
    );
    renderPage();
    const need = await screen.findByRole('region', { name: 'Needs a person' });
    expect(await within(need).findByRole('button', { name: /^1 Failed Show these$/ })).toBeVisible();
  });

  it("takes a case's receiver kind from the site profile the app already reads: a FHIR case is one FHIR update", async () => {
    const view = recordedSiteProfile()!;
    view.profile.receivers = [
      ...view.profile.receivers,
      { name: 'FHIR Encounters', tier: 1, fhir: { base: '/fhir/r4' } as FhirReceiverSettings },
    ];
    server.use(
      http.get('/api/shutter/site-profile', () => HttpResponse.json(view)),
      http.get('/api/shutter/cases', ({ request }) => {
        if (new URL(request.url).searchParams.get('state')) return undefined;
        return HttpResponse.json({
          items: [
            {
              caseId: 'C-F1',
              state: 'awaiting_approval',
              disposition: 'resend',
              receiver: 'FHIR Encounters',
            },
            { caseId: 'C-B1', state: 'awaiting_approval', disposition: 'resend', receiver: 'Bed Manager' },
          ],
          total: 2,
        });
      }),
    );
    renderPage();
    const fhirRow = (await screen.findByRole('link', { name: 'C-F1' })).closest('tr')!;
    expect(await within(fhirRow).findByText('One FHIR update')).toBeInTheDocument();
    expect(within(fhirRow).queryByText('Resend')).not.toBeInTheDocument();
    const otherRow = screen.getByRole('link', { name: 'C-B1' }).closest('tr')!;
    expect(within(otherRow).getByText('Resend')).toBeInTheDocument();
  });

  it('shows no Failed tile while no case failed', async () => {
    renderPage();
    const need = await screen.findByRole('region', { name: 'Needs a person' });
    await within(need).findByRole('button', { name: /^9 Blocked Show these$/ });
    await screen.findByText('64 cases');
    expect(within(need).queryByRole('button', { name: /Failed/ })).not.toBeInTheDocument();
  });

  it('shows the list with an Outcome column, C-000021 as not what its scenario expects, and the count of cases', async () => {
    renderPage();
    const table = await screen.findByRole('table');
    expect(within(table).getByRole('columnheader', { name: 'Outcome' })).toBeVisible();
    expect(within(table).queryByRole('columnheader', { name: 'State' })).not.toBeInTheDocument();
    expect(await screen.findByText('64 cases')).toBeVisible();
    // The newest 25 are shown; C-000021 is older, so find it by its scenario
    await userEvent.selectOptions(screen.getByLabelText('Scenario', { exact: true }), 'S8');
    const row = (await screen.findByRole('link', { name: 'C-000021' })).closest('tr')!;
    expect(row).toHaveAttribute('data-tone', 'blocking');
    expect(within(row).getByText('Not as expected')).toBeInTheDocument();
  });

  it('filters the list to a closed outcome from the same read, and a second press shows every case again', async () => {
    renderPage();
    const tile = await closedTile(/^26 Delivered, verified Show these$/);
    expect(tile).toHaveAttribute('aria-pressed', 'false');
    await userEvent.click(tile);
    expect(await screen.findByText('26 cases')).toBeVisible();
    expect(tile).toHaveAttribute('aria-pressed', 'true');
    expect(tile).toHaveAccessibleName('26 Delivered, verified Showing these; press to clear');
    const rows = () => screen.getAllByRole('row').slice(1);
    await waitFor(() => expect(rows()).toHaveLength(25));
    for (const r of rows()) expect(within(r).getAllByText('Delivered, verified').length).toBeGreaterThan(0);
    expect(screen.queryByText(/among the 100 most recent cases/)).not.toBeInTheDocument();
    // The 26th is on the second page
    await userEvent.click(screen.getByRole('button', { name: 'Page 2' }));
    await waitFor(() => expect(rows()).toHaveLength(1));
    await userEvent.click(tile);
    expect(await screen.findByText('64 cases')).toBeVisible();
    expect(tile).toHaveAttribute('aria-pressed', 'false');
  });

  it('puts an attention tile and a closed outcome on the list one at a time', async () => {
    renderPage();
    const escalated = await screen.findByRole('button', { name: /^15 Escalated Show these$/ });
    await userEvent.click(escalated);
    expect(await screen.findByText('15 cases')).toBeVisible();
    const delivered = await closedTile(/^26 Delivered, verified Show these$/);
    await userEvent.click(delivered);
    expect(await screen.findByText('26 cases')).toBeVisible();
    expect(delivered).toHaveAttribute('aria-pressed', 'true');
    expect(screen.getByRole('button', { name: /^15 Escalated Show these$/ })).toHaveAttribute(
      'aria-pressed',
      'false',
    );
  });

  it('states its base when there are more than 100 cases: the closed tiles count the newest 100 only', async () => {
    const many = Array.from({ length: 120 }, (_, i) => ({
      ...summaries.find((c) => c.caseId === 'C-000058')!,
      caseId: `C-${String(900 + i).padStart(6, '0')}`,
      openedAt: new Date(Date.UTC(2026, 10, 1, 5, 0, 0) - i * 60_000).toISOString(),
    }));
    server.use(
      http.get('/api/shutter/cases', ({ request }) => {
        const q = new URL(request.url).searchParams;
        const state = q.get('state');
        const rows = many.filter((c) => !state || c.state === state);
        const offset = Number(q.get('offset') ?? 0);
        return HttpResponse.json({
          items: rows.slice(offset, offset + Number(q.get('limit') ?? 25)),
          total: rows.length,
        });
      }),
    );
    renderPage();
    const closed = await screen.findByRole('region', { name: 'Closed, in the newest 100' });
    const tile = await within(closed).findByRole('button', { name: /^100 Delivered, verified Show these$/ });
    expect(screen.queryByText(/among the 100 most recent cases/)).not.toBeInTheDocument();
    await userEvent.click(tile);
    // The count with its scope, once: the bare "100 cases" would read as every case with this outcome
    expect(
      await screen.findByText(
        '100 matches among the 100 most recent cases. Older cases have not been searched.',
      ),
    ).toBeVisible();
    expect(screen.queryByText('100 cases')).not.toBeInTheDocument();
  });

  it('hides the Not as expected tile at nought, as on a hospital that never played S8 by rules alone', async () => {
    const rest = summaries.filter((c) => c.caseId !== 'C-000021');
    server.use(
      http.get('/api/shutter/cases', ({ request }) => {
        const q = new URL(request.url).searchParams;
        const state = q.get('state');
        const rows = rest.filter((c) => !state || c.state === state);
        const offset = Number(q.get('offset') ?? 0);
        return HttpResponse.json({
          items: rows.slice(offset, offset + Number(q.get('limit') ?? 25)),
          total: rows.length,
        });
      }),
    );
    const { container } = renderPage();
    const closed = await screen.findByRole('region', { name: 'Closed' });
    await within(closed).findByRole('button', { name: /Delivered, verified Show these$/ });
    expect(within(closed).queryByRole('button', { name: /Not as expected/ })).not.toBeInTheDocument();
    expect(container.querySelector('.cases-tile-groups')).toHaveAttribute('data-closed', '3');
  });

  it('keeps its words above the table within the budget, and Technical within one and a half times the Plain page', async () => {
    const plain = renderPage();
    const table = await plain.findByRole('table');
    await plain.findByText('64 cases');
    // Everything above the table: the lead, the tiles, the filters and the count. The colour key is a legend, counted
    // apart; a native select shows its chosen option only, not the list it opens
    const above = (c: HTMLElement) => {
      const range = document.createRange();
      range.setStart(c, 0);
      const card = c.querySelector('[data-tour="cases-list"]')!;
      let wrapper = c.querySelector('table')!.parentElement!;
      while (wrapper.parentElement !== card) wrapper = wrapper.parentElement!;
      range.setEndBefore(wrapper);
      const box = document.createElement('div');
      box.appendChild(range.cloneContents());
      box.querySelectorAll('ul[aria-label="What the colours mean"]').forEach((e) => e.remove());
      box.querySelectorAll('select').forEach((select) => {
        const chosen = select.selectedOptions[0]?.textContent ?? '';
        select.replaceWith(document.createTextNode(chosen));
      });
      return layer1WordCount(box);
    };
    expect(table).toBeVisible();
    const plainAbove = above(plain.container);
    const plainPage = layer1WordCount(plain.container);
    plain.unmount();
    const technical = renderPage({ detail: 'technical' });
    await technical.findByRole('table');
    await technical.findByText('64 cases');
    const technicalAbove = above(technical.container);
    const technicalPage = layer1WordCount(technical.container);
    // The spec's budget for the list above the table is 60 words (it was 110)
    expect(plainAbove).toBeLessThanOrEqual(60);
    expect(technicalAbove).toBeLessThanOrEqual(90);
    expect(technicalPage).toBeLessThanOrEqual(plainPage * 1.5);
    expect(technicalPage).toBeGreaterThan(plainPage);
  });
});
