import { expect, test, type Page, type Route } from '@playwright/test';
import fixtures from '../src/mocks/fixtures.json' with { type: 'json' };
import {
  DRAWN_DRAFT,
  DRAWN_SEQUENCE,
  REPLAY_B_TEXT,
  STOPPED_DRAFT,
} from '../src/features/cases/case/correctionDraft.fixture';
import { area } from './areas/case';
import { audit } from './axe';

/**
 * The drafted correction on the case page, live, against a stand-in: only the build IRIS serves has a live page, so the
 * `iris-trial` project picks this file up by its name's ending. The stub answers `/api/shutter` in the browser with the
 * recorded S22 case at Records Out, its plan carrying a drawn sequence, and the draft route with its text, then with a
 * further message for the patient. Nothing here reaches IRIS.
 */

const CASE = 'C-000055';
const recorded = fixtures.cases[CASE];
const ME = {
  username: 'approver',
  operator: true,
  approver: true,
  can: { operate: true, approve: true, configure: true, scenarios: true, liveAgents: true },
};

function planWithSequence() {
  const view = structuredClone(recorded.plan) as unknown as {
    plan: { plan: { correction_steps: Record<string, unknown> } };
  };
  view.plan.plan.correction_steps.sequence = DRAWN_SEQUENCE;
  return view;
}

async function stubServer(page: Page) {
  const seen = { reads: 0 };
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
        return json(route, recorded.runs);
      case `${c}/plan`:
        return json(route, planWithSequence());
      case `${c}/approvals`:
        return json(route, recorded.approvals ?? { tasks: [], decisions: [] });
      case `${c}/attempts`:
      case `${c}/escalations`:
        return json(route, []);
      case `${c}/correction-draft`:
        seen.reads += 1;
        return json(route, seen.reads === 1 ? DRAWN_DRAFT : STOPPED_DRAFT);
      default:
        return json(route, { error: 'not_found', detail: 'Not on the stub' }, 404);
    }
  });
  return seen;
}

async function openBlock(page: Page) {
  await page.goto(`./#/cases/${CASE}`);
  await expect(page.getByRole('heading', { name: `Case ${CASE}`, exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Why, and what to do' }).click();
  const block = page.getByTestId('correction-draft');
  await expect(block.getByRole('heading', { name: 'Drafted message sequence' })).toBeVisible();
  return block;
}

const noSidewaysScroll = (page: Page) =>
  page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth);

// A live page's first visit offers the trial ("New here?"), which would cover the case: it was seen before
test.beforeEach(({ page }) =>
  page.addInitScript(() => localStorage.setItem('shutter:live-welcome:v1', '2026-11-02T09:00:00Z')),
);

test.describe(`the drafted correction ${area.tag}`, () => {
  for (const [name, viewport] of [
    ['a phone', { width: 390, height: 844 }],
    ['a laptop', { width: 1280, height: 800 }],
  ] as const)
    for (const colorScheme of ['light', 'dark'] as const)
      test(`reads on ${name} in ${colorScheme}, axe clean, with no sideways scroll`, async ({ page }) => {
        await page.setViewportSize(viewport);
        await page.emulateMedia({ colorScheme });
        const seen = await stubServer(page);
        const block = await openBlock(page);
        expect(seen.reads).toBe(0);
        await expect(block.getByTestId('correction-draft-structure').getByRole('listitem')).toHaveCount(3);
        expect(await noSidewaysScroll(page)).toBe(true);
        expect(await audit(page)).toEqual([]);

        await block.getByRole('button', { name: 'Read the messages' }).click();
        await expect(block.getByTestId('correction-message-3')).toBeVisible();
        await expect(block.getByRole('button', { name: /^Send/ })).toHaveCount(0);
        expect(seen.reads).toBe(1);
        expect(await noSidewaysScroll(page)).toBe(true);
        // Nothing inside the block is cut off or scrolls either, the messages' long lines included
        expect(
          await block.evaluate((el) => {
            const box = el.getBoundingClientRect();
            return [...el.querySelectorAll('pre')].every(
              (pre) => pre.scrollWidth <= pre.clientWidth && pre.getBoundingClientRect().right <= box.right,
            );
          }),
        ).toBe(true);
        expect(await audit(page)).toEqual([]);
        if (process.env.E2E_SHOTS)
          await block.screenshot({ path: `${process.env.E2E_SHOTS}/draft-${name}-${colorScheme}.png` });

        await block.getByRole('button', { name: 'Read it again' }).click();
        await expect(block.getByTestId('correction-draft-stopped')).toContainText('ENC-2044');
        await expect(block.locator('pre')).toHaveCount(0);
        expect(await audit(page)).toEqual([]);
      });

  test('copies a message exactly as stored, its carriage returns included', async ({ page, context }) => {
    await context.grantPermissions(['clipboard-read', 'clipboard-write']);
    await stubServer(page);
    const block = await openBlock(page);
    await block.getByRole('button', { name: 'Read the messages' }).click();
    await block.getByRole('button', { name: 'Copy message 2' }).click();
    await expect(block.getByRole('button', { name: 'Copied message 2' })).toBeVisible();
    expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(REPLAY_B_TEXT);
  });
});
