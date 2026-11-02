import { expect, test } from '@playwright/test';
import { skipWelcome } from './guide';
import { go, signIn } from './helpers';

/**
 * The Scenarios page: no Run and no Reset for the live hospital's public role; the three starters' Run buttons in one
 * line; the guided path's links; each row's latest case by outcome; and on a phone each description toggle named after
 * its scenario, and the rows as compact cards that never scroll sideways.
 */

/** The live hospital's public role: the address keeps `?as=demo` in every step. */
const AS_DEMO = { as: 'demo' } as const;

// The guide's welcome would cover the screens these tests are about; guide.spec.ts tests it
test.beforeEach(({ page }) => skipWelcome(page));

test.describe('the live hospital, as the public role sees it @scenarios', () => {
  test('offers no Run and no Reset, and says the demo plays its stories by itself', async ({ page }) => {
    await signIn(page, AS_DEMO);
    await expect(page.getByText(/The public demo plays its stories by itself/)).toBeVisible();
    await expect(page.getByRole('region', { name: 'Every scenario' })).toBeVisible();
    await expect(page.getByRole('button', { name: /^Run / })).toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Reset' })).toHaveCount(0);
    await expect(page.getByRole('columnheader', { name: 'Play' })).toHaveCount(0);
    // The three first cases still open their cases
    await expect(
      page.getByRole('region', { name: 'Try these three first' }).getByRole('link', { name: /^Open C-/ }),
    ).toHaveCount(3);
  });
});

test.describe('the page at 1280 px @scenarios', () => {
  test.use({ viewport: { width: 1280, height: 900 } });

  test.beforeEach(({ page }) => signIn(page));

  test("lines up the three starters' Run buttons", async ({ page }) => {
    await go(page, '/scenarios');
    const first = page.getByRole('region', { name: 'Try these three first' });
    const runs = [
      first.getByRole('button', { name: 'Run S2 in Board mode' }),
      first.getByRole('button', { name: 'Run S8 in Board mode' }),
      first.getByRole('button', { name: 'Run S20 in Rules only mode' }),
    ];
    const tops: number[] = [];
    for (const run of runs) tops.push((await run.boundingBox())!.y);
    expect(Math.max(...tops) - Math.min(...tops)).toBeLessThanOrEqual(1);
  });

  test('leads through the guided path by its links, each step a sentence with the rest behind More', async ({
    page,
  }) => {
    await go(page, '/scenarios');
    const card = page.getByRole('region', { name: 'Start here' });
    await expect(card.getByRole('listitem')).toHaveCount(6);
    for (const name of [
      'Case C-000002',
      'Case C-000021',
      'Case C-000008',
      'Rules and board side by side',
      'Case C-000012',
      'Incident I-000001',
      'Settings and costs',
      'Evaluation',
    ])
      await expect(card.getByRole('link', { name, exact: true })).toBeVisible();
    const more = card.getByRole('button', { name: 'More about step 1' });
    await expect(more).toHaveAttribute('aria-expanded', 'false');
    await more.click();
    await expect(more).toHaveAttribute('aria-expanded', 'true');
    await expect(card.getByText(/one conditional write, then "Verified"/)).toBeVisible();
  });

  test("shows each row's latest case by its outcome, with how it compares with what the scenario expects", async ({
    page,
  }) => {
    await go(page, '/scenarios');
    const list = page.getByRole('region', { name: 'Every scenario' });
    const s5 = list.locator('tr[data-scenario="S5"]');
    await expect(s5.getByText('Delivered, verified')).toBeVisible();
    await expect(s5.getByText('As expected')).toBeVisible();
    await expect(s5).toHaveAttribute('data-tone', 'positive');
    await expect(list.locator('tr[data-scenario="S1"]')).toContainText(
      'Recorded: board as expected; simple rules stopped by the gate',
    );
  });

  test('adds the HL7 events and the proof bases in Technical', async ({ page }) => {
    await go(page, '/scenarios', { detail: 'technical' });
    const list = page.getByRole('region', { name: 'Every scenario' });
    await expect(list.locator('tr[data-scenario="S2"]').getByText('A01, A02 fails')).toBeVisible();
    await expect(
      page.getByText(/24 scored passes, proposed action; 11 scenarios, played end to end/),
    ).toBeVisible();
  });
});

test.describe('a phone at 390 px @scenarios', () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test.beforeEach(({ page }) => signIn(page));

  test("each scenario's description toggle is named after its scenario", async ({ page }) => {
    await go(page, '/scenarios');
    const list = page.getByRole('region', { name: 'Every scenario' });
    await expect(list.getByRole('button', { name: /^Run S\d+[a-z]?$/ }).first()).toBeVisible();
    await expect(list.getByRole('button', { name: /^More about S\d+[a-z]?$/ }).first()).toBeVisible();
    await expect(list.getByRole('button', { name: 'More', exact: true })).toHaveCount(0);
  });

  test('shows each scenario as a compact card, within the width of the phone', async ({ page }) => {
    await go(page, '/scenarios');
    const list = page.getByRole('region', { name: 'Every scenario' });
    const s2 = list.locator('tr[data-scenario="S2"]');
    await expect(s2.getByRole('button', { name: 'Run S2' })).toBeVisible();
    const box = (await s2.boundingBox())!;
    expect(box.x + box.width).toBeLessThanOrEqual(390);
    // The cells name themselves: no column names are drawn above them
    const label = await s2
      .locator('td[data-label="What should happen"]')
      .evaluate((td) => getComputedStyle(td, '::before').display);
    expect(label).toBe('none');
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
  });
});
