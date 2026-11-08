import { expect, test, type Route } from '@playwright/test';
import fixtures from '../src/mocks/fixtures.json' with { type: 'json' };

/**
 * The live first-run prompt on the online demo's role, on the build IRIS serves against a stand-in for a server: the page
 * stays in reach behind it, and the case Home offers to approve is not under it.
 */
const ME = {
  username: 'demo',
  roles: ['Shutter_Demo'],
  operator: true,
  approver: true,
  can: { operate: true, approve: true, configure: false, scenarios: false, liveAgents: false },
};
const HELD = { ...fixtures.cases['C-000002'].summary, caseId: 'C-000015', state: 'awaiting_approval' };

for (const [name, viewport] of [
  ['laptop', { width: 1280, height: 800 }],
  ['phone', { width: 390, height: 844 }],
] as const) {
  test(`New here? leaves Home's approve link in reach, at ${name} width`, async ({ page }) => {
    await page.setViewportSize(viewport);
    const json = (route: Route, body: unknown, status = 200) => route.fulfill({ status, json: body });
    await page.route('**/api/shutter/**', async (route) => {
      const path = new URL(route.request().url()).pathname.replace(/^.*\/api\/shutter/, '');
      if (path === '/me') return json(route, ME);
      if (path === '/health') return json(route, { ok: true, demo: true, version: 'stub', checks: [] });
      if (path === '/settings') return json(route, { ...fixtures.settings, live: { enabled: false } });
      if (path === '/scenarios') return json(route, { scenarios: fixtures.scenarios, run: null });
      if (path === '/site-profile') return json(route, fixtures.siteProfile);
      if (path === '/cases') return json(route, { items: [HELD], total: 1 });
      return json(route, { error: 'not_found', detail: 'Not on the stub' }, 404);
    });
    await page.goto('./#/home');
    const prompt = page.getByRole('dialog', { name: 'New here?' });
    await expect(prompt).toBeVisible();
    const link = page.getByRole('link', { name: 'Approve a fix yourself: C-000015' });
    await link.scrollIntoViewIfNeeded();
    await expect(link).toBeInViewport();
    const a = (await link.boundingBox())!;
    const b = (await prompt.boundingBox())!;
    expect(
      a.y + a.height <= b.y || b.y + b.height <= a.y || a.x + a.width <= b.x || b.x + b.width <= a.x,
    ).toBe(true);
    // The way out still works, and stays gone
    await prompt.getByRole('button', { name: 'Not now' }).click();
    await expect(prompt).toBeHidden();
  });
}
