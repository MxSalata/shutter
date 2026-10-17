import { MantineProvider } from '@mantine/core';
import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import type { CaseDetail } from '@/api/types';
import { theme } from '@/theme';
import { CaseHeader } from './CaseHeader';

const base = { caseId: 'C-000123', state: 'resolved', event: 'transfer', ward: 'WARD-B' } as CaseDetail;

function renderHeader(c: CaseDetail) {
  return render(
    <MantineProvider theme={theme}>
      <CaseHeader c={c} />
    </MantineProvider>,
  );
}

describe('CaseHeader', () => {
  it('flags a case no catalogue entry fits', () => {
    renderHeader({ ...base, candidateEntry: true });
    expect(screen.getByText('New pattern')).toBeInTheDocument();
  });

  it('says nothing about the catalogue when an entry fits', () => {
    renderHeader({ ...base, candidateEntry: false });
    expect(screen.queryByText('New pattern')).not.toBeInTheDocument();
  });
});
