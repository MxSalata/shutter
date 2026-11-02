import { expect, test } from '@playwright/test';
import { skipWelcome } from './guide';
import { go, READ_ONLY, signIn } from './helpers';

/**
 * The Site profile: the two halves (what the policy does, then the answers), the save bar and the review, and the
 * pre-filled draft and its review kept for reading by the live hospital's public role.
 */

/** The live hospital's public role: the address keeps `?as=demo` in every step. */
const AS_DEMO = { as: 'demo' } as const;

// The guide's welcome would cover the screens these tests are about; guide.spec.ts tests it
test.beforeEach(({ page }) => skipWelcome(page));

test.describe('the live hospital, as the public role sees it', () => {
  test('keeps the pre-filled draft and its review for reading, with a note instead of Save', async ({
    page,
  }) => {
    await signIn(page, AS_DEMO);
    await go(page, '/site-profile?suggest=C-000008&fact=W1', AS_DEMO);
    const card = page.getByRole('region', { name: 'A suggested change from case C-000008' });
    await expect(card).toBeVisible();
    await expect(card.getByRole('button', { name: 'Review and save…' })).toHaveCount(0);
    await expect(page.getByRole('button', { name: /Review and save|Confirm these answers/ })).toHaveCount(0);
    await card.getByRole('button', { name: 'Review the change…' }).click();
    const dialog = page.getByRole('dialog');
    await expect(dialog.getByText(/Authoritative source: from .* to BEDMGR/)).toBeVisible();
    await expect(dialog.getByText(READ_ONLY)).toBeVisible();
    await expect(dialog.getByRole('button', { name: /^Save version/ })).toHaveCount(0);
    await dialog.getByRole('button', { name: 'Done' }).click();
    await expect(dialog).toHaveCount(0);
    await expect(page.getByText(READ_ONLY).first()).toBeVisible();
  });
});

test.describe('the trial, as the approver of the recorded runs', () => {
  test('shows the policy first: receivers with their tier, and who releases each write', async ({ page }) => {
    await signIn(page);
    await go(page, '/site-profile');
    const cards = page.getByRole('list', { name: 'The receivers and what each needs' });
    await expect(cards.getByRole('listitem', { name: 'Downstream Out' })).toContainText('Current state');
    await expect(cards.getByRole('listitem', { name: 'Downstream Out' })).toContainText('Tier 2, operations');
    await expect(cards.getByRole('listitem', { name: 'Records Out' })).toContainText('History of record');
    const matrix = page.getByRole('table', { name: 'Who releases each write' });
    await expect(matrix.getByRole('columnheader', { name: 'One failed message' })).toBeVisible();
    await expect(matrix.getByRole('rowheader', { name: /Tier 3: clinical safety/ })).toBeVisible();
    // The policy half comes before the answers
    const policy = await page.getByRole('heading', { name: "What this site's policy does" }).boundingBox();
    const answers = await page.getByRole('heading', { name: 'The answers', exact: true }).boundingBox();
    expect(policy!.y).toBeLessThan(answers!.y);
  });

  test('raises the save bar on a change, and saves it in the trial with the trial’s words', async ({
    page,
  }) => {
    await signIn(page);
    await go(page, '/site-profile');
    await expect(page.getByRole('region', { name: 'Unsaved changes' })).toHaveCount(0);
    await page.getByRole('switch', { name: /Downstream Out accepts cancels/ }).check();
    const bar = page.getByRole('region', { name: 'Unsaved changes' });
    await expect(bar).toContainText('1 change');
    await expect(bar).toContainText('A save lasts until you reload or leave.');
    await bar.getByRole('button', { name: 'Review and save…' }).click();
    const dialog = page.getByRole('dialog');
    await expect(dialog).toContainText('Trial only');
    await expect(dialog).toContainText("In the trial, saving changes only this browser's copy");
    await dialog.getByRole('button', { name: 'Save version 11' }).click();
    await expect(page.getByText('Version 11 saved')).toBeVisible();
    await expect(page.getByText('Saved in the trial. It lasts until you reload or leave.')).toBeVisible();
    await expect(bar).toHaveCount(0);
    await expect(page.getByText('Shipped answers')).toHaveCount(0);
  });

  test('jumps to a section of the answers from On this page, a select below 1408 px', async ({ page }) => {
    await signIn(page);
    await go(page, '/site-profile');
    await expect(page.getByRole('navigation', { name: 'On this page' })).toBeHidden();
    await page.getByRole('combobox', { name: 'On this page' }).selectOption({ label: 'Approvals, 7' });
    const heading = page.getByRole('heading', { name: 'Approvals', exact: true });
    await expect(heading).toBeFocused();
    await expect(heading).toBeInViewport();
  });

  test('shows On this page as a column from 1408 px', async ({ page }) => {
    await page.setViewportSize({ width: 1500, height: 900 });
    await signIn(page);
    await go(page, '/site-profile');
    const nav = page.getByRole('navigation', { name: 'On this page' });
    await expect(nav).toBeVisible();
    await expect(page.getByRole('combobox', { name: 'On this page' })).toBeHidden();
    await nav.getByRole('button', { name: 'Incidents, 8' }).click();
    await expect(page.getByRole('heading', { name: 'Incidents', exact: true })).toBeFocused();
  });

  test('puts each question’s key path in Keys and values, open in Technical', async ({ page }) => {
    await signIn(page, { detail: 'technical' });
    await go(page, '/site-profile', { detail: 'technical' });
    await expect(page.getByText('approvers.close_needs_approver', { exact: true }).first()).toBeVisible();
    await expect(page.getByText('feed.time_zone', { exact: true }).first()).toBeVisible();
    await expect(page.getByRole('table', { name: 'Who releases each write' })).toContainText('interleaved');
  });
});
