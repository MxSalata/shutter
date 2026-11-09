import { expect, test } from '@playwright/test';
import { skipWelcome } from './guide';
import { go, signIn } from './helpers';

// The trial's recordings: a stopped case shows what to check at the receiver, folded above its manual-handling action,
// and opening it fits a phone with no sideways scroll.
test.beforeEach(({ page }) => skipWelcome(page));

test('a stopped case opens what to check at the receiver', async ({ page }) => {
  await signIn(page);
  await go(page, '/cases/C-000008');
  const toggle = page.getByRole('button', { name: 'What to check at the receiver' });
  await toggle.click();
  const card = page.getByRole('region', { name: 'What to check at the receiver' });
  await expect(
    card.getByRole('heading', { name: 'What this message asked the receiver to record' }),
  ).toBeVisible();
  await expect(card).toContainText('may still arrive');
  await expect(card).toContainText('MRN1008');
  await expect(card).not.toContainText(/expected result|safe to resend/i);
});

test('it fits a phone', async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 800 });
  await signIn(page);
  await go(page, '/cases/C-000008');
  await page.getByRole('button', { name: 'What to check at the receiver' }).click();
  await page
    .getByRole('region', { name: 'What to check at the receiver' })
    .getByRole('heading', { name: 'Where to look' })
    .waitFor();
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  expect(overflow).toBeLessThanOrEqual(0);
});
