import { render } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import type { Scenario } from '@/api/types';
import { ScenarioDiagram } from './ScenarioDiagram';
import { DIAGRAM_MODES } from './scenarioDiagramModel';
import definitions from '../../../../fixtures/scenarios.json';

const scenarios = definitions as unknown as Scenario[];

/** Where every box of the drawing stands, and the drawing's own size: what a switch of mode must leave as it is. */
function boxes(s: Scenario, mode: (typeof DIAGRAM_MODES)[number]) {
  const { container, unmount } = render(<ScenarioDiagram scenario={s} mode={mode} />);
  const svg = container.querySelector('svg');
  const found = svg
    ? {
        size: `${svg.getAttribute('width')}x${svg.getAttribute('height')}`,
        rects: [...svg.querySelectorAll('rect')].map((r) =>
          ['x', 'y', 'width', 'height'].map((a) => r.getAttribute(a)).join(' '),
        ),
        // A caption is centred under its box: its anchor stays put too
        captions: [...svg.querySelectorAll('.diagram-caption')].map((c) => c.getAttribute('x')),
      }
    : null;
  unmount();
  return found;
}

describe('ScenarioDiagram across the modes', () => {
  it('keeps every box where it is, so a switch of mode changes only the words', () => {
    const moved: string[] = [];
    for (const s of scenarios) {
      const [first, ...others] = DIAGRAM_MODES.map((m) => boxes(s, m));
      if (!first) continue;
      others.forEach((b, i) => {
        if (JSON.stringify(b) !== JSON.stringify(first)) moved.push(`${s.id} in ${DIAGRAM_MODES[i + 1]}`);
      });
    }
    expect(moved).toEqual([]);
  });

  it('draws the end pill of S2 the same width in Board and Site policy, whose captions differ', () => {
    const s = scenarios.find((x) => x.id === 'S2')!;
    const { container: board } = render(<ScenarioDiagram scenario={s} mode="board" />);
    const { container: policy } = render(<ScenarioDiagram scenario={s} mode="policy" />);
    const pill = (c: HTMLElement) => c.querySelector('.diagram-end rect')!.getAttribute('width');
    const caption = (c: HTMLElement) => c.querySelector('[data-row="end"] .diagram-caption')!.textContent;
    expect(caption(board)).toBe('after gate checks and approval');
    expect(caption(policy)).toBe('after gate checks and release');
    expect(pill(board)).toBe(pill(policy));
  });
});
