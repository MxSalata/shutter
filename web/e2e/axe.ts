import AxeBuilder from '@axe-core/playwright';
import type { Page } from '@playwright/test';

/**
 * Automated accessibility check (axe-core, WCAG 2.1 A and AA) of the page as it stands: the serious and critical
 * violations, one line each, for the test to expect none of; every violation is printed.
 */
export async function audit(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'])
    .analyze();
  const blocking = results.violations.filter((v) => v.impact === 'serious' || v.impact === 'critical');
  for (const v of results.violations)
    for (const n of v.nodes)
      console.log(`[a11y] ${v.impact ?? 'n/a'} ${v.id}: ${n.target.join(' ')} - ${n.any[0]?.message ?? ''}`);
  return blocking.map((v) => `${v.id} (${v.impact}) ×${v.nodes.length}: ${v.nodes[0]?.target.join(' ')}`);
}

/** The five appearances: light, pastel, dark, and the high-contrast mode of light and dark. */
export const MODES = [
  { colorScheme: 'light', contrast: 'no-preference', palette: 'default' },
  { colorScheme: 'light', contrast: 'no-preference', palette: 'pastel' },
  { colorScheme: 'dark', contrast: 'no-preference', palette: 'default' },
  { colorScheme: 'light', contrast: 'more', palette: 'default' },
  { colorScheme: 'dark', contrast: 'more', palette: 'default' },
] as const;

/** Pastel has no OS preference: it is the stored device setting, read before the first paint. */
export function choosePastel(page: Page) {
  return page.addInitScript(() =>
    localStorage.setItem(
      'shutter.appearance',
      JSON.stringify({ state: { contrast: 'auto', palette: 'pastel' }, version: 0 }),
    ),
  );
}
