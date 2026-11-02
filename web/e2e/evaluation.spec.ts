import { expect, test, type Page } from '@playwright/test';
import { audit, choosePastel, MODES } from './axe';
import { skipWelcome } from './guide';
import { go, signIn, type Opened } from './helpers';

/**
 * The Evaluation page: the per-scenario table opened filtered by the address (as a link or the engineers' tour opens
 * it) and filtered from the headline; its 8 columns on a laptop with no sideways scroll; and the page with every
 * disclosure and every table view open, checked by axe in all five appearances in Plain and in Technical, and at a
 * phone's width.
 */

// The guide's welcome would cover the screens these tests are about; guide.spec.ts tests it
test.beforeEach(({ page }) => skipWelcome(page));

const table = (page: Page) => page.getByRole('region', { name: 'Per scenario' });

/**
 * Opens every closed disclosure and swaps every bar chart for its table, then waits for the panels to settle. Each
 * click takes the first one still closed: a list taken beforehand would shift under the clicks.
 */
async function openEverything(page: Page) {
  const closed = page.locator('.tech-detail-toggle[aria-expanded="false"]');
  for (let i = 0; i < 40 && (await closed.count()); i++) await closed.first().click();
  await expect(closed).toHaveCount(0);
  const bars = page.getByRole('button', { name: 'Show as a table' });
  for (let i = 0; i < 10 && (await bars.count()); i++) await bars.first().click();
  await expect(bars).toHaveCount(0);
  await page.waitForFunction(() =>
    document
      .getAnimations()
      .every((a) => a.playState !== 'running' || a.effect?.getTiming().iterations === Infinity),
  );
}

test.describe('the per-scenario table @evaluation', () => {
  test.beforeEach(({ page }) => signIn(page));

  test('opens filtered by the address', async ({ page }) => {
    await go(page, '/evaluation?show=rules-differs');
    await expect(table(page).getByText('7 passes shown')).toBeVisible();
    await expect(table(page).getByRole('radio', { name: 'Rules alone not as expected' })).toBeChecked();
    // The 7 passes, the header row and the Total row
    await expect(table(page).getByRole('row')).toHaveCount(9);
    await expect(table(page).getByRole('row', { name: /^S8 / })).toContainText(
      'Rules alone: wrote, not as expected',
    );
  });

  test('filters from the headline, and brings the table into view', async ({ page }) => {
    await go(page, '/evaluation');
    const majority = page
      .getByRole('region', { name: 'The board against the expected outcome' })
      .getByRole('button', { name: 'With the majority 11 passes' });
    await majority.click();
    await expect(majority).toHaveAttribute('aria-pressed', 'true');
    await expect(table(page).getByText('11 passes shown')).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Per scenario' })).toBeFocused();
    await expect(page).toHaveURL(/#\/evaluation\?show=with-the-majority$/);
  });

  for (const width of [1280, 1024])
    test(`does not scroll the page sideways at ${width} px`, async ({ page }) => {
      await page.setViewportSize({ width, height: 900 });
      await go(page, '/evaluation');
      await expect(table(page).getByText('25 passes shown')).toBeVisible();
      expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
      // On a laptop the 8 columns fit their card: the table does not scroll inside it either. Narrower, it may,
      // with the pass column kept in view.
      const scroll = table(page).locator('.eval-passes-scroll');
      const { scrollWidth, clientWidth } = await scroll.evaluate((el) => ({
        scrollWidth: el.scrollWidth,
        clientWidth: el.clientWidth,
      }));
      if (width === 1280) expect(scrollWidth).toBeLessThanOrEqual(clientWidth + 1);
      else await expect(table(page).locator('tbody td').first()).toHaveCSS('position', 'sticky');
    });
});

test.describe('every disclosure open on a phone at 360 px @evaluation', () => {
  test.use({ viewport: { width: 360, height: 800 } });

  for (const detail of [undefined, 'technical'] as const)
    test(`stays within the window${detail ? ', Technical' : ''}`, async ({ page }) => {
      const opened: Opened = { detail };
      await signIn(page, opened);
      await go(page, '/evaluation', opened);
      await expect(page.getByRole('heading', { name: 'Evaluation', exact: true })).toBeVisible();
      await openEverything(page);
      expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(360);
    });
});

for (const { colorScheme, contrast, palette } of MODES) {
  const mode = `${palette === 'pastel' ? 'pastel' : colorScheme}${contrast === 'more' ? ', high contrast' : ''}`;
  test.describe(`every disclosure open, axe-core, ${mode} @evaluation`, () => {
    test.use({ colorScheme, contrast });
    if (palette === 'pastel') test.beforeEach(({ page }) => choosePastel(page));

    for (const detail of [undefined, 'technical'] as const)
      test(`Evaluation${detail ? ', Technical' : ''}`, async ({ page }) => {
        const opened: Opened = { detail };
        await signIn(page, opened);
        await go(page, '/evaluation', opened);
        await expect(page.getByRole('heading', { name: 'Evaluation', exact: true })).toBeVisible();
        await openEverything(page);
        expect(await audit(page)).toEqual([]);
      });
  });
}
