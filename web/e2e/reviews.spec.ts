import { expect, test } from '@playwright/test';
import { skipWelcome } from './guide';
import { go, READ_ONLY, signIn } from './helpers';

/**
 * The production review: a finished review of each production, its findings (closed until opened), the annotations
 * the live hospital's public role does not get, starting a review in the trial, and a review's findings stacked on a
 * phone.
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
      // The closed rows lead with a plain title; the check's code is in Technical and in the open finding
      for (const title of [
        'Alerts have nowhere to go',
        'No alert on error',
        'No alert on a growing queue',
        'A silent feed goes unnoticed',
      ])
        await expect(findings.getByText(title, { exact: true })).toBeVisible();
      // The recorded reviews carry no count of HL7 TCP items, so the page says nothing about them
      await expect(findings).not.toContainText('No HL7');
      // No recorded ranking: the agent's card says so, below the findings
      await expect(page.getByRole('region', { name: "The agent's ranking" })).toContainText(
        'This review was recorded without its ranking',
      );
    }
    await expect(
      page.getByRole('region', { name: 'Findings' }).getByText('No message purge task', { exact: true }),
    ).toBeVisible();
  });

  test('keeps every finding closed until it is opened, and shows its parts when it is', async ({ page }) => {
    await signIn(page);
    await go(page, '/reviews/PR-000001');
    await expect(page.getByRole('heading', { name: 'Review PR-000001', exact: true })).toBeVisible();
    const findings = page.getByRole('region', { name: 'Findings' });
    await expect(findings.getByRole('button', { expanded: true })).toHaveCount(0);
    // A closed finding keeps its text in the page but hides it
    await expect(findings.getByText('Why it matters', { exact: true }).first()).toBeHidden();
    const alerting = findings.getByRole('button', { name: 'No alert on error, ALERTING_OFF' });
    await alerting.click();
    await expect(alerting).toHaveAttribute('aria-expanded', 'true');
    const open = findings.getByRole('region', { name: 'No alert on error, ALERTING_OFF' });
    for (const part of [
      'Found',
      'Cases',
      'Evidence',
      'Why it matters',
      'Suggested',
      'In the Management Portal',
    ])
      await expect(open.getByText(part, { exact: true })).toBeVisible();
    // The Annotate button works while a finding is closed: it sits beside the control, not in it
    await expect(findings.getByRole('button', { name: 'Annotate F3, NO_ALERT_CONSUMER' })).toBeVisible();
  });

  test('narrows the findings with the filter chips', async ({ page }) => {
    await signIn(page);
    await go(page, '/reviews/PR-000001');
    const findings = page.getByRole('region', { name: 'Findings' });
    await expect(findings.getByRole('heading', { name: 'Low', level: 3 })).toBeVisible();
    await findings.getByText('Marked', { exact: true }).click();
    await expect(findings.getByRole('heading', { name: 'Low', level: 3 })).toHaveCount(0);
    await expect(findings.getByText('Repeated errors of one kind', { exact: true })).toHaveCount(1);
    await findings.getByText('All 13', { exact: true }).click();
    await expect(findings.getByRole('heading', { name: 'Low', level: 3 })).toBeVisible();
  });

  test('starts a review from a dialog in the trial, which replays a recorded one', async ({ page }) => {
    await signIn(page);
    await go(page, '/reviews');
    await expect(page.getByText('The trial replays a recorded review.')).toBeVisible();
    await page.getByRole('button', { name: 'Start a review' }).click();
    const dialog = page.getByRole('dialog');
    await expect(dialog.getByText('Trial only')).toBeVisible();
    await dialog.getByRole('button', { name: 'Start the review' }).click();
    await expect(page.getByRole('heading', { name: /^Review PR-\d{6}$/ })).toBeVisible();
    await expect(page.getByRole('region', { name: 'Findings' })).toBeVisible();
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
    // The findings are closed: open the first one before reading its halves
    const card = page.locator('[data-finding]').first();
    await card.getByRole('button', { expanded: false }).click();
    await expect(card.getByText('Found', { exact: true })).toBeVisible();
    const found = await card.getByText('Found', { exact: true }).boundingBox();
    const why = await card.getByText('Why it matters', { exact: true }).boundingBox();
    expect(found && why).toBeTruthy();
    // One column: the halves share a left edge, and the explanation half starts below the Found half
    expect(Math.abs(found!.x - why!.x)).toBeLessThanOrEqual(1);
    expect(why!.y).toBeGreaterThan(found!.y + found!.height);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
  });

  test('the list of reviews fits the width, with the latest of each production first', async ({ page }) => {
    await go(page, '/reviews');
    await expect(page.getByRole('heading', { name: 'Production review', exact: true })).toBeVisible();
    await expect(page.getByRole('region', { name: 'Latest per production' })).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
  });
});
