import { MantineProvider } from '@mantine/core';
import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import type { CaseDetail, CaseEvent } from '@/api/types';
import { theme } from '@/theme';
import { Lifecycle } from './Lifecycle';

const step = (seq: number, fromState: string, toState: string): CaseEvent => ({
  seq,
  at: '2026-11-09T19:00:00Z',
  kind: 'state',
  fromState,
  toState,
  text: '',
  actor: 'system',
  ref: '',
});

/** A lab case its own plan escalated, then resolved by the outage resend (no write of its own). */
const events = [
  step(1, 'detected', 'collecting'),
  step(2, 'collecting', 'investigating'),
  step(3, 'investigating', 'proposed'),
  step(4, 'proposed', 'gated'),
  step(5, 'gated', 'escalated'),
  step(6, 'escalated', 'resolved'),
];

const lab = (resends: CaseDetail['resends']) =>
  ({ caseId: 'C-000057', state: 'resolved', disposition: 'escalate', resends }) as unknown as CaseDetail;

function renderStrip(c: CaseDetail) {
  return render(
    <MantineProvider theme={theme}>
      <Lifecycle c={c} events={events} />
    </MantineProvider>,
  );
}

describe('Lifecycle of a message resent with its outage', () => {
  it('shows the approval, the send and the settled new header the outage card made, not "not needed"', () => {
    renderStrip(lab([{ runId: 'R8-3', position: 3, state: 'completed', closure: 'sent' }]));
    expect(screen.getByText('approved on the outage (R8-3)')).toBeInTheDocument();
    expect(screen.getByText('resent by the engine')).toBeInTheDocument();
    expect(screen.getByText('new header Completed')).toBeInTheDocument();
    // The rehearsal really was not needed
    expect(screen.getByText('not needed')).toBeInTheDocument();
  });

  it('keeps "not needed" where nothing was resent', () => {
    renderStrip(lab([]));
    expect(screen.getAllByText('not needed').length).toBeGreaterThanOrEqual(3);
    expect(screen.queryByText(/approved on the outage/)).toBeNull();
  });
});
