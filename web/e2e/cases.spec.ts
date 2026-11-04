import { expect, test, type Page } from '@playwright/test';
import { skipWelcome } from './guide';
import { go, signIn } from './helpers';

/**
 * The Cases list: who investigated each case, what its plan proposed, and what came of it.
 */

// The guide's welcome would cover the screens these tests are about; guide.spec.ts tests it
test.beforeEach(({ page }) => skipWelcome(page));

const row = (page: Page, id: string) =>
  page.getByRole('row').filter({ has: page.getByRole('link', { name: id }) });

/** The table's case rows, not its header. */
const caseRows = (page: Page) =>
  page.getByRole('row').filter({ has: page.getByRole('link', { name: /^C-/ }) });

test.describe('the guided path', () => {
  test('the cases list says who investigated each case and what its plan proposed', async ({ page }) => {
    await signIn(page);
    await go(page, '/cases');
    await expect(page.getByRole('columnheader', { name: 'Investigated by' })).toBeVisible();
    await expect(page.getByRole('columnheader', { name: 'Proposed action' })).toBeVisible();
    // How to read the columns sits behind its own disclosure
    await page.getByRole('button', { name: 'How to read this list' }).click();
    await expect(
      page.getByText(
        /^Outcome is where the case stands, and what came of it\. Proposed action is what its plan proposed/,
      ),
    ).toBeVisible();
    // 25 a page, newest first, as the API serves them: the older cases through their scenario
    await page.getByLabel('Scenario', { exact: true }).selectOption('S2');
    await expect(row(page, 'C-000002')).toContainText('Board');
    await expect(row(page, 'C-000028')).toContainText('Site policy (no agents)');
    await expect(row(page, 'C-000028')).toContainText('entry E2');
    await page.getByLabel('Scenario', { exact: true }).selectOption('S8');
    await expect(row(page, 'C-000021')).toContainText('Rules only');
  });
});

test.describe('the outcome of each case', () => {
  test('says what came of a case, and shows the rules-only S8 resend as not what S8 expects', async ({
    page,
  }) => {
    await signIn(page);
    await go(page, '/cases');
    await expect(page.getByRole('columnheader', { name: 'Outcome' })).toBeVisible();
    await expect(row(page, 'C-000058')).toContainText('Delivered, verified');
    await expect(row(page, 'C-000063')).toContainText('Nothing to send, verified');
    // C-000021 is older than the first page: find it through its scenario
    await page.getByLabel('Scenario', { exact: true }).selectOption('S8');
    await expect(row(page, 'C-000021')).toContainText('Not as expected');
    await expect(row(page, 'C-000021')).toHaveAttribute('data-tone', 'blocking');
  });

  test('counts the closed cases by outcome, and a tile filters the list to them', async ({ page }) => {
    await signIn(page);
    await go(page, '/cases');
    // The tile's name says what a press does next, so it changes once pressed
    const delivered = page.getByRole('button', {
      name: /^\d+ Delivered, verified (Show these|Showing these)/,
    });
    await expect(delivered).toHaveAccessibleName(/Show these$/);
    await expect(delivered).toHaveAttribute('aria-pressed', 'false');
    await delivered.click();
    await expect(delivered).toHaveAttribute('aria-pressed', 'true');
    await expect(delivered).toHaveAccessibleName(/Showing these; press to clear$/);
    await expect(caseRows(page).first()).toBeVisible();
    expect(await caseRows(page).count()).toBeLessThanOrEqual(25);
    await expect(caseRows(page).filter({ hasNotText: 'Delivered, verified' })).toHaveCount(0);
    // A second press shows every case again
    await delivered.click();
    await expect(delivered).toHaveAttribute('aria-pressed', 'false');
    await expect(row(page, 'C-000063')).toContainText('Nothing to send, verified');
  });

  test('shows a long headline as its first sentence and keeps the rest behind a button', async ({ page }) => {
    await signIn(page);
    await go(page, '/cases');
    const c58 = row(page, 'C-000058');
    await expect(c58).toContainText('Resend the transfer to WARD-B unchanged, after rehearsal and approval.');
    const more = c58.getByRole('button', { name: 'More about C-000058' });
    await expect(more).toHaveAttribute('aria-expanded', 'false');
    await more.click();
    await expect(more).toHaveAttribute('aria-expanded', 'true');
    await expect(c58).toContainText('The destination bed is held by a patient who is leaving');
  });
});

test.describe('the Technical detail', () => {
  test('leaves a row without the failure codes in Plain', async ({ page }) => {
    await signIn(page);
    await go(page, '/cases');
    await expect(row(page, 'C-000058')).toContainText('Delivered, verified');
    await expect(row(page, 'C-000058')).not.toContainText('header 9625');
    await expect(row(page, 'C-000058')).not.toContainText('catalogue E16');
  });

  test('adds the failure and its codes to a row', async ({ page }) => {
    await signIn(page, { detail: 'technical' });
    await go(page, '/cases', { detail: 'technical' });
    const c58 = row(page, 'C-000058');
    await expect(c58).toContainText('header 9625');
    await expect(c58).toContainText('catalogue E16');
    await expect(c58).toContainText('rejected');
  });
});

test.describe('on a phone', () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test('reads each case as a compact card: its id and outcome, then what failed', async ({ page }) => {
    await signIn(page);
    await go(page, '/cases');
    const card = row(page, 'C-000058');
    await expect(card).toContainText('Delivered, verified');
    await expect(card).toContainText('Resend the transfer to WARD-B unchanged');
    // The visible column names are hidden: the values name themselves
    const label = await card
      .locator('td[data-label="At the receiver"]')
      .evaluate((td) => getComputedStyle(td, '::before').display);
    expect(label).toBe('none');
    const box = (await card.boundingBox())!;
    expect(box.height).toBeLessThan(330);
    expect(box.width).toBeLessThanOrEqual(390);
  });
});
