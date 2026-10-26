import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { server } from '@/mocks/node';
import { resetMock } from '@/mocks/handlers';
import recording from '@/mocks/fixtures.json';
import { ToneLegend } from '@/components/ToneLegend';
import type { CaseSummary } from '@/api/types';
import { theme } from '@/theme';
import { MemoryRouter } from 'react-router';
import {
  AttentionTile,
  CasesTable,
  ForwardedBadge,
  InvestigatedBy,
  investigatedBy,
  proposalNote,
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
  const at = (mode: CaseSummary['mode'], more: Partial<CaseSummary> = {}) =>
    investigatedBy({ ...base, mode, ...more });

  it("reads the plan's origin: an agent run is the board's, or the single investigator's", () => {
    expect(at('board', { planCreatedBy: 'run:8' })).toEqual({ who: 'Board' });
    expect(at('single', { planCreatedBy: 'run:3' })).toEqual({ who: 'Single investigator' });
    // In site-policy mode the catalogue left this case to the board
    expect(at('policy', { planCreatedBy: 'run:56' })).toEqual({ who: 'Board' });
  });

  it('names the catalogue entry the site policy settled a case with', () => {
    expect(at('policy', { planCreatedBy: 'policy:E2' })).toEqual({ who: 'Site policy', entry: 'E2' });
    // A withheld merge is the policy's whatever the mode
    expect(at('board', { planCreatedBy: 'policy:E14', failureKind: 'withheld' })).toEqual({
      who: 'Site policy',
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
    expect(screen.getByText('Site policy')).toBeInTheDocument();
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
      'State',
      'Proposed action',
      'At the receiver',
      'What failed',
      'Scenario',
      'Investigated by',
    ]);
    const row = within(table).getByRole('link', { name: 'C-000123' }).closest('tr')!;
    expect(row).toHaveAttribute('role', 'row');
    const cells = within(row).getAllByRole('cell');
    // The first cell is the case id, the card's title on a phone; every other one carries its column's name
    expect(cells[0]).not.toHaveAttribute('data-label');
    expect(cells.slice(1).map((c) => c.getAttribute('data-label'))).toEqual([
      'State',
      'Proposed action',
      'At the receiver',
      'What failed',
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
