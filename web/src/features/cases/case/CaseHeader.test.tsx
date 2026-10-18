import { MantineProvider } from '@mantine/core';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it } from 'vitest';
import type { CaseDetail } from '@/api/types';
import { theme } from '@/theme';
import { CaseHeader } from './CaseHeader';

const base = { caseId: 'C-000123', state: 'resolved', event: 'transfer', ward: 'WARD-B' } as CaseDetail;

function renderHeader(c: CaseDetail) {
  return render(
    <MantineProvider theme={theme}>
      <MemoryRouter>
        <CaseHeader c={c} />
      </MemoryRouter>
    </MantineProvider>,
  );
}

describe('CaseHeader', () => {
  it('flags a case no catalogue entry fits', () => {
    renderHeader({ ...base, candidateEntry: true });
    expect(screen.getByText('New pattern')).toBeInTheDocument();
  });

  it('links a case to the incident that holds it, with its place in the chain', () => {
    renderHeader({
      ...base,
      incidentId: 'I-000001',
      incident: {
        incident_id: 'I-000001',
        incident_state: 'closed',
        chain_seq: 2,
        position: 1,
        chain_kind: 'ordered',
        item_state: 'resolved',
      },
    });
    expect(screen.getByRole('link', { name: 'I-000001' })).toHaveAttribute('href', '/incidents/I-000001');
    expect(screen.getByText('chain 2, item 1 · ordered · resolved')).toBeInTheDocument();
  });

  it('says nothing about the catalogue when an entry fits', () => {
    renderHeader({ ...base, candidateEntry: false });
    expect(screen.queryByText('New pattern')).not.toBeInTheDocument();
  });
});
