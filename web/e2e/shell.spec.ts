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
    await expect(banner(page)).toContainText('Break the feed plays on the online demo.');
    await expect(banner(page).getByRole('button')).toHaveCount(0);
    // A recording never resets on the hour, though it answers `live.enabled` like the demo
    await expect(banner(page).getByTestId('live-reset-line')).toHaveCount(0);
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

test.describe('Ask Shutter, from the header', () => {
  test('opens beside the page from 1200 px, answers a suggested question about it, and closes with Escape', async ({
    page,
  }) => {
    await page.setViewportSize({ width: 1280, height: 800 });
    await signIn(page);
    const button = page.getByRole('button', { name: 'Ask Shutter', exact: true });
    await expect(button).toHaveAttribute('aria-expanded', 'false');
    await button.click();
    const panel = page.getByRole('region', { name: 'Ask Shutter' });
    await expect(panel.getByRole('heading', { name: 'Ask Shutter', level: 2 })).toBeFocused();
    await expect(button).toHaveAttribute('aria-expanded', 'true');
    // Beside the page, not over it: the page's heading stays left of the panel, and there is no dialog
    const side = (await panel.boundingBox())!;
    const title = (await page.getByRole('heading', { name: 'Scenarios', exact: true }).boundingBox())!;
    expect(side.x).toBeGreaterThan(title.x + 200);
    await expect(page.getByRole('dialog')).toHaveCount(0);
    await expect(panel).toContainText('Read-only.');
    // The suggested questions are the page's own; the trial answers them with sample answers, labelled so
    await panel.getByRole('button', { name: 'What is a scenario?' }).click();
    const thread = panel.getByRole('region', { name: 'Conversation' });
    await expect(thread.getByRole('heading', { name: 'What is a scenario?', level: 4 })).toBeFocused();
    await expect(thread).toContainText('one known failure of a hospital message');
    await expect(thread).toContainText('Example (sample data)');
    // No question of one's own in the trial, and the written guide to the page
    await expect(panel.getByRole('textbox', { name: 'Your own question' })).toBeDisabled();
    await expect(panel.getByRole('region', { name: 'About this page: Scenarios' })).toContainText(
      'Known failures replayed',
    );
    // Open or closed is remembered in this tab: the panel is still open on the next page, about that page
    await page
      .getByRole('navigation', { name: 'Main' })
      .getByRole('link', { name: /^Cases/ })
      .click();
    await expect(page.getByRole('heading', { name: 'Cases', exact: true, level: 1 })).toBeVisible();
    await expect(page.getByRole('region', { name: 'Ask Shutter' })).toContainText(
      'Suggested questions about Cases',
    );
    await expect(
      page.getByRole('region', { name: 'Ask Shutter' }).getByRole('button', { name: 'Which cases need me?' }),
    ).toBeVisible();
    // Escape inside the panel closes it (beside the page it is no dialog, so Escape elsewhere is the page's own)
    await page
      .getByRole('region', { name: 'Ask Shutter' })
      .getByRole('button', { name: 'Which cases need me?' })
      .focus();
    await page.keyboard.press('Escape');
    await expect(page.getByRole('region', { name: 'Ask Shutter' })).toHaveCount(0);
    await expect(button).toBeFocused();
    await expect(button).toHaveAttribute('aria-expanded', 'false');
    // Closed is remembered too
    await page.reload();
    await expect(page.getByRole('heading', { name: 'Cases', exact: true, level: 1 })).toBeVisible();
    await expect(page.getByRole('region', { name: 'Ask Shutter' })).toHaveCount(0);
  });

  test('is a full-screen sheet on a phone, and comes back open after a reload', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await signIn(page);
    await page.getByRole('button', { name: 'Ask Shutter', exact: true }).click();
    const sheet = page.getByRole('dialog', { name: 'Ask Shutter' });
    await expect(sheet.getByRole('heading', { name: 'Ask Shutter' })).toBeFocused();
    await page.waitForFunction(() => document.getAnimations().every((a) => a.playState !== 'running'));
    expect(Math.round((await sheet.boundingBox())!.width)).toBe(390);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
    await page.reload();
    await expect(page.getByRole('dialog', { name: 'Ask Shutter' })).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(page.getByRole('dialog', { name: 'Ask Shutter' })).toBeHidden();
    await expect(page.getByRole('button', { name: 'Ask Shutter' })).toBeFocused();
  });

  test("says what the public demo's role can and cannot ask, in the trial's words", async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 800 });
    await signIn(page, AS_DEMO);
    await page.getByRole('button', { name: 'Ask Shutter' }).click();
    const panel = page.getByRole('region', { name: 'Ask Shutter' });
    // The trial has no model: the public role, like every trial role, has the suggested questions and the guide
    await expect(panel.getByRole('button', { name: 'What is a scenario?' })).toBeEnabled();
    await expect(panel.getByRole('textbox', { name: 'Your own question' })).toHaveAccessibleDescription(
      'Needs a real model: not in the trial.',
    );
  });
});

test.describe('the shell', () => {
  test('opens on Home, whose links reach every section', async ({ page }) => {
    await page.goto('./?trial#/');
    await expect(page.getByRole('heading', { name: 'Home', exact: true, level: 1 })).toBeVisible();
    await expect(page).toHaveURL(/#\/home$/);
    const nav = page.getByRole('navigation', { name: 'Main' });
    await expect(nav.getByRole('link', { name: 'Home' })).toHaveAttribute('aria-current', 'page');
    await page
      .getByRole('main')
      .getByRole('link', { name: /^Cases/ })
      .click();
    await expect(page.getByRole('heading', { name: 'Cases', exact: true, level: 1 })).toBeVisible();
    await page.getByRole('link', { name: 'Shutter: home' }).click();
    await expect(page.getByRole('heading', { name: 'Home', exact: true, level: 1 })).toBeVisible();
  });

  test('groups the navigation as Operate, Results and Configure, each icon in its hue', async ({ page }) => {
    await signIn(page);
    const nav = page.getByRole('navigation', { name: 'Main' });
    await expect(nav.getByRole('group')).toHaveText([/^Operate/, /^Results/, /^Configure/]);
    const hues = await nav
      .locator('.nav-link')
      .evaluateAll((links) => links.map((a) => (a as HTMLElement).style.getPropertyValue('--nav-icon')));
    expect(hues).toEqual([
      'var(--shutter-hue-cyan)',
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
    // One place to choose it: the Appearance menu holds the theme and the contrast, not the Detail switch again
    await page.getByRole('button', { name: 'Appearance' }).click();
    await expect(page.getByRole('menuitem', { name: /^Pastel/ })).toBeVisible();
    await expect(page.getByRole('menuitem', { name: /^Technical|^Plain words/ })).toHaveCount(0);
    // Each System says which: a screen reader hears no group
    await expect(page.getByRole('menuitem', { name: /^System theme/ })).toBeVisible();
    await expect(page.getByRole('menuitem', { name: /^System contrast/ })).toBeVisible();
    await page.keyboard.press('Escape');
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

  test("opens What's different? from the keyboard and closes it on Escape, focus back on the button", async ({
    page,
  }) => {
    await signIn(page);
    const trial = page.getByRole('region', { name: 'Trial environment' });
    const button = trial.getByRole('button', { name: "What's different?" });
    await button.focus();
    await page.keyboard.press('Enter');
    const dropdown = page.getByRole('dialog', { name: 'The trial environment' });
    await expect(dropdown).toBeVisible();
    await expect(dropdown).toContainText('Resets when you reload or leave.');
    await page.keyboard.press('Escape');
    await expect(dropdown).toBeHidden();
    await expect(button).toBeFocused();
    // The header's user menu is reachable again
    await page.getByRole('button', { name: /^Signed in as / }).click();
    await expect(page.getByRole('menu', { name: /^Signed in as / })).toBeVisible();
    await page.keyboard.press('Escape');
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
      // In rem, as AppShell makes the header's own height, so the two stay equal at any text size
      token:
        parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--shutter-header-h')) *
        parseFloat(getComputedStyle(document.documentElement).fontSize),
    }));
    expect(Math.round(h.header)).toBe(h.token);
  });
});

for (const width of [1280, 1920])
  test.describe(`Home's lead at ${width} px`, () => {
    test.use({ viewport: { width, height: 800 } });

    test('stays on one line, and a long lead elsewhere keeps its measure', async ({ page }) => {
      await page.goto('./#/home');
      const lead = page.getByText('only when its checks pass. Otherwise it stops and names the patient.');
      await expect(lead).toBeVisible();
      const lines = await lead.evaluate(
        (el) => el.getBoundingClientRect().height / parseFloat(getComputedStyle(el).lineHeight),
      );
      expect(Math.round(lines)).toBe(1);
      expect(await lead.evaluate((el) => getComputedStyle(el).maxWidth)).toBe('none');
      await page.goto('./#/scenarios');
      const other = page.getByText('Known message failures to play');
      await expect(other).toBeVisible();
      expect(await other.evaluate((el) => getComputedStyle(el).maxWidth)).not.toBe('none');
    });
  });
