import { expect, test, type Page, type Route } from '@playwright/test';
import fixtures from '../src/mocks/fixtures.json' with { type: 'json' };
import { audit } from './axe';

/**
 * Settings, Your tasks, on the build IRIS serves, against a stand-in for a live server: the `iris-trial` project picks
 * this file up by its name's ending, since only that build has a live page (the demo build is always the trial). Each
 * test gives the server a state the external review names (no model key, shadow mode, a role that is not enough, the
 * budget used up, the stop) and reads what the section says to do. Nothing here reaches IRIS: the build's instance
 * address is one nothing listens on.
 */

const OPERATOR = {
  username: 'operator',
  operator: true,
  approver: false,
  can: {
    operate: true,
    approve: false,
    configure: false,
    scenarios: true,
    reset: true,
    stopRecovery: true,
    liveAgents: true,
  },
};
const APPROVER = {
  ...OPERATOR,
  username: 'approver',
  approver: true,
  can: { ...OPERATOR.can, approve: true, configure: true },
};

const control = (over: Record<string, unknown>) => ({
  mode: 'enabled',
  generation: 3,
  stopped: false,
  stoppedAt: '',
  stoppedBy: '',
  stopReason: '',
  outstanding: [],
  outstandingCount: 0,
  readable: true,
  covers: 'Rehearsals, recovery writes, blind-resend previews and outage resends that Shutter itself starts.',
  doesNotCover: "The hospital's ordinary feed and its retries.",
  ...over,
});

/**
 * The stand-in: the signed-in user, the settings, the recovery control and the site profile a test gives, and the health
 * report's last live run when it gives one.
 */
async function stubServer(
  page: Page,
  state: {
    me: unknown;
    settings: Record<string, unknown>;
    recovery: Record<string, unknown>;
    profile: Record<string, unknown>;
    lastLiveRun?: Record<string, unknown> | null;
  },
) {
  const json = (route: Route, body: unknown, status = 200) => route.fulfill({ status, json: body });
  await page.route('**/api/shutter/**', async (route) => {
    const request = route.request();
    const path = new URL(request.url()).pathname.replace(/^.*\/api\/shutter/, '');
    if (request.method() !== 'GET')
      return json(route, { error: 'not_found', detail: 'Not on the stub' }, 404);
    switch (path) {
      case '/me':
        return json(route, state.me);
      case '/health':
        return json(route, {
          ok: true,
          demo: true,
          version: 'stub',
          checks: [],
          ...(state.lastLiveRun === undefined ? {} : { last_live_run: state.lastLiveRun }),
        });
      case '/settings':
        return json(route, { ...fixtures.settings, ...state.settings });
      case '/costs':
        return json(route, fixtures.costs);
      case '/recovery-control':
        return json(route, control(state.recovery));
      case '/site-profile':
        return json(route, {
          ...fixtures.siteProfile,
          profile: { ...fixtures.siteProfile.profile, ...state.profile },
        });
      case '/access':
        return json(route, fixtures.access);
      default:
        return json(route, { error: 'not_found', detail: 'Not on the stub' }, 404);
    }
  });
}

/** Opens Settings and the section's one line, and gives the section. */
async function openTasks(page: Page) {
  await page.goto('./#/settings');
  await expect(page.getByRole('heading', { name: 'Settings and costs', exact: true })).toBeVisible();
  const section = page.getByRole('region', { name: 'Your tasks', exact: true });
  await section.getByRole('button', { name: 'Each task, and whether it is ready' }).click();
  await expect(section.getByRole('list', { name: 'Your tasks' }).getByRole('listitem')).toHaveCount(6);
  return section;
}

/** Saves a picture for the record when E2E_SHOTS names a folder. */
async function shot(target: { screenshot: Page['screenshot'] }, name: string) {
  if (!process.env.E2E_SHOTS) return;
  await target.screenshot({ path: `${process.env.E2E_SHOTS}/${name}.png` });
}

// A live page's first visit offers the trial ("New here?"), which would cover the page: it was seen before
test.beforeEach(({ page }) =>
  page.addInitScript(() => localStorage.setItem('shutter:live-welcome:v1', '2026-11-02T09:00:00Z')),
);

test.describe('Your tasks on a live server @settings', () => {
  test('an operator, with no model key, in shadow mode, under the two-person rule: each says the next step', async ({
    page,
  }) => {
    await stubServer(page, {
      me: OPERATOR,
      settings: { providerConfigured: false, mock: false },
      recovery: { mode: 'shadow' },
      profile: { recovery: { mode: 'shadow' }, approvers: { close_needs_approver: true } },
    });
    const section = await openTasks(page);
    await expect(section.getByTestId('tasks-summary')).toHaveText(
      '3 of 6 ready for you. Not now: your own questions, approving, closing.',
    );
    const ask = section.getByTestId('task-ask');
    await expect(ask).toHaveAttribute('data-state', 'blocked');
    await expect(ask.getByTestId('task-condition')).toHaveText(
      'No model key is configured here, so the agents only replay recordings.',
    );
    await expect(ask.getByTestId('task-next')).toContainText('ANTHROPIC_API_KEY (or OPENAI_API_KEY) in .env');
    // Set up, now and seen stay apart; the time it was read is a time element, in the feed's zone
    await expect(ask.locator('[data-kind="set up"]')).toHaveText('Set up: No model key is configured.');
    await expect(ask.locator('[data-kind="seen"]')).toContainText('Seen: ');
    // The role first, then shadow mode, which an approver would meet next
    const approve = section.getByTestId('task-approve');
    await expect(approve.getByTestId('task-condition')).toHaveAttribute('data-code', 'role');
    await expect(approve.locator('[data-code="shadow"]')).toContainText('Also: Shutter is in shadow mode');
    await expect(approve.locator('[data-kind="now"] time')).toHaveAttribute('datetime', /Z$/);
    const escalate = section.getByTestId('task-escalate');
    await expect(escalate).toHaveAttribute('data-state', 'limited');
    await expect(escalate.getByTestId('task-condition')).toContainText('reads Not sent');
    await expect(section.getByTestId('task-close').getByTestId('task-next')).toHaveText(
      'Next: Ask an approver to close it. You can still escalate it.',
    );
    await expect(section.getByTestId('task-scenario')).toHaveAttribute('data-state', 'limited');
    expect(await audit(page)).toEqual([]);
    await shot(section, 'tasks-live-operator-shadow');
  });

  test('an approver, with the budget used up and recovery stopped, at a phone width', async ({ page }) => {
    await page.setViewportSize({ width: 360, height: 780 });
    await stubServer(page, {
      me: APPROVER,
      settings: {
        demo: false,
        providerConfigured: true,
        budget: {
          ...fixtures.settings.budget,
          dailyUsd: 5,
          spentTodayUsd: 5.2,
          exhausted: true,
        },
      },
      recovery: { stopped: true, stoppedBy: 'operator', stopReason: 'receiver upgrade' },
      profile: { recovery: { mode: 'enabled' } },
      lastLiveRun: {
        at: '2026-11-15T09:12:00Z',
        status: 'budget_exceeded',
        member: 'coordinator',
        model: 'stub-model',
        mode: 'live',
      },
    });
    const section = await openTasks(page);
    await expect(section.getByTestId('tasks-summary')).toHaveText(
      '3 of 6 ready for you. Not now: scenarios, your own questions, approving.',
    );
    await expect(section.getByTestId('task-scenario').getByTestId('task-condition')).toHaveAttribute(
      'data-code',
      'not_demo',
    );
    const ask = section.getByTestId('task-ask');
    await expect(ask.getByTestId('task-condition')).toHaveText(
      'The live AI budget for this site is used up until 00:00 UTC.',
    );
    await expect(ask.getByTestId('task-next')).toContainText('SHUTTER_DAILY_BUDGET_USD');
    await expect(ask.locator('[data-kind="now"]')).toContainText('Now: The model cannot be asked. Read ');
    // The last observed live call, apart from what holds now, with when it started
    const seen = ask.locator('[data-kind="seen"]');
    await expect(seen).toContainText(
      'Seen: The newest run that reached a real model ended without a usable answer (budget_exceeded). Started ',
    );
    await expect(seen.locator('time')).toHaveAttribute('datetime', '2026-11-15T09:12:00Z');
    const approve = section.getByTestId('task-approve');
    await expect(approve.getByTestId('task-condition')).toHaveText(
      'Recovery is stopped by operator: receiver upgrade. No new recovery call is admitted.',
    );
    await expect(approve.getByTestId('task-next')).toContainText(
      'Clear the stop under Stop Shutter recovery below',
    );
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
    expect(await audit(page)).toEqual([]);
    await shot(section, 'tasks-live-approver-budget-stop-phone');
  });
});
