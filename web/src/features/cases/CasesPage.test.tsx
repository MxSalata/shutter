import { MantineProvider } from '@mantine/core';
import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import type { CaseSummary } from '@/api/types';
import { theme } from '@/theme';
import { ForwardedBadge, InvestigatedBy, investigatedBy } from './CasesPage';

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

  it('falls back to the mode when the server sends no plan origin', () => {
    expect(at('board')).toEqual({ who: 'Board' });
    expect(at('single')).toEqual({ who: 'Single investigator' });
    expect(at('rules')).toEqual({ who: 'Rules only' });
    expect(at('policy')).toEqual({ who: 'Site policy' });
    expect(at('board', { failureKind: 'withheld' })).toEqual({ who: 'Site policy' });
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
