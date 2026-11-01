import { expect, test, type Page } from '@playwright/test';
import { audit, choosePastel, MODES } from './axe';
import { skipWelcome } from './guide';

/**
 * The demo opened as the live hospital's public role (`?as=demo`): the mock signs "Try the demo" in as `demo`, who
 * approves but cannot run or reset scenarios or save the site, and whose settings carry a live hospital. The address
 * keeps `?as=demo` in every step: a navigation that drops it reloads the page, and the mock forgets who is signed in.
 */
const go = (page: Page, path: string) => page.goto(`./?as=demo#${path}`);

// The guide's welcome would cover the screens these tests are about; guide.spec.ts tests it
test.beforeEach(({ page }) => skipWelcome(page));

async function signIn(page: Page) {
  await go(page, '/login');
  await page.getByRole('button', { name: /^Try the demo \(live hospital/ }).click();
  await expect(page.getByRole('heading', { name: 'Scenarios', exact: true })).toBeVisible();
}

const banner = (page: Page) => page.getByRole('region', { name: 'Live hospital' });
const READ_ONLY = /The public demo is read-only: a site's approver saves changes here/;

test.describe('the live hospital, as the public role sees it', () => {
  test('shows the live banner on every page', async ({ page }) => {
    await signIn(page);
    await expect(banner(page)).toContainText(
      /^Live hospital: a new failure every 7 minutes\. Last: S2, Never-accepted transfer, still current, \d+ (s|min) ago\. Next: S8 at \d\d:\d\d:\d\d (GMT|BST|UTC)\.$/,
    );
    for (const [path, heading] of [
      ['/cases', 'Cases'],
      ['/library', 'Agent library'],
      ['/site-profile', 'Site profile'],
      ['/settings', 'Settings and costs'],
    ]) {
      await go(page, path);
      await expect(page.getByRole('heading', { name: heading, exact: true })).toBeVisible();
      await expect(banner(page)).toBeVisible();
    }
  });

  test('offers no Run and no Reset, and says the demo plays its stories by itself', async ({ page }) => {
    await signIn(page);
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

  test('keeps the pre-filled draft and its review for reading, with a note instead of Save', async ({
    page,
  }) => {
    await signIn(page);
    await go(page, '/site-profile?suggest=C-000008&fact=W1');
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

  test('hides the library switches and the review annotations', async ({ page }) => {
    await signIn(page);
    await go(page, '/library');
    await expect(page.getByText(READ_ONLY)).toBeVisible();
    await expect(page.getByRole('switch')).toHaveCount(0);
    await go(page, '/reviews/PR-000001');
    await expect(page.getByRole('heading', { name: 'Review PR-000001', exact: true })).toBeVisible();
    await expect(page.getByText(READ_ONLY)).toBeVisible();
    await expect(page.getByRole('button', { name: /Annotate|Remove the annotation/ })).toHaveCount(0);
  });

  test('keeps Approve and Reject', async ({ page }) => {
    await signIn(page);
    await go(page, '/cases/C-000002');
    await expect(page.getByRole('heading', { name: 'Case C-000002', exact: true })).toBeVisible();
    for (const step of await page.getByRole('button', { name: /^\d\. / }).all())
      if ((await step.getAttribute('aria-expanded')) !== 'true') await step.click();
    await expect(page.getByRole('button', { name: 'Approve plan' })).toBeEnabled();
    await expect(page.getByRole('button', { name: 'Reject plan' })).toBeEnabled();
  });
});

/** The screens that change in live mode, in every appearance: the banner on each, the missing controls, the note. */
const SCREENS: [path: string, heading: string][] = [
  ['/scenarios', 'Scenarios'],
  ['/site-profile?suggest=C-000008&fact=W1', 'Site profile'],
  ['/library', 'Agent library'],
  ['/reviews/PR-000001', 'Review PR-000001'],
  ['/cases/C-000002', 'Case C-000002'],
];

for (const { colorScheme, contrast, palette } of MODES) {
  const mode = `${palette === 'pastel' ? 'pastel' : colorScheme}${contrast === 'more' ? ', high contrast' : ''}`;
  test.describe(`accessibility of the live hospital (axe-core, WCAG 2.1 A/AA), ${mode}`, () => {
    test.use({ colorScheme, contrast });
    if (palette === 'pastel') test.beforeEach(({ page }) => choosePastel(page));

    for (const [path, heading] of SCREENS)
      test(heading + (path.includes('?') ? ' (a suggested change)' : ''), async ({ page }) => {
        await signIn(page);
        await go(page, path);
        await expect(page.getByRole('heading', { name: heading, exact: true })).toBeVisible();
        await expect(banner(page)).toBeVisible();
        // The page's data, not its loading state
        await expect(page.getByRole('status')).toHaveCount(0);
        expect(await audit(page)).toEqual([]);
      });

    test('the review of a change, for reading', async ({ page }) => {
      await signIn(page);
      await go(page, '/site-profile?suggest=C-000008&fact=W1');
      await page.getByRole('button', { name: 'Review the change…' }).click();
      await expect(page.getByRole('dialog').getByText(READ_ONLY)).toBeVisible();
      expect(await audit(page)).toEqual([]);
    });
  });
}
