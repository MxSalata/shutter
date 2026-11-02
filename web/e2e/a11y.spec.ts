import { expect, test } from '@playwright/test';
import { audit, choosePastel, MODES } from './axe';
import { GUIDE_KEY, skipWelcome } from './guide';
import { atWidth, checkedBy, go, openSteps, screenName, signIn, signOutOfTrial } from './helpers';
import { areas, caseEvidence, shell, signIn as signInArea } from './areas';

/**
 * Automated accessibility check (axe-core, WCAG 2.1 A and AA) of the trial's sign-in page and every screen of the
 * demo build, which is always the trial (its banner, frame and pill on every screen), in every appearance: light,
 * pastel, dark, and both high-contrast modes. Serious and critical violations fail the run; the rest are printed. The
 * screens are each area's (`e2e/areas/`), and each test's title ends with its area's tag, so `--grep @<area>` runs one
 * area's share. The live sign-in page, which only a build IRIS serves has, is audited in e2e/trial.spec.ts.
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
      await signIn(page);
      await page.emulateMedia({ reducedMotion: 'reduce' });
      await signOutOfTrial(page);
      expect(await audit(page)).toEqual([]);
    });

    for (const area of areas)
      for (const screen of area.screens.filter((sc) => checkedBy(sc, 'a11y')))
        test(`${screenName(screen)} ${area.tag}`, async ({ page }) => {
          await atWidth(page, screen);
          await signIn(page, { detail: screen.detail });
          await go(page, screen.path, { detail: screen.detail });
          await expect(page.getByRole('heading', { name: screen.heading, exact: true })).toBeVisible();
          // Wait for the page's data: the audit should see the screen, not its loading state.
          await expect(page.getByRole('status')).toHaveCount(0);
          if (screen.steps) await openSteps(page);
          expect(await audit(page)).toEqual([]);
        });

    // The guide, open: Help's menu, the welcome, a step's card before a case section with its ring and try-it, and
    // the chapter picker; and the finish card.
    test('the guide', async ({ page }) => {
      await signIn(page);
      await page.emulateMedia({ reducedMotion: 'reduce' });
      await page.getByRole('button', { name: 'Tour' }).click();
      await expect(page.getByRole('menuitem', { name: 'Restart the tour' })).toBeVisible();
      expect(await audit(page)).toEqual([]);
      await page.getByRole('menuitem', { name: 'Restart the tour' }).click();
      const welcome = page.getByRole('dialog', { name: 'Welcome to the Shutter trial' });
      await expect(welcome.getByRole('radio', { name: /Quick tour/ })).toBeVisible();
      expect(await audit(page)).toEqual([]);
      await welcome.getByRole('button', { name: 'Start the tour' }).click();
      const guide = page.getByRole('region', { name: 'Guide' });
      await expect(guide).toContainText('Step 1 of 9');
      await guide.getByRole('button', { name: 'Next' }).click();
      await guide.getByRole('button', { name: 'Next' }).click();
      await expect(guide).toContainText('Step 3 of 9');
      await expect(guide.getByRole('button', { name: 'Try it: press Approve plan' })).toBeVisible();
      await expect(page.getByRole('status')).toHaveCount(0);
      expect(await audit(page)).toEqual([]);
      await page.getByRole('button', { name: 'Tour' }).click();
      await page.getByRole('menuitem', { name: 'Choose a chapter' }).click();
      await expect(page.getByRole('dialog', { name: 'Choose a chapter' })).toBeVisible();
      expect(await audit(page)).toEqual([]);
      await page
        .getByRole('dialog', { name: 'Choose a chapter' })
        .getByRole('button', { name: /^Evaluation/ })
        .click();
      await expect(guide).toContainText('Step 9 of 9');
      await guide.getByRole('button', { name: 'Finish' }).click();
      await expect(guide.getByRole('heading', { name: 'That is the tour.' })).toBeVisible();
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

    // Ask beside the tour on a laptop: the sheet with no overlay, and the guide's card in its dock
    test(`Ask about this case beside the tour ${caseEvidence.tag}`, async ({ page }) => {
      await page.addInitScript((key) => {
        localStorage.setItem(
          key,
          JSON.stringify({ version: 2, scope: 'quick', at: 's8/ask', completed: [], dismissed: true }),
        );
      }, GUIDE_KEY);
      await page.setViewportSize({ width: 1280, height: 800 });
      await signIn(page);
      await page.emulateMedia({ reducedMotion: 'reduce' });
      await page.getByRole('button', { name: 'Resume tour' }).click();
      await page.getByRole('menuitem', { name: 'Resume the tour' }).click();
      const guide = page.getByRole('region', { name: 'Guide' });
      await expect(guide).toContainText('Step 7 of 9');
      await page.locator('[data-tour-action="ask-open"]').click();
      const panel = page.getByRole('region', { name: 'Ask about this case' });
      await expect(
        panel.getByRole('region', { name: 'What if: the setting behind this outcome' }),
      ).toBeVisible();
      await expect(page.locator('[data-guide-dock] [data-guide-card]')).toBeVisible();
      await expect(page.getByRole('status')).toHaveCount(0);
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
