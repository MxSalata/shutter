import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { AgentRun } from '@/api/types';
import fixtures from '@/mocks/fixtures.json';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { renderUi } from '@/test/render';
import { call, livePass, withLiveClock } from '@/test/runs';
import { BoardPanel } from './BoardPanel';
import { RunTimeline } from './RunTimeline';

const toggle = () => screen.getByRole('button', { name: 'When each agent worked' });
const picture = () => screen.findByRole('img', { name: /^When each agent worked: / });

/** A drawn element's position and width, as the SVG has them (the picture is 640 px wide before it is measured). */
const box = (el: Element) => ({ x: Number(el.getAttribute('x')), width: Number(el.getAttribute('width')) });

describe('When each agent worked', () => {
  it('is a disclosure closed in Plain, which opens on the picture, its sentence and what the marks mean', async () => {
    renderUi(<RunTimeline runs={livePass()} />);
    expect(toggle()).toHaveAttribute('aria-expanded', 'false');
    await userEvent.click(toggle());
    expect(toggle()).toHaveAttribute('aria-expanded', 'true');
    expect(await picture()).toHaveAccessibleName(
      'When each agent worked: the three specialists at the same time, then the coordinator; the pass took 31 s.',
    );
    expect(screen.getByTestId('run-timeline-sentence')).toHaveTextContent(
      'The three specialists worked at the same time, then the coordinator wrote the plan. The pass took 31 s.',
    );
    expect(
      screen.getByText(/each mark on it a tool call; the gaps between the marks are the model's turns\./),
    ).toBeVisible();
    expect(screen.getByText(/An outlined mark is a call the policy refused before it ran\./)).toBeVisible();
    // Technical's split is not in Plain
    expect(screen.queryByTestId('run-timeline-figures')).not.toBeInTheDocument();
  });

  it("opens in Technical, with each run's split from AI Hub's counters, or that its timings are as recorded", () => {
    renderUi(<RunTimeline runs={livePass()} />, { detail: 'technical' });
    expect(toggle()).toHaveAttribute('aria-expanded', 'true');
    const figures = within(screen.getByTestId('run-timeline-figures')).getAllByRole('listitem');
    expect(figures.map((li) => li.textContent)).toEqual([
      'Conformance: model 11.2 s, tools 0.8 s, 1,240 reasoning tokens',
      'Encounter Integrity: timings as recorded',
      'Impact Analysis: timings as recorded',
      'Coordinator: timings as recorded',
    ]);
    // The table is the same facts again: closed in both modes
    expect(screen.getByRole('button', { name: 'As a table' })).toHaveAttribute('aria-expanded', 'false');
  });

  it('draws a bar per run from its start for its duration on one axis, the coordinator after the specialists', () => {
    const { container } = renderUi(<RunTimeline runs={livePass()} />, { detail: 'technical' });
    const bars = [...container.querySelectorAll('.run-clock-bar')];
    expect(bars.map((b) => b.getAttribute('data-member'))).toEqual([
      'conformance',
      'encounter',
      'impact',
      'coordinator',
    ]);
    const [conformance, encounter, impact, coordinator] = bars.map(box);
    // The specialists side by side from the start, each as long as it ran
    expect(Math.abs(conformance.x - encounter.x)).toBeLessThan(1);
    expect(impact.width / conformance.width).toBeCloseTo(15_976 / 14_735, 2);
    // The coordinator after the last of them, to the axis's end
    expect(coordinator.x).toBeGreaterThanOrEqual(impact.x + impact.width - 0.5);
    expect(coordinator.x + coordinator.width).toBeCloseTo(640 - 20, 0);
    // Each bar in its member's hue, by the validated tokens
    expect((bars[3] as SVGElement).style.getPropertyValue('--mark-hue')).toBe('var(--shutter-hue-violet)');
    // The axis in seconds from the first start, and the moment it started
    const ticks = [...container.querySelectorAll('.run-clock-tick')].map((t) => t.textContent);
    expect(ticks[0]).toBe('0 s');
    expect(ticks.at(-1)).toBe('30 s');
    expect(screen.getByText(/^Seconds from the pass's first start, /)).toBeInTheDocument();
  });

  it('marks each tool call on its bar at its time, a refused one outlined, and moves nothing', () => {
    const { container } = renderUi(<RunTimeline runs={livePass()} />, { detail: 'technical' });
    const rows = [...container.querySelectorAll('[data-row]')];
    const marks = (i: number) => [...rows[i].querySelectorAll('.run-clock-mark')];
    expect(rows.map((_, i) => marks(i).length)).toEqual([3, 2, 1, 1]);
    const bar = box(rows[0].querySelector('.run-clock-bar')!);
    for (const m of marks(0).map(box)) {
      expect(m.x).toBeGreaterThanOrEqual(bar.x);
      expect(m.x + m.width).toBeLessThanOrEqual(bar.x + bar.width + 0.01);
      expect(m.width).toBeGreaterThanOrEqual(2);
    }
    const refused = marks(1).filter((m) => m.hasAttribute('data-refused'));
    expect(refused).toHaveLength(1);
    expect(refused[0].querySelector('title')).toHaveTextContent('read_evidence, refused');
    expect(container.querySelector('animate, animateTransform, animateMotion, set')).toBeNull();
  });

  it('gives the same facts as a table', async () => {
    renderUi(<RunTimeline runs={livePass()} />, { detail: 'technical' });
    await userEvent.click(screen.getByRole('button', { name: 'As a table' }));
    const table = await screen.findByRole('table');
    expect(
      within(table)
        .getAllByRole('columnheader')
        .map((h) => h.textContent),
    ).toEqual(['Agent', 'Start', 'Took', 'Tool calls', 'Model time', 'Tool time', 'Reasoning tokens']);
    const rows = within(table)
      .getAllByRole('row')
      .slice(1)
      .map((r) => [...r.querySelectorAll('[role="rowheader"], [role="cell"]')].map((c) => c.textContent));
    expect(rows).toEqual([
      ['Conformance', '0.0 s', '14.7 s', '3', '11.2 s', '0.8 s', '1,240'],
      [
        'Encounter Integrity',
        '0.0 s',
        '11.6 s',
        '2, 1 refused',
        'not recorded',
        'not recorded',
        'not recorded',
      ],
      ['Impact Analysis', '0.0 s', '16.0 s', '1', 'not recorded', 'not recorded', 'not recorded'],
      ['Coordinator', '16.0 s', '14.9 s', '1', 'not recorded', 'not recorded', 'not recorded'],
    ]);
  });

  it('draws bars without marks when the starts are to the second, and says why', async () => {
    const pass = livePass().map((r) => ({ ...r, startedAtMs: undefined }));
    const { container } = renderUi(<RunTimeline runs={pass} />, { detail: 'technical' });
    expect(container.querySelectorAll('.run-clock-bar')).toHaveLength(4);
    expect(container.querySelectorAll('.run-clock-mark')).toHaveLength(0);
    expect(
      screen.getByText(/Its start is recorded to the second, so its tool calls are not drawn\./),
    ).toBeVisible();
    expect(screen.getByText(/, to the second\.$/)).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'As a table' }));
    expect(
      within(await screen.findByRole('table')).getByRole('rowheader', { name: 'Coordinator' }).parentElement,
    ).toHaveTextContent(/^Coordinator16 s/);
  });

  it('draws bars without marks when no call carries its time', () => {
    const pass = livePass().map((r) => ({ ...r, toolCalls: r.toolCalls.map((c) => ({ ...c, at: '' })) }));
    const { container } = renderUi(<RunTimeline runs={pass} />, { detail: 'technical' });
    expect(container.querySelectorAll('.run-clock-mark')).toHaveLength(0);
    expect(screen.getByText(/No tool-call times are recorded, so the bars carry no marks\./)).toBeVisible();
  });

  it('shows nothing for a pass its rows cannot draw honestly: the recording the trial replays, or no coordinator yet', () => {
    const recorded = (fixtures.cases as unknown as Record<string, { runs: AgentRun[] }>)['C-000008'].runs;
    const stray = livePass();
    stray[3] = {
      ...stray[3],
      toolCalls: [call(1, '2026-10-25T13:28:52.000Z', 1)],
      startedAtMs: '2026-10-25T13:28:52.000Z',
    };
    for (const runs of [recorded, livePass().slice(0, 3), stray]) {
      const { container, unmount } = renderUi(<RunTimeline runs={runs} />, { detail: 'technical' });
      expect(container.querySelector('[data-testid="run-timeline"], .tech-detail-toggle')).toBeNull();
      unmount();
    }
  });
});

describe('When each agent worked, on the board', () => {
  beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
  afterEach(() => server.resetHandlers());
  afterAll(() => server.close());
  beforeEach(() => resetMock('approver'));

  const board = (caseId: string) =>
    renderUi(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <BoardPanel caseId={caseId} open={false} mode="board" portalBase="/csp/shutter/" />
      </QueryClientProvider>,
    );

  it('sits under the specialists and above the coordinator, for a pass with its own clock', async () => {
    const recorded = (fixtures.cases as unknown as Record<string, { runs: AgentRun[] }>)['C-000008'].runs;
    server.use(
      http.get('/api/shutter/cases/C-000008/runs', () => HttpResponse.json(withLiveClock(recorded))),
    );
    board('C-000008');
    const section = await screen.findByRole('region', { name: 'The board' });
    const timeline = await within(section).findByRole('button', { name: 'When each agent worked' });
    const last = within(section).getByRole('region', { name: 'Impact Analysis' });
    const coordinator = within(section).getByRole('region', { name: 'Coordinator' });
    expect(last.compareDocumentPosition(timeline) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(timeline.compareDocumentPosition(coordinator) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });

  it('is not on the recorded board the trial replays', async () => {
    board('C-000008');
    const section = await screen.findByRole('region', { name: 'The board' });
    await within(section).findByRole('region', { name: 'Coordinator' });
    expect(within(section).queryByRole('button', { name: 'When each agent worked' })).not.toBeInTheDocument();
  });
});
