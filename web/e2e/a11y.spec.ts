import { expect, test } from '@playwright/test';
import { audit, choosePastel, MODES } from './axe';
import { skipWelcome } from './guide';
import { checkedBy, go, openSteps, screenName, signIn } from './helpers';
import { areas, caseEvidence, shell, signIn as signInArea } from './areas';

/**
 * Automated accessibility check (axe-core, WCAG 2.1 A and AA) of the sign-in page and every screen of the demo
 * build, in every appearance: light, pastel, dark, and both high-contrast modes. Serious and critical violations
 * fail the run; the rest are printed. The screens are each area's (`e2e/areas/`), and each test's title ends with
 * its area's tag, so `--grep @<area>` runs one area's share.
 */

// The guide's welcome would cover the screens these tests are about; guide.spec.ts tests it
test.beforeEach(({ page }) => skipWelcome(page));

for (const { colorScheme, contrast, palette } of MODES) {
  const mode = `${palette === 'pastel' ? 'pastel' : colorScheme}${contrast === 'more' ? ', high contrast' : ''}`;
  test.describe(`accessibility (axe-core, WCAG 2.1 A/AA), ${mode}`, () => {
    // Until the user picks otherwise, the app follows prefers-color-scheme and prefers-contrast.
    test.use({ colorScheme, contrast });
    // Pastel has no OS preference: it is the stored device setting, read before the first paint.
    if (palette === 'pastel') test.beforeEach(({ page }) => choosePastel(page));

    test(`sign-in page ${signInArea.tag}`, async ({ page }) => {
      await go(page, '/login');
      await expect(page.getByRole('button', { name: /^Sign in$/ })).toBeVisible();
      expect(await audit(page)).toEqual([]);
    });

    for (const area of areas)
      for (const screen of area.screens.filter((sc) => checkedBy(sc, 'a11y')))
        test(`${screenName(screen)} ${area.tag}`, async ({ page }) => {
          await signIn(page, { detail: screen.detail });
          await go(page, screen.path, { detail: screen.detail });
          await expect(page.getByRole('heading', { name: screen.heading, exact: true })).toBeVisible();
          // Wait for the page's data: the audit should see the screen, not its loading state.
          await expect(page.getByRole('status')).toHaveCount(0);
          if (screen.steps) await openSteps(page);
          expect(await audit(page)).toEqual([]);
        });

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
    test(`Ask about this case on a phone ${caseEvidence.tag}`, async ({ page }) => {
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
    test(`appearance menu ${shell.tag}`, async ({ page }) => {
      await signIn(page);
      await page.emulateMedia({ reducedMotion: 'reduce' });
      await page.getByRole('button', { name: 'Appearance' }).click();
      await expect(page.getByRole('menuitem', { name: /^Pastel/ })).toBeVisible();
      expect(await audit(page)).toEqual([]);
    });
  });
}
