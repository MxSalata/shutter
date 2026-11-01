import { expect, test } from '@playwright/test';
import { skipWelcome } from './guide';
import { go, READ_ONLY, signIn } from './helpers';

/**
 * The production review: a finished review of each production, the annotations the live hospital's public role
 * does not get, and a review's findings stacked on a phone.
 */

/** The live hospital's public role: the address keeps `?as=demo` in every step. */
const AS_DEMO = { as: 'demo' } as const;

// The guide's welcome would cover the screens these tests are about; guide.spec.ts tests it
test.beforeEach(({ page }) => skipWelcome(page));

test.describe('the production review', () => {
  test('shows a finished review of each production, read only', async ({ page }) => {
    await signIn(page);
    await page.getByRole('link', { name: /Production review/ }).click();
    await expect(page.getByRole('heading', { name: 'Production review', exact: true })).toBeVisible();
    const past = page.getByRole('region', { name: 'Past reviews' });
    for (const [id, production] of [
      ['PR-000001', 'Shutter.Production'],
      ['PR-000003', 'Hospital.Production'],
    ]) {
      await go(page, '/reviews');
      await past.getByRole('link', { name: id, exact: true }).click();
      await expect(page.getByRole('heading', { name: `Review ${id}`, exact: true })).toBeVisible();
      await expect(page.getByText(`${production} in`, { exact: false }).first()).toBeVisible();
      const findings = page.getByRole('region', { name: 'Findings' });
      for (const code of ['NO_ALERT_CONSUMER', 'ALERTING_OFF', 'QUEUE_ALERTS_OFF', 'FEED_SILENCE_UNWATCHED'])
        await expect(findings.getByText(code, { exact: true })).toBeVisible();
      // The recorded reviews carry no count of HL7 TCP items, so the page says nothing about them
      await expect(findings).not.toContainText('No HL7');
      await expect(page.getByRole('region', { name: "The agent's ranking" })).toContainText(
        'No recorded explanation for this configuration',
      );
    }
    await expect(page.getByRole('region', { name: 'Findings' }).getByText('PURGE_MISSING')).toBeVisible();
  });
});

test.describe('the live hospital, as the public role sees it', () => {
  test('hides the review annotations', async ({ page }) => {
    await signIn(page, AS_DEMO);
    await go(page, '/reviews/PR-000001', AS_DEMO);
    await expect(page.getByRole('heading', { name: 'Review PR-000001', exact: true })).toBeVisible();
    await expect(page.getByText(READ_ONLY)).toBeVisible();
    await expect(page.getByRole('button', { name: /Annotate|Remove the annotation/ })).toHaveCount(0);
  });
});

test.describe('a phone at 390 px', () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test.beforeEach(({ page }) => signIn(page));

  test('a review stacks each finding, the Found half before the explanation half', async ({ page }) => {
    await go(page, '/reviews/PR-000001');
    await expect(page.getByRole('heading', { name: 'Review PR-000001', exact: true })).toBeVisible();
    await expect(page.getByRole('status')).toHaveCount(0);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
    const card = page.getByRole('region', { name: 'Findings' }).getByRole('article').first();
    const found = await card.getByText('Found', { exact: true }).boundingBox();
    const why = await card.getByText('Why it matters', { exact: true }).boundingBox();
    expect(found && why).toBeTruthy();
    // One column: the halves share a left edge, and the explanation half starts below the Found half
    expect(Math.abs(found!.x - why!.x)).toBeLessThanOrEqual(1);
    expect(why!.y).toBeGreaterThan(found!.y + found!.height);
  });
});
