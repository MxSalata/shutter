import { expect, test, type Page } from '@playwright/test';
import { GUIDE_KEY } from './guide';
import { go, signIn } from './helpers';

/**
 * The first-run guide in the trial (the demo build is always the trial): the welcome on a first entry, the quick tour
 * with its cards placed before their sections, the approval it makes for the reader on Next, Help's resume and
 * chapters, the engineers' tour with Technical on, the movements that wait for their control, and a phone.
 */

const stored = (page: Page) =>
  page.evaluate((key) => JSON.parse(localStorage.getItem(key) ?? 'null'), GUIDE_KEY);

/** The calls the trial answered in the page that would change something on a live system. */
const writes = (page: Page) =>
  page.evaluate(() =>
    (window.shutterTrial?.journal.entries() ?? [])
      .filter((e) => e.method !== 'GET' && e.method !== 'HEAD')
      .map((e) => `${e.method} ${e.path}`),
  );

/** Progress stored before the app starts, so a test can begin at a step. */
const startAt = (page: Page, at: string, scope = 'quick') =>
  page.addInitScript(({ key, value }) => localStorage.setItem(key, value), {
    key: GUIDE_KEY,
    value: JSON.stringify({ version: 2, scope, at, completed: [], dismissed: true }),
  });

test.describe('the guide', () => {
  test.use({ viewport: { width: 1280, height: 800 } });

  test('welcomes a first entry and walks the quick tour, approving for the reader on Next', async ({
    page,
  }) => {
    await signIn(page);
    const welcome = page.getByRole('dialog', { name: 'Welcome to the Shutter trial' });
    await expect(welcome.getByRole('radio', { name: /Quick tour/ })).toBeChecked();
    await expect(welcome).toContainText('9 steps, about 4 min');
    await welcome.getByRole('button', { name: 'Start the tour' }).click();
    await expect(welcome).toBeHidden();
    // The welcome has closed: the banner keeps to one line
    await expect(page.getByRole('region', { name: 'Trial environment' })).toHaveAttribute(
      'data-compact',
      'true',
    );

    const guide = page.getByRole('region', { name: 'Guide' });
    await expect(guide).toContainText('Trial tour · Scenarios');
    await expect(guide).toContainText('Step 1 of 9');
    await expect(guide.getByRole('heading', { name: 'Three stories to start with', level: 2 })).toBeFocused();
    // The card stands just before its section, which carries the ring
    const section = page.locator('[data-tour="scenarios"]');
    await expect(section).toHaveAttribute('data-tour-active', 'true');
    expect(
      await guide.evaluate(
        (card, s) =>
          !!(card.compareDocumentPosition(document.querySelector(s)!) & Node.DOCUMENT_POSITION_FOLLOWING),
        '[data-tour="scenarios"]',
      ),
    ).toBe(true);
    // From the title, Tab reaches the card's controls (Back is off on the first step), then the section
    await page.keyboard.press('Tab');
    await expect(guide.getByRole('button', { name: 'More' })).toBeFocused();
    await page.keyboard.press('Tab');
    await expect(guide.getByRole('button', { name: 'Next' })).toBeFocused();

    for (let n = 1; n <= 9; n++) {
      await expect(guide).toContainText(`Step ${n} of 9`);
      // Every place of the quick tour resolves in the trial
      await expect(page.getByText('This section is not on the page just now.')).toHaveCount(0);
      if (n === 3) {
        await expect(page).toHaveURL(/#\/cases\/C-000002\?open=decision$/);
        await expect(page.locator('[data-tour-action="approve-plan"]')).toBeVisible();
      }
      if (n === 4) {
        // Next on the decision approved the held case for the reader, through Approve plan's own call
        await expect(guide).toContainText('Approved for you, in the trial.');
        await expect(page.locator('[data-tour-action="approve-plan"]')).toHaveCount(0);
      }
      await guide.getByRole('button', { name: n === 9 ? 'Finish' : 'Next' }).click();
    }
    await expect(guide.getByRole('heading', { name: 'That is the tour.' })).toBeVisible();
    await expect(guide.getByRole('button', { name: 'Run S20 yourself' })).toBeVisible();
    expect(await stored(page)).toMatchObject({ at: null, dismissed: true });
    // The tour's only write is the approval it made for the reader, answered in this browser
    expect(await writes(page)).toEqual(['POST /api/shutter/cases/C-000002/approvals']);

    // Run S20 yourself: Scenarios, with S20's Run button focused and pointed at, not pressed
    await guide.getByRole('button', { name: 'Run S20 yourself' }).click();
    const run = page.locator('[data-tour-action="run-S20"]').first();
    await expect(run).toBeFocused();
    await expect(page.getByTestId('guide-try-pointer')).toBeVisible();
    expect(await writes(page)).toEqual(['POST /api/shutter/cases/C-000002/approvals']);
  });

  test("starts the engineers' tour with Technical on, from its address", async ({ page }) => {
    await page.goto('./?trial=engineer#/scenarios');
    const welcome = page.getByRole('dialog', { name: 'Welcome to the Shutter trial' });
    await expect(welcome.getByRole('radio', { name: /For integration engineers/ })).toBeChecked();
    await welcome.getByRole('button', { name: 'Start the tour' }).click();
    const guide = page.getByRole('region', { name: 'Guide' });
    await expect(guide).toContainText("Engineers' tour · A transfer recovered (S2)");
    await expect(guide).toContainText('Step 1 of 6');
    await expect(
      page.getByRole('radiogroup', { name: 'Detail' }).getByRole('radio', { name: 'Technical' }),
    ).toBeChecked();
    // The address no longer opens the welcome on a reload
    await expect(page).toHaveURL(/\?trial#\//);
  });

  test("opens a chapter from Help, and stays away after Don't show again", async ({ page }) => {
    await signIn(page);
    const welcome = page.getByRole('dialog', { name: 'Welcome to the Shutter trial' });
    await welcome.getByRole('button', { name: "Don't show again" }).click();
    await expect(welcome).toBeHidden();
    await page.reload();
    await expect(page.getByRole('heading', { name: 'Scenarios', exact: true })).toBeVisible();
    await expect(welcome).toBeHidden();
    await page.getByRole('button', { name: 'Help' }).click();
    await page.getByRole('menuitem', { name: 'Choose a chapter' }).click();
    const chapters = page.getByRole('dialog', { name: 'Choose a chapter' });
    await expect(chapters.getByRole('group')).toHaveCount(3);
    await chapters.getByRole('button', { name: /^An incident/ }).click();
    await expect(page).toHaveURL(/#\/incidents\/I-00000\d$/);
    const guide = page.getByRole('region', { name: 'Guide' });
    await expect(guide).toContainText('Every screen · An incident');
    await expect(guide.getByRole('heading', { name: 'One chain per encounter', level: 2 })).toBeFocused();
  });

  test('starts no pointer or halo while its control is out of view', async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 600 });
    await startAt(page, 's8/ask');
    await signIn(page);
    await page.getByRole('button', { name: 'Help' }).click();
    await page.getByRole('menuitem', { name: 'Resume the tour' }).click();
    const guide = page.getByRole('region', { name: 'Guide' });
    await expect(guide).toContainText('Step 7 of 9');
    const control = page.locator('[data-tour-action="ask-open"]');
    // Away from the control at once, before the section's ring has played
    await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
    await page.waitForTimeout(1500);
    const before = await control.evaluate((el) => ({
      halo: el.getAttribute('data-tour-try'),
      running: el.getAnimations().filter((a) => a.playState === 'running').length,
      inView: el.getBoundingClientRect().bottom > 0 && el.getBoundingClientRect().top < window.innerHeight,
    }));
    if (!before.inView) {
      expect(before.halo).toBeNull();
      expect(before.running).toBe(0);
      await expect(page.getByTestId('guide-try-pointer')).toHaveCount(0);
    }
    // In view again: the halo takes its place
    await control.scrollIntoViewIfNeeded();
    await expect(control).toHaveAttribute('data-tour-try', /^(true|rest)$/);
    await expect(page.getByTestId('guide-try-pointer')).toBeVisible();
  });

  test('keeps the card in the column on a phone, every control a 44 px target', async ({ page }) => {
    await page.setViewportSize({ width: 360, height: 760 });
    await signIn(page);
    const welcome = page.getByRole('dialog', { name: 'Welcome to the Shutter trial' });
    await welcome.getByRole('button', { name: 'Start the tour' }).click();
    const guide = page.getByRole('region', { name: 'Guide' });
    await expect(guide).toContainText('Step 1 of 9');
    for (const button of await guide.getByRole('button', { name: /^(Back|More|Next)$/ }).all())
      expect((await button.boundingBox())!.height).toBeGreaterThanOrEqual(44);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(360);
    await go(page, '/scenarios');
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(360);
  });
});
