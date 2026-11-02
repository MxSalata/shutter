import { expect, test, type Page, type Route } from '@playwright/test';
import fixtures from '../src/mocks/fixtures.json' with { type: 'json' };
import { audit } from './axe';
import { area } from './areas/shell';

/**
 * The public demo's live budget on the build IRIS serves, against a stand-in for a v1.37 server: the `iris-trial`
 * project picks this file up by its name's ending, as it does the live case page's, since only that build has a live
 * page (the demo build is always the trial). The banner says what the author pays for the live agents and, while they
 * cannot run (the budget used up, the provider refusing the key), the notice under it says so, until when, and where to
 * install Shutter with one's own key; the board's dialog says the same, and so does a refusal of the press. Nothing
 * here reaches IRIS: the build's instance address is one nothing listens on.
 */

const CASE = 'C-000008';
const recorded = fixtures.cases[CASE];
const ME = {
  username: 'judge',
  roles: ['%All'],
  operator: true,
  approver: true,
  can: { operate: true, approve: true, configure: false, scenarios: false, liveAgents: true },
};
const INSTALL_URL = 'https://github.com/MxSalata/shutter#try-it';

/** An ISO time some minutes from now, as the server sends times. */
const inMinutes = (n: number) => new Date(Date.now() + n * 60_000).toISOString().replace(/\.\d+Z$/, 'Z');

/** The settings of the public demo: its live hospital on, the budget and live.agents a test gives. */
function settings(live: Record<string, unknown>, budget: Record<string, unknown>) {
  return {
    ...fixtures.settings,
    live: {
      enabled: true,
      every_minutes: 7,
      last_played: { scenario: 'S2', title: 'a lost transfer', at: inMinutes(-4) },
      next: { scenario: 'S8', at: inMinutes(3) },
      ...live,
    },
    budget: { ...fixtures.settings.budget, ...budget },
  };
}

/** The stand-in for a v1.37 server, signed in as a judge; the board's press answers as `board` says. */
async function stubServer(page: Page, s: unknown, board?: { status: number; body: unknown }) {
  const json = (route: Route, body: unknown, status = 200) => route.fulfill({ status, json: body });
  await page.route('**/api/shutter/**', async (route) => {
    const request = route.request();
    const path = new URL(request.url()).pathname.replace(/^.*\/api\/shutter/, '');
    const c = `/cases/${CASE}`;
    if (request.method() === 'POST' && path === `${c}/board` && board)
      return json(route, board.body, board.status);
    if (request.method() === 'POST')
      return json(route, { error: 'not_found', detail: 'Not on the stub' }, 404);
    switch (path) {
      case '/me':
        return json(route, ME);
      case '/health':
        return json(route, { ok: true, demo: true, version: 'stub', checks: [] });
      case '/settings':
        return json(route, s);
      case '/scenarios':
        return json(route, { scenarios: fixtures.scenarios, run: null });
      case '/site-profile':
        return json(route, fixtures.siteProfile);
      case '/cases':
        return json(route, { items: [recorded.summary], total: 1 });
      case c:
        return json(route, recorded.detail);
      case `${c}/events`:
        return json(route, recorded.events);
      case `${c}/snapshot`:
        return json(route, recorded.snapshot);
      case `${c}/runs`:
        return json(route, recorded.runs);
      case `${c}/plan`:
        return json(route, recorded.plan);
      case `${c}/approvals`:
        return json(route, recorded.approvals);
      case `${c}/attempts`:
      case `${c}/escalations`:
        return json(route, []);
      default:
        return json(route, { error: 'not_found', detail: 'Not on the stub' }, 404);
    }
  });
}

const banner = (page: Page) => page.getByRole('region', { name: 'Live hospital' });

/** A part's words as they read, its lines (paragraphs of their own) joined by a space. */
const said = (page: Page, testId: string) =>
  page
    .getByTestId(testId)
    .first()
    .evaluate((el) =>
      [...el.querySelectorAll('p')]
        .map((p) => p.textContent?.trim())
        .filter(Boolean)
        .join(' '),
    );

/** Saves a picture for the record when E2E_SHOTS names a folder. */
async function shot(page: Page, name: string, target?: { screenshot: Page['screenshot'] }) {
  if (!process.env.E2E_SHOTS) return;
  await (target ?? page).screenshot({ path: `${process.env.E2E_SHOTS}/${name}.png` });
}

test.use({ viewport: { width: 1280, height: 800 } });

// A live page's first visit offers the trial ("New here?"), which would cover the page: it was seen before
test.beforeEach(({ page }) =>
  page.addInitScript(() => localStorage.setItem('shutter:live-welcome:v1', '2026-11-02T09:00:00Z')),
);

test.describe(`the live budget on the public demo, against a v1.37 server ${area.tag}`, () => {
  test('says what the author pays under the feed, and at the cap the notice, with the install link', async ({
    page,
  }) => {
    await stubServer(
      page,
      settings(
        { agents: { available: false, reason: 'budget', until: inMinutes(35), detail: 'The cap is spent' } },
        { dailyUsd: 2, spentTodayUsd: 2.04, exhausted: true, resetsAt: inMinutes(35) },
      ),
    );
    await page.goto('./#/cases');
    await expect(page.getByRole('heading', { name: 'Cases', exact: true })).toBeVisible();
    await expect(banner(page).getByTestId('live-budget-line')).toHaveText(
      '$2 an hour, paid by the author, runs the live agents (so far: $2.04).',
    );
    const note = banner(page).getByRole('note');
    await expect(note).toBeVisible();
    expect(await said(page, 'live-unavailable')).toMatch(
      /^The live AI budget for this demo is used up until \d\d:\d\d (GMT|BST), when the demo resets\. Open cases, recorded runs and the trial still work\. To run the live agents yourself, install Shutter with your own API key: how to install$/,
    );
    const link = note.getByRole('link', { name: 'how to install' });
    await expect(link).toHaveAttribute('href', INSTALL_URL);
    await expect(link).toHaveAttribute('target', '_blank');
    await expect(banner(page)).not.toContainText(/budget_exhausted|The cap is spent/);
    expect(await audit(page)).toEqual([]);
    await shot(page, 'banner-budget-notice-light');
    await shot(page, 'banner-budget-notice-crop-light', banner(page));
  });

  test('says the provider is refusing the key until its own time, and the figure the demo build sets', async ({
    page,
  }) => {
    await stubServer(
      page,
      settings(
        {
          budgetNote: { amountUsd: 15, period: 'day' },
          agents: { available: false, reason: 'provider_auth', until: inMinutes(200), detail: 'refused' },
        },
        { dailyUsd: 2, spentTodayUsd: 0.4 },
      ),
    );
    await page.goto('./#/cases');
    await expect(banner(page).getByTestId('live-budget-line')).toHaveText(
      '$15 a day, paid by the author, runs the live agents.',
    );
    expect(await said(page, 'live-unavailable')).toMatch(
      /^The live AI service for this demo is unavailable until \d\d:\d\d (GMT|BST)\. Open cases/,
    );
    expect(await audit(page)).toEqual([]);
    await shot(page, 'banner-provider-notice-crop-light', banner(page));
  });

  test("says the line and the notice within a phone's width, the line on one line", async ({ page }) => {
    await page.setViewportSize({ width: 360, height: 780 });
    await stubServer(
      page,
      settings(
        {
          budgetNote: { amountUsd: 15, period: 'day' },
          agents: { available: false, reason: 'provider_auth', until: null },
        },
        { dailyUsd: 2, spentTodayUsd: 0.4 },
      ),
    );
    await page.goto('./#/cases');
    const line = banner(page).getByTestId('live-budget-line');
    await expect(line).toBeVisible();
    const lines = await line.evaluate((el) => {
      const height = el.getBoundingClientRect().height;
      const lineHeight = parseFloat(getComputedStyle(el).lineHeight);
      return Math.round(height / lineHeight);
    });
    expect(lines).toBe(1);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
    await shot(page, 'banner-phone-light', banner(page));
  });

  test("says it in the board's dialog, where Convene cannot be pressed, and for a refused press", async ({
    page,
  }) => {
    await stubServer(
      page,
      settings(
        { agents: { available: false, reason: 'provider_auth', until: inMinutes(200), detail: 'refused' } },
        { dailyUsd: 2, spentTodayUsd: 0.4 },
      ),
    );
    await page.goto(`./#/cases/${CASE}`);
    await expect(page.getByRole('heading', { name: `Case ${CASE}`, exact: true })).toBeVisible();
    await page.getByRole('button', { name: 'Convene the board' }).click();
    const dialog = page.getByRole('dialog', { name: `Convene the board on ${CASE}` });
    await expect(dialog.getByRole('note')).toContainText(
      'The live AI service for this demo is unavailable until',
    );
    await expect(dialog.getByRole('button', { name: 'Convene', exact: true })).toBeDisabled();
    await expect(dialog.getByRole('link', { name: 'how to install' })).toHaveAttribute('href', INSTALL_URL);
    expect(await audit(page)).toEqual([]);
    await shot(page, 'convene-dialog-unavailable-light');
    await shot(page, 'convene-dialog-unavailable-crop-light', dialog);
  });

  test('reads a refused press, 409 live_unavailable, as the same notice', async ({ page }) => {
    await stubServer(
      page,
      settings(
        { agents: { available: true, reason: null, until: null, detail: '' } },
        { dailyUsd: 2, spentTodayUsd: 0.4 },
      ),
      {
        status: 409,
        body: {
          error: 'live_unavailable',
          detail: "The model provider refused Shutter's key (provider_auth)",
          live: { available: false, reason: 'provider_auth', until: inMinutes(200), detail: 'refused' },
        },
      },
    );
    await page.goto(`./#/cases/${CASE}`);
    await page.getByRole('button', { name: 'Convene the board' }).click();
    const dialog = page.getByRole('dialog', { name: `Convene the board on ${CASE}` });
    await dialog.getByRole('button', { name: 'Convene', exact: true }).click();
    await expect(dialog.getByRole('status')).toContainText(
      'The live AI service for this demo is unavailable until',
    );
    await expect(dialog).not.toContainText(/live_unavailable|provider_auth/);
    await shot(page, 'convene-dialog-refused-crop-light', dialog);
  });
});
