import { expect, test, type Route } from '@playwright/test';
import fixtures from '../src/mocks/fixtures.json' with { type: 'json' };
import { skipWelcome } from './guide';

/**
 * The Scenarios page of the online demo on the build IRIS serves, against a stand-in server signed in as a judge, before
 * its hospital has played a story: the three cards keep their text and say they have no case yet, Run and Reset are greyed
 * out, and all four modes are described with no word about the trial. Nothing here reaches IRIS.
 */

const ME = {
  username: 'judge',
  roles: ['%All'],
  operator: true,
  approver: true,
  can: { operate: true, approve: true, configure: false, scenarios: false, liveAgents: true },
};

test.beforeEach(({ page }) => skipWelcome(page));

for (const width of [1280, 360])
  test.describe(`at ${width} px`, () => {
    test.use({ viewport: { width, height: 900 } });

    test('shows the fresh demo its three cards, greyed-out controls and four modes', async ({ page }) => {
      const json = (route: Route, body: unknown, status = 200) => route.fulfill({ status, json: body });
      await page.route('**/api/shutter/**', (route) => {
        const path = new URL(route.request().url()).pathname.replace(/^.*\/api\/shutter/, '');
        switch (path) {
          case '/me':
            return json(route, ME);
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
      await page.goto('./#/scenarios');
      // The live build's first visit offers the trial in a dialog over the page
      await page.getByRole('button', { name: 'Not now' }).click();
      const first = page.getByRole('region', { name: 'Three to look at first' });
      await expect(first.getByText('No case yet: the hospital plays one every few minutes.')).toHaveCount(3);
      for (const run of await first.getByRole('button', { name: /^Run / }).all())
        await expect(run).toBeDisabled();
      await expect(page.getByRole('button', { name: 'Reset' })).toBeDisabled();
      const modes = page.getByRole('region', { name: 'Investigation modes' });
      await expect(modes.getByText('Single investigator')).toBeVisible();
      await expect(modes.getByText(/Not in the trial/)).toHaveCount(0);
      await expect(page.getByRole('heading', { name: /^Try/ })).toHaveCount(0);
      expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
      if (process.env.E2E_SHOTS)
        await page.screenshot({
          path: `${process.env.E2E_SHOTS}/b-live-judge-${width}.png`,
          fullPage: true,
        });
    });
  });
