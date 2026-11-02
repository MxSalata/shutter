import axe from 'axe-core';

/**
 * Automated accessibility check (axe-core, WCAG 2.1 A and AA) of a part of a rendered component, for the component
 * tests: every violation, one line each, for the test to expect none of. jsdom lays nothing out and paints nothing, so
 * colour contrast cannot be measured here; the browser runs (e2e/axe.ts) measure it on the built pages.
 */
export async function axeViolations(node: Element): Promise<string[]> {
  const results = await axe.run(node, {
    runOnly: { type: 'tag', values: ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'] },
    rules: { 'color-contrast': { enabled: false } },
  });
  return results.violations.map(
    (v) => `${v.id} (${v.impact ?? 'n/a'}) x${v.nodes.length}: ${v.nodes[0]?.target.join(' ') ?? ''}`,
  );
}
