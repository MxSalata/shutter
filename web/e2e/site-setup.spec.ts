import { expect, test, type Locator, type Page } from '@playwright/test';
import { audit } from './axe';
import { skipWelcome } from './guide';
import { go, READ_ONLY, signIn } from './helpers';

/**
 * Set up the site, in the trial: one receiver from "Add a receiver" to the Site profile's own review, by keyboard alone,
 * at a desktop's width and a phone's, in light and in dark; the draft discarded; the two panes as tabs; and the public
 * demo's role, whose Save stays locked. Nothing is saved from the page itself.
 */

test.beforeEach(({ page }) => skipWelcome(page));

const AS_DEMO = { as: 'demo' } as const;
const NAME = 'Which receiver? Name it by its production item.';
const KIND = 'What kind of system is it?';
const TIER = 'Its tier';

const sideways = (page: Page) =>
  page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth);

/** Presses a button with the keyboard, as a person without a pointer does. */
async function press(page: Page, target: Locator, key = 'Enter') {
  await target.focus();
  await page.keyboard.press(key);
}

const card = (page: Page, name: string) => page.getByRole('region', { name, exact: true });

/** One receiver through the checklist with the keyboard alone: named, described, its kind and tier chosen, the rest left. */
async function describeReceiver(page: Page) {
  await press(page, page.getByRole('button', { name: 'Add a receiver' }));
  const name = page.getByRole('textbox', { name: 'Production item' });
  await name.focus();
  await page.keyboard.type('Bed Board');
  await press(page, card(page, NAME).getByRole('button', { name: 'Next question' }));
  await expect(page.getByRole('heading', { name: 'What is the system, in a few words?' })).toBeFocused();
  await page.getByRole('textbox', { name: /What it does/ }).focus();
  await page.keyboard.type('the ward whiteboard');
  await press(page, page.getByRole('button', { name: 'Next question' }));
  await expect(page.getByRole('heading', { name: KIND })).toBeFocused();
  await press(page, card(page, KIND).getByRole('radio', { name: /Current state/ }), 'Space');
  await press(page, card(page, KIND).getByRole('button', { name: 'Next question' }));
  await press(page, card(page, TIER).getByRole('radio', { name: /2, operations/ }), 'Space');
  await press(page, card(page, TIER).getByRole('button', { name: 'Next question' }));
  await press(page, page.getByRole('button', { name: 'Leave for now' }));
  await press(page, page.getByRole('button', { name: 'Leave for now' }));
  await press(page, page.getByRole('button', { name: 'It accepts neither' }));
  await press(page, page.getByRole('button', { name: 'Done' }));
  await expect(page.getByRole('heading', { name: 'Summary: Bed Board' })).toBeFocused();
}

for (const colorScheme of ['light', 'dark'] as const) {
  test.describe(colorScheme, () => {
    test.use({ colorScheme });

    test(`at 1280 px in ${colorScheme}, by keyboard: a receiver from its name to the review, saved in the trial`, async ({
      page,
    }) => {
      await page.setViewportSize({ width: 1280, height: 900 });
      await signIn(page);
      await go(page, '/site-setup');
      await expect(page.getByRole('heading', { name: 'Set up the site', level: 1 })).toBeVisible();
      await expect(
        page.getByText(
          'Ask Shutter explains each question here. It does not read typed answers in the trial, which has no model.',
        ),
      ).toBeVisible();
      await describeReceiver(page);
      // The two panes side by side: the draft with what Shutter will do there, worked out by the page
      const draft = page.getByRole('region', { name: 'Draft', exact: true });
      await expect(draft.getByRole('heading', { name: 'What Shutter will do here' })).toBeVisible();
      await expect(draft.getByText(/the gate blocks every write/)).toBeVisible();
      await expect(draft.getByText('Overtaken failure: closes, no write.', { exact: true })).toBeVisible();
      const [c, d] = [
        await page.getByRole('region', { name: 'Conversation', exact: true }).boundingBox(),
        await draft.boundingBox(),
      ];
      expect(c && d && c.x + c.width <= d.x).toBe(true);
      expect(await sideways(page)).toBe(false);
      expect(await audit(page)).toEqual([]);
      // The header's Ask Shutter goes to the conversation: no panel beside the two panes
      await press(page, page.getByRole('button', { name: 'Ask Shutter', exact: true }));
      await expect(page.getByRole('region', { name: 'Ask Shutter about this page' })).toBeVisible();
      await expect(page.getByRole('region', { name: 'Ask Shutter', exact: true })).toHaveCount(0);
      // The existing review, on the Site profile page, opens at once and holds focus
      await press(page, card(page, 'Summary: Bed Board').getByRole('button', { name: 'Review and save…' }));
      const dialog = page.getByRole('dialog');
      await expect(dialog.getByText('Receiver added: Bed Board')).toBeVisible();
      await expect(page.getByRole('heading', { name: 'Site profile', level: 1 })).toBeVisible();
      expect(await dialog.evaluate((el) => el.contains(document.activeElement))).toBe(true);
      expect(await audit(page)).toEqual([]);
      // Cancel: the band above the form, with focus on it
      await press(page, dialog.getByRole('button', { name: 'Cancel' }));
      const band = page.getByRole('region', { name: 'A draft from Set up the site' });
      await expect(band.getByRole('heading', { name: 'A draft from Set up the site' })).toBeFocused();
      await expect(band.getByRole('row', { name: /Bed Board: tier/ })).toContainText('Tier 2, operations');
      // Reviewed again and saved: the trial's own save
      await press(page, band.getByRole('button', { name: 'Review and save…' }));
      await press(page, page.getByRole('dialog').getByRole('button', { name: /^Save version/ }));
      await expect(page.getByText(/^Version \d+ saved$/)).toBeVisible();
      await expect(band).toHaveCount(0);
      await expect(
        page.getByRole('list', { name: 'The receivers and what each needs' }).getByRole('listitem', {
          name: 'Bed Board',
        }),
      ).toContainText('Takes: nothing declared.');
    });

    test(`on a phone in ${colorScheme}: the two panes are tabs, and nothing scrolls sideways`, async ({
      page,
    }) => {
      await page.setViewportSize({ width: 360, height: 800 });
      await signIn(page);
      await go(page, '/site-setup');
      await describeReceiver(page);
      expect(await sideways(page)).toBe(false);
      const tabs = page.getByRole('tablist', { name: 'The conversation and the draft' });
      await tabs.getByRole('tab', { name: 'Conversation' }).focus();
      await page.keyboard.press('ArrowRight');
      const draftTab = tabs.getByRole('tab', { name: /^Draft \(\d+ changes?\)$/ });
      await expect(draftTab).toHaveAttribute('aria-selected', 'true');
      await expect(page.getByRole('heading', { name: 'What Shutter will do here' })).toBeVisible();
      expect(await sideways(page)).toBe(false);
      expect(await audit(page)).toEqual([]);
      // Edit goes back to the question's card, in the other tab
      await press(page, page.getByRole('button', { name: 'Edit: Tier' }));
      await expect(tabs.getByRole('tab', { name: 'Conversation' })).toHaveAttribute('aria-selected', 'true');
      await expect(page.getByRole('heading', { name: TIER })).toBeFocused();
      expect(await audit(page)).toEqual([]);
      // The save bar's primary action is whole, inside the window
      const review = page
        .getByRole('region', { name: 'Unsaved changes' })
        .getByRole('button', { name: 'Review and save…' });
      const box = await review.boundingBox();
      expect(box && box.x >= 0 && box.x + box.width <= 360).toBe(true);
    });
  });
}

test('discards the draft after asking, and the start list is the stored profile again', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await signIn(page);
  await go(page, '/site-setup');
  await describeReceiver(page);
  await page
    .getByRole('region', { name: 'Unsaved changes' })
    .getByRole('button', { name: 'Discard the draft' })
    .click();
  const dialog = page.getByRole('dialog', { name: 'Discard this draft?' });
  await expect(dialog.getByText('Nothing has been saved, and nothing will be.')).toBeVisible();
  await dialog.getByRole('button', { name: 'Discard the draft' }).click();
  await expect(page.getByRole('heading', { name: 'Choose a receiver' })).toBeVisible();
  await expect(page.getByText('Bed Board')).toHaveCount(0);
  await expect(page.getByRole('region', { name: 'Unsaved changes' })).toHaveCount(0);
});

test("the Site profile links to it, and to one receiver's checklist", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await signIn(page);
  await go(page, '/site-profile');
  await page.getByRole('link', { name: 'Change in Set up the site: Records Out' }).click();
  await expect(page.getByRole('heading', { name: 'Set up the site', level: 1 })).toBeVisible();
  await expect(card(page, KIND)).toContainText(/In force, version \d+: History of record/);
  await page.getByRole('button', { name: 'All receivers' }).click();
  await page.getByRole('link', { name: 'Site profile page' }).first().click();
  await page.getByRole('link', { name: 'Set up with Ask Shutter' }).click();
  await expect(page.getByRole('heading', { name: 'Choose a receiver' })).toBeVisible();
});

test.describe('the live hospital, as the public role sees it', () => {
  test('answers with the controls, reads the written explanation, and finds the Save locked', async ({
    page,
  }) => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await signIn(page, AS_DEMO);
    await go(page, '/site-setup', AS_DEMO);
    await expect(
      page.getByRole('region', { name: 'Where this page stands' }).getByText(READ_ONLY),
    ).toBeVisible();
    await describeReceiver(page);
    // No live answer for this role: the written explanation, and nothing asked
    await card(page, KIND).getByRole('button', { name: 'Change: Kind of system' }).click();
    await card(page, KIND).getByRole('button', { name: 'Why does this matter?' }).click();
    await expect(card(page, KIND).getByText(/^The kind says what the system keeps/)).toBeVisible();
    const bar = page.getByRole('region', { name: 'Unsaved changes' });
    await expect(bar.getByText(READ_ONLY)).toBeVisible();
    await bar.getByRole('button', { name: 'Review and save…' }).click();
    const dialog = page.getByRole('dialog');
    const save = dialog.getByRole('button', { name: /^Save version/ });
    await expect(save).toHaveAttribute('aria-disabled', 'true');
    await expect(save).toHaveAccessibleDescription(READ_ONLY);
    await save.focus();
    await page.keyboard.press('Enter');
    await expect(dialog).toBeVisible();
    await expect(page.getByText(/^Version \d+ saved$/)).toHaveCount(0);
  });
});
