import { expect, test, type Page } from '@playwright/test';
import { GUIDE_KEY } from './guide';

/**
 * Where the tour's scrolling leaves things, with real smooth scrolling: on every step of the quick and the engineers' tours,
 * at a desktop's and a laptop's size, the card's top stands in view below everything that stays at the top of the screen
 * (the trial's band and header, and on a case page the tab bar once it has stuck), without having stopped far short of
 * there, the section it talks about starts on the screen, and nothing has shifted sideways. Everything is measured on
 * the page, so a header or a bar of another height is caught too.
 */

type Tour = 'quick' | 'engineer';

/** Until the page has stood still long enough for a scroll, and any correction of it, to be over. */
async function atRest(page: Page) {
  await page.evaluate(
    () =>
      new Promise<void>((resolve) => {
        let y = window.scrollY;
        let top = document.querySelector('[data-guide-card]')?.getBoundingClientRect().top;
        let still = performance.now();
        const look = () => {
          const t = document.querySelector('[data-guide-card]')?.getBoundingClientRect().top;
          if (window.scrollY !== y || t !== top) {
            y = window.scrollY;
            top = t;
            still = performance.now();
          }
          if (t !== undefined && performance.now() - still > 1200) resolve();
          else requestAnimationFrame(look);
        };
        look();
      }),
  );
}

/** Everything the assertions read, from the page as it stands. */
const measure = (page: Page) =>
  page.evaluate(() => {
    const host = document.querySelector<HTMLElement>('[data-guide-host]');
    const card = document.querySelector('[data-guide-card]')!.getBoundingClientRect();
    const target = host?.nextElementSibling?.getBoundingClientRect();
    const header = document.querySelector('.mantine-AppShell-header')!.getBoundingClientRect();
    const bar = document.querySelector('.sticky-tabs')?.getBoundingClientRect();
    const stuck = !!bar && bar.top <= header.bottom + 1;
    const sideways = Array.from(document.querySelectorAll('*')).filter((e) => {
      if (e.scrollLeft === 0) return false;
      // A table or a code block the reader may scroll is its own business: the frame around the page is not
      return e.contains(host);
    }).length;
    return {
      title: document.querySelector('[data-guide-card] h2')?.textContent,
      cardTop: card.top,
      targetTop: target?.top ?? null,
      headerBottom: header.bottom,
      // Under the header, as the bar's own place must be: a bar behind the header is a fault of its own
      barTop: stuck ? bar.top : null,
      line: stuck ? bar.bottom : header.bottom,
      scrollX: window.scrollX,
      sideways,
      wide: document.documentElement.scrollWidth - document.documentElement.clientWidth,
      atEnd:
        window.scrollY >= document.documentElement.scrollHeight - window.innerHeight - 1 ||
        window.scrollY < 1,
      height: window.innerHeight,
    };
  });

/** The engineers' tour starts by itself from its address; the quick tour from the welcome's Start the tour. */
async function startTour(page: Page, tour: Tour) {
  if (tour === 'engineer') {
    await page.goto('./?trial=engineer#/scenarios');
    await expect(page.getByRole('region', { name: 'Guide' })).toBeVisible();
    return;
  }
  await page.goto('./?trial#/scenarios');
  const welcome = page.getByRole('dialog', { name: 'Welcome to the Shutter trial' });
  await welcome.getByRole('button', { name: 'Start the tour' }).click();
}

function checkStep(m: Awaited<ReturnType<typeof measure>>, where: string) {
  expect(m.cardTop, `${where}: the card's top clears what stays at the top`).toBeGreaterThanOrEqual(m.line);
  // Close under it, unless the page has no more to scroll
  if (!m.atEnd) expect(m.cardTop, `${where}: the scroll did not stop short`).toBeLessThanOrEqual(m.line + 24);
  expect(m.cardTop, `${where}: the card's top is on the screen`).toBeLessThan(m.height);
  expect(m.targetTop, `${where}: the section's start is on the screen`).toBeLessThan(m.height);
  if (m.barTop !== null)
    expect(Math.abs(m.barTop - m.headerBottom), `${where}: the tab bar is under the header`).toBeLessThan(1);
  expect(m.scrollX, `${where}: the page has not shifted sideways`).toBe(0);
  expect(m.sideways, `${where}: nothing around the card has shifted sideways`).toBe(0);
  expect(m.wide, `${where}: the page is no wider than the screen`).toBeLessThanOrEqual(0);
}

async function walk(page: Page, total: number, label: string) {
  const guide = page.getByRole('region', { name: 'Guide' });
  for (let n = 1; n <= total; n++) {
    await expect(guide).toContainText(`Step ${n} of ${total}`);
    await atRest(page);
    const m = await measure(page);
    checkStep(m, `${label} step ${n}, "${m.title}"`);
    await guide.getByRole('button', { name: n === total ? 'Finish' : 'Next' }).click();
  }
  await expect(guide.getByRole('heading', { name: 'That is the tour.' })).toBeVisible();
}

test.describe('where the tour scrolls to', () => {
  test.describe.configure({ timeout: 150_000 });

  for (const [width, height] of [
    [1920, 1080],
    [1280, 800],
  ] as const) {
    test.describe(`at ${width} by ${height}`, () => {
      test.use({ viewport: { width, height } });
      for (const [tour, total] of [
        ['quick', 9],
        ['engineer', 6],
      ] as const) {
        test(`every step of the ${tour} tour stands clear of what stays at the top`, async ({ page }) => {
          await startTour(page, tour);
          await walk(page, total, `${tour} at ${width}`);
        });
      }
    });
  }

  test.describe('with reduced motion', () => {
    test.use({ viewport: { width: 1280, height: 800 }, reducedMotion: 'reduce' });
    test('step 1 stays where it landed, under what stays at the top, as the page finishes loading', async ({
      page,
    }) => {
      await startTour(page, 'quick');
      const guide = page.getByRole('region', { name: 'Guide' });
      await expect(guide).toContainText('Step 1 of 9');
      await atRest(page);
      const m = await measure(page);
      checkStep(m, 'step 1 with reduced motion');
    });
  });

  test('a larger text size in the browser grows the header, and the card and the tab bar stay under it', async ({
    page,
  }) => {
    await page.setViewportSize({ width: 1280, height: 800 });
    // What Chrome's "Large" font size does: the root's size, which every rem in the app follows
    await page.addInitScript(() => {
      const style = document.createElement('style');
      style.textContent = 'html { font-size: 20px !important; }';
      document.addEventListener('DOMContentLoaded', () => document.head.append(style));
    });
    await startTour(page, 'engineer');
    const guide = page.getByRole('region', { name: 'Guide' });
    for (let n = 1; n <= 3; n++) {
      await expect(guide).toContainText(`Step ${n} of 6`);
      await atRest(page);
      const m = await measure(page);
      expect(m.headerBottom, 'the header has grown with the text').toBeGreaterThan(100);
      checkStep(m, `step ${n}, "${m.title}"`);
      if (n < 3) await guide.getByRole('button', { name: 'Next' }).click();
    }
  });

  /** Resumes a stored step of the quick tour from the Tour menu. */
  async function resumeAt(page: Page, at: string, n: number, width = 1280, height = 800) {
    await page.setViewportSize({ width, height });
    await page.addInitScript(
      ([key, value]) => localStorage.setItem(key, value),
      [GUIDE_KEY, JSON.stringify({ version: 2, scope: 'quick', at, completed: [], dismissed: true })],
    );
    await page.goto('./?trial#/scenarios');
    await page.getByRole('button', { name: 'Resume tour' }).click();
    await page.getByRole('menuitem', { name: 'Resume the tour' }).click();
    const guide = page.getByRole('region', { name: 'Guide' });
    await expect(guide).toContainText(`Step ${n} of 9`);
    return guide;
  }

  test('pressing the try-it leaves the card where it is when its control is already in view', async ({
    page,
  }) => {
    const guide = await resumeAt(page, 's8/ask', 7);
    await atRest(page);
    const before = await measure(page);
    checkStep(before, 'step 7');
    await guide.getByRole('button', { name: /^Try it/ }).click();
    await expect(page.locator('[data-tour-action="ask-open"]')).toBeFocused();
    await atRest(page);
    expect((await measure(page)).cardTop).toBe(before.cardTop);
  });

  /** The S2 decision step's Try it, by hand: the chip, the real button, the confirm. */
  async function approveByHand(page: Page, width = 1280, height = 800) {
    const guide = await resumeAt(page, 's2/decision', 3, width, height);
    await expect(page.locator('[data-guide-card]')).toBeVisible();
    await guide.getByRole('button', { name: 'Try it: press Approve plan' }).click();
    await expect(page.getByTestId('guide-try-pointer')).toBeVisible();
    const control = page.locator('[data-tour-action="approve-plan"]');
    await expect(control).toBeFocused();
    await control.click();
    // Pressed, the pointer has done its work: nothing floats over the dialog
    await expect(page.getByTestId('guide-try-pointer')).toHaveCount(0);
    await page
      .getByRole('dialog')
      .getByRole('button', { name: /^Approve this plan/ })
      .click();
    return guide;
  }

  /** The reader who approved by hand stands on the verified step, as one who pressed Next would, with no pointer. */
  async function expectLandedOnVerified(page: Page, guide: ReturnType<Page['getByRole']>) {
    // The replay plays first, and only then the tour moves on
    await expect(page.getByTestId('replay-note')).toBeVisible({ timeout: 15_000 });
    await expect(guide).toContainText('Step 4 of 9');
    await expect(guide.getByRole('heading', { name: 'Checked at the bed system' })).toBeFocused();
    // Approved by the reader's own hand: the card does not claim it was done for them
    await expect(guide).not.toContainText('Approved for you');
    await atRest(page);
    const m = await measure(page);
    checkStep(m, 'the verified step after an approval by hand');
    expect(m.cardTop, "the card is on the screen, not left a screen's height below it").toBeLessThan(
      m.height / 2,
    );
    await expect(page.getByTestId('guide-try-pointer')).toHaveCount(0);
    await expect(page.locator('[data-tour-try]')).toHaveCount(0);
  }

  test('an approval by hand on the Try it step goes on to the verified step, and drops the pointer', async ({
    page,
  }) => {
    const guide = await approveByHand(page);
    await expectLandedOnVerified(page, guide);
    // One step on, not two: the tour stays there
    await page.waitForTimeout(1000);
    await expect(guide).toContainText('Step 4 of 9');
  });

  test('an approval by hand on a wide screen does too', async ({ page }) => {
    const guide = await approveByHand(page, 1920, 1080);
    await expectLandedOnVerified(page, guide);
  });

  test.describe('an approval by hand with reduced motion', () => {
    test.use({ reducedMotion: 'reduce' });
    test('goes on to the verified step too', async ({ page }) => {
      const guide = await approveByHand(page);
      await expectLandedOnVerified(page, guide);
    });
  });

  test('a rejection by hand on the Try it step goes on to say nothing was written, and lands the card', async ({
    page,
  }) => {
    const guide = await resumeAt(page, 's2/decision', 3);
    await expect(page.locator('[data-guide-card]')).toBeVisible();
    await page.getByRole('button', { name: 'Reject plan' }).click();
    await page.getByRole('dialog').getByRole('button', { name: 'Reject this plan' }).click();
    await expect(guide).toContainText('Step 4 of 9');
    await expect(guide.getByRole('heading', { name: 'Rejected, so nothing written' })).toBeFocused();
    await expect(guide).toContainText('The plan was rejected, so nothing was written.');
    await expect(guide).not.toContainText('it landed');
    await expect(guide).not.toContainText('Approved for you');
    await atRest(page);
    const m = await measure(page);
    checkStep(m, 'the step after a rejection by hand');
    expect(m.cardTop, 'the card is on the screen, not left above it').toBeLessThan(m.height / 2);

    // Back and Next again say the same, and approve nothing
    await guide.getByRole('button', { name: 'Back' }).click();
    await expect(guide.getByRole('heading', { name: 'The plan was rejected here' })).toBeVisible();
    await expect(guide.getByRole('button', { name: /^Try it/ })).toHaveCount(0);
    await guide.getByRole('button', { name: 'Next' }).click();
    await expect(guide.getByRole('heading', { name: 'Rejected, so nothing written' })).toBeVisible();
    await expect(guide).not.toContainText('Approved for you');
  });

  test('cancelling the approval leaves the step where it was, and the chip brings the pointer back', async ({
    page,
  }) => {
    const guide = await resumeAt(page, 's2/decision', 3);
    await guide.getByRole('button', { name: 'Try it: press Approve plan' }).click();
    const control = page.locator('[data-tour-action="approve-plan"]');
    await control.click();
    await page.getByRole('dialog').getByRole('button', { name: 'Cancel' }).click();
    await expect(guide).toContainText('Step 3 of 9');
    await expect(page.getByTestId('guide-try-pointer')).toHaveCount(0);
    await guide.getByRole('button', { name: 'Try it: press Approve plan' }).click();
    await expect(page.getByTestId('guide-try-pointer')).toBeVisible();
  });

  test("leaves the page where the reader's own scroll put it, even while the card is landing", async ({
    page,
  }) => {
    await resumeAt(page, 's8/compare', 6);
    await expect(page.locator('[data-guide-card]')).toBeVisible();
    await page.mouse.move(800, 400);
    await page.mouse.wheel(0, 300);
    await atRest(page);
    const y = await page.evaluate(() => window.scrollY);
    // Past the time the landing watches the page for
    await page.waitForTimeout(4500);
    expect(await page.evaluate(() => window.scrollY)).toBe(y);
  });
});
