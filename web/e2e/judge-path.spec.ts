import { expect, test, type Page } from '@playwright/test';
import { audit } from './axe';

/**
 * The judges' path, each test in a fresh browser at 1280 and 390 px, as a judge arrives: from the S8 card in Rules only
 * to the write over the bed manager's ward, then the same card in Board to C-000008 escalated; `?trial=judge` landing on
 * S8 in Rules only with no welcome, before and after a reload; and the held-out card on the Evaluation. With E2E_SHOTS
 * set, each step is saved there. The Evaluation is also audited at the widths where its boundary table used to scroll
 * sideways.
 */

/** Waits until the page has stopped scrolling (a landing scrolls smoothly), then saves the screen when asked to. */
const shot = async (page: Page, name: string) => {
  if (!process.env.E2E_SHOTS) return;
  let last = -1;
  await expect
    .poll(async () => {
      const y = await page.evaluate(() => window.scrollY);
      const still = y === last;
      last = y;
      return still;
    })
    .toBe(true);
  await page.screenshot({ path: `${process.env.E2E_SHOTS}/${name}.png` });
};

const welcome = (page: Page) => page.getByRole('dialog', { name: 'Welcome to the Shutter trial' });
const s8Card = (page: Page) => page.locator('[data-first="S8"]');
const runS8 = (page: Page, mode: string) =>
  s8Card(page).getByRole('button', { name: `Run S8 in ${mode} mode` });

/** Plays S8 from its card in the mode the page has chosen, and waits for the run to finish. */
async function playS8(page: Page, mode: 'Rules only' | 'Board') {
  const run = runS8(page, mode);
  await expect(run).toHaveText(`Run S8 in ${mode}`);
  await run.click();
  // The recording plays for about eight seconds
  await expect(
    page.getByText(new RegExp(`^S8 played \\(${mode === 'Board' ? 'Board' : 'Rules'}\\)$`)),
  ).toBeVisible({ timeout: 20_000 });
}

for (const width of [1280, 390])
  test.describe(`the judges' path at ${width} px @scenarios`, () => {
    test.use({ viewport: { width, height: width < 600 ? 844 : 900 } });

    test('from the S8 card: Rules only writes WARD-B over WARD-C, Board escalates C-000008', async ({
      page,
    }) => {
      await page.goto('./#/scenarios');
      // A first entry is welcomed; Explore on my own puts it off, past a reload
      await welcome(page).getByRole('button', { name: 'Explore on my own' }).click();
      await expect(welcome(page)).toBeHidden();
      await page.reload();
      await expect(page.getByRole('heading', { name: 'Scenarios', exact: true })).toBeVisible();
      await expect(welcome(page)).toHaveCount(0);

      await page.getByRole('radio', { name: /^Rules only/ }).click();
      await expect(page).toHaveURL(/mode=rules/);
      await s8Card(page).scrollIntoViewIfNeeded();
      await expect(
        s8Card(page).getByRole('heading', { name: 'Rules only writes over a ward' }),
      ).toBeVisible();
      await shot(page, `card-rules-${width}`);
      await playS8(page, 'Rules only');
      await s8Card(page)
        .getByRole('link', { name: /^Open C-\d{6}, the latest S8 case in Rules only mode$/ })
        .click();
      await expect(page.getByRole('heading', { name: /^Case C-\d{6}/, level: 1 })).toBeVisible();
      const note = page.getByTestId('s8-rules-note');
      await expect(note).toHaveText(
        'Rules only, exempted here on purpose to show a plain resend: every check passed and WARD-B was written over WARD-C. On a real case the gate holds it.',
        { timeout: 15_000 },
      );
      await note.scrollIntoViewIfNeeded();
      await shot(page, `case-rules-${width}`);
      expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);

      await page.goBack();
      await expect(page).toHaveURL(/mode=rules/);
      await page.getByRole('radio', { name: /^Board/ }).click();
      await expect(page.getByRole('radio', { name: /^Board/ })).toBeChecked();
      await playS8(page, 'Board');
      await s8Card(page)
        .getByRole('link', { name: 'Open C-000008, the latest S8 case in Board mode' })
        .click();
      await expect(page.getByRole('heading', { name: /^Case C-000008/, level: 1 })).toBeVisible();
      await expect(page.getByText('Escalated', { exact: true }).first()).toBeVisible();
      await expect(page.getByTestId('s8-rules-note')).toHaveCount(0);
      await shot(page, `case-board-${width}`);
      expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
    });

    test('?trial=judge lands on S8 in Rules only with no welcome, and a reload keeps it away', async ({
      page,
    }) => {
      await page.goto('./?trial=judge');
      await expect(page).toHaveURL(/\?trial#\/scenarios\?mode=rules$/);
      await expect(page.getByRole('radio', { name: /^Rules only/ })).toBeChecked();
      await expect(runS8(page, 'Rules only')).toBeFocused();
      await expect(runS8(page, 'Rules only')).toBeInViewport();
      await expect(welcome(page)).toHaveCount(0);
      // The diagram draws how S8 should end; in Rules only the card says in words that it writes instead
      await expect(
        s8Card(page).getByText('Should end: a person decides. Rules only writes instead.'),
      ).toBeVisible();
      await shot(page, `judge-landing-${width}`);
      expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
      expect(await audit(page)).toEqual([]);

      await page.reload();
      await expect(page.getByRole('heading', { name: 'Scenarios', exact: true })).toBeVisible();
      await expect(page).toHaveURL(/\?trial#\/scenarios\?mode=rules$/);
      await expect(page.getByRole('radio', { name: /^Rules only/ })).toBeChecked();
      await expect(welcome(page)).toHaveCount(0);
    });

    test("puts the held-out card above the board's own score on the Evaluation", async ({ page }) => {
      await page.goto('./?trial=judge');
      await expect(runS8(page, 'Rules only')).toBeFocused();
      await page.goto('./?trial#/evaluation');
      await expect(page.getByRole('heading', { name: 'Evaluation', exact: true })).toBeVisible();
      await expect(welcome(page)).toHaveCount(0);
      const card = page.getByRole('region', { name: /^Held out: 12 sealed cases/ });
      await expect(card).toContainText(
        'the board 0.167, the single investigator 0.167 with two F08 runs settled (0.500 as graded), Site policy with no model 3.500, always escalating 1.250',
      );
      await expect(card).toContainText(
        "On 1.1.1's code the board proposed the same and the gate also held F03 and F07",
      );
      await card.scrollIntoViewIfNeeded();
      await shot(page, `evaluation-held-out-${width}`);
      expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
      expect(await audit(page)).toEqual([]);
    });
  });

// From 768 to about 1000 px the boundary's checks were a table wider than its column, which scrolled sideways; as a
// register they fit the column there, with nothing to scroll, and the page passes axe, in light and in dark
for (const width of [768, 992])
  for (const colorScheme of ['light', 'dark'] as const)
    test(`the Evaluation passes axe at ${width} px in ${colorScheme} @scenarios`, async ({ page }) => {
      await page.setViewportSize({ width, height: 900 });
      await page.emulateMedia({ colorScheme });
      await page.goto('./?trial=judge');
      await expect(runS8(page, 'Rules only')).toBeFocused();
      await page.goto('./?trial#/evaluation');
      await expect(page.getByRole('heading', { name: 'Evaluation', exact: true })).toBeVisible();
      const section = page.getByRole('region', { name: 'Approval safeguards' });
      await section.scrollIntoViewIfNeeded();
      await expect(section.getByRole('table')).toHaveCount(0);
      expect(await section.evaluate((el) => el.scrollWidth <= el.clientWidth)).toBe(true);
      expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
      expect(await audit(page)).toEqual([]);
    });
