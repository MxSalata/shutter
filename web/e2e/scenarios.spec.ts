import { expect, test } from '@playwright/test';
import { skipWelcome } from './guide';
import { go, signIn } from './helpers';

/**
 * The Scenarios page: no Run and no Reset for the live hospital's public role, and each description toggle named
 * after its scenario on a phone.
 */

/** The live hospital's public role: the address keeps `?as=demo` in every step. */
const AS_DEMO = { as: 'demo' } as const;

// The guide's welcome would cover the screens these tests are about; guide.spec.ts tests it
test.beforeEach(({ page }) => skipWelcome(page));

test.describe('the live hospital, as the public role sees it', () => {
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

test.describe('a phone at 390 px', () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test.beforeEach(({ page }) => signIn(page));

  test("each scenario's description toggle is named after its scenario", async ({ page }) => {
    await go(page, '/scenarios');
    const list = page.getByRole('region', { name: 'Every scenario' });
    await expect(list.getByRole('button', { name: /^Run S\d+[a-z]?$/ }).first()).toBeVisible();
    await expect(list.getByRole('button', { name: /^More about S\d+[a-z]?$/ }).first()).toBeVisible();
    await expect(list.getByRole('button', { name: 'More', exact: true })).toHaveCount(0);
  });
});
