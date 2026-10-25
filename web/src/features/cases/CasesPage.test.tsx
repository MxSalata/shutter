import { MantineProvider } from '@mantine/core';
import { render, screen, within } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import type { CaseSummary } from '@/api/types';
import { theme } from '@/theme';
import { MemoryRouter } from 'react-router';
import { CasesTable, ForwardedBadge, InvestigatedBy, investigatedBy } from './CasesPage';

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
    ).toEqual(['Case', 'State', 'Proposed action', 'What failed', 'Scenario', 'Investigated by', 'Opened']);
    const row = within(table).getByRole('link', { name: 'C-000123' }).closest('tr')!;
    expect(row).toHaveAttribute('role', 'row');
    const cells = within(row).getAllByRole('cell');
    // The first cell is the case id, the card's title on a phone; every other one carries its column's name
    expect(cells[0]).not.toHaveAttribute('data-label');
    expect(cells.slice(1).map((c) => c.getAttribute('data-label'))).toEqual([
      'State',
      'Proposed action',
      'What failed',
      'Scenario',
      'Investigated by',
      'Opened',
    ]);
  });
});
