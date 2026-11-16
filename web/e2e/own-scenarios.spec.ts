import { expect, test, type Locator, type Page } from '@playwright/test';
import { audit } from './axe';
import { skipWelcome } from './guide';
import { go, READ_ONLY, signIn } from './helpers';

/**
 * The site's own scenarios on the Site profile page (CONTRACTS 6.8), in the trial's sample entries: the workbench
 * started from a closed case, its chips wrapping at a phone's width, by keyboard and by touch, in light and dark; a
 * second person's review of the waiting sample; and the public demo's role, who reads and tries and saves nothing.
 */

test.beforeEach(({ page }) => skipWelcome(page));

const noSidewaysScroll = (page: Page) =>
  page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth);

/** Every chip inside its group's box, the group no wider than its box: the chips wrap and nothing runs off. */
const chipsWrap = (chips: Locator) =>
  chips.evaluate((el) => {
    const box = el.getBoundingClientRect();
    const labels = [...el.querySelectorAll('label')];
    const rows = new Set(labels.map((l) => Math.round(l.getBoundingClientRect().top)));
    return {
      inside: labels.every((l) => l.getBoundingClientRect().right <= box.right + 1),
      fits: el.scrollWidth <= el.clientWidth + 1,
      rows: rows.size,
    };
  });

async function openFromCase(page: Page, caseId = 'C-000028') {
  await signIn(page);
  await go(page, `/site-profile?own=new&case=${caseId}`);
  const bench = page.getByTestId('own-workbench');
  await expect(bench.getByTestId('own-chips')).toBeVisible();
  await expect(bench.getByTestId('own-live-impact')).toContainText(/Of the last \d+ cases, it would catch/);
  return bench;
}

for (const width of [1280, 360])
  for (const colorScheme of ['light', 'dark'] as const)
    test.describe(`the workbench at ${width} px in ${colorScheme}`, () => {
      test.use({ colorScheme, viewport: { width, height: 900 } });
      test('opens from a case with every condition ticked, the chips wrap, and the page is axe clean', async ({
        page,
      }) => {
        const bench = await openFromCase(page);
        const chips = bench.getByTestId('own-chips');
        const boxes = chips.getByRole('checkbox');
        expect(await boxes.count()).toBeGreaterThan(5);
        for (const box of await boxes.all()) await expect(box).toBeChecked();
        const wrap = await chipsWrap(chips);
        expect(wrap.inside && wrap.fits).toBe(true);
        if (width === 360) expect(wrap.rows).toBeGreaterThan(1);
        await expect(bench.getByTestId('own-near-miss-ask')).toBeVisible();
        expect(await noSidewaysScroll(page)).toBe(true);
        expect(await audit(page)).toEqual([]);
        if (process.env.E2E_SHOTS)
          await bench.screenshot({ path: `${process.env.E2E_SHOTS}/workbench-${width}-${colorScheme}.png` });
        // The proof's table, from a try, at this width
        await bench.getByLabel('Another closed case').fill('C-000027');
        await bench.getByRole('button', { name: 'Add as a near miss' }).click();
        await bench.getByTestId('own-try').click();
        const tried = bench.getByTestId('own-tried');
        await expect(tried).toContainText('The proof passes');
        await expect(tried.getByRole('row')).toHaveCount(3);
        expect(await noSidewaysScroll(page)).toBe(true);
        expect(await audit(page)).toEqual([]);
        if (process.env.E2E_SHOTS)
          await tried.screenshot({ path: `${process.env.E2E_SHOTS}/proof-${width}-${colorScheme}.png` });
        // The review dialog of the waiting sample
        await page.getByRole('button', { name: 'Review L2' }).click();
        const dialog = page.getByRole('dialog', { name: 'Approve or reject: L2 version 1' });
        await expect(dialog.getByTestId('own-displaces')).toContainText('Without it: E2');
        expect(await noSidewaysScroll(page)).toBe(true);
        expect(await audit(page)).toEqual([]);
        if (process.env.E2E_SHOTS)
          await dialog.screenshot({ path: `${process.env.E2E_SHOTS}/review-${width}-${colorScheme}.png` });
      });
    });

test.describe('the workbench without a mouse', () => {
  test('unticks a chip from the keyboard, and the count is asked again', async ({ page }) => {
    const bench = await openFromCase(page);
    const chip = bench.getByTestId('own-chips').getByRole('checkbox', { name: 'nothing later was applied' });
    await chip.focus();
    await page.keyboard.press('Space');
    await expect(chip).not.toBeChecked();
    await expect(bench.getByTestId('own-live-impact')).toContainText(/it would catch/);
    await page.keyboard.press('Space');
    await expect(chip).toBeChecked();
    // Tab reaches the scope's chips and the buttons, with nothing that needs a hover
    await bench.getByRole('button', { name: 'Try it' }).focus();
    await page.keyboard.press('Enter');
    await expect(bench.getByTestId('own-tried')).toBeVisible();
  });

  test('works by touch on a phone: a chip, a near miss, Try it and the review', async ({ browser }) => {
    const context = await browser.newContext({ viewport: { width: 360, height: 800 }, hasTouch: true });
    const page = await context.newPage();
    await skipWelcome(page);
    const bench = await openFromCase(page);
    const chip = bench.getByTestId('own-chips').getByRole('checkbox', { name: 'nothing later was applied' });
    await bench.getByTestId('own-chips').getByText('nothing later was applied').tap();
    await expect(chip).not.toBeChecked();
    await bench.getByTestId('own-chips').getByText('nothing later was applied').tap();
    await expect(chip).toBeChecked();
    await bench.getByLabel('Another closed case').fill('C-000027');
    await bench.getByRole('button', { name: 'Add as a near miss' }).tap();
    await bench.getByTestId('own-try').tap();
    await expect(bench.getByTestId('own-tried')).toContainText('The proof passes');
    await page.getByRole('button', { name: 'Review L2' }).tap();
    await expect(page.getByRole('dialog', { name: 'Approve or reject: L2 version 1' })).toBeVisible();
    await context.close();
  });
});

test.describe('a second person approves the waiting sample', () => {
  test('with a reason: it becomes active, in this browser only', async ({ page }) => {
    await signIn(page);
    await go(page, '/site-profile');
    await page.getByRole('button', { name: 'Review L2' }).click();
    const dialog = page.getByRole('dialog', { name: 'Approve or reject: L2 version 1' });
    await expect(dialog.getByText(/approving changes only this browser's copy/)).toBeVisible();
    await expect(dialog.getByTestId('own-approval-proof')).toContainText('The proof passes');
    await dialog.getByLabel(/^Reason/).fill('Agreed with the ward');
    await dialog.getByRole('button', { name: 'Approve' }).click();
    await expect(dialog).toHaveCount(0);
    await expect(page.getByTestId('own-group-active').getByTestId('own-scenario-L2')).toContainText(
      'Version 1 approved by approver',
    );
  });
});

test.describe('the public demo', () => {
  const AS_DEMO = { as: 'demo' } as const;
  test("reads an entry and tries it; Save, propose and approve are locked with the site profile's explanation", async ({
    page,
  }) => {
    await signIn(page, AS_DEMO);
    await go(page, '/site-profile', AS_DEMO);
    await expect(page.getByTestId('own-new')).toHaveCount(0);
    await page.getByRole('button', { name: 'Open L2' }).click();
    const bench = page.getByTestId('own-workbench');
    await bench.getByTestId('own-try').click();
    await expect(bench.getByTestId('own-tried')).toContainText('The proof passes');
    await expect(bench.getByText(READ_ONLY)).toBeVisible();
    await bench.getByRole('button', { name: 'Review the proposal…' }).click();
    const dialog = page.getByRole('dialog', { name: 'Approve or reject: L2 version 1' });
    const approve = dialog.getByRole('button', { name: 'Approve' });
    await expect(approve).toHaveAttribute('aria-disabled', 'true');
    await expect(approve).toHaveAccessibleDescription(READ_ONLY);
  });
});

test.describe('from a case', () => {
  test('a closed case offers "Make this one of our scenarios", which opens the workbench on it', async ({
    page,
  }) => {
    await signIn(page);
    await go(page, '/cases/C-000028');
    await page.getByRole('tab', { name: 'Audit trail' }).click();
    await page.getByTestId('own-scenario-from-case').click();
    const bench = page.getByTestId('own-workbench');
    await expect(bench.getByTestId('own-chips')).toBeVisible();
    await expect(bench.getByTestId('own-fixtures')).toContainText('C-000028: it must catch this case');
  });
});
