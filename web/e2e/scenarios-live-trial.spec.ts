import { expect, test, type Page, type Route } from '@playwright/test';
import fixtures from '../src/mocks/fixtures.json' with { type: 'json' };
import { audit } from './axe';
import { skipWelcome } from './guide';

/**
 * The Scenarios page of the online demo on the build IRIS serves, against a stand-in server, before its hospital has
 * played a story. Signed in as the public demo's viewer: the three cards keep their text and say they have no case yet,
 * Run and Reset are greyed out, and all four modes are described with no word about the trial. Signed in as a judge
 * (1.4.3): Run is on, Reset is greyed out with its reason written under it, and no reason asks for the operator or
 * approver role, which the user menu shows the judge. Nothing here reaches IRIS.
 */

const DEMO = {
  username: 'demo',
  roles: ['Shutter_Demo'],
  operator: true,
  approver: true,
  can: { operate: true, approve: true, configure: false, scenarios: false, reset: false, liveAgents: false },
};

const JUDGE = {
  username: 'judge',
  roles: ['Shutter_Judge'],
  operator: true,
  approver: true,
  can: { operate: true, approve: true, configure: false, scenarios: true, reset: false, liveAgents: true },
};

const RESET_WHY =
  'This sign-in runs scenarios but does not reset the shared demo, which would clear it for everyone signed in';

/** The stand-in server, signed in as `me`, with a fresh demo: no scenario has a case yet. */
async function standIn(page: Page, me: unknown) {
  const json = (route: Route, body: unknown, status = 200) => route.fulfill({ status, json: body });
  await page.route('**/api/shutter/**', (route) => {
    const path = new URL(route.request().url()).pathname.replace(/^.*\/api\/shutter/, '');
    switch (path) {
      case '/me':
        return json(route, me);
      case '/health':
        return json(route, { ok: true, demo: true, version: 'stub', checks: [] });
      case '/settings':
        return json(route, fixtures.settings);
      case '/scenarios':
        return json(route, {
          scenarios: fixtures.scenarios.map((s) => ({ ...s, latestCase: null })),
          run: null,
        });
      case '/site-profile':
        return json(route, fixtures.siteProfile);
      case '/cases':
        return json(route, { items: [], total: 0 });
      default:
        return json(route, { error: 'not_found', detail: 'Not on the stub' }, 404);
    }
  });
}

test.beforeEach(({ page }) => skipWelcome(page));

for (const width of [1280, 360])
  test.describe(`at ${width} px`, () => {
    test.use({ viewport: { width, height: 900 } });

    test("shows the public demo's viewer its three cards, greyed-out controls and four modes", async ({
      page,
    }) => {
      await standIn(page, DEMO);
      await page.goto('./#/scenarios');
      // The live build's first visit offers the trial in a dialog over the page
      await page.getByRole('button', { name: 'Not now' }).click();
      const first = page.getByRole('region', { name: 'Three to look at first' });
      await expect(first.getByText('No case yet: the hospital plays one every few minutes.')).toHaveCount(3);
      for (const run of await first.getByRole('button', { name: /^Run / }).all())
        await expect(run).toBeDisabled();
      await expect(page.getByRole('button', { name: 'Reset' })).toBeDisabled();
      const modes = page.getByRole('radiogroup', { name: 'Investigation modes' });
      await expect(modes.getByText('Single investigator')).toBeVisible();
      await expect(modes.getByText(/Not in the trial/)).toHaveCount(0);
      await expect(page.getByRole('heading', { name: /^Try/ })).toHaveCount(0);
      expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
      await expect(page.getByText(/needs the operator or approver role/)).toHaveCount(0);
      if (process.env.E2E_SHOTS)
        await page.screenshot({
          path: `${process.env.E2E_SHOTS}/b-live-demo-${width}.png`,
          fullPage: true,
        });
    });

    test('gives a judge Run, and Reset greyed out with a reason that asks for no role it shows', async ({
      page,
    }) => {
      await standIn(page, JUDGE);
      await page.goto('./#/scenarios');
      await page.getByRole('button', { name: 'Not now' }).click();
      const list = page.getByRole('region', { name: 'Every scenario' });
      await expect(list.getByRole('button', { name: 'Run S8' })).toBeEnabled();
      await expect(page.getByRole('button', { name: 'Reset' })).toBeDisabled();
      await expect(page.getByText(RESET_WHY)).toBeVisible();
      await expect(page.getByText(/plays its stories by itself/)).toHaveCount(0);
      await expect(page.getByText(/needs the operator or approver role/)).toHaveCount(0);
      expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
      // WCAG 2.1 A and AA, as every screen is audited
      expect(await audit(page)).toEqual([]);
      // The tooltip of the greyed-out Reset says the same, not a role the menu shows, and wraps within the screen
      await page.getByRole('button', { name: 'Reset' }).locator('..').hover();
      await expect(page.getByRole('tooltip')).toHaveText(RESET_WHY);
      expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
      if (process.env.E2E_SHOTS)
        await page.screenshot({
          path: `${process.env.E2E_SHOTS}/b-live-judge-${width}.png`,
          fullPage: true,
        });
    });
  });
