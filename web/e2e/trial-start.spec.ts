import { expect, test } from './test';

/**
 * Where the trial starts: on its own sign-in page, as the live app starts on its sign-in page, unless the address
 * names a role (`?as=`) or the tab chose one before a reload. Continue goes on to the page the address asked for, with
 * the welcome, a tour or the judges' path after it.
 */

test.use({ trialRole: null });

const chooser = (page: import('./test').Page) =>
  page.getByRole('heading', { name: 'Choose who you are in the trial', level: 1 });

test.describe('the start of the trial', () => {
  test('opens on the sign-in page; Continue signs in, the welcome follows and a reload keeps the role', async ({
    page,
  }) => {
    await page.goto('./');
    await expect(chooser(page)).toBeVisible();
    await expect(
      page.getByText('The trial plays recorded runs in your browser, and nothing is sent anywhere.'),
    ).toBeVisible();
    await expect(page.getByRole('dialog', { name: 'Welcome to the Shutter trial' })).toHaveCount(0);
    await page.getByRole('button', { name: 'Continue as operator' }).click();
    await expect(page.getByRole('dialog', { name: 'Welcome to the Shutter trial' })).toBeVisible();
    await expect(page.getByRole('button', { name: /^Signed in as / })).toContainText(/operator/i);
    await page.reload();
    await expect(page.getByRole('button', { name: /^Signed in as / })).toContainText(/operator/i);
    await expect(chooser(page)).toHaveCount(0);
  });

  test('goes on to the page the address asked for', async ({ page }) => {
    await page.goto('./#/scenarios');
    await expect(chooser(page)).toBeVisible();
    await page.getByRole('button', { name: 'Continue as approver' }).click();
    await expect(page.getByRole('heading', { name: 'Scenarios', exact: true })).toBeVisible();
  });

  test("takes the judges' path after the sign-in page", async ({ page }) => {
    await page.goto('./?trial=judge');
    await expect(chooser(page)).toBeVisible();
    await page.getByRole('button', { name: 'Continue as judge' }).click();
    await expect(page.getByRole('radio', { name: /^Rules only/ })).toBeChecked();
    await expect(page.getByRole('dialog', { name: 'Welcome to the Shutter trial' })).toHaveCount(0);
  });

  test('skips the sign-in page when the address names a role', async ({ page }) => {
    await page.goto('./?as=operator#/scenarios');
    await expect(page.getByRole('heading', { name: 'Scenarios', exact: true })).toBeVisible();
    await expect(chooser(page)).toHaveCount(0);
  });
});
