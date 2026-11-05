import { expect, test, type Page, type Route } from '@playwright/test';
import fixtures from '../src/mocks/fixtures.json' with { type: 'json' };
import { audit } from './axe';
import { area } from './areas/shell';

/**
 * The way from the app to the demo's page inside IRIS, on the build IRIS serves against a stand-in for a server: the
 * `iris-trial` project picks this file up by its name's ending, since only that build has a live page. A demo instance
 * shows it in the navigation and on Home, at a phone's width in the navigation's phone form too; a site install, where
 * the page answers 404, shows neither, and nor does the trial of the same build, which has no IRIS behind it.
 */

const HREF = '/csp/healthshare/shutter/Shutter.Portal.Guide.cls';
const ME = {
  username: 'judge',
  roles: ['%All'],
  operator: true,
  approver: true,
  can: { operate: true, approve: true, configure: false, scenarios: false, liveAgents: true },
};

async function stubServer(page: Page, demo: boolean) {
  const json = (route: Route, body: unknown, status = 200) => route.fulfill({ status, json: body });
  await page.route('**/api/shutter/**', async (route) => {
    const path = new URL(route.request().url()).pathname.replace(/^.*\/api\/shutter/, '');
    switch (path) {
      case '/me':
        return json(route, ME);
      case '/health':
        return json(route, { ok: true, demo, version: 'stub', checks: [] });
      case '/settings':
        return json(route, { ...fixtures.settings, live: { enabled: false } });
      case '/scenarios':
        return json(route, { scenarios: fixtures.scenarios, run: null });
      case '/site-profile':
        return json(route, fixtures.siteProfile);
      case '/cases':
        return json(route, { items: [], total: 0 });
      default:
        return json(route, { error: 'not_found', detail: 'Not on the stub' }, 404);
    }
  });
}

const navLink = (page: Page) =>
  page.getByRole('navigation', { name: 'Main' }).getByRole('link', { name: /^Shutter in IRIS/ });
const homeCard = (page: Page) => page.getByTestId('home-portal-card');

/** Saves a picture for the record when E2E_SHOTS names a folder. */
async function shot(page: Page, name: string) {
  if (process.env.E2E_SHOTS) await page.screenshot({ path: `${process.env.E2E_SHOTS}/${name}.png` });
}

test.use({ viewport: { width: 1280, height: 800 } });

// A live page's first visit offers the trial ("New here?"), which would cover the page: it was seen before
test.beforeEach(({ page }) =>
  page.addInitScript(() => localStorage.setItem('shutter:live-welcome:v1', '2026-11-02T09:00:00Z')),
);

test.describe(`the way to the page inside IRIS ${area.tag}`, () => {
  test('a demo instance shows it in the navigation and on Home, opening in a new tab', async ({ page }) => {
    await stubServer(page, true);
    await page.goto('./#/home');
    await expect(page.getByRole('heading', { name: 'Home', level: 1 })).toBeVisible();
    await expect(navLink(page)).toHaveAttribute('href', HREF);
    await expect(navLink(page)).toHaveAttribute('target', '_blank');
    await expect(homeCard(page)).toHaveAttribute('href', HREF);
    await expect(homeCard(page)).toHaveAccessibleName(/opens in a new tab/);
    await expect(homeCard(page)).toContainText('Visual Trace');
    await expect(homeCard(page)).toContainText('Cloudflare sign-in first');
    // Said once: the page's words carry the sign-in only on the card
    await expect(page.getByText(/Cloudflare/)).toHaveCount(1);
    expect(await audit(page)).toEqual([]);
    await shot(page, 'a-portal-home-light');
    await page.getByRole('button', { name: 'Appearance' }).click();
    await page.getByRole('menuitem', { name: /^Dark/ }).click();
    await page.keyboard.press('Escape');
    await expect(page.locator('html')).toHaveAttribute('data-mantine-color-scheme', 'dark');
    await shot(page, 'a-portal-home-dark');
    expect(await audit(page)).toEqual([]);
  });

  test('it stays in the navigation on the other pages, and a click opens a new tab', async ({
    page,
    context,
  }) => {
    await stubServer(page, true);
    await context.route(`**${HREF}`, (route) =>
      route.fulfill({ status: 200, contentType: 'text/html', body: '<title>Portal</title>' }),
    );
    await page.goto('./#/cases');
    await expect(page.getByRole('heading', { name: 'Cases', exact: true })).toBeVisible();
    const opened = context.waitForEvent('page');
    await navLink(page).click();
    const portal = await opened;
    await portal.waitForLoadState();
    expect(new URL(portal.url()).pathname).toBe(HREF);
    await portal.close();
    await expect(page).toHaveURL(/#\/cases$/);
  });

  test("at a phone's width it is in the navigation's phone form, and no wider than the screen", async ({
    page,
  }) => {
    await page.setViewportSize({ width: 360, height: 760 });
    await stubServer(page, true);
    await page.goto('./#/home');
    await expect(homeCard(page)).toBeVisible();
    await expect(navLink(page)).not.toBeInViewport();
    await page.getByRole('button', { name: 'Menu' }).click();
    await expect(navLink(page)).toBeInViewport();
    const box = (await navLink(page).boundingBox())!;
    expect(box.height).toBeGreaterThanOrEqual(36);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(360);
    await shot(page, 'a-portal-phone-nav-light');
  });

  test('a site install shows neither', async ({ page }) => {
    let asked = false;
    await stubServer(page, false);
    page.on('response', (r) => {
      if (r.url().endsWith('/api/shutter/health')) asked = true;
    });
    await page.goto('./#/home');
    await expect(page.getByRole('heading', { name: 'Home', level: 1 })).toBeVisible();
    await expect.poll(() => asked).toBe(true);
    await expect(navLink(page)).toHaveCount(0);
    await expect(homeCard(page)).toHaveCount(0);
  });

  test('the trial of the same build shows neither, with no IRIS behind it', async ({ page }) => {
    await stubServer(page, true);
    await page.goto('./?trial#/home');
    await expect(page.getByRole('region', { name: 'Trial environment' })).toBeVisible();
    await page
      .getByRole('dialog', { name: 'Welcome to the Shutter trial' })
      .getByRole('button', { name: 'Explore on my own' })
      .click();
    await expect(page.getByRole('heading', { name: 'Home', level: 1 })).toBeVisible();
    await expect(page.getByRole('link', { name: 'Open the scenarios' })).toBeVisible();
    await expect(navLink(page)).toHaveCount(0);
    await expect(homeCard(page)).toHaveCount(0);
  });
});
