import { expect, test, type Route } from '@playwright/test';
import fixtures from '../src/mocks/fixtures.json' with { type: 'json' };
import { withLiveClock } from '../src/test/runs';

/**
 * The recording stays out of a live case page. The `iris-trial` project picks this file up by its name's ending, since
 * only the build IRIS serves has a live page; a stand-in answers `/api/shutter` in the browser, with S2's case and its
 * board. Named scripts alone would not catch an eager import, which puts the panel inside the case page's own chunk, so
 * the scripts the page loaded are read as well.
 */

const CASE = 'C-000002';
const recorded = fixtures.cases[CASE];

const ME = {
  username: 'approver',
  operator: true,
  approver: true,
  can: { operate: true, approve: true, configure: true, scenarios: true, liveAgents: true },
};

/** The panel's and the toggle's own words, and the names of their chunks. */
const RECORDING_WORDS = [
  'Reading the recording',
  'What this agent was sent and did',
  'could not be read here',
  'public recordings',
  'tree/main/fixtures/records',
  'RunRecording-',
];

test.use({ viewport: { width: 1280, height: 900 } });

// A live page's first visit offers the trial ("New here?"), which would cover the case: it was seen before
test.beforeEach(({ page }) =>
  page.addInitScript(() => localStorage.setItem('shutter:live-welcome:v1', '2026-11-02T09:00:00Z')),
);

test('a live case page has no recording control, no recording script and none of the panel in its scripts', async ({
  page,
}) => {
  const json = (route: Route, body: unknown, status = 200) => route.fulfill({ status, json: body });
  await page.route('**/api/shutter/**', async (route) => {
    const path = new URL(route.request().url()).pathname.replace(/^.*\/api\/shutter/, '');
    const c = `/cases/${CASE}`;
    switch (path) {
      case '/me':
        return json(route, ME);
      case '/health':
        return json(route, { ok: true, demo: false, version: 'stub', checks: [] });
      case '/settings':
        return json(route, fixtures.settings);
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
        return json(route, withLiveClock(recorded.runs as never));
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
  const scripts: string[] = [];
  page.on('response', (r) => {
    if (r.request().resourceType() === 'script') scripts.push(new URL(r.url()).pathname);
  });

  await page.goto(`./#/cases/${CASE}`);
  await expect(page.getByRole('heading', { name: `Case ${CASE}`, exact: true })).toBeVisible();
  await expect(page.getByRole('region', { name: 'Trial environment' })).toHaveCount(0);
  const board = page.getByRole('region', { name: 'The board' });
  await expect(board.getByRole('region', { name: 'Coordinator' })).toBeVisible();
  await expect(board.getByRole('button', { name: 'Show the finding' })).toHaveCount(3);
  await page.waitForLoadState('networkidle');

  await expect(page.getByRole('button', { name: 'Show the recording' })).toHaveCount(0);
  expect(scripts.filter((s) => /RecordingToggle-|RunRecording-|scenario-S/.test(s))).toEqual([]);
  expect(await page.locator('link[rel="modulepreload"][href*="scenario-S"]').count()).toBe(0);

  const carrying = await page.evaluate(
    async ({ paths, words }) => {
      const texts = await Promise.all(paths.map((p) => fetch(p).then((r) => r.text())));
      return texts.flatMap((text, i) =>
        words.filter((w) => text.includes(w)).map((word) => `${paths[i]}: ${word}`),
      );
    },
    { paths: scripts, words: RECORDING_WORDS },
  );
  expect(carrying).toEqual([]);
});
