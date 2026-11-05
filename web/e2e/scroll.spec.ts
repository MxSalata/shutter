import { expect, test, type Page } from '@playwright/test';
import { GUIDE_KEY, skipWelcome } from './guide';
import { go } from './helpers';

/**
 * Where the page stands after something on it changes, with a real browser's scrolling: jsdom has no layout and never
 * scrolls, so nothing but this can catch a tab tap or a filter throwing the reader back to the top of the page.
 */

const scrollY = (page: Page) => page.evaluate(() => window.scrollY);

/** Starts recording the highest the page goes, frame by frame: a jump to the top and back would pass a check of the end. */
function watchTop(page: Page) {
  return page.evaluate(() => {
    const w = window as unknown as { __top: number; __watching: boolean };
    w.__top = window.scrollY;
    w.__watching = true;
    const look = () => {
      w.__top = Math.min(w.__top, window.scrollY);
      if (w.__watching) requestAnimationFrame(look);
    };
    requestAnimationFrame(look);
  });
}
const highest = (page: Page) => page.evaluate(() => (window as unknown as { __top: number }).__top);

/** Until the page has stood still for half a second, so a scroll and any correction of it are over. */
function atRest(page: Page) {
  return page.evaluate(
    () =>
      new Promise<void>((resolve) => {
        let y = window.scrollY;
        let still = performance.now();
        const look = () => {
          if (window.scrollY !== y) {
            y = window.scrollY;
            still = performance.now();
          }
          if (performance.now() - still > 500) resolve();
          else requestAnimationFrame(look);
        };
        look();
      }),
  );
}

/** Scrolls the page with the reader's own wheel, until it has gone at least this far. */
async function wheelTo(page: Page, y: number) {
  await page.mouse.move(page.viewportSize()!.width / 2, page.viewportSize()!.height / 2);
  await expect(async () => {
    await page.mouse.wheel(0, y);
    await atRest(page);
    expect(await scrollY(page)).toBeGreaterThanOrEqual(y);
  }).toPass();
}

const barTop = (page: Page) =>
  page.evaluate(() => document.querySelector('.sticky-tabs')!.getBoundingClientRect().top);

test.beforeEach(async ({ page }) => {
  await skipWelcome(page);
});

for (const [width, height] of [
  [1920, 1080],
  [1280, 800],
  [390, 844],
] as const) {
  test.describe(`at ${width} by ${height}`, () => {
    test.use({ viewport: { width, height } });

    test('a tab tapped far down a case keeps its bar where it is and starts the new tab under it', async ({
      page,
    }) => {
      await go(page, '/cases/C-000008?open=compare');
      const evidence = page.getByRole('tab', { name: 'Evidence' });
      await expect(evidence).toBeVisible();
      await expect(page.locator('#case-lifecycle')).toBeVisible();
      // Far enough for the bar to have stuck, wherever the case's header leaves it at this width
      const natural = await barTop(page);
      await wheelTo(page, natural + 500);
      const before = await barTop(page);
      await watchTop(page);
      await evidence.click();
      await expect(evidence).toHaveAttribute('aria-selected', 'true');
      await expect(page.getByRole('tabpanel', { name: 'Evidence' })).toBeVisible();
      await atRest(page);
      expect(await barTop(page), 'the tab bar has not moved').toBe(before);
      expect(await highest(page), 'the page never went to its top').toBeGreaterThan(0);
      const gap = await page.evaluate(() => {
        const bar = document.querySelector('.sticky-tabs')!.getBoundingClientRect();
        const panel = document.querySelector('.case-tab-panel:not([style*="none"])')!.getBoundingClientRect();
        return panel.top - bar.bottom;
      });
      expect(Math.abs(gap), 'the new tab starts under the bar, not partway down itself').toBeLessThan(2);
      await page.getByRole('tab', { name: 'Summary' }).click();
      await atRest(page);
      expect(await barTop(page), 'and going back moves nothing either').toBe(before);
    });
  });
}

test.describe('at a laptop size', () => {
  test.use({ viewport: { width: 1280, height: 800 } });

  test("a tab tapped at the page's top leaves the page where it stands", async ({ page }) => {
    await go(page, '/cases/C-000008');
    const evidence = page.getByRole('tab', { name: 'Evidence' });
    await expect(evidence).toBeVisible();
    // The bar on the screen, at its own place in the page: not stuck, with the case's header above it
    await page.evaluate(() => {
      const bar = document.querySelector('.sticky-tabs')!.getBoundingClientRect();
      window.scrollTo(0, bar.top - window.innerHeight / 2);
    });
    await atRest(page);
    const y = await scrollY(page);
    await evidence.click();
    await expect(page.getByRole('tabpanel', { name: 'Evidence' })).toBeVisible();
    await atRest(page);
    expect(await scrollY(page)).toBe(y);
  });

  for (const [width, height] of [
    [1280, 800],
    [390, 844],
  ] as const)
    test(`after the side by side link, tabs at ${width} wide do not scroll back down to it`, async ({
      page,
    }) => {
      await page.setViewportSize({ width, height });
      await go(page, '/cases/C-000008?show=compare');
      await expect(page.getByRole('region', { name: /^S8 side by side/ })).toBeVisible();
      await atRest(page);
      const summary = page.getByRole('tab', { name: 'Summary' });
      await page.getByRole('tab', { name: 'Evidence' }).click();
      await expect(page.getByRole('tabpanel', { name: 'Evidence' })).toBeVisible();
      await atRest(page);
      const y = await scrollY(page);
      await summary.click();
      await expect(page.getByRole('region', { name: /^S8 side by side/ })).toBeVisible();
      await atRest(page);
      expect(await scrollY(page)).toBeLessThanOrEqual(y);
    });

  test('a stage of the lifecycle goes to its section, without going by the top of the page', async ({
    page,
  }) => {
    await go(page, '/cases/C-000008');
    const stage = page.locator('.lifecycle-step[data-stage="evidence"]');
    await expect(stage).toBeVisible();
    await wheelTo(page, 200);
    await watchTop(page);
    await stage.click();
    await expect(page.locator('#evidence-title')).toBeFocused();
    await atRest(page);
    expect(await highest(page)).toBeGreaterThan(0);
    const place = await page.evaluate(() => {
      const bar = document.querySelector('.sticky-tabs')!.getBoundingClientRect();
      const top = document.querySelector('#evidence')!.getBoundingClientRect().top;
      return { top, bar: bar.bottom, height: window.innerHeight };
    });
    expect(place.top).toBeLessThan(place.height);
    expect(place.top).toBeGreaterThanOrEqual(place.bar - 2);
  });

  test("Evaluation's marks bring their table into view, and stay on it", async ({ page }) => {
    await go(page, '/evaluation');
    const mark = page.getByRole('button', { name: /written wrongly/ });
    await expect(mark).toBeVisible();
    await mark.scrollIntoViewIfNeeded();
    await atRest(page);
    await mark.click();
    await expect(page.locator('#passes-title')).toBeFocused();
    await atRest(page);
    const place = await page.evaluate(() => {
      const top = document.querySelector('#passes')!.getBoundingClientRect().top;
      const header = document.querySelector('.mantine-AppShell-header')!.getBoundingClientRect().bottom;
      return { top, header, height: window.innerHeight };
    });
    expect(place.top, 'the table is not behind the header').toBeGreaterThanOrEqual(place.header - 2);
    expect(place.top, 'the table is on the screen').toBeLessThan(place.height / 2);
    // Pressed again it turns off where it is: the reader's place stays
    const y = await scrollY(page);
    expect(y).toBeGreaterThan(0);
    await page.getByRole('button', { name: /written wrongly/ }).evaluate((b: HTMLElement) => b.click());
    await atRest(page);
    expect(await scrollY(page)).toBeGreaterThan(0);
  });

  test('Back from a case returns to the place in the list, and a new visit starts at the top', async ({
    page,
  }) => {
    await go(page, '/cases');
    const row = page.locator('.case-row').nth(15).getByRole('link').first();
    await expect(row).toBeVisible();
    await row.scrollIntoViewIfNeeded();
    await atRest(page);
    const y = await scrollY(page);
    expect(y).toBeGreaterThan(100);
    await row.click();
    await expect(page.getByRole('tab', { name: 'Evidence' })).toBeVisible();
    expect(await scrollY(page), 'a new page starts at its top').toBe(0);
    await page.mouse.move(640, 400);
    await page.mouse.wheel(0, 500);
    await atRest(page);
    await page.goBack();
    await expect(page.locator('.case-row').nth(15)).toBeVisible();
    await atRest(page);
    expect(Math.abs((await scrollY(page)) - y), 'Back returns to the place left').toBeLessThan(2);
    // The same case opened again is a new visit, whatever was left of the last one
    await page.locator('.case-row').nth(15).getByRole('link').first().click();
    await expect(page.getByRole('tab', { name: 'Evidence' })).toBeVisible();
    await atRest(page);
    expect(await scrollY(page)).toBe(0);
  });

  test('the tour moving on within a case scrolls from where it stood, not by way of the top', async ({
    page,
  }) => {
    await page.addInitScript(
      ([key, value]) => localStorage.setItem(key, value),
      [
        GUIDE_KEY,
        JSON.stringify({ version: 2, scope: 'quick', at: 's8/compare', completed: [], dismissed: true }),
      ],
    );
    await page.goto('./?trial#/scenarios');
    await page.getByRole('button', { name: 'Resume tour' }).click();
    await page.getByRole('menuitem', { name: 'Resume the tour' }).click();
    const guide = page.getByRole('region', { name: 'Guide' });
    await expect(guide).toContainText('Step 6 of 9');
    await page.waitForTimeout(1500);
    await atRest(page);
    expect(await scrollY(page)).toBeGreaterThan(0);
    await watchTop(page);
    await guide.getByRole('button', { name: 'Next' }).click();
    await expect(guide).toContainText('Step 7 of 9');
    await page.waitForTimeout(1500);
    await atRest(page);
    expect(await highest(page)).toBeGreaterThan(0);
  });

  test('Ask about this case opens the page and leaves it where it stands', async ({ page }) => {
    await go(page, '/cases/C-000008');
    await expect(page.getByRole('tab', { name: 'Evidence' })).toBeVisible();
    const ask = page.getByRole('button', { name: /^Ask/ }).first();
    await ask.scrollIntoViewIfNeeded();
    await page.evaluate(() => window.scrollBy(0, 150));
    await atRest(page);
    const y = await scrollY(page);
    expect(y).toBeGreaterThan(0);
    await ask.evaluate((b: HTMLElement) => b.click());
    await expect(page.getByRole('dialog')).toBeVisible();
    await atRest(page);
    expect(Math.abs((await scrollY(page)) - y)).toBeLessThan(2);
  });
});
