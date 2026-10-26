import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';
import { skipWelcome } from './guide';

/**
 * Automated accessibility check (axe-core, WCAG 2.1 A and AA) of the sign-in page and every screen of the demo
 * build, in every appearance: light, pastel, dark, and both high-contrast modes. Serious and critical violations
 * fail the run; the rest are printed.
 */
const go = (page: Page, path: string) => page.goto(`./#${path}`);

// The guide's welcome would cover the screens these tests are about; guide.spec.ts tests it
test.beforeEach(({ page }) => skipWelcome(page));

/**
 * Opens every closed story step of a case page and waits for the panels to finish opening: a closed step is hidden,
 * and a check of the page would skip it.
 */
async function openSteps(page: Page) {
  for (const step of await page.getByRole('button', { name: /^\d\. / }).all())
    if ((await step.getAttribute('aria-expanded')) !== 'true') await step.click();
  await expect(page.getByRole('button', { name: /^\d\. /, expanded: false })).toHaveCount(0);
  await expect(page.getByRole('status')).toHaveCount(0);
  // The panels' opening transitions, not an endless one such as a progress bar's stripes
  await page.waitForFunction(() =>
    document
      .getAnimations()
      .every((a) => a.playState !== 'running' || a.effect?.getTiming().iterations === Infinity),
  );
}

async function signIn(page: Page) {
  await go(page, '/login');
  await page.getByRole('button', { name: /Try the demo/ }).click();
  await expect(page.getByRole('heading', { name: 'Scenarios' })).toBeVisible();
}

async function audit(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'])
    .analyze();
  const blocking = results.violations.filter((v) => v.impact === 'serious' || v.impact === 'critical');
  for (const v of results.violations)
    for (const n of v.nodes)
      console.log(`[a11y] ${v.impact ?? 'n/a'} ${v.id}: ${n.target.join(' ')} - ${n.any[0]?.message ?? ''}`);
  return blocking.map((v) => `${v.id} (${v.impact}) ×${v.nodes.length}: ${v.nodes[0]?.target.join(' ')}`);
}

/** The Site profile page with a change a case's What-if card suggested, pre-filled: the address names the case and the fact. */
const SUGGESTION = '/site-profile?suggest=C-000008&fact=W1';

const SCREENS: [path: string, heading: string, steps?: 'open'][] = [
  ['/scenarios', 'Scenarios'],
  ['/cases', 'Cases'],
  ['/cases/C-000009', 'Case C-000009'],
  ['/cases/C-000002', 'Case C-000002'],
  ['/cases/C-000007', 'Case C-000007'],
  ['/cases/C-000008', 'Case C-000008'],
  // The case page's other tabs, and the S8 comparison opened as the guide links to it
  ['/cases/C-000008?tab=evidence', 'Case C-000008'],
  ['/cases/C-000007?tab=audit', 'Case C-000007'],
  // Ask about this case, open: the example conversation, the suggested questions and the What-if card
  ['/cases/C-000008?ask=1', 'Case C-000008'],
  ['/cases/C-000002?ask=1', 'Case C-000002'],
  ['/cases/C-000008?show=compare', 'Case C-000008'],
  // Every story step open, on a case that waits for a person, one escalated by the board, a resolved one and two
  // blocked ones with the gate's checks and the next action
  ['/cases/C-000002', 'Case C-000002', 'open'],
  ['/cases/C-000008', 'Case C-000008', 'open'],
  ['/cases/C-000009', 'Case C-000009', 'open'],
  ['/cases/C-000053', 'Case C-000053', 'open'],
  ['/cases/C-000020', 'Case C-000020', 'open'],
  // S22's case at the patient records system: its category beside the outcome and the steps that correct its history
  ['/cases/C-000055', 'Case C-000055'],
  ['/incidents', 'Incidents'],
  ['/incidents/I-000001', 'Incident I-000001'],
  ['/reviews', 'Production review'],
  ['/reviews/PR-000001', 'Review PR-000001'],
  ['/reviews/PR-000003', 'Review PR-000003'],
  ['/site-profile', 'Site profile'],
  [SUGGESTION, 'Site profile'],
  ['/library', 'Agent library'],
  ['/settings', 'Settings and costs'],
  ['/evaluation', 'Evaluation'],
  ['/health', 'Health'],
];

const MODES = [
  { colorScheme: 'light', contrast: 'no-preference', palette: 'default' },
  { colorScheme: 'light', contrast: 'no-preference', palette: 'pastel' },
  { colorScheme: 'dark', contrast: 'no-preference', palette: 'default' },
  { colorScheme: 'light', contrast: 'more', palette: 'default' },
  { colorScheme: 'dark', contrast: 'more', palette: 'default' },
] as const;

for (const { colorScheme, contrast, palette } of MODES) {
  const mode = `${palette === 'pastel' ? 'pastel' : colorScheme}${contrast === 'more' ? ', high contrast' : ''}`;
  test.describe(`accessibility (axe-core, WCAG 2.1 A/AA), ${mode}`, () => {
    // Until the user picks otherwise, the app follows prefers-color-scheme and prefers-contrast.
    test.use({ colorScheme, contrast });
    // Pastel has no OS preference: it is the stored device setting, read before the first paint.
    if (palette === 'pastel')
      test.beforeEach(({ page }) =>
        page.addInitScript(() =>
          localStorage.setItem(
            'shutter.appearance',
            JSON.stringify({ state: { contrast: 'auto', palette: 'pastel' }, version: 0 }),
          ),
        ),
      );

    test('sign-in page', async ({ page }) => {
      await go(page, '/login');
      await expect(page.getByRole('button', { name: /^Sign in$/ })).toBeVisible();
      expect(await audit(page)).toEqual([]);
    });

    for (const [path, heading, steps] of SCREENS) {
      const name =
        path === SUGGESTION
          ? `${heading} (a suggested change)`
          : path.includes('?')
            ? `${heading} (${path.split('?')[1]})`
            : heading;
      test(steps ? `${name}, every step open` : name, async ({ page }) => {
        await signIn(page);
        await go(page, path);
        await expect(page.getByRole('heading', { name: heading, exact: true })).toBeVisible();
        // Wait for the page's data: the audit should see the screen, not its loading state.
        await expect(page.getByRole('status')).toHaveCount(0);
        if (steps) await openSteps(page);
        expect(await audit(page)).toEqual([]);
      });
    }

    // The guide, open: Help's menu, the welcome, a step, a case section it shows with Continue guide beside it, and
    // the chapter picker.
    test('the guide', async ({ page }) => {
      await signIn(page);
      await page.emulateMedia({ reducedMotion: 'reduce' });
      await page.getByRole('button', { name: 'Help' }).click();
      await expect(page.getByRole('menuitem', { name: 'Restart guide' })).toBeVisible();
      expect(await audit(page)).toEqual([]);
      await page.getByRole('menuitem', { name: 'Restart guide' }).click();
      const dialog = page.getByRole('dialog');
      await expect(dialog.getByRole('heading', { name: 'Welcome to Shutter' })).toBeVisible();
      expect(await audit(page)).toEqual([]);
      await dialog.getByRole('button', { name: 'Start guide' }).click();
      await expect(dialog.getByText('Step 1 of 3 · Scenarios')).toBeVisible();
      expect(await audit(page)).toEqual([]);
      await dialog.getByRole('button', { name: 'Skip chapter' }).click();
      await expect(dialog.getByText('Step 1 of 4 · S2: a transfer recovered')).toBeVisible();
      await dialog.getByRole('button', { name: 'Show this section' }).click();
      await expect(page.getByRole('region', { name: 'Guide' })).toBeVisible();
      await expect(page.getByRole('heading', { name: 'Outcome' })).toBeFocused();
      await expect(page.getByRole('status')).toHaveCount(0);
      expect(await audit(page)).toEqual([]);
      await page.getByRole('button', { name: 'Help' }).click();
      await page.getByRole('menuitem', { name: 'Choose a chapter' }).click();
      await expect(dialog.getByRole('heading', { name: 'Choose a chapter' })).toBeVisible();
      expect(await audit(page)).toEqual([]);
    });

    // Ask about this case on a phone: the full-screen sheet with the example, the chips and the What-if card
    test('Ask about this case on a phone', async ({ page }) => {
      await page.setViewportSize({ width: 390, height: 844 });
      await signIn(page);
      await page.emulateMedia({ reducedMotion: 'reduce' });
      await go(page, '/cases/C-000008?ask=1');
      const sheet = page.getByRole('dialog', { name: 'Ask about this case' });
      await expect(
        sheet.getByRole('region', { name: 'What if: the setting behind this outcome' }),
      ).toBeVisible();
      await expect(page.getByRole('status')).toHaveCount(0);
      expect(await audit(page)).toEqual([]);
      await sheet.getByRole('tab', { name: /Ask the board/ }).click();
      expect(await audit(page)).toEqual([]);
    });

    // The appearance menu, open: its items and their current-state labels are audited too.
    test('appearance menu', async ({ page }) => {
      await signIn(page);
      await page.emulateMedia({ reducedMotion: 'reduce' });
      await page.getByRole('button', { name: 'Appearance' }).click();
      await expect(page.getByRole('menuitem', { name: /^Pastel/ })).toBeVisible();
      expect(await audit(page)).toEqual([]);
    });
  });
}
