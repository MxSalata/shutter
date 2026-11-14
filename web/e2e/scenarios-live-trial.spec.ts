import { expect, test, type Page, type Route } from '@playwright/test';
import fixtures from '../src/mocks/fixtures.json' with { type: 'json' };
import paths from '../../fixtures/pathology.json' with { type: 'json' };
import { audit } from './axe';
import { skipWelcome } from './guide';

/**
 * The Scenarios page of the online demo on the build IRIS serves, against a stand-in server, before its hospital has
 * played a story. Signed in as the public demo's viewer of a server before 1.4.4: the three cards keep their text and say
 * they have no case yet, Run and Reset are greyed out, and all four modes are described with no word about the trial.
 * Signed in as the public demo's viewer since 1.4.4: Run is on and says its runs replay the recorded agents, the single
 * investigator can't be chosen, Reset is greyed out with its reason. Signed in as a judge (1.4.3): Run is on, Reset is
 * greyed out with its reason written under it, and no reason asks for the operator or approver role, which the user menu
 * shows the judge. Nothing here reaches IRIS.
 */

/** The public demo's viewer as a server before 1.4.4 answers: it runs no scenarios. */
const OLD_DEMO = {
  username: 'demo',
  roles: ['Shutter_Demo'],
  operator: true,
  approver: true,
  can: { operate: true, approve: true, configure: false, scenarios: false, reset: false, liveAgents: false },
};

/** The public demo's viewer since 1.4.4: it runs the scenarios with no live agents, so they replay their recordings. */
const DEMO = { ...OLD_DEMO, can: { ...OLD_DEMO.can, scenarios: true } };

const JUDGE = {
  username: 'judge',
  roles: ['Shutter_Judge'],
  operator: true,
  approver: true,
  can: { operate: true, approve: true, configure: false, scenarios: true, reset: false, liveAgents: true },
};

const RESET_WHY =
  'This sign-in runs scenarios but does not reset the shared demo, which would clear it for everyone signed in';

/** The pathology paths (1.4.6) as a demo with the results route lists them: P1 played, P2's outage offered. */
const PATHOLOGY = paths.map((p) => ({
  ...p,
  kind: 'pathology',
  latestCase:
    p.id === 'P1'
      ? { caseId: 'C-000901', state: 'escalated', disposition: 'escalate', headline: 'A person decides' }
      : null,
  latestOutage: p.id === 'P2' ? { id: 7, state: 'offered', openedAt: '2026-11-14T02:32:04Z' } : null,
}));

/** The stand-in server, signed in as `me`, with a fresh demo: no scenario has a case yet. */
async function standIn(page: Page, me: unknown, pathology?: unknown[]) {
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
          ...(pathology ? { pathology } : {}),
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

    test("shows the public demo's viewer of an older server its three cards, greyed-out controls and four modes", async ({
      page,
    }) => {
      await standIn(page, OLD_DEMO);
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

    test("gives the public demo's viewer Run from the recordings, and Reset greyed out with its reason", async ({
      page,
    }) => {
      await standIn(page, DEMO);
      await page.goto('./#/scenarios');
      await page.getByRole('button', { name: 'Not now' }).click();
      const list = page.getByRole('region', { name: 'Every scenario' });
      const run = list.getByRole('button', { name: 'Run S8' });
      await expect(run).toBeEnabled();
      await expect(
        page.getByText(
          /Scenario runs from this sign-in replay the recorded agents on this IRIS instance: no new inference/,
        ),
      ).toBeVisible();
      await expect(page.getByRole('button', { name: 'Reset' })).toBeDisabled();
      await expect(page.getByText(RESET_WHY)).toBeVisible();
      await expect(page.getByText(/plays its stories by itself/)).toHaveCount(0);
      await expect(page.getByText(/needs the operator or approver role/)).toHaveCount(0);
      const modes = page.getByRole('radiogroup', { name: 'Run mode' });
      await expect(modes.getByRole('radio', { name: /Single investigator/ })).toBeDisabled();
      await expect(modes.getByText('No recording to replay')).toBeVisible();
      await expect(modes.getByText(/Not in the trial/)).toHaveCount(0);
      expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
      // WCAG 2.1 A and AA, as every screen is audited
      expect(await audit(page)).toEqual([]);
      if (process.env.E2E_SHOTS)
        await page.screenshot({
          path: `${process.env.E2E_SHOTS}/demo-runs-${width}.png`,
          fullPage: true,
        });
      // Run's tooltip says the run replays, and wraps within the screen
      await run.locator('..').hover();
      await expect(page.getByRole('tooltip')).toHaveText('Play S8 in Board mode from its recordings');
      expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
      if (process.env.E2E_SHOTS)
        await page.screenshot({ path: `${process.env.E2E_SHOTS}/demo-run-tooltip-${width}.png` });
      await page.mouse.move(0, 0);
      await page.getByRole('button', { name: 'Reset' }).locator('..').hover();
      await expect(page.getByRole('tooltip')).toHaveText(RESET_WHY);
      if (process.env.E2E_SHOTS)
        await page.screenshot({ path: `${process.env.E2E_SHOTS}/demo-reset-tooltip-${width}.png` });
    });

    test('shows a judge the optional pathology paths after the scenarios, P2 held while its outage is open', async ({
      page,
    }) => {
      await standIn(page, JUDGE, PATHOLOGY);
      await page.goto('./#/scenarios');
      await page.getByRole('button', { name: 'Not now' }).click();
      await page.getByRole('button', { name: /^Optional, after these three: pathology on the demo/ }).click();
      const group = page.getByRole('region', { name: 'Pathology on the demo (optional)' });
      await expect(group).toBeInViewport();
      await expect(group.getByText(/No agent runs and no model is called\./)).toBeVisible();
      await expect(group.getByRole('button', { name: 'Run P1' })).toBeEnabled();
      await expect(group.getByRole('button', { name: 'Run P2' })).toBeDisabled();
      await expect(group.getByText(/^P2 runs again once this outage is closed/)).toBeVisible();
      await expect(group.getByRole('link', { name: 'Outage 7 on Incidents' })).toHaveAttribute(
        'href',
        '#/incidents#outage-7',
      );
      expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
      // WCAG 2.1 A and AA, as every screen is audited
      expect(await audit(page)).toEqual([]);
      if (process.env.E2E_SHOTS)
        await group.screenshot({ path: `${process.env.E2E_SHOTS}/live-pathology-${width}.png` });
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
