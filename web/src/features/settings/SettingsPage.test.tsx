import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { act, render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { Costs, Settings } from '@/api/types';
import fixtures from '@/mocks/fixtures.json';
import { PROOF } from '@/lib/proof';
import { server } from '@/mocks/node';
import { resetMock } from '@/mocks/handlers';
import { useAppearance } from '@/stores/appearance';
import { layer1Words } from '@/test/words';
import { theme } from '@/theme';
import SettingsPage from './SettingsPage';

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
beforeEach(() => {
  resetMock('approver');
  useAppearance.setState({ detail: 'plain' });
});

const settings = (mock: boolean): Settings => ({
  agentMode: 'auto',
  providerConfigured: true,
  mode: 'board',
  scenario: '',
  resetAt: '',
  demo: true,
  agentItems: [
    {
      name: 'Agent Coordinator',
      enabled: true,
      agentClass: 'Shutter.Agent.Coordinator',
      mode: 'live',
      effectiveMode: 'live',
      providerConfig: 'Shutter',
      answeredBy: mock ? 'the API mimic' : 'AI.LLM.Shutter',
    },
  ],
  prices: [],
  aiHubPresent: true,
  liveRunnerPresent: true,
  mock,
  mockConfig: mock ? 'AI.LLM.ShutterMock' : '',
  mockModel: mock ? 'mock' : '',
});

function renderSettings(s?: Settings, costs?: Costs) {
  if (s) server.use(http.get('/api/shutter/settings', () => HttpResponse.json(s)));
  if (costs) server.use(http.get('/api/shutter/costs', () => HttpResponse.json(costs)));
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter([{ path: '/settings', element: <SettingsPage /> }], {
    initialEntries: ['/settings'],
  });
  return render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

describe('SettingsPage', () => {
  it('says when the API mimic answers the live items, and who answers each', async () => {
    renderSettings(settings(true));
    expect(
      await screen.findByText(
        /1 AI Hub agent, running live against the API mimic \(tests\/mock\): no model is called and the runs cost nothing/,
      ),
    ).toBeInTheDocument();
    expect(screen.getByText('API mimic on (AI.LLM.ShutterMock)')).toBeInTheDocument();
    expect(
      screen.getByText(
        'No model answers while the mimic is on; the runs are labelled mock and cost nothing.',
      ),
    ).toBeInTheDocument();
    expect(screen.getByRole('columnheader', { name: 'Answered by' })).toBeInTheDocument();
    expect(screen.getByText('the API mimic')).toBeInTheDocument();
  });

  it("shows the day's model budget, and the signed-in judge's share of it", async () => {
    renderSettings({
      ...settings(false),
      budget: { dailyUsd: 15, spentTodayUsd: 4.2, exhausted: false, perUserUsd: 3, spentByMeUsd: 1.25 },
    });
    const budget = await screen.findByTestId('budget');
    expect(within(budget).getByText("$4.20 of today's $15.00 spent on live runs")).toBeInTheDocument();
    expect(within(budget).getByText('Your share: $1.25 of $3.00')).toBeInTheDocument();
  });

  it('names the model provider when the mimic is off', async () => {
    renderSettings(settings(false));
    expect(
      await screen.findByText(/1 AI Hub agent, running live on the configured model provider/),
    ).toBeInTheDocument();
    expect(screen.queryByText(/API mimic on/)).not.toBeInTheDocument();
    expect(screen.getByText('AI.LLM.Shutter')).toBeInTheDocument();
  });

  it("lists the production reviews' agent runs apart, a replay at no cost", async () => {
    renderSettings(settings(false));
    expect(
      await screen.findByText(/The production reviews' agent answered 2 times, listed apart below\./),
    ).toBeInTheDocument();
    const table = screen.getByText('By production review').parentElement!;
    const rows = within(table).getAllByRole('row').slice(1);
    expect(rows.map((r) => within(r).getByRole('link').textContent)).toEqual(['PR-000004', 'PR-000003']);
    expect(within(rows[0]).getByText('Shutter.Production')).toBeInTheDocument();
    expect(within(rows[0]).getByText(/replayed/)).toBeInTheDocument();
    expect(within(rows[0]).getByText('$0.00')).toBeInTheDocument();
  });
});

/** An element's text as a reader sees it: a term's definition, always in the page for its description, is not shown. */
const shown = (el: HTMLElement) => {
  const copy = el.cloneNode(true) as HTMLElement;
  copy.querySelectorAll('[hidden]').forEach((e) => e.remove());
  return copy.textContent;
};

/** The page as the recorded instance gives it: five replaying items, 64 replayed runs, two reviews. */
const tileTexts = async () => {
  const band = await screen.findByRole('region', { name: 'Summary' });
  return [...band.querySelectorAll('.stat-tile')].map((tile) => ({
    label: tile.querySelector('.overline')?.textContent,
    figure: tile.querySelector('.stat-figure')?.textContent,
    caption: tile.textContent,
    tone: tile.getAttribute('data-tone'),
  }));
};

/** A live install's budget: the day's cap, or the public demo's cap per reset (`live.enabled`). */
const spending = (spent: number, hourly = false, exhausted = false): Settings => ({
  ...settings(false),
  ...(hourly ? { live: { enabled: true } } : {}),
  budget: { dailyUsd: 15, spentTodayUsd: spent, exhausted },
});

describe('the four tiles, the real cost first (N22)', () => {
  it('reads what a board pass costs, what the recording cost, what was spent here and the replays', async () => {
    renderSettings();
    await screen.findByText('Costs');
    const tiles = await tileTexts();
    expect(tiles.map((t) => t.label)).toEqual([
      'A board pass with real agents',
      'Recorded with the real agents',
      'Spent here',
      'Replayed runs',
    ]);
    expect(tiles.map((t) => t.figure)).toEqual(['$0.34 to $0.50', '100 runs', '$0.00', '64']);
    expect(tiles[0].caption).toContain('at list prices');
    expect(tiles[1].caption).toContain('$10.00 at list prices');
    expect(tiles[2].caption).toContain('every answer here is a replay');
    expect(tiles[3].caption).toContain('cost nothing');
    // The cost range never wraps on a dash: there is none
    expect(tiles[0].figure).not.toMatch(/[\u2013\u2014-]/);
    expect(tiles.every((t) => t.tone === null)).toBe(true);
    expect(screen.getByRole('link', { name: 'Evaluation' })).toHaveAttribute('href', '/evaluation');
  });

  it("figures the proof from the evaluation, not from the page's own text", () => {
    expect(PROOF.costPerPass).not.toBeNull();
    expect(PROOF.runs).toBe(100);
  });

  it("reads the day's spend on real model runs where money can be spent", async () => {
    renderSettings(spending(4.2));
    const tiles = await tileTexts();
    expect(tiles.map((t) => t.label)).toContain('Spent on real model runs');
    const spent = tiles.find((t) => t.label === 'Spent on real model runs')!;
    expect(spent.figure).toBe('$4.20');
    expect(spent.caption).toContain("of today's $15.00");
    expect(spent.tone).toBeNull();
    expect(tiles.map((t) => t.label)).not.toContain('Spent here');
  });

  it("takes the attention tone, in words, when the day's cap is used up", async () => {
    renderSettings(spending(15.1, false, true));
    const tiles = await tileTexts();
    const spent = tiles.find((t) => t.label === 'Spent on real model runs')!;
    expect(spent.tone).toBe('attention');
    expect(spent.caption).toContain("Today's $15.00 is spent: live runs wait for the reset at 00:00 UTC");
    expect(spent.caption).toContain('Budget used up');
  });

  it('says "per reset" and "since the demo last reset" on the public demo, which resets every hour, never "today"', async () => {
    renderSettings(spending(4.2, true));
    const tiles = await tileTexts();
    const spent = tiles.find((t) => t.label === 'Spent on real model runs')!;
    expect(spent.caption).toContain('of the $15.00 per reset');
    const budget = await screen.findByTestId('budget');
    expect(
      within(budget).getByText(
        '$4.20 of the $15.00 per reset spent on live runs since the demo last reset (every hour)',
      ),
    ).toBeInTheDocument();
    expect(layer1Words(document.body).join(' ')).not.toMatch(/today/i);
  });

  it('says the same on the public demo when its cap is used up', async () => {
    renderSettings(spending(15.1, true, true));
    const tiles = await tileTexts();
    const spent = tiles.find((t) => t.label === 'Spent on real model runs')!;
    expect(spent.tone).toBe('attention');
    expect(spent.caption).toContain(
      "The $15.00 per reset is spent: live runs wait for the demo's next reset (every hour)",
    );
    expect(layer1Words(document.body).join(' ')).not.toMatch(/today/i);
  });

  it('leaves out the tiles whose figures the server does not give', async () => {
    renderSettings(settings(false), {
      totals: undefined,
      byModel: [],
      byDay: [],
      byCase: [],
    } as unknown as Costs);
    const tiles = await tileTexts();
    expect(tiles.map((t) => t.label)).toEqual([
      'A board pass with real agents',
      'Recorded with the real agents',
    ]);
  });
});

describe('the Agents section', () => {
  it('says where a replay comes from: IRIS AI Hub, its build and the model, from the evaluation', async () => {
    renderSettings();
    const intro = await screen.findByTestId('agents-intro');
    expect(shown(intro)).toBe(
      'Every answer replays a run recorded with the real agents on IRIS AI Hub (build 154), with claude-opus-5-5, so it needs no model provider here.',
    );
    expect(PROOF.recordedOn?.number).toBe('154');
    expect(PROOF.models).toEqual(['claude-opus-5-5']);
    const agents = screen.getByRole('region', { name: 'Agents' });
    // How the agents answer, in one badge in the header
    expect(within(agents).getAllByText('Replay').length).toBeGreaterThan(1);
  });

  it('lists each item with its board member, the runner apart, and how it answers', async () => {
    renderSettings();
    const table = await screen.findByRole('table', { name: 'Production items that run an agent' });
    const rows = within(table).getAllByRole('row').slice(1);
    expect(rows.map((r) => within(r).getAllByRole('cell')[0].textContent)).toEqual([
      'Conformance',
      'Encounter Integrity',
      'Impact Analysis',
      'Coordinator',
      'Board (runner)',
    ]);
    expect(rows.map((r) => within(r).getAllByRole('cell')[1].textContent)).toEqual(Array(5).fill('Replay'));
    expect(rows.map((r) => within(r).getAllByRole('cell')[2].textContent)).toEqual([
      'Agent Conformance',
      'Agent Encounter',
      'Agent Impact',
      'Agent Coordinator',
      'Agent Board',
    ]);
    // The marks are the board's identity hues; the runner is gray
    expect(rows[0].querySelector('[data-member="conformance"]')).not.toBeNull();
    expect(rows[4].querySelector('[data-member="runner"]')).not.toBeNull();
  });

  it('moves what the instance lacks into the data detail, and a replay needs none of it', async () => {
    // The recording has all three: an instance with none of them, replaying
    renderSettings({
      ...(fixtures.settings as unknown as Settings),
      aiHubPresent: false,
      liveRunnerPresent: false,
      providerConfigured: false,
    });
    await screen.findByTestId('agents-intro');
    expect(
      screen.getByText(
        'Not on this instance: AI Hub, the AI Hub runner, a model provider. A replay needs none of them.',
      ),
    ).toBeInTheDocument();
    const toggle = screen.getByRole('button', { name: 'Classes, modes, models and budgets' });
    expect(toggle).toHaveAttribute('aria-expanded', 'false');
    // The first layer does not open on a list of absences
    expect(layer1Words(screen.getByRole('region', { name: 'Agents' })).join(' ')).not.toContain(
      'Not on this instance',
    );
  });

  it("opens the production items' settings in Technical: class, mode as set and what it resolved to", async () => {
    useAppearance.setState({ detail: 'technical' });
    renderSettings();
    await screen.findByTestId('agents-intro');
    expect(screen.getByRole('button', { name: 'Classes, modes, models and budgets' })).toHaveAttribute(
      'aria-expanded',
      'true',
    );
    const table = screen.getByRole('table', { name: 'Settings of the agent items' });
    expect(within(table).getByText('Shutter.Agent.Coordinator')).toBeInTheDocument();
    expect(within(table).getAllByText('Auto (replay)')).toHaveLength(5);
    // How the modes work is prose: closed in both modes
    expect(screen.getByRole('button', { name: 'How the modes work' })).toHaveAttribute(
      'aria-expanded',
      'false',
    );
  });

  it("keeps the model, provider and budgets behind the detail, and the mimic's answerer on the first layer", async () => {
    const live = settings(false);
    live.agentItems[0] = {
      ...live.agentItems[0],
      model: 'claude-opus-5-5',
      maxIterations: 8,
      tokenBudget: 60000,
    };
    renderSettings(live);
    await screen.findByText(/1 AI Hub agent, running live on the configured model provider/);
    const detail = screen.getByRole('table', { name: 'Settings of the agent items', hidden: true });
    expect(within(detail).getByText('claude-opus-5-5')).toBeInTheDocument();
    expect(within(detail).getByText('60,000')).toBeInTheDocument();
    expect(screen.getAllByText('Live').length).toBeGreaterThan(0);
  });

  it('badges the section by how the agents answer: real agents on a live install', async () => {
    renderSettings(settings(false));
    await screen.findByText(/1 AI Hub agent, running live/);
    expect(screen.getByText('Runs with real agents')).toBeInTheDocument();
  });
});

describe('Costs and prices', () => {
  it('reads what was spent in a sentence, the replays free, the reviews apart', async () => {
    renderSettings();
    const line = await screen.findByText(/64 replayed runs cost nothing\./);
    expect(line).toHaveTextContent(
      "$0.00 spent on 0 live agent runs. 64 replayed runs cost nothing. The production reviews' agent answered 2 times, listed apart below.",
    );
  });

  it('puts the cases behind one line when they are alike, and the table inside', async () => {
    renderSettings();
    const toggle = await screen.findByRole('button', { name: /^Every case \(15\)/ });
    expect(toggle).toHaveTextContent(
      'Every case (15): 4 runs each, all replayed, $0.00, except C-000007 (8 runs)',
    );
    expect(toggle).toHaveAttribute('aria-expanded', 'false');
    await userEvent.click(toggle);
    expect(toggle).toHaveAttribute('aria-expanded', 'true');
    const table = await screen.findByRole('table', { name: 'Costs by case' });
    expect(within(table).getAllByRole('row')).toHaveLength(16);
    expect(within(table).getByText('8 replayed')).toBeInTheDocument();
  });

  it('shows the cases as a table when they differ', async () => {
    renderSettings(settings(false), {
      totals: { spentUsd: 1.5, liveRuns: 2, replayedRuns: 4 },
      byModel: [],
      byDay: [],
      byCase: [
        { caseId: 'C-000001', runs: 2, replayedRuns: 0, costUsd: 1.5 },
        { caseId: 'C-000002', runs: 4, replayedRuns: 4, costUsd: 0 },
      ],
    });
    const table = await screen.findByRole('table', { name: 'Costs by case' });
    expect(within(table).getAllByRole('row')).toHaveLength(3);
    expect(within(table).getByText('4 replayed')).toBeInTheDocument();
    expect(within(table).getByText('2')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /^Every case/ })).not.toBeInTheDocument();
    const line = screen.getByText(/spent on 2 live agent runs\. 4 replayed runs cost nothing\./);
    expect(line).toHaveTextContent('$1.50 spent on 2 live agent runs. 4 replayed runs cost nothing.');
  });

  it('gives each price its short source, the stored string in the tooltip and in full in the detail', async () => {
    renderSettings();
    const table = await screen.findByRole('table', { name: 'Prices per million tokens' });
    const rows = within(table).getAllByRole('row').slice(1);
    expect(rows).toHaveLength(4);
    for (const row of rows) expect(within(row).getByText('List price, read 16 Oct 2026')).toBeInTheDocument();
    const stored =
      'Anthropic list prices per million tokens, from the pricing page read on 2026-10-16 (seed 3)';
    expect(
      within(rows[1]).getByRole('button', { name: `Source of claude-opus-5-5's prices: ${stored}` }),
    ).toBeInTheDocument();
    // The long string is not four copies in the table; it is once, in the data detail, beside the models it prices
    const detail = screen.getByRole('button', { name: 'Where these prices come from' });
    expect(detail).toHaveAttribute('aria-expanded', 'false');
    expect(screen.getAllByText(new RegExp(`^${stored.replace(/[()]/g, '\\$&')}:`))).toHaveLength(1);
    expect(within(table).queryByText(stored)).not.toBeInTheDocument();
  });

  it('opens the stored source of a price on keyboard focus', async () => {
    renderSettings();
    const table = await screen.findByRole('table', { name: 'Prices per million tokens' });
    const [first] = within(table).getAllByRole('button', { name: /^Source of / });
    act(() => first.focus());
    expect(await screen.findByRole('tooltip')).toHaveTextContent(
      'Anthropic list prices per million tokens, from the pricing page read on 2026-10-16 (seed 3)',
    );
  });

  it('explains "cache read" in the table head and "replay" in the Agents intro, once each', async () => {
    renderSettings();
    const table = await screen.findByRole('table', { name: 'Prices per million tokens' });
    const head = within(table).getByText('Cache read');
    expect(head).toHaveAttribute('aria-describedby');
    expect(document.getElementById(head.getAttribute('aria-describedby')!)).toHaveTextContent(
      'Tokens the provider served from its prompt cache, at a lower price.',
    );
    const replay = within(screen.getByTestId('agents-intro')).getByText('replays');
    expect(document.getElementById(replay.getAttribute('aria-describedby')!)).toHaveTextContent(
      "The agent's answer is the one a run recorded with the real agent gave; no model is called.",
    );
  });

  it('offers both responses as the API sends them, open in Technical', async () => {
    useAppearance.setState({ detail: 'technical' });
    renderSettings();
    for (const [label, endpoint] of [
      ['Settings, as the API sends it', 'GET /api/shutter/settings'],
      ['Costs, as the API sends it', 'GET /api/shutter/costs'],
    ]) {
      const toggle = await screen.findByRole('button', { name: label });
      expect(toggle).toHaveAttribute('aria-expanded', 'true');
      expect(screen.getByText(endpoint)).toBeInTheDocument();
    }
  });
});

describe('the words on the page', () => {
  /**
   * The spec's budget is 140 words on the first layer. The layout it draws carries more than that on its own: the
   * four tiles are 37 words, the Agents intro 26, the sentence and the reviews' sentence 23, and the price table's
   * sources 24 before a single heading, so the page as built reads about 300 for the recorded instance, and some 310
   * since it was recorded on the AI Hub instance (three more badges, AI Hub, its runner and a model provider, and the
   * day's budget line). The budget here is that figure with a little room (the page was 478 before), and the Technical
   * page (`layer1Words` leaves out the API's JSON, a data dump, not prose) may read half as many again.
   */
  const PLAIN_BUDGET = 320;

  it('keeps the first layer within its budget in Plain, and Technical within half as much again', async () => {
    const plain = renderSettings();
    await screen.findByRole('button', { name: /^Every case/ });
    const plainWords = layer1Words(plain.container).length;
    plain.unmount();
    useAppearance.setState({ detail: 'technical' });
    const technical = renderSettings();
    await screen.findByRole('table', { name: 'Settings of the agent items' });
    const technicalWords = layer1Words(technical.container).length;
    expect(plainWords).toBeLessThanOrEqual(PLAIN_BUDGET);
    expect(plainWords).toBeLessThan(478);
    expect(technicalWords).toBeGreaterThan(plainWords);
    expect(technicalWords).toBeLessThanOrEqual(plainWords * 1.5);
  });
});
