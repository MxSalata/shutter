import { expect, test } from '@playwright/test';
import { skipWelcome } from './guide';
import { signIn, signOutOfTrial } from './helpers';

/**
 * Signing in. The demo build is always the trial and opens signed in, so the sign-in page it can show is the trial's
 * own: its roles, no password. The live sign-in page (the proof and the way into the trial) exists only in a build
 * IRIS serves, so `trial.spec.ts` (the `iris-trial` project) opens and audits that one.
 */

// The guide's welcome would cover the page these tests are about; guide.spec.ts tests it
test.beforeEach(({ page }) => skipWelcome(page));

test.describe("the trial's sign-in page", () => {
  test('offers the four roles with no password, and no way out of the demo build', async ({ page }) => {
    await signIn(page);
    await signOutOfTrial(page);
    await expect(page.getByText("No password: these are the trial's own roles.")).toBeVisible();
    for (const role of ['approver', 'operator', 'public demo role', 'judge'])
      await expect(page.getByRole('button', { name: `Continue as ${role}` })).toBeVisible();
    await expect(page.getByLabel(/Password/)).toHaveCount(0);
    // The demo build has no live system at its address to go back to
    await expect(page.getByRole('button', { name: 'Leave trial' })).toHaveCount(0);
  });

  test('signs in as the role chosen', async ({ page }) => {
    await signIn(page);
    await signOutOfTrial(page);
    await page.getByRole('button', { name: 'Continue as operator' }).click();
    await expect(page.getByRole('heading', { name: 'Scenarios', exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Signed in as operator' })).toBeVisible();
  });
});
