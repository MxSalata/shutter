import { expect, test } from '@playwright/test';
import { audit, choosePastel, MODES } from './axe';
import { skipWelcome } from './guide';
import { atWidth, banner, go, READ_ONLY, screenName, signIn } from './helpers';
import { areas, siteProfile } from './areas';

/**
 * The demo opened as the live hospital's public role (`?as=demo`): the trial opens signed in as `demo`, who approves
 * but cannot run or reset scenarios or save the site, and whose settings carry the hospital feed (replayed in the
 * trial). The address keeps `?as=demo` in every step: a navigation that drops it reloads the page, and the trial
 * starts afresh as the approver. The screens that change for this role are each area's `liveScreens`; the flows are in
 * each area's own spec.
 */
const AS_DEMO = { as: 'demo' } as const;

// The guide's welcome would cover the screens these tests are about; guide.spec.ts tests it
test.beforeEach(({ page }) => skipWelcome(page));

/** The screens that change in live mode, in every appearance: the banner on each, the missing controls, the note. */
for (const { colorScheme, contrast, palette } of MODES) {
  const mode = `${palette === 'pastel' ? 'pastel' : colorScheme}${contrast === 'more' ? ', high contrast' : ''}`;
  test.describe(`accessibility of the live hospital (axe-core, WCAG 2.1 A/AA), ${mode}`, () => {
    test.use({ colorScheme, contrast });
    if (palette === 'pastel') test.beforeEach(({ page }) => choosePastel(page));

    for (const area of areas)
      for (const screen of area.liveScreens ?? [])
        test(`${screenName(screen)} ${area.tag}`, async ({ page }) => {
          await atWidth(page, screen);
          await signIn(page, AS_DEMO);
          await go(page, screen.path, AS_DEMO);
          await expect(page.getByRole('heading', { name: screen.heading, exact: true })).toBeVisible();
          await expect(banner(page)).toBeVisible();
          // The page's data, not its loading state
          await expect(page.getByRole('status')).toHaveCount(0);
          expect(await audit(page)).toEqual([]);
        });

    test(`the review of a change, for reading ${siteProfile.tag}`, async ({ page }) => {
      await signIn(page, AS_DEMO);
      await go(page, '/site-profile?suggest=C-000008&fact=W1', AS_DEMO);
      await page.getByRole('button', { name: 'Review the change…' }).click();
      await expect(page.getByRole('dialog').getByText(READ_ONLY)).toBeVisible();
      expect(await audit(page)).toEqual([]);
    });
  });
}
