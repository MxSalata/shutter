import { screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { renderUi } from '@/test/render';
import { ProofLine } from './ProofLine';

const board = { matched: 24, scored: 24, passes: 25, cases: 24, notScored: 1 };
const played = { of: 11, board: 11, rules: 4, scenarios: [] };

describe('ProofLine', () => {
  it('is left out when the evaluation gives neither figure', () => {
    const { container } = renderUi(<ProofLine proof={{ board: null, played: null }} />);
    expect(container.querySelector('[data-proof-line]')).toBeNull();
    expect(screen.queryByRole('link')).not.toBeInTheDocument();
  });

  it('says the played comparison on its own base when the scored passes are missing', () => {
    renderUi(<ProofLine proof={{ board: null, played }} />);
    expect(screen.getByText(/^Played end to end on 11 one-failure scenarios/)).toBeInTheDocument();
    expect(screen.queryByText(/^Tested on/)).not.toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'See the evaluation' })).toHaveAttribute('href', '/evaluation');
  });

  it('says what each figure counts: recorded cases from fewer scenarios, then the one-failure scenarios played', () => {
    const { container } = renderUi(<ProofLine proof={{ board: { ...board, scenarios: 19 }, played }} />);
    expect(container.querySelector('[data-proof-line]')).toHaveTextContent(
      'Tested on 24 recorded cases from 19 scenarios (an incident gives several), the board chose the expected action every time. Played end to end on 11 one-failure scenarios:',
    );
  });

  it('names the bases only in Technical', () => {
    renderUi(<ProofLine proof={{ board, played }} />, { detail: 'technical' });
    expect(
      screen.getByText(/\(24 scored passes, proposed action; 11 scenarios, played end to end\)/),
    ).toBeInTheDocument();
  });
});
