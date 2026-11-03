import { expect, test } from '@playwright/test';
import { GUIDE_KEY, skipWelcome } from './guide';
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
    await expect(banner(page).getByTestId('live-line')).toContainText(
      /^Mikolaj's Fictional Hospital, replayed: a new failure every 7 minutes\. Last: S2, \d+ (s|min) ago\. Next: S8 at \d\d:\d\d (GMT|BST|UTC)\.$/,
    );
    // The trial has no demo hospital to break: the banner says where the storm plays, and offers no button
    await expect(banner(page)).toContainText('Break the feed plays on the public demo.');
    await expect(banner(page).getByRole('button')).toHaveCount(0);
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

  test('names the help button for the tour: its word beside the icon on a laptop, its name alone on a phone', async ({
    page,
  }) => {
    await page.setViewportSize({ width: 1280, height: 800 });
    await signIn(page);
    const header = page.locator('header');
    const tour = header.getByRole('button', { name: 'Tour' });
    await expect(tour).toBeVisible();
    await expect(tour).toHaveText('Tour');
    // A tour left part way: the button says it can be resumed, and its menu's first item does it
    await page.evaluate(
      (key) =>
        localStorage.setItem(
          key,
          JSON.stringify({ version: 2, scope: 'quick', at: 's2/receipt', completed: [], dismissed: true }),
        ),
      GUIDE_KEY,
    );
    await page.reload();
    const resume = header.getByRole('button', { name: 'Resume tour' });
    await expect(resume).toHaveText('Resume tour');
    await resume.click();
    await expect(page.getByRole('menuitem').first()).toHaveText('Resume the tour');
    await page.keyboard.press('Escape');
    // On a phone the icon alone, a square like the header's other icon buttons, named the same; the row still fits
    for (const width of [390, 360]) {
      await page.setViewportSize({ width, height: 760 });
      await expect(resume).toBeVisible();
      await expect(resume.locator('.header-help-label')).toBeHidden();
      const box = (await resume.boundingBox())!;
      expect(box.width).toBeLessThanOrEqual(40);
      expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
      const row = await header.evaluate((h) => {
        const r = h.querySelector(':scope > div:last-child')!;
        return { scroll: r.scrollWidth, client: r.clientWidth };
      });
      expect(row.scroll).toBeLessThanOrEqual(row.client);
      await expect(page.locator('.trial-pill')).toHaveText('Trial');
    }
  });

  test('says where Leave trial would be: the demo build is the trial only', async ({ page }) => {
    await signIn(page);
    const words =
      'This copy is the trial only. The live system runs on an IRIS instance: your own install or the online demo.';
    await page.getByRole('button', { name: /^Signed in as / }).click();
    const user = page.getByRole('menu', { name: /^Signed in as / });
    await expect(user.getByTestId('trial-only-note')).toHaveText(words);
    await expect(user.getByRole('menuitem', { name: 'Leave trial' })).toHaveCount(0);
    await expect(user).toHaveAccessibleDescription(words);
    // Closed from its button: with its first item (the current role) disabled, focus stays on the button
    await page.getByRole('button', { name: /^Signed in as / }).click();
    await expect(user).toBeHidden();
    await page.getByRole('button', { name: 'Tour' }).click();
    const help = page.getByRole('menu', { name: 'Tour' });
    await expect(help.getByTestId('trial-only-note')).toHaveText(words);
    await expect(help.getByRole('menuitem', { name: 'Leave trial' })).toHaveCount(0);
    await expect(help).toHaveAccessibleDescription(words);
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
