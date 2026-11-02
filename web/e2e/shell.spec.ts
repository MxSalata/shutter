import { expect, test } from '@playwright/test';
import { skipWelcome } from './guide';
import { banner, go, signIn } from './helpers';

/**
 * The shell: the hospital feed's banner on every page for the public demo's role, the navigation's groups and hues,
 * the Detail switch, and the trial's chrome on every page of the demo build (which is always the trial).
 */

/** The live hospital's public role: the address keeps `?as=demo` in every step. */
const AS_DEMO = { as: 'demo' } as const;

// The guide's welcome would cover the screens these tests are about; guide.spec.ts tests it
test.beforeEach(({ page }) => skipWelcome(page));

test.describe('the live hospital, as the public role sees it', () => {
  test('shows the live banner on every page', async ({ page }) => {
    await signIn(page, AS_DEMO);
    // In the trial the feed is the recording replayed, and says so
    await expect(banner(page)).toContainText(
      /^Hospital feed \(replayed\): a new failure every 7 minutes\. Last: S2, \d+ (s|min) ago\. Next: S8 at \d\d:\d\d (GMT|BST|UTC)\.$/,
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

test.describe('the shell', () => {
  test('groups the navigation as Operate, Results and Configure, each icon in its hue', async ({ page }) => {
    await signIn(page);
    const nav = page.getByRole('navigation', { name: 'Main' });
    await expect(nav.getByRole('group')).toHaveText([/^Operate/, /^Results/, /^Configure/]);
    const hues = await nav
      .locator('.nav-link')
      .evaluateAll((links) => links.map((a) => (a as HTMLElement).style.getPropertyValue('--nav-icon')));
    expect(hues).toEqual([
      'var(--shutter-hue-cyan)',
      'var(--shutter-hue-indigo)',
      'var(--shutter-hue-pink)',
      'var(--shutter-hue-violet)',
      'var(--shutter-hue-teal)',
      'var(--shutter-hue-indigo)',
      'var(--shutter-hue-teal)',
      'var(--shutter-hue-violet)',
      'var(--shutter-hue-cyan)',
    ]);
    await expect(nav.getByRole('link', { name: 'Scenarios' })).toHaveAttribute('aria-current', 'page');
    // The held S2 case needs a person: the count beside Cases says how many, in words for a screen reader
    await expect(nav.getByRole('link', { name: /^Cases \d+ cases? needs? a person$/ })).toBeVisible();
  });

  test('switches the Detail level from the header, and ?detail=technical sets it at start', async ({
    page,
  }) => {
    await signIn(page);
    const detail = page.getByRole('radiogroup', { name: 'Detail' });
    await expect(detail.getByRole('radio', { name: 'Plain' })).toBeChecked();
    await detail.getByText('Technical').click();
    await expect(detail.getByRole('radio', { name: 'Technical' })).toBeChecked();
    await page.goto('./?detail=plain#/scenarios');
    await expect(
      page.getByRole('radiogroup', { name: 'Detail' }).getByRole('radio', { name: 'Plain' }),
    ).toBeChecked();
    await page.goto('./?detail=technical#/scenarios');
    await expect(
      page.getByRole('radiogroup', { name: 'Detail' }).getByRole('radio', { name: 'Technical' }),
    ).toBeChecked();
  });

  test('marks every page of the demo build as the trial: banner, frame, pill and title', async ({ page }) => {
    await signIn(page);
    const trial = page.getByRole('region', { name: 'Trial environment' });
    await expect(trial).toContainText('Trial environment');
    // The demo build has no live system to go back to
    await expect(trial.getByRole('button', { name: 'Leave trial' })).toHaveCount(0);
    await expect(page.locator('.trial-pill')).toHaveText('Trial');
    await expect(page).toHaveTitle(/\(trial\)$/);
    expect(await page.evaluate(() => getComputedStyle(document.body, '::after').borderTopWidth)).toBe('3px');
    for (const [path, heading] of [
      ['/cases', 'Cases'],
      ['/health', 'Health'],
    ]) {
      await go(page, path);
      await expect(page.getByRole('heading', { name: heading, exact: true })).toBeVisible();
      await expect(trial).toBeVisible();
    }
    // The header clears the banner: --shutter-header-h matches the header's height
    const h = await page.evaluate(() => ({
      header: document.querySelector('header')!.getBoundingClientRect().height,
      token: getComputedStyle(document.documentElement).getPropertyValue('--shutter-header-h').trim(),
    }));
    expect(`${Math.round(h.header)}px`).toBe(h.token);
  });
});
