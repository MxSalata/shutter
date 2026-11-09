import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import evaluation from '../../../../docs/readme/evaluation.json';
import boundary from '../../../../docs/readme/boundary.json';
import { server } from '@/mocks/node';
import { resetMock } from '@/mocks/handlers';
import { useAppearance } from '@/stores/appearance';
import { layer1Words } from '@/test/words';
import { theme } from '@/theme';
import type { DetailLevel } from '@/env/mode';
import { outweighedIn, passName, type Evaluation } from './evaluation';
import EvaluationPage from './EvaluationPage';
import { HELD_OUT } from './heldOut';

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
beforeEach(() => resetMock('approver'));

/**
 * The page reads the evaluation from the repository's documents at build time; only the links to the recorded cases
 * come from the API (the newest 100 cases, from the mock).
 */
function renderPage(
  data?: Evaluation,
  { path = '/evaluation', detail = 'plain' }: { path?: string; detail?: DetailLevel } = {},
) {
  useAppearance.setState({ detail });
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <MemoryRouter initialEntries={[path]}>
          <EvaluationPage data={data} />
        </MemoryRouter>
      </QueryClientProvider>
    </MantineProvider>,
  );
}

const recorded = evaluation as unknown as Evaluation;
const headline = () => screen.getByRole('region', { name: 'The board against the expected outcome' });
const table = () => screen.getByRole('region', { name: 'Per scenario' });
/** The passes the table shows, by name, in its order (the header row and the Total row aside). */
const shownPasses = () =>
  within(within(table()).getByRole('table'))
    .getAllByRole('row')
    .slice(1, -1)
    .map((r) => r.querySelector('td')?.firstElementChild?.textContent);

/** What a reader sees of an element: its text without what is hidden in it (a term's definition). */
function visible(el: Element | null): string {
  const copy = el!.cloneNode(true) as Element;
  for (const h of copy.querySelectorAll('[hidden]')) h.remove();
  return (copy.textContent ?? '').replace(/\s+/g, ' ').trim();
}

/**
 * The first-layer words above the per-scenario table (the page's header, the headline and How the specialists differed), all of them,
 * and the copy alone: specs/evaluation.md 3 budgets the copy (the lead, the sentences, the captions and the lines),
 * not the headings, the controls' labels and the figures, which `copy` leaves out.
 */
function wordsAbove(container: HTMLElement): { all: number; copy: number } {
  const above = container.cloneNode(true) as HTMLElement;
  const passes = above.querySelector('[data-tour="evaluation-table"]')!;
  for (let node: Element = passes; node !== above && node.parentElement; node = node.parentElement)
    while (node.nextElementSibling) node.nextElementSibling.remove();
  passes.remove();
  const all = layer1Words(above).length;
  for (const el of above.querySelectorAll('h1, h2, h3, button, .stat-figure, .comparison-bars')) el.remove();
  return { all, copy: layer1Words(above).length };
}

describe('EvaluationPage', () => {
  it('says plainly where the figures come from: the real agents, IRIS AI Hub and its build, and CI', () => {
    renderPage();
    expect(screen.getByRole('heading', { name: 'Evaluation', level: 1 })).toBeInTheDocument();
    expect(screen.getByText('How the board decides, measured on recorded runs.')).toBeInTheDocument();
    expect(
      within(headline()).getByText(
        'From 100 runs recorded with the real agents on IRIS AI Hub (build 2026.3.0AI.154.0), 25 Oct to 1 Nov 2026; CI replays them on every push. Nothing on this page was measured on this instance.',
      ),
    ).toBeInTheDocument();
    // The evaluation's own provenance, word for word, behind "Where these figures come from"
    const source = screen.getByText(
      /^Every figure here comes from the recorded live runs of 25 October 2026 to 1 November 2026: 100 runs/,
    );
    expect(source.closest('[data-tech-detail]')).toHaveAttribute('data-tech-detail', 'closed');
    expect(screen.getByRole('button', { name: 'Where these figures come from' })).toHaveAttribute(
      'aria-expanded',
      'false',
    );
    expect(screen.getByText(/Nothing on this page was measured on this instance/)).toBeInTheDocument();
  });

  it('gives the board against the expected outcome, the agreement, the tokens and the cost', () => {
    renderPage();
    expect(screen.getByText(/^24 of 24 scored passes/)).toBeInTheDocument();
    expect(screen.getByText(/^unanimous in 12, with the majority in 11/)).toBeInTheDocument();
    expect(screen.getByText(/1,896,147 uncached input/)).toBeInTheDocument();
    expect(screen.getByText(/\$10\.00 at list prices/)).toBeInTheDocument();
  });

  it('tells the two-layer story: the gate stops six of the misses, and the board catches S8 as its entry says', async () => {
    renderPage();
    const hero = headline();
    expect(hero).toHaveAttribute('data-tour', 'evaluation-headline');
    expect(within(hero).getByRole('heading', { name: 'The board against the expected outcome', level: 2 }));
    expect(visible(hero.querySelector('.hero-statement'))).toBe(
      "On the same 11 failures, played end to end: the board 11, Rules only 4. Of Rules only's 7 misses, the gate stopped 6.",
    );
    expect(
      within(hero).getByText(
        /^The seventh, S8, wrote over the bed manager's ward with every check passed\. The board escalated, as entry E7 says\./,
      ),
    ).toBeInTheDocument();
    // What the agents had to go on, carried over from the evaluation so the page doesn't overclaim
    expect(
      within(hero).getByText(
        /coordinator is given the catalogue's entry and took its outcome in 24 of 25 plans, S8 included/,
      ),
    ).toBeInTheDocument();
    // The side by side of S8's two cases, found among the recorded cases
    expect(await within(hero).findByRole('link', { name: 'Compare the two cases' })).toHaveAttribute(
      'href',
      '/cases/C-000008?show=compare',
    );
  });

  it("puts the held-out fair test above the board's own score, its figures fair-test.md's", () => {
    renderPage();
    const card = within(headline()).getByRole('region', {
      name: "Held out: 12 sealed cases, 3 runs each, on release 1.0.0's code",
    });
    expect(visible(card.querySelector('p')!)).toBe(
      'Strict mean loss, lower is better: the board 0.167, the single investigator 0.167 with two F08 runs settled (0.500 as graded), Site policy with no model 3.500, always escalating 1.250; with no model, F09 was written wrongly in every run. fair-test.md',
    );
    expect(within(card).getByRole('link', { name: 'fair-test.md' })).toHaveAttribute(
      'href',
      'https://github.com/MxSalata/shutter/blob/main/docs/readme/fair-test.md',
    );
    // Release 1.1.1's own figure for the board, so the 1.0.0 figure is not read as the trial's release
    const later = card.querySelectorAll('p')[1]!;
    expect(visible(later)).toBe(
      "On 1.1.1's code the board proposed the same and the gate also held F03 and F07: 0.667 as graded. Release 1.1.x",
    );
    expect(within(later as HTMLElement).getByRole('link', { name: 'Release 1.1.x' })).toHaveAttribute(
      'href',
      'https://github.com/MxSalata/shutter/blob/main/docs/readme/fair-test.md#release-11x',
    );
    // Above the self-graded tile: the board's proposals on its own recorded scenarios
    const own = within(headline()).getByText('recorded failures where the board chose the expected action');
    expect(card.compareDocumentPosition(own) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });

  it('sets Rules only beside the board on one base, apart from the proposed action', () => {
    renderPage();
    const hero = headline();
    expect(
      within(hero).getByRole('heading', { name: "The board's proposals", level: 3 }),
    ).toBeInTheDocument();
    expect(within(hero).getByText('24 of 24')).toBeInTheDocument();
    expect(
      within(hero).getByText('recorded failures where the board chose the expected action'),
    ).toBeInTheDocument();
    // The tested caption, in the tile's data detail
    expect(
      within(hero).getByText("scored passes proposed the scenario's expected action"),
    ).toBeInTheDocument();
    // The tile's heading, which holds its info button
    const played = within(hero).getByRole('heading', { name: 'Played end to end, same 11', level: 3 });
    expect(
      within(hero).getByRole('img', { name: 'The board: 11 of 11 failures ended as expected' }),
    ).toBeInTheDocument();
    expect(
      within(hero).getByRole('img', { name: 'Rules only: 4 of 11 failures ended as expected' }),
    ).toBeInTheDocument();
    expect(within(hero).getByText('Ended as expected, of the same 11 failures')).toBeInTheDocument();
    // The comparison's long form, as the info button's description
    const info = within(played).getByRole('button', { name: 'How the comparison was played' });
    expect(info).toHaveAccessibleDescription(
      '4 of 11 scored passes played end to end in Rules only mode, no agents, ended as expected; played the same way, the board ended as expected in 11 of the same 11',
    );
    expect(
      within(hero).getByRole('button', { name: '6 stopped by the gate, nothing written' }),
    ).toHaveAttribute('aria-pressed', 'false');
    expect(within(hero).getByRole('button', { name: '1 written wrongly: S8' })).toHaveAttribute(
      'aria-pressed',
      'false',
    );
    expect(hero).not.toHaveTextContent('same scenarios');
  });

  it('puts the cost per pass, the agreement, the scope and the limits beside the headline, computed from the document', () => {
    renderPage();
    const hero = headline();
    expect(within(hero).getByText('25 passes in 24 cases; 1 not scored.')).toBeInTheDocument();
    const scored = recorded.passes.filter((p) => p.scored).map((p) => p.cost_usd);
    const usd = (n: number) => `$${n.toFixed(2)}`;
    expect(
      within(hero).getByText(`${usd(Math.min(...scored))} to ${usd(Math.max(...scored))}`),
    ).toBeInTheDocument();
    expect(within(hero).getByText(/^\$10\.00 for 25 passes \(100 runs\)$/)).toBeInTheDocument();
    expect(within(hero).getByRole('heading', { name: 'Agreement', level: 3 })).toBeInTheDocument();
    for (const [how, n] of Object.entries(recorded.totals.agreement))
      expect(
        within(hero)
          .getByText(new RegExp(`^${how}$`, 'i'))
          .closest('div')!.parentElement,
      ).toHaveTextContent(`${n} ${n === 1 ? 'pass' : 'passes'}`);
    const limits = within(hero).getByRole('heading', { name: 'Limits', level: 3 });
    expect(limits.closest('[data-tour]')).toHaveAttribute('data-tour', 'evaluation-limits');
    expect(visible(limits.closest('[data-tour]'))).toMatch(
      /^Limits19 scenarios, 24 cases, 25 passes\. A match shows agreement with each scenario's expected outcome; it is not evidence of general reliability\./,
    );
    expect(
      within(hero).getByText(
        /The plan cited an entry the site's policy may settle in 16 of 24, one needing the board in 3, a person in 5\./,
      ),
    ).toBeInTheDocument();
    expect(within(hero).getByRole('button', { name: 'What is not yet measured' })).toBeInTheDocument();
  });

  it('says so when no scored pass was played in Rules only mode', () => {
    renderPage({ ...recorded, passes: recorded.passes.map((p) => ({ ...p, played: {} })) });
    const hero = headline();
    expect(within(hero).getByText('Not played')).toBeInTheDocument();
    expect(within(hero).getByText('no scored pass was played in Rules only mode')).toBeInTheDocument();
    // The statement falls back on the board's own figure; no sentence about a comparison it cannot make
    expect(visible(hero.querySelector('.hero-statement'))).toBe(
      'The board chose the expected action in 24 of 24 recorded failures.',
    );
    expect(hero).not.toHaveTextContent('the gate stopped');
    expect(screen.getByRole('region', { name: 'How the specialists differed' })).not.toHaveTextContent(
      'The gate alone',
    );
  });

  it('leaves the gate and the build out for an older document that does not record them, never typing them', () => {
    const older: Evaluation = {
      ...recorded,
      sources: Object.fromEntries(Object.entries(recorded.sources).filter(([k]) => k !== 'recorded_on')),
      passes: recorded.passes.map((p) => ({
        ...p,
        played: Object.fromEntries(
          Object.entries(p.played).map(([k, v]) => [k, { status: v.status, cost_usd: v.cost_usd }]),
        ),
      })),
    };
    renderPage(older);
    const hero = headline();
    expect(visible(hero.querySelector('.hero-statement'))).toBe(
      'On the same 11 failures, played end to end: the board 11, Rules only 4.',
    );
    expect(hero).not.toHaveTextContent('The seventh');
    expect(hero).not.toHaveTextContent('stopped by the gate');
    expect(within(hero).queryByRole('link', { name: 'Compare the two cases' })).toBeNull();
    expect(
      within(hero).getByText(
        'From 100 runs recorded with the real agents, 25 Oct to 1 Nov 2026; CI replays them on every push. Nothing on this page was measured on this instance.',
      ),
    ).toBeInTheDocument();
    expect(screen.getByRole('region', { name: 'How the specialists differed' })).not.toHaveTextContent(
      'The gate alone',
    );
    // Rules only's misses are still marked, without saying how they ended
    const s1 = within(table()).getByText('S1').closest('tr')!;
    expect(s1).toHaveTextContent('Rules only: not as expected');
  });

  it('shows who proposed the expected action on one base, and which misses the gate catches alone', async () => {
    renderPage();
    const why = screen.getByRole('region', { name: 'How the specialists differed' });
    for (const [who, n] of [
      ['The board', 24],
      ['Impact Analysis', 23],
      ['Encounter Integrity', 21],
      ['Conformance', 13],
    ] as const)
      expect(within(why).getByRole('img', { name: `${who}: ${n} of 24 scored passes` })).toBeInTheDocument();
    expect(
      within(why).getByText('Who proposed the expected action, of 24 scored passes'),
    ).toBeInTheDocument();
    const single = within(why).getByText(/^Each specialist answers from its own view\./);
    expect(visible(single)).toBe(
      'Each specialist answers from its own view. The single investigator was measured with the real model on the 12 held-out cases (fair-test.md); it has no recording in the trial.',
    );
    expect(within(single).getByRole('link', { name: 'fair-test.md' })).toHaveAttribute('href', HELD_OUT.url);
    expect(why).not.toHaveTextContent('No single-agent run was recorded');
    expect(why).toHaveTextContent(
      'The gate alone catches S1, S3, S6, S7, S10 and S13. The board catches S8.',
    );
    // Each id opens that scenario's Rules only case, once the recorded cases have loaded
    expect(await within(why).findByRole('link', { name: 'S1' })).toHaveAttribute('href', '/cases/C-000014');
    expect(within(why).getByRole('link', { name: 'S13' })).toHaveAttribute('href', '/cases/C-000024');
    expect(within(why).getByRole('link', { name: 'S8' })).toHaveAttribute('href', '/cases/C-000021');
  });

  it('opens the table filtered by the address, as a link or the guide gives it', () => {
    renderPage(undefined, { path: '/evaluation?show=rules-differs' });
    const region = table();
    expect(region).toHaveAttribute('data-tour', 'evaluation-table');
    expect(within(region).getByRole('radio', { name: 'Rules only not as expected' })).toBeChecked();
    expect(within(region).getByText('7 passes shown')).toHaveAttribute('aria-live', 'polite');
    expect(shownPasses()).toEqual(['S1', 'S3', 'S6', 'S7 pass 2', 'S8', 'S10', 'S13']);
  });

  it('filters by who the cited entry says decides and by whose view was outweighed', () => {
    const { unmount } = renderPage(undefined, { path: '/evaluation?decides=board' });
    expect(shownPasses()).toEqual(['S4', 'S8', 'S11 ENC-1103 discharge']);
    expect(within(table()).getByRole('combobox', { name: 'Entry decides' })).toHaveValue('board');
    unmount();

    renderPage(undefined, { path: '/evaluation?outweighed=conformance' });
    const expected = recorded.passes.filter((p) => outweighedIn(p).includes('conformance')).map(passName);
    expect(expected.length).toBeGreaterThan(0);
    expect(shownPasses()).toEqual(expected);
    // Choosing Any shows every pass again
    fireEvent.change(within(table()).getByRole('combobox', { name: 'Outweighed' }), {
      target: { value: '' },
    });
    expect(shownPasses()).toHaveLength(recorded.passes.length);
  });

  it('turns a filter on and off from the Agreement rows and the comparison marks', () => {
    renderPage();
    const majority = within(headline()).getByRole('button', { name: 'With the majority 11 passes' });
    fireEvent.click(majority);
    expect(majority).toHaveAttribute('aria-pressed', 'true');
    expect(within(table()).getByRole('radio', { name: 'With the majority' })).toBeChecked();
    expect(within(table()).getByText('11 passes shown')).toBeInTheDocument();
    fireEvent.click(majority);
    expect(majority).toHaveAttribute('aria-pressed', 'false');
    expect(within(table()).getByText('25 passes shown')).toBeInTheDocument();
    expect(within(table()).getByRole('radio', { name: 'All 25' })).toBeChecked();

    fireEvent.click(within(headline()).getByRole('button', { name: '1 written wrongly: S8' }));
    expect(shownPasses()).toEqual(['S8']);
    fireEvent.click(
      within(headline()).getByRole('button', { name: '6 stopped by the gate, nothing written' }),
    );
    expect(shownPasses()).toEqual(['S1', 'S3', 'S6', 'S7 pass 2', 'S10', 'S13']);
  });

  it('sorts by cost, dearest first, and says which column it sorts', () => {
    renderPage(undefined, { path: '/evaluation?sort=cost' });
    const costs = recorded.passes.map((p) => p.cost_usd).sort((a, b) => b - a);
    const first = recorded.passes.find((p) => p.cost_usd === costs[0])!;
    expect(shownPasses()[0]).toBe(passName(first));
    expect(within(table()).getByRole('columnheader', { name: 'Cost · time' })).toHaveAttribute(
      'aria-sort',
      'descending',
    );
    expect(within(table()).getByRole('columnheader', { name: 'Pass' })).not.toHaveAttribute('aria-sort');
  });

  it("puts the totals under the table's own columns: the cost and the time under Cost · time", () => {
    renderPage();
    const region = table();
    const headers = within(region).getAllByRole('columnheader');
    const columns = headers.map((h) => h.textContent);
    expect(columns).toEqual([
      'Pass',
      'Expected',
      'Conformance',
      'Encounter Integrity',
      'Impact Analysis',
      'Plan',
      'Played',
      'Cost · time',
    ]);
    const total = within(region).getByRole('rowheader', { name: 'Total' }).closest('tr')!;
    // Each cell starts at the column after the cells before it, counting their spans
    let at = 0;
    const starts = Array.from(total.children).map((c) => {
      const start = at;
      at += (c as HTMLTableCellElement).colSpan;
      return start;
    });
    expect(at).toBe(columns.length);
    const last = Array.from(total.children).at(-1)!;
    expect(columns[starts[starts.length - 1]]).toBe('Cost · time');
    expect(last).toHaveTextContent('$10.00');
    expect(last).toHaveTextContent('of agent time');
  });

  it('keeps the table, its column headers and its cells announced when it stacks on a phone', () => {
    renderPage();
    const t = within(table()).getByRole('table');
    expect(t).toHaveAttribute('role', 'table');
    expect(within(t).getAllByRole('rowgroup')).toHaveLength(2);
    expect(within(t).getByRole('columnheader', { name: 'Expected' })).toHaveAttribute('role', 'columnheader');
    const row = within(t).getByText('S8').closest('tr')!;
    expect(row).toHaveAttribute('role', 'row');
    const cells = within(row).getAllByRole('cell');
    expect(cells.every((c) => c.getAttribute('role') === 'cell')).toBe(true);
    // Every cell but the first, which names the pass, carries its column's name for the stacked layout
    expect(cells.slice(1).map((c) => c.getAttribute('data-label'))).toEqual([
      'Expected',
      'Conformance',
      'Encounter Integrity',
      'Impact Analysis',
      'Plan',
      'Played',
      'Cost · time',
    ]);
    // The merged cells keep the names of the columns they took in
    expect(cells[5].querySelector('[data-label="Entry"]')).toHaveTextContent('E7 · board');
    expect(cells[5].querySelector('[data-label="Agreement"]')).toHaveTextContent('With the majority');
    expect(cells[7].querySelector('[data-label="Cost and tokens"]')).toHaveTextContent('$0.37');
    expect(cells[7].querySelector('[data-label="Elapsed"]')).toHaveTextContent('30.9 s');
  });

  it("keeps the expected, the members' and the plan's action badges out of the tab order, the played marks' own words in it", () => {
    renderPage();
    const row = within(table()).getByText('S8').closest('tr')!;
    const cells = within(row).getAllByRole('cell');
    // The expected, the specialists' and the plan's actions: the same definition in every row, so no stop per badge
    expect(cells[1].querySelector('.disposition-badge')).not.toBeNull();
    for (const cell of cells.slice(1, 6)) expect(cell.querySelector('[tabindex="0"]')).toBeNull();
    // The played marks carry this row's own comparison words, so the keyboard still reaches them
    expect(cells[6].querySelectorAll('[tabindex="0"]').length).toBeGreaterThan(0);
  });

  it("shows each member's view and confidence, the plan, and how the pass ended played end to end", () => {
    renderPage();
    const region = table();
    const row = within(region).getByText('S8').closest('tr')!;
    const cells = within(row).getAllByRole('cell');
    expect(cells[1]).toHaveTextContent('Escalate (or more evidence)');
    expect(cells[2]).toHaveTextContent('Resend');
    expect(cells[2]).toHaveTextContent('confidence 80% · outweighed');
    expect(cells[3]).toHaveTextContent('Escalate');
    expect(cells[3]).toHaveTextContent('confidence 85%');
    expect(cells[5]).toHaveTextContent('Escalate');
    expect(cells[5]).toHaveTextContent('E7 · board');
    expect(cells[5]).toHaveTextContent('With the majority');
    expect(cells[6]).toHaveTextContent('Board: as expected');
    expect(cells[6]).toHaveTextContent('Rules only: wrote, not as expected');
    expect(cells[7]).toHaveTextContent('$0.37 · 30.9 s');
    // Rules alone missed it; the board did not: the row's edge says worth seeing, not refused
    expect(row).toHaveAttribute('data-tone', 'info');
    const s1 = within(region).getByText('S1').closest('tr')!;
    expect(s1).toHaveTextContent('Rules only: stopped by the gate');
    expect(within(region).getByText('S2').closest('tr')).not.toHaveAttribute('data-tone');
    expect(within(region).getByText('S2').closest('tr')).toHaveTextContent('Rules only: as expected');
    const unscored = within(region).getByText('S7 pass 1').closest('tr')!;
    expect(unscored).toHaveTextContent('Not scored: planned again after the change');
    expect(within(region).getByText('S11 ENC-1103 transfer').closest('tr')).toHaveTextContent(
      'Not played end to end',
    );
  });

  it('marks nothing in a pass that is not scored, as the document does', () => {
    renderPage();
    const region = table();
    // Every member said resend, which the scenario's later expectation does not match
    const unscored = within(region).getByText('S7 pass 1').closest('tr')!;
    expect(within(unscored).getAllByText('Resend')).toHaveLength(4);
    expect(unscored).not.toHaveTextContent('outweighed');
    expect(unscored).not.toHaveTextContent('Not as expected');
    expect(unscored).not.toHaveTextContent('Board:');
    // The pass after the change is scored: conformance's resend was set aside, and the plan is the expected one
    const scored = within(region).getByText('S7 pass 2').closest('tr')!;
    const cells = within(scored).getAllByRole('cell');
    expect(cells[2]).toHaveTextContent('outweighed');
    expect(cells[3]).not.toHaveTextContent('outweighed');
    expect(cells[5]).not.toHaveTextContent('Not as expected');
  });

  it('reads an empty confidence group and an evaluation with no recordings, as the script can write them', () => {
    const allAgreed: Evaluation = {
      ...recorded,
      totals: { ...recorded.totals, confidence: { ...recorded.totals.confidence, differed: { n: 0 } } },
    };
    const { unmount } = renderPage(allAgreed);
    expect(
      screen.getByText(/the findings with the expected outcome: 57, from 0\.70 to 0\.95/),
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
    expect(screen.getByText('How the board decides, measured on recorded runs.')).toBeInTheDocument();
    expect(
      within(headline()).getByText(
        'No runs have been recorded with the real agents yet. Nothing on this page was measured on this instance.',
      ),
    ).toBeInTheDocument();
    expect(within(table()).getByText('No pass matches these filters.')).toBeInTheDocument();
  });

  it("lists the document's Not yet measured items, each first sentence with the rest a click away", () => {
    renderPage();
    const notYet = screen.getByRole('region', { name: 'Not yet measured' });
    expect(within(notYet).getAllByRole('listitem').length).toBeGreaterThanOrEqual(4);
    expect(within(notYet).getByText('Repeat runs.')).toBeInTheDocument();
    expect(within(notYet).getByText('Each pass above is one recording per member.')).toBeInTheDocument();
    const more = within(notYet).getByRole('button', { name: 'More about repeat runs' });
    expect(more).toHaveAttribute('aria-expanded', 'false');
    fireEvent.click(more);
    expect(more).toHaveAttribute('aria-expanded', 'true');
    expect(within(notYet).getByText(/^Nothing here shows how often the same model/)).toBeInTheDocument();
    expect(
      within(notYet).getByRole('button', { name: 'More about adversarial variants' }),
    ).toBeInTheDocument();
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
    // The answer is the machine's: a code chip
    expect(within(digest).getByText('409 stale_version').tagName).toBe('CODE');
    const receiver = within(section)
      .getByText('The receiving system changed after the approval')
      .closest('tr')!;
    expect(receiver).toHaveTextContent('S20, rules only');
    expect(receiver).toHaveTextContent('APPROVAL_RECEIVER_CHANGED, no write');
  });

  it("lets a keyboard scroll the boundary's table where it is wider than the page: its scroll area takes the focus, named", () => {
    renderPage();
    const section = screen.getByRole('region', { name: 'What the boundary refuses' });
    // Nothing in the table can take the focus, so its scroll area must (axe: scrollable-region-focusable)
    const area = within(section).getByRole('region', { name: 'What the boundary refuses, scrolls sideways' });
    expect(area).toHaveAttribute('tabindex', '0');
    expect(within(area).getAllByRole('row')).toHaveLength(boundary.checks.length + 1);
  });

  it('gives the document as the page reads it, with Copy as JSON, opened in Technical', () => {
    const { unmount } = renderPage();
    expect(screen.getByRole('button', { name: 'As the API sends it' })).toHaveAttribute(
      'aria-expanded',
      'false',
    );
    expect(screen.getByText('docs/readme/evaluation.json').tagName).toBe('CODE');
    unmount();

    renderPage(undefined, { detail: 'technical' });
    expect(screen.getByRole('button', { name: 'As the API sends it' })).toHaveAttribute(
      'aria-expanded',
      'true',
    );
    expect(screen.getByRole('button', { name: 'Copy as JSON' })).toBeInTheDocument();
    // The data details open; the explanations stay closed
    expect(screen.getByRole('button', { name: 'How they are counted' })).toHaveAttribute(
      'aria-expanded',
      'true',
    );
    expect(screen.getByRole('button', { name: 'Tokens and model' })).toHaveAttribute('aria-expanded', 'true');
    expect(screen.getByRole('button', { name: 'How to read this table' })).toHaveAttribute(
      'aria-expanded',
      'false',
    );
    expect(within(headline()).getByText('claude-opus-5-5').tagName).toBe('CODE');
    // Each pass's tokens join its cost
    const s8 = within(table()).getByText('S8').closest('tr')!;
    expect(s8).toHaveTextContent('70,042 in · 23,490 cached · 4,337 out');
  });

  it('keeps the first layer above the table within its word budget, Plain and Technical', async () => {
    // Counted once the recorded cases have loaded, with the hero's link to S8's two cases in
    const plain = renderPage();
    await within(headline()).findByRole('link', { name: 'Compare the two cases' });
    const words = wordsAbove(plain.container);
    plain.unmount();
    const tech = renderPage(undefined, { detail: 'technical' });
    await within(headline()).findByRole('link', { name: 'Compare the two cases' });
    const technical = wordsAbove(tech.container);
    // At most 325 words in Plain, which includes the catalogue line beside the result, the held-out card (with the
    // baseline, both single investigator figures and release 1.1.1's) and where the single investigator was measured
    // (245 before those); Technical at most 1.5 times that
    expect(words.copy).toBeLessThanOrEqual(325);
    expect(technical.copy).toBeLessThanOrEqual(487);
    // Every visible word, the headings, the controls and the figures with it: Technical adds at most half again
    expect(technical.all).toBeGreaterThan(words.all);
    expect(technical.all).toBeLessThanOrEqual(1.5 * words.all);
  });
});
