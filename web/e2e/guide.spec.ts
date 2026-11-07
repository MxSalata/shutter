import { expect, test, type Locator, type Page } from '@playwright/test';
import { GUIDE_KEY, skipWelcome } from './guide';
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

/** Whether the element's centre is its own on the screen: nothing covers it there. */
const uncovered = (locator: Locator) =>
  locator.evaluate((el) => {
    const r = el.getBoundingClientRect();
    return el.contains(document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2));
  });

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
        // The case page played out the recording after that approval
        await expect(page.getByRole('region', { name: 'Outcome' }).getByTestId('outcome-line')).toHaveText(
          'Delivered: verified at the receiver',
        );
        // Back to the decision: it no longer says the fix waits, and Next there approves nothing more
        await guide.getByRole('button', { name: 'Back' }).click();
        await expect(guide.getByRole('heading', { name: 'The fix was approved here' })).toBeVisible();
        await expect(guide).not.toContainText('waits for you');
        await guide.getByRole('button', { name: 'Next' }).click();
        await expect(guide).toContainText('Step 4 of 9');
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
    await expect(page.getByRole('dialog', { name: 'Welcome to the Shutter trial' })).toBeHidden();
    const guide = page.getByRole('region', { name: 'Guide' });
    await expect(guide).toContainText("Engineers' tour · A transfer recovered (S2)");
    await expect(guide).toContainText('Step 1 of 6');
    await expect(
      page.getByRole('radiogroup', { name: 'Detail' }).getByRole('radio', { name: 'Technical' }),
    ).toBeChecked();
    // The address no longer starts the tour on a reload
    await expect(page).toHaveURL(/\?trial#\//);
  });

  test("the Tour menu's items put focus inside what they open, and closing it brings focus back to Tour", async ({
    page,
  }) => {
    await skipWelcome(page);
    await page.goto('./?trial#/scenarios');
    const tour = page.getByRole('button', { name: 'Tour', exact: true });
    for (const [item, dialog] of [
      ['Choose a chapter', 'Choose a chapter'],
      ['Restart the tour', 'Welcome to the Shutter trial'],
    ]) {
      await tour.click();
      await page.getByRole('menuitem', { name: item }).click();
      const opened = page.getByRole('dialog', { name: dialog });
      await expect(opened).toBeVisible();
      // Past the moment a closing menu gives focus back
      await page.waitForTimeout(300);
      expect(
        await opened.evaluate((d) => d.contains(document.activeElement)),
        `${item}: focus is inside the dialog`,
      ).toBe(true);
      await page.keyboard.press('Escape');
      await expect(opened).toHaveCount(0);
      await expect(tour).toBeFocused();
    }
    // Closed with Escape, with nothing chosen, the menu itself still gives focus back
    await tour.click();
    await expect(page.getByRole('menuitem', { name: 'Choose a chapter' })).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(tour).toBeFocused();
  });

  test("the card's More menu puts focus inside the chapters too", async ({ page }) => {
    await startAt(page, 'scenarios/start');
    await page.goto('./?trial#/scenarios');
    await page.getByRole('button', { name: 'Resume tour' }).click();
    await page.getByRole('menuitem', { name: 'Resume the tour' }).click();
    const guide = page.getByRole('region', { name: 'Guide' });
    await expect(guide.getByRole('heading', { level: 2 })).toBeFocused();
    await guide.getByRole('button', { name: 'More' }).click();
    await page.getByRole('menuitem', { name: 'Choose a chapter' }).click();
    const opened = page.getByRole('dialog', { name: 'Choose a chapter' });
    await expect(opened).toBeVisible();
    await page.waitForTimeout(300);
    expect(await opened.evaluate((d) => d.contains(document.activeElement))).toBe(true);
  });

  test("the banner's full form, open with the welcome, never stops mid-word", async ({ page }) => {
    await signIn(page);
    const words = page.locator('.trial-banner-words');
    for (const [width, long] of [
      [1280, false],
      [1439, false],
      [1440, true],
    ] as const) {
      await page.setViewportSize({ width, height: 800 });
      await expect(page.locator('.trial-banner-long')).toBeVisible({ visible: long });
      expect(await words.evaluate((el) => el.scrollWidth <= el.clientWidth)).toBe(true);
    }
  });

  test('stays on its step when the reader filters the list the step is on', async ({ page }) => {
    await signIn(page);
    const welcome = page.getByRole('dialog', { name: 'Welcome to the Shutter trial' });
    await welcome.getByRole('button', { name: 'Start the tour' }).click();
    const guide = page.getByRole('region', { name: 'Guide' });
    await expect(guide).toContainText('Step 1 of 9');
    await page.getByRole('radio', { name: /^Rules only/ }).click();
    await expect(page).toHaveURL(/#\/scenarios\?mode=rules$/);
    await expect(guide).toContainText('Step 1 of 9');
    await guide.getByRole('button', { name: 'Next' }).click();
    await expect(guide).toContainText('Step 2 of 9');
  });

  test("opens a chapter from Help, and stays away after Don't show again", async ({ page }) => {
    await signIn(page);
    const welcome = page.getByRole('dialog', { name: 'Welcome to the Shutter trial' });
    await welcome.getByRole('button', { name: "Don't show again" }).click();
    await expect(welcome).toBeHidden();
    await page.reload();
    await expect(page.getByRole('heading', { name: 'Scenarios', exact: true })).toBeVisible();
    await expect(welcome).toBeHidden();
    await page.getByRole('button', { name: 'Tour' }).click();
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
    await page.getByRole('button', { name: 'Resume tour' }).click();
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
      // A sub-pixel layout can measure 43.99997: a 44 px target to the hundredth of a pixel
      expect(Math.round((await button.boundingBox())!.height * 100) / 100).toBeGreaterThanOrEqual(44);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(360);
    await go(page, '/scenarios');
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(360);
  });
});

/**
 * Ask about this case opened from the tour's Ask step (s8/ask, step 7 of 9). Below 1440 px Ask opens as a sheet with no
 * overlay and no focus trap while the tour runs, and the card moves into a dock beside it: left of the sheet on a
 * laptop, at the foot of the screen on a phone, just before the sheet in the tab order. Next then goes on, by mouse
 * and by keyboard.
 */
test.describe('the tour with Ask open', () => {
  /** Resumes the quick tour at its Ask step, from the header's button. */
  async function atAskStep(page: Page) {
    await startAt(page, 's8/ask');
    await signIn(page);
    await page.getByRole('button', { name: 'Resume tour' }).click();
    await page.getByRole('menuitem', { name: 'Resume the tour' }).click();
    const guide = page.getByRole('region', { name: 'Guide' });
    await expect(guide).toContainText('Step 7 of 9');
    await expect(guide.getByRole('heading', { name: 'Ask about this case', level: 2 })).toBeFocused();
    return guide;
  }

  /** The card stands in the dock, in sight and uncovered, beside the open panel and not over it on a laptop. */
  async function besideAsk(page: Page, guide: Locator, width: number) {
    const panel = page.getByRole('region', { name: 'Ask about this case' });
    await expect(panel).toBeVisible();
    // No dialog and no overlay: the page around the panel stays usable
    await expect(page.getByRole('dialog')).toHaveCount(0);
    await expect(page.locator('.mantine-Drawer-overlay')).toHaveCount(0);
    await expect(guide).toBeVisible();
    await expect(guide).toContainText('Step 7 of 9');
    await expect(page.locator('[data-guide-dock] [data-guide-card]')).toHaveCount(1);
    // The try-it has done its work once Ask is open
    await expect(guide.getByRole('button', { name: /^Try it/ })).toHaveCount(0);
    expect(await uncovered(guide.getByRole('button', { name: 'Next' }))).toBe(true);
    const card = (await guide.boundingBox())!;
    const sheet = (await panel.boundingBox())!;
    if (width >= 992) expect(card.x + card.width).toBeLessThanOrEqual(sheet.x);
    else expect(card.y + card.height).toBeLessThanOrEqual(page.viewportSize()!.height);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
    return panel;
  }

  for (const viewport of [
    { width: 1280, height: 800 },
    { width: 390, height: 844 },
  ]) {
    test(`goes on with Ask open, by mouse, at ${viewport.width} px`, async ({ page }) => {
      await page.setViewportSize(viewport);
      const guide = await atAskStep(page);
      await page.locator('[data-tour-action="ask-open"]').click();
      const panel = await besideAsk(page, guide, viewport.width);
      await expect(panel.getByRole('heading', { name: 'Ask about this case' })).toBeFocused();
      // Pick a suggested question, as the step says: its recorded answer is shown
      await panel.getByRole('button', { name: /^Which movement is current\?/ }).click();
      await expect(
        panel.getByRole('heading', { name: 'Which movement is current?', level: 4 }),
      ).toBeVisible();
      expect(await uncovered(guide.getByRole('button', { name: 'Next' }))).toBe(true);
      await guide.getByRole('button', { name: 'Next' }).click();
      await expect(guide).toContainText('Step 8 of 9');
      // The tour moved on to another case, and Ask closed with the page it was on
      await expect(panel).toHaveCount(0);
      await expect(page.locator('[data-guide-dock]')).toHaveCount(0);
    });

    test(`goes on with Ask open, by keyboard, at ${viewport.width} px`, async ({ page }) => {
      await page.setViewportSize(viewport);
      const guide = await atAskStep(page);
      // The card's try-it moves focus to Ask's button; Enter opens Ask, on its heading
      await page.keyboard.press('Tab');
      await expect(guide.getByRole('button', { name: 'Try it: open Ask, pick a question' })).toBeFocused();
      await page.keyboard.press('Enter');
      await expect(page.locator('[data-tour-action="ask-open"]')).toBeFocused();
      await page.keyboard.press('Enter');
      const panel = await besideAsk(page, guide, viewport.width);
      await expect(panel.getByRole('heading', { name: 'Ask about this case' })).toBeFocused();
      // The card stands just before the panel: Shift+Tab from its heading reaches Next, and Tab goes back in
      await page.keyboard.press('Shift+Tab');
      await expect(guide.getByRole('button', { name: 'Next' })).toBeFocused();
      await page.keyboard.press('Tab');
      await expect(panel.getByRole('button', { name: 'Close Ask about this case' })).toBeFocused();
      // On to a suggested question, and ask it
      const question = panel.getByRole('button', { name: /^Which movement is current\?/ });
      for (let i = 0; i < 12 && !(await question.evaluate((el) => el === document.activeElement)); i++)
        await page.keyboard.press('Tab');
      await expect(question).toBeFocused();
      await page.keyboard.press('Enter');
      const answer = panel.getByRole('heading', { name: 'Which movement is current?', level: 4 });
      await expect(answer).toBeFocused();
      // Back to the card's Next, still open beside Ask
      const next = guide.getByRole('button', { name: 'Next' });
      for (let i = 0; i < 40 && !(await next.evaluate((el) => el === document.activeElement)); i++)
        await page.keyboard.press('Shift+Tab');
      await expect(next).toBeFocused();
      await expect(panel).toBeVisible();
      await page.keyboard.press('Enter');
      await expect(guide).toContainText('Step 8 of 9');
      await expect(guide.getByRole('heading', { level: 2 })).toBeFocused();
    });
  }

  test('keeps the card before its section from 1440 px, with Ask beside the case', async ({ page }) => {
    await page.setViewportSize({ width: 1600, height: 900 });
    const guide = await atAskStep(page);
    await page.locator('[data-tour-action="ask-open"]').click();
    const panel = page.getByRole('region', { name: 'Ask about this case' });
    await expect(panel).toBeVisible();
    // Opening Ask adds ?ask=1 to the address, which keeps the step's page: the card stays where it was
    await expect(page).toHaveURL(/\?ask=1$/);
    await expect(guide).toContainText('Step 7 of 9');
    await expect(page.locator('[data-guide-dock]')).toHaveCount(0);
    expect(await uncovered(guide.getByRole('button', { name: 'Next' }))).toBe(true);
    await guide.getByRole('button', { name: 'Next' }).click();
    await expect(guide).toContainText('Step 8 of 9');
  });

  test('keeps Ask a sheet when the tour is closed from its card, and Escape in Ask leaves the tour where it was', async ({
    page,
  }) => {
    await page.setViewportSize({ width: 1280, height: 800 });
    const guide = await atAskStep(page);
    await page.locator('[data-tour-action="ask-open"]').click();
    const panel = await besideAsk(page, guide, 1280);
    // Escape in Ask closes Ask, back to its button; the card returns before it
    await page.keyboard.press('Escape');
    await expect(panel).toHaveCount(0);
    await expect(page.locator('[data-tour-action="ask-open"]')).toBeFocused();
    await expect(guide).toContainText('Step 7 of 9');
    await expect(guide.getByRole('button', { name: 'Try it: open Ask, pick a question' })).toBeVisible();
    // Open again, then exit the tour from its card: Ask stays open as it was, with no overlay dropping over the page
    await page.locator('[data-tour-action="ask-open"]').click();
    await expect(panel).toBeVisible();
    await guide.getByRole('button', { name: 'Exit guide' }).click();
    await expect(guide).toHaveCount(0);
    await expect(panel).toBeVisible();
    await expect(page.getByRole('dialog')).toHaveCount(0);
  });
});

test.describe("the engineers' gate step on a phone", () => {
  test.use({ viewport: { width: 360, height: 780 } });

  test('breaks the long reason code rather than leave the card', async ({ page }) => {
    await startAt(page, 's2/gate', 'engineer');
    await signIn(page);
    await page.getByRole('button', { name: 'Resume tour' }).click();
    await page.getByRole('menuitem', { name: 'Resume the tour' }).click();
    const guide = page.getByRole('region', { name: 'Guide' });
    await expect(guide).toContainText('APPROVAL_RECEIVER_CHANGED');
    const { scroll, client } = await guide.evaluate((el) => ({
      scroll: el.scrollWidth,
      client: el.clientWidth,
    }));
    expect(scroll).toBeLessThanOrEqual(client);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(360);
  });
});

/**
 * The other routes' dialogs: a step whose try-it opens a dialog (the message trace's screenshot on the engineers' tour,
 * Start a review on every screen) shows it over the card while it is open, and closes back to the card, whose Next
 * then goes on.
 */
test.describe("the tour through a step's dialog", () => {
  test.use({ viewport: { width: 1280, height: 800 } });

  test("the engineers' message trace", async ({ page }) => {
    await startAt(page, 's8/trace', 'engineer');
    await signIn(page);
    await page.getByRole('button', { name: 'Resume tour' }).click();
    await page.getByRole('menuitem', { name: 'Resume the tour' }).click();
    const guide = page.getByRole('region', { name: 'Guide' });
    await expect(guide).toContainText(/Step \d of 6/);
    await guide.getByRole('button', { name: 'Try it: open the message trace' }).click();
    await page.keyboard.press('Enter');
    const shot = page.getByRole('dialog');
    await expect(shot).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(shot).toHaveCount(0);
    await expect(guide).toBeVisible();
    expect(await uncovered(guide.getByRole('button', { name: /^(Next|Finish)$/ }))).toBe(true);
    await guide.getByRole('button', { name: /^(Next|Finish)$/ }).click();
    await expect(guide).not.toContainText('The message trace in IRIS');
  });

  test('Start a review, on every screen', async ({ page }) => {
    await startAt(page, 'reviews/start', 'all');
    await signIn(page);
    await page.getByRole('button', { name: 'Resume tour' }).click();
    await page.getByRole('menuitem', { name: 'Resume the tour' }).click();
    const guide = page.getByRole('region', { name: 'Guide' });
    await expect(guide).toContainText('A review reads, it repairs nothing');
    await page.locator('[data-tour-action="start-review"]').click();
    const dialog = page.getByRole('dialog', { name: /Start a review/ });
    await expect(dialog).toBeVisible();
    await dialog.getByRole('button', { name: 'Cancel' }).click();
    await expect(dialog).toHaveCount(0);
    expect(await uncovered(guide.getByRole('button', { name: 'Next' }))).toBe(true);
    await guide.getByRole('button', { name: 'Next' }).click();
    await expect(guide).toContainText('Past reviews');
  });
});
