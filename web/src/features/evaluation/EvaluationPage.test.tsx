import { MantineProvider } from '@mantine/core';
import { render, screen, within } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { theme } from '@/theme';
import EvaluationPage from './EvaluationPage';

/** The page needs no API: the evaluation is read from the repository's documents at build time. */
function renderPage() {
  return render(
    <MantineProvider theme={theme}>
      <EvaluationPage />
    </MantineProvider>,
  );
}

describe('EvaluationPage', () => {
  it('says plainly where the figures come from', () => {
    renderPage();
    expect(screen.getByRole('heading', { name: 'Evaluation' })).toBeInTheDocument();
    expect(
      screen.getByText(/^Every figure here comes from the recorded live runs of 19 October 2026: 56 runs/),
    ).toBeInTheDocument();
    expect(screen.getByText(/Nothing on this page was measured on this instance/)).toBeInTheDocument();
  });

  it('gives the board against the expected outcome, the agreement, the tokens and the cost', () => {
    renderPage();
    expect(screen.getByText(/^13 of 13 scored passes/)).toBeInTheDocument();
    expect(screen.getByText(/^unanimous in 7, with the majority in 6/)).toBeInTheDocument();
    expect(screen.getByText(/1,010,261 uncached input/)).toBeInTheDocument();
    expect(screen.getByText(/\$5\.31 at list prices/)).toBeInTheDocument();
  });

  it("shows each member's disposition and confidence per pass, and marks a view the plan set aside", () => {
    renderPage();
    const table = screen.getByRole('region', { name: 'Per scenario' });
    const row = within(table).getByText('S8').closest('tr')!;
    const cells = within(row).getAllByRole('cell');
    expect(cells[1]).toHaveTextContent('Escalate (or more evidence)');
    expect(cells[2]).toHaveTextContent('Resend');
    expect(cells[2]).toHaveTextContent('confidence 80% · outweighed');
    expect(cells[3]).toHaveTextContent('Escalate');
    expect(cells[3]).toHaveTextContent('confidence 85%');
    expect(cells[5]).toHaveTextContent('Escalate');
    expect(cells[6]).toHaveTextContent('E7 (board)');
    expect(cells[7]).toHaveTextContent('with the majority');
    expect(cells[9]).toHaveTextContent('$0.37');
    expect(cells[10]).toHaveTextContent('31.3 s');
    const unscored = within(table).getByText('S7 pass 1').closest('tr')!;
    expect(unscored).toHaveTextContent('Not scored: planned again after the change');
    expect(within(table).getByText('S11 ENC-1103 transfer')).toBeInTheDocument();
  });

  it("lists the document's Not yet measured items and the scenarios with no recordings", () => {
    renderPage();
    const notYet = screen.getByRole('region', { name: 'Not yet measured' });
    expect(within(notYet).getAllByRole('listitem').length).toBeGreaterThanOrEqual(4);
    expect(within(notYet).getByText('Repeat runs.')).toBeInTheDocument();
    const without = screen.getByRole('region', { name: 'Scenarios with no board recordings' });
    expect(
      within(without).getByText(/withheld before any agent runs \(MERGE_WITHHELD\)/),
    ).toBeInTheDocument();
  });
});
