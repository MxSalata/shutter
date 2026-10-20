import { MantineProvider } from '@mantine/core';
import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import type { CaseSummary } from '@/api/types';
import { theme } from '@/theme';
import { ForwardedBadge } from './CasesPage';

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
