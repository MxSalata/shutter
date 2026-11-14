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
import { BOUNDARY_DISPLAY, outweighedIn, passName, type BoundaryChecks, type Evaluation } from './evaluation';
import EvaluationPage, { heroSecond, RULES_EXEMPTION } from './EvaluationPage';
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
  {
    path = '/evaluation',
    detail = 'plain',
    refusals,
  }: { path?: string; detail?: DetailLevel; refusals?: BoundaryChecks } = {},
) {
  useAppearance.setState({ detail });
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <MemoryRouter initialEntries={[path]}>
          <EvaluationPage data={data} refusals={refusals} />
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
        'Catalogue demonstration: 100 runs recorded with the real agents on IRIS AI Hub (build 2026.3.0AI.154.0), 25 Oct to 1 Nov 2026; CI replays them on every push. Nothing on this page was measured on this instance.',
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
    // The band's heading names the cohort and the release its figures come from
    expect(
      within(hero).getByRole('heading', {
        name: 'Catalogue demonstration, recorded before release 1.0.0',
        level: 2,
      }),
    ).toHaveClass('overline');
    expect(visible(hero.querySelector('.hero-statement'))).toBe(
      "On the same 11 failures, played end to end: the board 11, Rules only 4. Of Rules only's 7 misses, the gate stopped 6.",
    );
    expect(
      within(hero).getByText(
        /^The seventh, S8, wrote over the bed manager's ward with every check passed: Rules only is exempted there on purpose, and on a real case the gate holds it\. The board escalated, as entry E7 says\./,
      ),
    ).toBeInTheDocument();
    // What the agents had to go on, carried over from the evaluation so the page doesn't overclaim
    expect(
      within(hero).getByText(
        /agents are given the catalogue's matching entry and preferred outcome. The coordinator took that outcome in 24 of 25 plans, S8 included/,
      ),
    ).toBeInTheDocument();
    // The side by side of S8's two cases, found among the recorded cases
    expect(await within(hero).findByRole('link', { name: 'Compare the two cases' })).toHaveAttribute(
      'href',
      '/cases/C-000008?show=compare',
    );
  });

  it("puts the held-out cases above the board's own score, each line with its release, the latest first", () => {
    renderPage();
    const card = within(headline()).getByRole('region', {
      name: 'Held-out cases F01 to F12: 12 cases, 36 runs in each mode (strict mean loss, lower is better)',
    });
    const lines = [...card.querySelectorAll(':scope > div > p')].map(visible);
    expect(lines).toEqual([
      'Release 1.4.3, regression rerun: the board 0.167, the single investigator 0.167 as settled (0.667 as graded), Rules only 4.000; no mode executed a wrong write.',
      'Release 1.0.0, the original test: the board 0.167, the single investigator 0.167 as settled (0.500 as graded); with no model, F09 was written wrongly in every run.',
      "Evaluation evidence, same gate, release 1.4.3: on F03 the board reconciled, Rules only's resend was blocked; neither wrote.",
    ]);
    expect(within(card).getByRole('link', { name: 'Release 1.4.3' })).toHaveAttribute(
      'href',
      'https://github.com/MxSalata/shutter/blob/main/docs/readme/fair-test.md#release-143-all-12-cases-rerun',
    );
    expect(within(card).getByRole('link', { name: 'Release 1.0.0' })).toHaveAttribute(
      'href',
      'https://github.com/MxSalata/shutter/blob/main/docs/readme/fair-test.md',
    );
    // Above the self-graded tile (the board's proposals on its own recorded scenarios), with the cohort said again
    // where the catalogue demonstration's figures resume
    const resumes = within(headline()).getByText(/^Catalogue demonstration: 100 runs recorded/);
    const own = within(headline()).getByText('recorded failures, the expected action chosen');
    expect(card.compareDocumentPosition(resumes) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(resumes.compareDocumentPosition(own) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });

  it('shows F03 as evaluation evidence under the same gate: its release, both outcomes and no write, never as S3', () => {
    renderPage();
    const card = within(headline()).getByRole('region', { name: /^Held-out cases F01 to F12/ });
    const example = within(card).getByTestId('same-gate-example');
    expect(example).toHaveTextContent(/^Evaluation evidence, same gate, release 1\.4\.3:/);
    // One press away in Plain (the opened content is found as hidden while its transition runs): the case, the release, what each mode proposed and what the gate did, and the writes
    const toggle = within(card).getByRole('button', { name: 'F03 in detail' });
    expect(toggle).toHaveAttribute('aria-expanded', 'false');
    fireEvent.click(toggle);
    expect(toggle).toHaveAttribute('aria-expanded', 'true');
    const detail = card.querySelector('[data-tech-detail="open"]')!;
    const rows = Object.fromEntries(
      [...detail.querySelectorAll('tr')].map((tr) => [
        visible(tr.querySelector('th')),
        visible(tr.querySelector('td')),
      ]),
    );
    expect(rows).toEqual({
      'The case': 'F03: committed, and the patient has moved on',
      Release: '1.4.3, one site profile and the same gate for every mode, nothing exempted',
      'The board, the single investigator':
        'proposed reconcile in 3 of 3 runs each; the gate passed it and the case resolved, verified',
      'Rules only':
        'proposed resend in 3 of 3 runs; the gate blocked it at proposal: ALREADY_COMMITTED, SUPERSEDED_BY_LATER_EVENT',
      'Writes to the receiver': '0 in every run of the three modes',
      'What this is': 'A held-out case, not a scenario: nothing in the app runs it',
      'Every run': 'results-r143-all.json',
    });
    expect(within(card).getByRole('link', { name: 'results-r143-all.json', hidden: true })).toHaveAttribute(
      'href',
      HELD_OUT.r143.sameGate.url,
    );
    // Evidence, not something to run: the card names no scenario and links no case or scenario page
    expect(card).not.toHaveTextContent(/\bS\d+\b/);
    const links = within(card).getAllByRole('link', { hidden: true });
    expect(links).toHaveLength(5);
    for (const link of links)
      expect(link.getAttribute('href')).toMatch(
        /^https:\/\/github\.com\/MxSalata\/shutter\/blob\/main\/docs\//,
      );
    expect(within(card).queryByRole('button', { name: /run/i })).toBeNull();
  });

  it('keeps the baselines and release 1.1.1 one press away, labelled with their releases', () => {
    renderPage(undefined, { detail: 'technical' });
    const card = within(headline()).getByRole('region', { name: /^Held-out cases F01 to F12/ });
    // An explanation, so Technical leaves it closed; the same-gate detail is data, which Technical opens
    expect(within(card).getByRole('button', { name: 'F03 in detail' })).toHaveAttribute(
      'aria-expanded',
      'true',
    );
    const toggle = within(card).getByRole('button', { name: 'Baselines and release 1.1.1' });
    expect(toggle).toHaveAttribute('aria-expanded', 'false');
    fireEvent.click(toggle);
    const earlier = document.getElementById(toggle.getAttribute('aria-controls')!)!;
    expect([...earlier.querySelectorAll('p')].map(visible)).toEqual([
      "On 1.0.0, Site policy with no model scored 3.500 and always escalating 1.250, a computed baseline that is the same on 1.4.3; the single investigator's 0.167 has two F08 runs settled. fair-test.md",
      "On 1.1.1's code the board proposed the same and the gate also held F03 and F07: 0.667 as graded. Release 1.1.x",
    ]);
    expect(within(earlier).getByRole('link', { name: 'Release 1.1.x', hidden: true })).toHaveAttribute(
      'href',
      'https://github.com/MxSalata/shutter/blob/main/docs/readme/fair-test.md#release-11x',
    );
  });

  it('says the exemption, the ward and every check passed only of S8, whatever else Rules only wrote', () => {
    const entryOf = (id: string) => (id === 'S8' ? 'E7' : '');
    const exemption = 'Rules only is exempted there on purpose, and on a real case the gate holds it';
    expect(RULES_EXEMPTION).toBe(exemption);
    // The recorded evaluation: the seventh miss, S8
    expect(
      heroSecond(
        { rulesMisses: { total: 7, stopped: ['S1', 'S3', 'S6', 'S7', 'S10', 'S13'], wrote: ['S8'] } },
        entryOf,
      ),
    ).toBe(
      `The seventh, S8, wrote over the bed manager's ward with every check passed: ${exemption}. The board escalated, as entry E7 says.`,
    );
    // S8 and another: the other is only said to have written
    expect(
      heroSecond({ rulesMisses: { total: 4, stopped: ['S1', 'S3'], wrote: ['S8', 'S9'] } }, entryOf),
    ).toBe(`S8 and S9 wrote. S8 wrote with every check passed: ${exemption}. The board caught them.`);
    // S8 alone, when the gate stopped none of the others
    expect(heroSecond({ rulesMisses: { total: 1, stopped: [], wrote: ['S8'] } }, entryOf)).toBe(
      `S8 wrote with every check passed: ${exemption}. The board caught it.`,
    );
    // Other scenarios alone: no ward, no exemption and nothing about their checks
    const others = heroSecond({ rulesMisses: { total: 3, stopped: ['S1'], wrote: ['S4', 'S9'] } }, entryOf);
    expect(others).toBe('S4 and S9 wrote. The board caught them.');
    const one = heroSecond({ rulesMisses: { total: 2, stopped: ['S1'], wrote: ['S9'] } }, entryOf);
    expect(one).toBe('S9 wrote. The board caught it.');
    for (const said of [others, one]) expect(said).not.toMatch(/exempt|every check|ward/);
    expect(heroSecond({ rulesMisses: null }, entryOf)).toBe('');
    expect(heroSecond({ rulesMisses: { total: 2, stopped: ['S1', 'S3'], wrote: [] } }, entryOf)).toBe('');
  });

  it('sets Rules only beside the board on one base, apart from the proposed action', () => {
    renderPage();
    const hero = headline();
    expect(
      within(hero).getByRole('heading', { name: "The board's proposals", level: 3 }),
    ).toBeInTheDocument();
    expect(within(hero).getByText('24 of 24')).toBeInTheDocument();
    expect(within(hero).getByText('recorded failures, the expected action chosen')).toBeInTheDocument();
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
        'Catalogue demonstration: 100 runs recorded with the real agents, 25 Oct to 1 Nov 2026; CI replays them on every push. Nothing on this page was measured on this instance.',
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
    // Its figures are the held-out cases', in the card above with their releases, so they are not said twice
    expect(visible(single)).toBe(
      'Each specialist answers from its own view. The single investigator has no recording in the trial; its figures are above.',
    );
    const card = screen.getByRole('region', { name: /^Held-out cases F01 to F12/ });
    expect(card).toHaveTextContent('the single investigator 0.167 as settled');
    expect(card.compareDocumentPosition(single) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
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

  const safeguards = () => screen.getByRole('region', { name: 'Approval safeguards' });
  /** The register's checks, each a list item named by its h3, in the order the page shows them. */
  const register = () => within(within(safeguards()).getByRole('list')).getAllByRole('listitem');

  it("lists the boundary's checks as a register, in the document's order, each headline and outcome in words", () => {
    renderPage();
    const section = safeguards();
    expect(
      within(section).getByText(`${boundary.checks.length} HTTP checks, run in CI on real IRIS for Health.`),
    ).toBeInTheDocument();
    // Every check runs in Rules only, so the label above them says so once
    expect(within(section).getByText('Expected outcomes · Rules only')).toBeInTheDocument();
    // A list, never a table: no table roles are left
    expect(within(section).queryByRole('table')).toBeNull();
    expect(within(section).queryByRole('row')).toBeNull();
    const items = register();
    expect(items).toHaveLength(boundary.checks.length);
    expect(items.map((li) => within(li).getByRole('heading', { level: 3 }).textContent)).toEqual(
      boundary.checks.map((c) => BOUNDARY_DISPLAY[c.id].headline),
    );
    const digest = items[0];
    expect(digest).toHaveTextContent('Approval refused; nothing stored or written.');
    expect(within(digest).getByRole('button', { name: 'Inspect plan mismatch' })).toHaveAttribute(
      'aria-expanded',
      'false',
    );
    // No pass or fail marks: these are the outcomes each check requires, not a run's results
    expect(section).not.toHaveTextContent(/passed\b.*\d+\/\d+|\d+\/\d+ passed/);
  });

  it('has words for every check the document lists, and a disclosure name for each, all different', () => {
    for (const c of boundary.checks) expect(BOUNDARY_DISPLAY[c.id], c.id).toBeDefined();
    const names = boundary.checks.map((c) => BOUNDARY_DISPLAY[c.id].inspect);
    expect(new Set(names).size).toBe(names.length);
  });

  it('keeps every field of each check one click away in Plain: its title, scenario, exact answer and proof', () => {
    renderPage();
    const items = register();
    boundary.checks.forEach((c, i) => {
      const li = items[i];
      const button = within(li).getByRole('button', { name: BOUNDARY_DISPLAY[c.id].inspect });
      fireEvent.click(button);
      expect(button).toHaveAttribute('aria-expanded', 'true');
      const panel = document.getElementById(button.getAttribute('aria-controls')!)!;
      expect(panel).toHaveAttribute('data-tech-detail', 'open');
      expect(panel).toHaveTextContent(c.title);
      expect(panel).toHaveTextContent(c.scenario);
      expect(panel).toHaveTextContent(c.proves);
      // The answer is the machine's: a code chip
      expect(within(panel).getByText(c.answer).tagName).toBe('CODE');
    });
    // Several stay open at once: no accordion
    expect(
      within(safeguards())
        .getAllByRole('button', { name: /^Inspect / })
        .every((b) => b.getAttribute('aria-expanded') === 'true'),
    ).toBe(true);
  });

  it('shows the scenario and the exact answer inline in Technical, the proof still behind its disclosure', () => {
    renderPage(undefined, { detail: 'technical' });
    const items = register();
    boundary.checks.forEach((c, i) => {
      const li = items[i];
      const button = within(li).getByRole('button', { name: BOUNDARY_DISPLAY[c.id].inspect });
      // An explanation: closed in Technical too
      expect(button).toHaveAttribute('aria-expanded', 'false');
      const panel = document.getElementById(button.getAttribute('aria-controls')!)!;
      const inline = li.querySelector('.boundary-check-body > .boundary-facts')!;
      expect(inline).toHaveTextContent(`Scenario${c.scenario}`);
      expect(within(inline as HTMLElement).getByText(c.answer).tagName).toBe('CODE');
      // Once on the row: the disclosure does not repeat them
      expect(panel.querySelector('.boundary-facts')).toBeNull();
      expect(panel).toHaveTextContent(c.proves);
    });
  });

  it('gives a check it has no words for its own title and answer, so a new check never goes missing', () => {
    const extra = {
      id: 'new_check',
      title: 'An approval by a stranger',
      scenario: 'S9, board',
      answer: '401 unauthorised',
      proves: 'Nobody else approves.',
    };
    renderPage(undefined, { refusals: { ...boundary, checks: [...boundary.checks, extra] } });
    const items = register();
    expect(items).toHaveLength(boundary.checks.length + 1);
    const last = items[items.length - 1];
    expect(within(last).getByRole('heading', { level: 3 })).toHaveTextContent('An approval by a stranger');
    expect(last).toHaveTextContent('401 unauthorised');
    expect(
      within(last).getByRole('button', { name: 'Inspect an approval by a stranger' }),
    ).toBeInTheDocument();
    // The checks no longer share one mode, so the label names none
    expect(within(safeguards()).getByText('Expected outcomes')).toBeInTheDocument();
  });

  it("says at its foot where the checks come from, where they run, and that they are not a run's results", () => {
    renderPage();
    const section = safeguards();
    const button = within(section).getByRole('button', { name: 'Test source and CI' });
    expect(button).toHaveAttribute('aria-expanded', 'false');
    fireEvent.click(button);
    const panel = document.getElementById(button.getAttribute('aria-controls')!)!;
    expect(within(panel).getByText(boundary.script).tagName).toBe('CODE');
    expect(panel).toHaveTextContent(`It runs in ${boundary.runs}.`);
    expect(panel).toHaveTextContent('an instance of your own that nobody else is using');
    expect(panel).toHaveTextContent('not the status of the latest CI run');
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
    // (245 before those), and since 13 November 2026 the Rules only exemption beside the write that passed every check
    // (15 words; 325 before it); Technical at most 1.5 times that. The held-out card's lines by release and its
    // same-gate example fit the same 340: the baselines and release 1.1.1 went one press away, and the single
    // investigator's figures are said once, in the card
    expect(words.copy).toBeLessThanOrEqual(340);
    expect(technical.copy).toBeLessThanOrEqual(510);
    // Every visible word, the headings, the controls and the figures with it: Technical adds at most half again
    expect(technical.all).toBeGreaterThan(words.all);
    expect(technical.all).toBeLessThanOrEqual(1.5 * words.all);
  });
});
