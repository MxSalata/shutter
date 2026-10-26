import { expect, test, type Page } from '@playwright/test';
import { GUIDE_KEY } from './guide';

/**
 * The first-run guide on the demo build: the welcome on a first visit, the quick route through the recorded cases,
 * Show this section and Continue guide, Help's resume and chapters, and the bottom sheet on a phone. The guide only
 * moves between pages and opens sections.
 */
const go = (page: Page, path: string) => page.goto(`./#${path}`);

async function signIn(page: Page) {
  await go(page, '/login');
  await page.getByRole('button', { name: /Try the demo/ }).click();
  await expect(page.getByRole('heading', { name: 'Scenarios', level: 1 })).toBeVisible();
}

const stored = (page: Page) =>
  page.evaluate((key) => JSON.parse(localStorage.getItem(key) ?? 'null'), GUIDE_KEY);

test.describe('the guide', () => {
  test.use({ viewport: { width: 1280, height: 800 } });

  test('welcomes a first visit and walks the quick route through the recorded cases', async ({ page }) => {
    const writes: string[] = [];
    page.on('request', (r) => {
      // Signing in is the test's own write (twice: the demo forgets its sign-in on a reload); the guide makes none
      if (
        r.url().includes('/api/shutter/') &&
        !r.url().endsWith('/session') &&
        !['GET', 'HEAD'].includes(r.method())
      )
        writes.push(`${r.method()} ${new URL(r.url()).pathname}`);
    });
    await signIn(page);
    const dialog = page.getByRole('dialog');
    await expect(dialog.getByRole('heading', { name: 'Welcome to Shutter' })).toBeVisible();
    await expect(dialog.getByRole('radio', { name: /Quick demonstration/ })).toBeChecked();
    await dialog.getByRole('button', { name: 'Start guide' }).click();
    await expect(dialog.getByText('Step 1 of 3 · Scenarios')).toBeVisible();

    await dialog.getByRole('button', { name: 'Show this section' }).click();
    await expect(dialog).toBeHidden();
    await expect(page.getByRole('heading', { name: 'Try these three first', level: 2 })).toBeFocused();
    const guide = page.getByRole('region', { name: 'Guide' });
    await expect(guide).toContainText('Step 1 of 3 · Scenarios');
    // Continue guide is the next stop after the heading
    await page.keyboard.press('Tab');
    await expect(guide.getByRole('button', { name: 'Continue guide' })).toBeFocused();
    await page.keyboard.press('Enter');
    await expect(dialog.getByText('Step 1 of 3 · Scenarios')).toBeVisible();

    // To the S2 case, found among the recorded cases, at its evidence
    await dialog.getByRole('button', { name: 'Skip chapter' }).click();
    await dialog.getByRole('button', { name: 'Next' }).click();
    await expect(dialog.getByText('Step 2 of 4 · S2: a transfer recovered')).toBeVisible();
    await dialog.getByRole('button', { name: 'Show this section' }).click();
    await expect(page).toHaveURL(/#\/cases\/C-000002\?open=evidence$/);
    await expect(page.getByRole('button', { name: /^2\. What the evidence says/ })).toHaveAttribute(
      'aria-expanded',
      'true',
    );
    await expect(page.getByRole('region', { name: 'Guide' })).toContainText('Step 2 of 4');

    // The S8 side by side, behind why the board matters
    await page.getByRole('button', { name: 'Continue guide' }).click();
    await dialog.getByRole('button', { name: 'Skip chapter' }).click();
    await dialog.getByRole('button', { name: 'Next' }).click();
    await dialog.getByRole('button', { name: 'Next' }).click();
    await expect(dialog.getByText('Step 3 of 3 · S8: a write withheld')).toBeVisible();
    await dialog.getByRole('button', { name: 'Show this section' }).click();
    await expect(page).toHaveURL(/#\/cases\/C-000008\?open=compare$/);
    await expect(
      page.getByRole('heading', { name: 'S8 side by side: rules alone and the board' }),
    ).toBeVisible();

    // S20's chapter shows its Rules only case
    await page.getByRole('button', { name: 'Continue guide' }).click();
    await dialog.getByRole('button', { name: 'Next' }).click();
    await expect(
      dialog.getByText('Step 1 of 2 · S20 in Rules only mode: an approval no longer valid'),
    ).toBeVisible();
    await dialog.getByRole('button', { name: 'Show this section' }).click();
    await expect(page).toHaveURL(/#\/cases\/C-000053$/);
    await expect(page.getByRole('heading', { name: 'Outcome' })).toBeFocused();

    // Escape exits without finishing; Help resumes where it stopped
    await page.getByRole('button', { name: 'Continue guide' }).click();
    await page.keyboard.press('Escape');
    await expect(dialog).toBeHidden();
    expect(await stored(page)).toMatchObject({ scope: 'quick', chapter: 's20', step: 0, dismissed: false });
    // A new visit (the demo forgets its sign-in on a reload): no welcome, the place kept on the device
    await page.reload();
    await signIn(page);
    await expect(dialog).toBeHidden();
    await page.getByRole('button', { name: 'Help' }).click();
    await page.getByRole('menuitem', { name: 'Resume guide' }).click();
    await expect(
      dialog.getByText('Step 1 of 2 · S20 in Rules only mode: an approval no longer valid'),
    ).toBeVisible();

    // To the end: the evaluation, then Finish
    await dialog.getByRole('button', { name: 'Skip chapter' }).click();
    await dialog.getByRole('button', { name: 'Next' }).click();
    await dialog.getByRole('button', { name: 'Finish' }).click();
    await expect(dialog).toBeHidden();
    expect(await stored(page)).toMatchObject({ chapter: null, dismissed: true });
    expect(writes).toEqual([]);
  });

  test("opens a chapter from Help, and stays away after Don't show again", async ({ page }) => {
    await signIn(page);
    const dialog = page.getByRole('dialog');
    await dialog.getByRole('button', { name: "Don't show again" }).click();
    await expect(dialog).toBeHidden();
    await page.reload();
    await signIn(page);
    await expect(dialog).toBeHidden();
    await page.getByRole('button', { name: 'Help' }).click();
    await page.getByRole('menuitem', { name: 'Choose a chapter' }).click();
    await dialog.getByRole('button', { name: 'An incident' }).click();
    await expect(dialog.getByText('Step 1 of 1 · An incident')).toBeVisible();
    await dialog.getByRole('button', { name: 'Show this section' }).click();
    await expect(page).toHaveURL(/#\/incidents\/I-00000\d$/);
    await expect(page.getByRole('heading', { name: 'Chains' })).toBeFocused();
    await expect(page.getByRole('region', { name: 'Guide' })).toContainText('Step 1 of 1 · An incident');
  });

  test('opens in a bottom sheet on a phone', async ({ page }) => {
    await page.setViewportSize({ width: 360, height: 760 });
    await signIn(page);
    const dialog = page.getByRole('dialog');
    await dialog.getByRole('button', { name: 'Start guide' }).click();
    await expect(dialog.getByText('Step 1 of 3 · Scenarios')).toBeVisible();
    const box = (await dialog.boundingBox())!;
    expect(Math.round(box.y + box.height)).toBe(760);
    // Every control is a 44 px target, and the page does not scroll sideways
    for (const button of await dialog.getByRole('button').all())
      expect((await button.boundingBox())!.height).toBeGreaterThanOrEqual(44);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(360);
  });
});
