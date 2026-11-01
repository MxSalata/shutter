import { expect, test } from '@playwright/test';
import { skipWelcome } from './guide';
import { go, READ_ONLY, signIn } from './helpers';

/**
 * The Agent library: the switches the live hospital's public role does not get.
 */

/** The live hospital's public role: the address keeps `?as=demo` in every step. */
const AS_DEMO = { as: 'demo' } as const;

// The guide's welcome would cover the screens these tests are about; guide.spec.ts tests it
test.beforeEach(({ page }) => skipWelcome(page));

test.describe('the live hospital, as the public role sees it', () => {
  test('hides the library switches', async ({ page }) => {
    await signIn(page, AS_DEMO);
    await go(page, '/library', AS_DEMO);
    await expect(page.getByText(READ_ONLY)).toBeVisible();
    await expect(page.getByRole('switch')).toHaveCount(0);
  });
});
