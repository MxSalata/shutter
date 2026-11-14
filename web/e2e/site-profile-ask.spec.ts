import { expect, test, type Page } from '@playwright/test';
import { audit } from './axe';
import { skipWelcome } from './guide';
import { go, READ_ONLY, signIn } from './helpers';

/**
 * "Ask Shutter about this" on the Site profile, in the trial: beside each receiver's kind and tier and beside enabling
 * recovery. From 1200 px it opens the panel beside the form, which stays in view; on a phone it opens under the question.
 * The trial gives no live answers, so the question's written explanation shows, and asking changes nothing in the profile.
 */

test.beforeEach(({ page }) => skipWelcome(page));

const TIER = 'Ask Shutter about this: The tier of Downstream Out';
const RECOVERY = 'Ask Shutter about this: Enable recovery';

/** Whether the page scrolls sideways: it must not, at any width. */
const sideways = (page: Page) =>
  page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth);

// Light and dark: the open panel and the region under the question are audited in both (axe's colour contrast)
for (const colorScheme of ['light', 'dark'] as const) {
  test.describe(colorScheme, () => {
    test.use({ colorScheme });

    test(`at 1280 px in ${colorScheme} it opens the panel beside the form, with the written explanation, and the form stays in view`, async ({
      page,
    }) => {
      await page.setViewportSize({ width: 1280, height: 900 });
      await signIn(page);
      await go(page, '/site-profile');
      const receiver = page.getByRole('group', { name: 'Receiver 1: Downstream Out' });
      const button = receiver.getByRole('button', { name: TIER });
      await button.click();
      const panel = page.getByRole('region', { name: 'Ask Shutter', exact: true });
      const card = panel.getByRole('region', { name: 'The tier of Downstream Out' });
      await expect(card).toBeVisible();
      await expect(card.getByText('Tier 2, operations')).toBeVisible();
      await expect(card.getByText('The trial gives no live answers.')).toBeVisible();
      await expect(card.getByText(/^The tier is how sensitive the system is/)).toBeVisible();
      await expect(button).toHaveAttribute('aria-expanded', 'true');
      // The question's own control is beside the panel, not under it
      const radio = receiver.getByRole('radio', { name: /2, operations/ });
      await radio.scrollIntoViewIfNeeded();
      const [r, p] = [await radio.boundingBox(), await panel.boundingBox()];
      expect(r && p && r.x + r.width <= p.x).toBe(true);
      expect(await sideways(page)).toBe(false);
      expect(await audit(page)).toEqual([]);
      // Nothing changed in the profile
      await expect(page.getByRole('region', { name: 'Unsaved changes' })).toHaveCount(0);
      // The panel follows the page: the person's new answer shows there, and the button still names the panel
      await receiver.getByRole('radio', { name: /3, clinical safety/ }).check();
      await expect(card).toContainText('On the page: Tier 3, clinical safety');
      await expect(card).not.toContainText('Tier 2, operations');
      await expect(button).toHaveAttribute('aria-expanded', 'true');
      // Escape closes the panel and goes back to the button
      await card.getByRole('heading', { name: 'The tier of Downstream Out' }).focus();
      await page.keyboard.press('Escape');
      await expect(panel).toHaveCount(0);
      await expect(button).toBeFocused();
    });

    test(`on a phone in ${colorScheme} it opens under the question, in the page, and the switch it is about stays in reach`, async ({
      page,
    }) => {
      await page.setViewportSize({ width: 360, height: 800 });
      await signIn(page);
      await go(page, '/site-profile');
      const button = page.getByRole('button', { name: RECOVERY });
      await button.scrollIntoViewIfNeeded();
      // A 44 px touch target on a phone
      const size = await button.boundingBox();
      expect([size?.width, size?.height]).toEqual([44, 44]);
      const enabled = await page.locator('#site-recovery-mode').isChecked();
      await button.click();
      const region = page.getByRole('region', { name: 'Ask Shutter: Enable recovery' });
      await expect(region).toBeVisible();
      await expect(region.getByText(/^Off is shadow mode: Shutter investigates/)).toBeVisible();
      await expect(page.getByRole('dialog')).toHaveCount(0);
      const toggle = page.locator('#site-recovery-mode');
      await toggle.scrollIntoViewIfNeeded();
      await expect(toggle).toBeInViewport();
      expect(await toggle.isChecked()).toBe(enabled);
      expect(await sideways(page)).toBe(false);
      expect(await audit(page)).toEqual([]);
      await expect(page.getByRole('region', { name: 'Unsaved changes' })).toHaveCount(0);
      await button.click();
      await expect(region).toHaveCount(0);
    });
  });
}

test("the public demo's role reads the written explanation, and its Save stays locked", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await signIn(page, { as: 'demo' });
  await go(page, '/site-profile', { as: 'demo' });
  await page
    .getByRole('button', { name: 'Ask Shutter about this: What kind of system is Records Out?' })
    .click();
  const card = page.getByRole('region', { name: 'What kind of system is Records Out?' });
  await expect(card.getByText("Live answers need the judges' account.")).toBeVisible();
  await expect(card.getByText(/^The kind says what the system keeps/)).toBeVisible();
  // A change of the reader's own still reviews with the locked Save
  const receiver = page.getByRole('group', { name: 'Receiver 2: Records Out' });
  await receiver.getByRole('radio', { name: /3, clinical safety/ }).check();
  const bar = page.getByRole('region', { name: 'Unsaved changes' });
  await expect(bar.getByText('1 change')).toBeVisible();
  await expect(bar.getByText(READ_ONLY)).toBeVisible();
});
