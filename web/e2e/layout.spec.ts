import { expect, test } from '@playwright/test';
import { skipWelcome } from './guide';
import { checkedBy, go, openSteps, screenName, signIn, signOutOfTrial } from './helpers';
import { areas, signIn as signInArea } from './areas';

/**
 * Every screen fits its window at a phone's width (360 px) and a small laptop's (1024 px): the page itself never
 * scrolls sideways. Tables scroll inside their own containers, which is allowed. The screens are each area's
 * (`e2e/areas/`), and each test's title ends with its area's tag, so `--grep @<area>` runs one area's share. The
 * flows on a phone are in each area's own spec.
 */

// The guide's welcome would cover the screens these tests are about; guide.spec.ts tests it
test.beforeEach(({ page }) => skipWelcome(page));

for (const width of [360, 1024]) {
  test.describe(`layout at ${width} px`, () => {
    test.use({ viewport: { width, height: 800 } });

    test(`sign-in page ${signInArea.tag}`, async ({ page }) => {
      await signIn(page);
      await signOutOfTrial(page);
      expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
    });

    for (const area of areas)
      for (const screen of area.screens.filter((sc) => checkedBy(sc, 'layout')))
        test(`${screenName(screen)} ${area.tag}`, async ({ page }) => {
          await signIn(page, { detail: screen.detail });
          await go(page, screen.path, { detail: screen.detail });
          await expect(page.getByRole('heading', { name: screen.heading, exact: true })).toBeVisible();
          await expect(page.getByRole('status')).toHaveCount(0);
          if (screen.steps) await openSteps(page);
          const wide = await page.evaluate(() => ({
            scrollWidth: document.documentElement.scrollWidth,
            // What sticks out, for the failure message
            offenders: [...document.querySelectorAll('body *')]
              .filter((e) => {
                const r = e.getBoundingClientRect();
                if (r.right <= window.innerWidth + 1) return false;
                // Inside a container that scrolls on its own: allowed
                for (let p = e.parentElement; p; p = p.parentElement) {
                  const o = getComputedStyle(p).overflowX;
                  if (o === 'auto' || o === 'scroll' || o === 'hidden') return false;
                }
                return getComputedStyle(e).position !== 'fixed';
              })
              .slice(0, 5)
              .map((e) => `${e.tagName.toLowerCase()}.${String(e.className).slice(0, 40)}`),
          }));
          expect(wide.scrollWidth, `sticks out: ${wide.offenders.join(', ')}`).toBeLessThanOrEqual(width);
        });
  });
}
