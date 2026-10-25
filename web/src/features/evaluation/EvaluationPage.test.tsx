import { MantineProvider } from '@mantine/core';
import { render, screen, within } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import evaluation from '../../../../docs/readme/evaluation.json';
import boundary from '../../../../docs/readme/boundary.json';
import { theme } from '@/theme';
import type { Evaluation } from './evaluation';
import EvaluationPage from './EvaluationPage';

/** The page needs no API: the evaluation is read from the repository's documents at build time. */
function renderPage(data?: Evaluation) {
  return render(
    <MantineProvider theme={theme}>
      <EvaluationPage data={data} />
    </MantineProvider>,
  );
}

const recorded = evaluation as unknown as Evaluation;

describe('EvaluationPage', () => {
  it('says plainly where the figures come from', () => {
    renderPage();
    expect(screen.getByRole('heading', { name: 'Evaluation' })).toBeInTheDocument();
    expect(
      screen.getByText(/^Every figure here comes from the recorded live runs of 25 October 2026: 56 runs/),
    ).toBeInTheDocument();
    expect(screen.getByText(/Nothing on this page was measured on this instance/)).toBeInTheDocument();
  });

  it('gives the board against the expected outcome, the agreement, the tokens and the cost', () => {
    renderPage();
    expect(screen.getByText(/^13 of 13 scored passes/)).toBeInTheDocument();
    expect(screen.getByText(/^unanimous in 7, with the majority in 7/)).toBeInTheDocument();
    expect(screen.getByText(/1,033,046 uncached input/)).toBeInTheDocument();
    expect(screen.getByText(/\$5\.38 at list prices/)).toBeInTheDocument();
  });

  it('sets rules alone beside the board played end to end on the same passes, apart from the proposed action', () => {
    renderPage();
    const headline = screen.getByRole('region', { name: 'The board against the expected outcome' });
    expect(within(headline).getByText('13 of 13')).toBeInTheDocument();
    expect(
      within(headline).getByText("scored passes proposed the scenario's expected action"),
    ).toBeInTheDocument();
    expect(within(headline).getByText('4 of 11')).toBeInTheDocument();
    expect(
      within(headline).getByText(
        'scored passes played end to end with rules alone, no agents, ended as expected; played the same way, the board ended as expected in 11 of the same 11',
      ),
    ).toBeInTheDocument();
    expect(headline).not.toHaveTextContent('same scenarios');
  });

  it('says so when no scored pass was played with rules alone', () => {
    renderPage({ ...recorded, passes: recorded.passes.map((p) => ({ ...p, played: {} })) });
    const headline = screen.getByRole('region', { name: 'The board against the expected outcome' });
    expect(within(headline).getByText('Not played')).toBeInTheDocument();
    expect(within(headline).getByText('no scored pass was played with rules alone')).toBeInTheDocument();
  });

  it("puts the totals under the table's own columns: the cost under Cost and tokens, the time under Elapsed", () => {
    renderPage();
    const table = screen.getByRole('region', { name: 'Per scenario' });
    const headers = within(table).getAllByRole('columnheader');
    const columns = headers.map((h) => h.textContent);
    const total = within(table).getByRole('rowheader', { name: 'Total' }).closest('tr')!;
    // Each cell starts at the column after the cells before it, counting their spans
    let at = 0;
    const starts = Array.from(total.children).map((c) => {
      const start = at;
      at += (c as HTMLTableCellElement).colSpan;
      return start;
    });
    expect(at).toBe(columns.length);
    const [cost, time] = Array.from(total.children).slice(-2);
    expect(columns[starts[starts.length - 2]]).toBe('Cost and tokens');
    expect(cost).toHaveTextContent('$5.38');
    expect(columns[starts[starts.length - 1]]).toBe('Elapsed');
    expect(time).toHaveTextContent('of agent time');
  });

  it('keeps the table, its column headers and its cells announced when it stacks on a phone', () => {
    renderPage();
    const region = screen.getByRole('region', { name: 'Per scenario' });
    const table = within(region).getByRole('table');
    expect(table).toHaveAttribute('role', 'table');
    expect(within(table).getAllByRole('rowgroup')).toHaveLength(2);
    expect(within(table).getByRole('columnheader', { name: 'Expected' })).toHaveAttribute(
      'role',
      'columnheader',
    );
    const row = within(table).getByText('S8').closest('tr')!;
    expect(row).toHaveAttribute('role', 'row');
    const cells = within(row).getAllByRole('cell');
    expect(cells.every((c) => c.getAttribute('role') === 'cell')).toBe(true);
    // Every cell but the first, which names the pass, carries its column's name for the stacked layout
    expect(cells.slice(1).map((c) => c.getAttribute('data-label'))).toEqual([
      'Expected',
      'Conformance',
      'Encounter',
      'Impact',
      'Plan',
      'Entry',
      'Agreement',
      'Cost and tokens',
      'Elapsed',
    ]);
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
    expect(cells[8]).toHaveTextContent('$0.37');
    expect(cells[9]).toHaveTextContent('30.9 s');
    const unscored = within(table).getByText('S7 pass 1').closest('tr')!;
    expect(unscored).toHaveTextContent('Not scored: planned again after the change');
    expect(within(table).getByText('S11 ENC-1103 transfer')).toBeInTheDocument();
  });

  it('marks nothing in a pass that is not scored, as the document does', () => {
    renderPage();
    const table = screen.getByRole('region', { name: 'Per scenario' });
    // Every member said resend, which the scenario's later expectation does not match
    const unscored = within(table).getByText('S7 pass 1').closest('tr')!;
    expect(within(unscored).getAllByText('Resend')).toHaveLength(4);
    expect(unscored).not.toHaveTextContent('outweighed');
    expect(unscored).not.toHaveTextContent('differs');
    // The pass after the change is scored: conformance's resend was set aside, and the plan is the expected one
    const scored = within(table).getByText('S7 pass 2').closest('tr')!;
    const cells = within(scored).getAllByRole('cell');
    expect(cells[2]).toHaveTextContent('outweighed');
    expect(cells[3]).not.toHaveTextContent('outweighed');
    expect(cells[5]).not.toHaveTextContent('differs');
  });

  it('reads an empty confidence group and an evaluation with no recordings, as the script can write them', () => {
    const allAgreed: Evaluation = {
      ...recorded,
      totals: { ...recorded.totals, confidence: { ...recorded.totals.confidence, differed: { n: 0 } } },
    };
    const { unmount } = renderPage(allAgreed);
    expect(
      screen.getByText(/the findings with the expected outcome: 32, from 0\.70 to 0\.95/),
    ).toHaveTextContent(/and those another view outweighed: none$/);
    unmount();

    const none: Evaluation = {
      ...recorded,
      passes: [],
      totals: {
        ...recorded.totals,
        runs: 0,
        passes: 0,
        cases: 0,
        scenarios: 0,
        scored_passes: 0,
        board_matches: 0,
        models: [],
        recorded_from: '',
        recorded_to: '',
        confidence: { matched: { n: 0 }, differed: { n: 0 } },
      },
    };
    renderPage(none);
    expect(
      screen.getByText(
        /^There are no recorded live runs to evaluate yet: scripts\/evaluate\.py found none\./,
      ),
    ).toBeInTheDocument();
    expect(screen.getByText(/^the findings with the expected outcome: none/)).toBeInTheDocument();
    expect(screen.getByText('No scored passes')).toBeInTheDocument();
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

  it('lists what the boundary refuses, each attempt with its scenario, its answer and what it proves', () => {
    renderPage();
    const section = screen.getByRole('region', { name: 'What the boundary refuses' });
    expect(
      within(section).getByText(/^What tests\/e2e\/boundary_check\.py tries over HTTP/),
    ).toBeInTheDocument();
    const rows = within(section).getAllByRole('row').slice(1);
    expect(rows).toHaveLength(boundary.checks.length);
    const digest = within(section)
      .getByText('An approval of a plan that is not the one shown')
      .closest('tr')!;
    expect(digest).toHaveTextContent('S2, rules only');
    expect(digest).toHaveTextContent('409 stale_version');
    const receiver = within(section)
      .getByText('The receiving system changed after the approval')
      .closest('tr')!;
    expect(receiver).toHaveTextContent('S20, rules only');
    expect(receiver).toHaveTextContent('APPROVAL_RECEIVER_CHANGED, no write');
  });
});
