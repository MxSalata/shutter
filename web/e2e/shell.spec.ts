import { expect, test } from '@playwright/test';
import { skipWelcome } from './guide';
import { banner, go, signIn } from './helpers';

/**
 * The shell: the live hospital's banner on every page, for the public demo's role.
 */

/** The live hospital's public role: the address keeps `?as=demo` in every step. */
const AS_DEMO = { as: 'demo' } as const;

// The guide's welcome would cover the screens these tests are about; guide.spec.ts tests it
test.beforeEach(({ page }) => skipWelcome(page));

test.describe('the live hospital, as the public role sees it', () => {
  test('shows the live banner on every page', async ({ page }) => {
    await signIn(page, AS_DEMO);
    await expect(banner(page)).toContainText(
      /^Live hospital: a new failure every 7 minutes\. Last: S2, Never-accepted transfer, still current, \d+ (s|min) ago\. Next: S8 at \d\d:\d\d:\d\d (GMT|BST|UTC)\.$/,
    );
    for (const [path, heading] of [
      ['/cases', 'Cases'],
      ['/library', 'Agent library'],
      ['/site-profile', 'Site profile'],
      ['/settings', 'Settings and costs'],
    ]) {
      await go(page, path, AS_DEMO);
      await expect(page.getByRole('heading', { name: heading, exact: true })).toBeVisible();
      await expect(banner(page)).toBeVisible();
    }
  });
});
