import { expect, test, type Locator } from '@playwright/test';
import { skipWelcome } from './guide';
import { go } from './helpers';

/**
 * Getting at things without a mouse: the whole card of a case under a finger, a ring on what has the keyboard's focus,
 * and the user menu by the arrow keys whichever role is current. Layout and real focus: jsdom has neither.
 */

test.beforeEach(async ({ page }) => {
  await skipWelcome(page);
});

const outlineOf = (el: Locator) =>
  el.evaluate((e) => {
    const s = getComputedStyle(e);
    return { style: s.outlineStyle, width: parseFloat(s.outlineWidth), colour: s.outlineColor };
  });

/** WCAG's contrast ratio of two `rgb()` colours. */
function contrast(a: string, b: string) {
  const luminance = (c: string) => {
    const [r, g, b] = c
      .match(/[\d.]+/g)!
      .slice(0, 3)
      .map((v) => {
        const s = Number(v) / 255;
        return s <= 0.04045 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
      });
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  };
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}

test.describe('the focus ring in dark mode', () => {
  test.use({ viewport: { width: 1280, height: 800 }, colorScheme: 'dark' });

  test('stands out at 3:1 from what is around it, on a tile, a Home card and a lifecycle stage', async ({
    page,
  }) => {
    const ringOn = async (el: Locator) => {
      await expect(el).toBeVisible();
      await el.focus();
      await page.keyboard.press('Shift+Tab');
      await page.keyboard.press('Tab');
      await expect(el).toBeFocused();
      return contrast(
        (await outlineOf(el)).colour,
        await page.evaluate(() => {
          // The ring stands off the element, on what the element stands on: the nearest painted ancestor's colour
          let e: Element | null = document.activeElement!.parentElement;
          while (e) {
            const c = getComputedStyle(e).backgroundColor;
            if (c !== 'rgba(0, 0, 0, 0)' && c !== 'transparent') return c;
            e = e.parentElement;
          }
          return getComputedStyle(document.body).backgroundColor;
        }),
      );
    };
    await go(page, '/home');
    expect(await ringOn(page.locator('.home-card').first())).toBeGreaterThanOrEqual(3);
    await go(page, '/cases');
    expect(await ringOn(page.getByRole('button', { name: / Escalated / }))).toBeGreaterThanOrEqual(3);
    await go(page, '/cases/C-000008');
    expect(await ringOn(page.locator('.lifecycle-step[data-stage]').first())).toBeGreaterThanOrEqual(3);
  });
});

test.describe('a case on a phone', () => {
  test.use({ viewport: { width: 390, height: 844 }, hasTouch: true });

  test('opens from a tap anywhere on its card', async ({ page }) => {
    await go(page, '/cases');
    const row = page.locator('.case-row').filter({ hasText: 'C-000064' });
    await row.scrollIntoViewIfNeeded();
    const box = (await row.boundingBox())!;
    // Well away from the id's link, on the card's last line
    await page.touchscreen.tap(box.x + box.width / 2, box.y + box.height - 8);
    await expect(page).toHaveURL(/#\/cases\/C-000064/);
  });

  test('opens from a tap on its badges and time, which only a pointer or the keyboard needs the tooltips of', async ({
    page,
  }) => {
    await go(page, '/cases');
    const row = page.locator('.case-row').filter({ hasText: 'C-000064' });
    const badge = row.locator("td[data-label='Outcome'] [tabindex='0']").first();
    await badge.scrollIntoViewIfNeeded();
    // A finger, not a locator's tap: that refuses an element something else covers, and here the card's link does
    const box = (await badge.boundingBox())!;
    await page.touchscreen.tap(box.x + box.width / 2, box.y + box.height / 2);
    await expect(page).toHaveURL(/#\/cases\/C-000064/);
  });

  test('stays on the list when the text More about opened is tapped, so the reader keeps their place', async ({
    page,
  }) => {
    await go(page, '/cases');
    const more = page
      .locator('.case-row')
      .getByRole('button', { name: /^More about C-/ })
      .first();
    await more.scrollIntoViewIfNeeded();
    await more.tap();
    await expect(more).toHaveAttribute('aria-expanded', 'true');
    const opened = page.locator(".case-row [data-tech-detail='open']").first();
    await expect(opened).toBeVisible();
    await opened.tap();
    await expect(page).toHaveURL(/#\/cases$/);
  });

  test("keeps More about and an incident's link as controls of their own", async ({ page }) => {
    await go(page, '/cases');
    const row = page.locator('.case-row').filter({ hasText: 'C-000049' });
    await expect(row).toBeVisible();
    const more = row.getByRole('button', { name: 'More about C-000049' });
    await more.scrollIntoViewIfNeeded();
    await more.tap();
    await expect(more).toHaveAttribute('aria-expanded', 'true');
    await expect(page).toHaveURL(/#\/cases$/);
    await row.getByRole('link', { name: 'I-000002' }).tap();
    await expect(page).toHaveURL(/#\/incidents\/I-000002/);
  });
});

test.describe('at a desktop width', () => {
  test.use({ viewport: { width: 1280, height: 800 } });

  test('a row is not one big link: its text can be selected', async ({ page }) => {
    await go(page, '/cases');
    const row = page.locator('.case-row').first();
    await expect(row).toBeVisible();
    const box = (await row.boundingBox())!;
    await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
    await expect(page).toHaveURL(/#\/cases$/);
  });

  test("Home's cards and Cases' tiles show a ring when the keyboard reaches them", async ({ page }) => {
    await go(page, '/home');
    const card = page.locator('.home-card').first();
    await expect(card).toBeVisible();
    await card.focus();
    await page.keyboard.press('Shift+Tab');
    await page.keyboard.press('Tab');
    await expect(card).toBeFocused();
    expect(await outlineOf(card)).toMatchObject({ style: 'solid', width: 2 });

    await go(page, '/cases');
    const tile = page.getByRole('button', { name: / Escalated / });
    await expect(tile).toBeVisible();
    await tile.focus();
    await page.keyboard.press('Shift+Tab');
    await page.keyboard.press('Tab');
    await expect(tile).toBeFocused();
    const ring = await outlineOf(tile);
    expect(ring).toMatchObject({ style: 'solid', width: 2 });
    // Pressed by the keyboard: told apart from the chosen tile's own outline, which it holds once the focus leaves
    await page.keyboard.press('Enter');
    await expect(tile).toHaveAttribute('aria-pressed', 'true');
    expect((await outlineOf(tile)).colour).toBe(ring.colour);
    await page.keyboard.press('Tab');
    await expect(tile).not.toBeFocused();
    expect((await outlineOf(tile)).colour).not.toBe(ring.colour);
  });

  test("the rules-only S8 case has a Closed tile of its own, so the tiles add up to the list's", async ({
    page,
  }) => {
    await go(page, '/cases');
    const tile = page.getByRole('button', { name: /^1 Not as expected Show these$/ });
    await expect(tile).toBeVisible();
    const figures = await page.locator('.stat-tile .stat-figure').allTextContents();
    expect(figures.reduce((a, b) => a + Number(b), 0)).toBe(64);
    await tile.click();
    await expect(page.locator('.case-row')).toHaveCount(1);
    await expect(page.locator('.case-row')).toContainText('C-000021');
  });

  for (const role of ['Approver', 'Operator', 'Judge']) {
    test(`the user menu works from the keyboard with ${role} current`, async ({ page }) => {
      await go(page, '/cases');
      const trigger = page.getByRole('button', { name: /^Signed in as / });
      await trigger.click();
      const item = page.getByRole('menuitem', { name: new RegExp(`^${role}`) });
      if ((await item.getAttribute('aria-current')) !== 'true') {
        await item.click();
        await trigger.click();
      }
      await expect(page.getByRole('menuitem', { name: new RegExp(`^${role}.*current`) })).toHaveAttribute(
        'aria-current',
        'true',
      );
      await page.keyboard.press('Escape');
      await trigger.focus();
      await page.keyboard.press('Enter');
      await expect(page.getByRole('menu')).toBeVisible();
      await page.keyboard.press('ArrowDown');
      await expect(page.getByRole('menu').locator(':focus')).toHaveCount(1);
      await page.keyboard.press('Escape');
    });
  }
});
