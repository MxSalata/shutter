import { expect, test, type Page } from '@playwright/test';
import { skipWelcome } from './guide';

/**
 * Every screen fits its window at a phone's width (360 px) and a small laptop's (1024 px): the page itself never
 * scrolls sideways. Tables scroll inside their own containers, which is allowed.
 */
const go = (page: Page, path: string) => page.goto(`./#${path}`);

// The guide's welcome would cover the screens these tests are about; guide.spec.ts tests it
test.beforeEach(({ page }) => skipWelcome(page));

/**
 * Opens every closed story step of a case page and waits for the panels to finish opening: a closed step is hidden,
 * and a check of the page would skip it.
 */
async function openSteps(page: Page) {
  for (const step of await page.getByRole('button', { name: /^\d\. / }).all())
    if ((await step.getAttribute('aria-expanded')) !== 'true') await step.click();
  await expect(page.getByRole('button', { name: /^\d\. /, expanded: false })).toHaveCount(0);
  await expect(page.getByRole('status')).toHaveCount(0);
  // The panels' opening transitions, not an endless one such as a progress bar's stripes
  await page.waitForFunction(() =>
    document
      .getAnimations()
      .every((a) => a.playState !== 'running' || a.effect?.getTiming().iterations === Infinity),
  );
}

const SCREENS: [path: string, heading: string, steps?: 'open'][] = [
  ['/scenarios', 'Scenarios'],
  ['/cases', 'Cases'],
  ['/cases/C-000009', 'Case C-000009'],
  ['/cases/C-000002', 'Case C-000002'],
  ['/cases/C-000007', 'Case C-000007'],
  ['/cases/C-000008?show=compare', 'Case C-000008'],
  ['/cases/C-000008?tab=evidence', 'Case C-000008'],
  ['/cases/C-000007?tab=audit', 'Case C-000007'],
  // Every story step open, on a case that waits for a person, one escalated by the board, a resolved one and two
  // blocked ones with the gate's checks and the next action
  ['/cases/C-000002', 'Case C-000002', 'open'],
  ['/cases/C-000008', 'Case C-000008', 'open'],
  ['/cases/C-000009', 'Case C-000009', 'open'],
  ['/cases/C-000053', 'Case C-000053', 'open'],
  ['/cases/C-000020', 'Case C-000020', 'open'],
  ['/incidents', 'Incidents'],
  ['/incidents/I-000001', 'Incident I-000001'],
  ['/reviews', 'Production review'],
  ['/reviews/PR-000001', 'Review PR-000001'],
  ['/reviews/PR-000003', 'Review PR-000003'],
  ['/site-profile', 'Site profile'],
  ['/library', 'Agent library'],
  ['/settings', 'Settings and costs'],
  ['/evaluation', 'Evaluation'],
  ['/health', 'Health'],
];

for (const width of [360, 1024]) {
  test.describe(`layout at ${width} px`, () => {
    test.use({ viewport: { width, height: 800 } });

    test('sign-in page', async ({ page }) => {
      await go(page, '/login');
      await expect(page.getByRole('button', { name: /^Sign in$/ })).toBeVisible();
      expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
    });

    for (const [path, heading, steps] of SCREENS) {
      const name = path.includes('?') ? `${heading} (${path.split('?')[1]})` : heading;
      test(steps ? `${name}, every step open` : name, async ({ page }) => {
        await go(page, '/login');
        await page.getByRole('button', { name: /Try the demo/ }).click();
        await expect(page.getByRole('heading', { name: 'Scenarios' })).toBeVisible();
        await go(page, path);
        await expect(page.getByRole('heading', { name: heading, exact: true })).toBeVisible();
        await expect(page.getByRole('status')).toHaveCount(0);
        if (steps) await openSteps(page);
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
    }
  });
}
