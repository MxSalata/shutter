import { expect, test, type Page, type Route } from './test';
import fixtures from '../src/mocks/fixtures.json' with { type: 'json' };

/**
 * The keyboard walk's live states, on the build IRIS serves (the `iris-trial` project picks this file up by its name's
 * ending): a decision the server refuses as stale, a case that changes under an open review, another refusal, and a
 * list read that fails and is tried again. A stand-in answers `/api/shutter` in the browser with the held S2 case, as
 * e2e/case-live-trial.spec.ts does, and can be told to refuse; nothing here reaches IRIS.
 */

const CASE = 'C-000002';
const recorded = fixtures.cases[CASE];

interface Event {
  kind: string;
  fromState?: string;
  at: string;
}

/** The held S2 case as it waited for its approval, at its own version or at another (a change under the review). */
function held(version?: number) {
  const all = recorded.events as Event[];
  const cut = all.findIndex((e) => e.kind === 'state' && e.fromState === 'awaiting_approval');
  const events = cut < 0 ? all : all.slice(0, cut);
  const open = {
    state: 'awaiting_approval',
    version: version ?? events.filter((e) => e.kind === 'state').length,
    outcome: '',
    closedAt: '',
    updatedAt: events.at(-1)?.at,
    currentApprovalId: '',
  };
  const plan = recorded.plan as { gateDecisions?: { stage: string }[] };
  const tasks = (recorded.approvals as { tasks: Record<string, unknown>[] }).tasks;
  return {
    open,
    detail: { ...recorded.detail, ...open },
    events,
    plan: { ...plan, gateDecisions: (plan.gateDecisions ?? []).filter((g) => g.stage !== 'dispatch') },
    approvals: {
      approvals: [],
      tasks: tasks.map((t) => ({
        ...t,
        action: '',
        userName: '',
        assignedTo: '',
        complete: false,
        timeCompleted: '',
      })),
    },
  };
}

const ME = {
  username: 'approver',
  operator: true,
  approver: true,
  can: { operate: true, approve: true, configure: true, scenarios: true, liveAgents: true },
};

/** What the stand-in does: answer a decision with this, move the case, fail the cases list's reads. */
interface Stub {
  decision?: { status: number; body: unknown };
  moved?: boolean;
  casesFail?: boolean;
}

async function stubServer(page: Page, stub: Stub) {
  const json = (route: Route, body: unknown, status = 200) => route.fulfill({ status, json: body });
  await page.route('**/api/shutter/**', async (route) => {
    const request = route.request();
    const path = new URL(request.url()).pathname.replace(/^.*\/api\/shutter/, '');
    const c = `/cases/${CASE}`;
    const view = held(stub.moved ? 99 : undefined);
    if (request.method() === 'POST') {
      if (path === `${c}/approvals` && stub.decision)
        return json(route, stub.decision.body, stub.decision.status);
      return json(route, { error: 'not_found', detail: 'Not on the stub' }, 404);
    }
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
      case '/recovery-control':
        return json(route, {
          mode: 'enabled',
          generation: 1,
          stopped: false,
          outstanding: [],
          outstandingCount: 0,
        });
      case `${c}/warehouse-history`:
        return json(route, { enabled: false, read: null });
      case '/cases':
        if (stub.casesFail)
          return json(route, { error: 'unavailable', detail: 'The cases could not be read now' }, 503);
        return json(route, { items: [{ ...recorded.summary, ...view.open }], total: 1 });
      case c:
        return json(route, view.detail);
      case `${c}/events`:
        return json(route, view.events);
      case `${c}/snapshot`:
        return json(route, recorded.snapshot);
      case `${c}/runs`:
        return json(route, recorded.runs);
      case `${c}/plan`:
        return json(route, view.plan);
      case `${c}/approvals`:
        return json(route, view.approvals);
      case `${c}/attempts`:
      case `${c}/escalations`:
        return json(route, []);
      case `${c}/precedents`:
        return json(route, { receiver: 'Downstream Out', conditions: [], summary: {}, precedents: [] });
      default:
        return json(route, { error: 'not_found', detail: 'Not on the stub' }, 404);
    }
  });
}

/** Opens the held case and its review from the action button with the keyboard, then puts the focus on the confirm. */
async function openReview(page: Page) {
  await page.goto(`./#/cases/${CASE}`);
  await expect(page.getByRole('heading', { name: `Case ${CASE}`, exact: true })).toBeVisible();
  const action = page.getByTestId('case-action');
  await action.focus();
  await page.keyboard.press('Enter');
  const dialog = page.getByRole('dialog', { name: /^Approve the resend: plan v\d+$/ });
  const confirm = dialog.getByRole('button', { name: 'Approve the resend' });
  await confirm.focus();
  return { action, dialog, confirm };
}

/** Whether the focus is inside the open dialog. */
const focusInDialog = (page: Page) =>
  page.evaluate(() => !!document.activeElement?.closest('[role="dialog"]'));

test.use({ viewport: { width: 1280, height: 900 } });

// A live Home's first visit offers the trial ("New here?"): it was seen before, so a pass through Home finds nothing over it
test.beforeEach(({ page }) =>
  page.addInitScript(() => localStorage.setItem('shutter:live-welcome:v1', '2026-11-02T09:00:00Z')),
);

test.describe('the keyboard walk on a live page', () => {
  test('a decision refused as stale leaves the focus on Review current plan, in the review, and Escape goes back', async ({
    page,
  }) => {
    await stubServer(page, {
      decision: {
        status: 409,
        body: {
          error: 'stale_version',
          detail: "expectedVersion is not the case's version",
          currentVersion: 99,
        },
      },
    });
    const { action, dialog, confirm } = await openReview(page);
    await page.keyboard.press('Enter');
    await expect(dialog.getByRole('alert')).toContainText('Approval no longer valid');
    // The stopped review offers no decision; the way forward, Review current plan, takes the focus
    await expect(confirm).toHaveCount(0);
    const again = dialog.getByRole('button', { name: 'Review current plan' });
    await expect(again).toBeFocused();
    // The next Shift+Tab and Tab stay in the review
    await page.keyboard.press('Shift+Tab');
    expect(await focusInDialog(page)).toBe(true);
    await page.keyboard.press('Tab');
    await expect(again).toBeFocused();
    await page.keyboard.press('Escape');
    await expect(dialog).toBeHidden();
    await expect(action).toBeFocused();
  });

  test('a case that changes under the open review stops it and leaves the focus on Review current plan', async ({
    page,
  }) => {
    const stub: Stub = {};
    await stubServer(page, stub);
    const { dialog, confirm } = await openReview(page);
    await expect(confirm).toBeFocused();
    stub.moved = true;
    await expect(dialog.getByRole('alert')).toContainText(
      'The plan or the case changed since you opened this',
      {
        timeout: 20_000,
      },
    );
    await expect(confirm).toHaveCount(0);
    await expect(dialog.getByRole('button', { name: 'Review current plan' })).toBeFocused();
  });

  test('another refusal leaves the focus on Cancel, with the decision still there to press', async ({
    page,
  }) => {
    await stubServer(page, {
      decision: {
        status: 403,
        body: { error: 'forbidden', detail: 'You are not in the Workflow role this task is assigned to' },
      },
    });
    const { dialog, confirm } = await openReview(page);
    await page.keyboard.press('Enter');
    await expect(dialog.getByRole('alert')).toContainText('Workflow role');
    await expect(confirm).toBeEnabled();
    await expect(dialog.getByRole('button', { name: 'Cancel' })).toBeFocused();
  });

  test('a list that could not be read is said, and Try again leaves the focus on the filters as it reads again', async ({
    page,
  }) => {
    const stub: Stub = { casesFail: true };
    await stubServer(page, stub);
    await page.goto('./#/cases');
    await expect(page.getByRole('heading', { name: 'Cases', exact: true })).toBeVisible();
    const failed = page.getByRole('alert').filter({ hasText: 'The cases could not be read' });
    await expect(failed).toBeVisible({ timeout: 20_000 });
    const count = page.getByTestId('cases-count');
    await expect(count).toHaveText('');
    await count.evaluate((el) => {
      (el as HTMLElement & { walkMark?: boolean }).walkMark = true;
    });
    stub.casesFail = false;
    await failed.getByRole('button', { name: 'Try again' }).focus();
    await page.keyboard.press('Enter');
    await expect(page.getByRole('combobox', { name: 'State' })).toBeFocused();
    await expect(page.getByRole('link', { name: CASE })).toBeVisible();
    // Said: the count region was on the page all along, and now holds the list's count
    await expect(count).toHaveText('1 case');
    expect(await count.evaluate((el) => (el as HTMLElement & { walkMark?: boolean }).walkMark === true)).toBe(
      true,
    );
  });
});
