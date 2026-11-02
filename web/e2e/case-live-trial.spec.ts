import { expect, test, type Page, type Route } from '@playwright/test';
import fixtures from '../src/mocks/fixtures.json' with { type: 'json' };
import { withLiveClock } from '../src/test/runs';
import { audit } from './axe';
import { area } from './areas/case';

/**
 * The case page live, against a stand-in for a v1.35 server, on the build IRIS serves: the `iris-trial` project picks
 * this file up by its name's ending, as it does the live sign-in page's, since only that build has a live page (the
 * demo build is always the trial). The stub answers `/api/shutter` in the browser with the held S2 case as it waited
 * for its approval, its board's runs with the run's own clock (a millisecond start, the tool calls' times, AI Hub's
 * counters on one run) and precedents for its conditions, one already retired; it retires one as the server does.
 * Nothing here reaches IRIS: the build's instance address is one nothing listens on.
 */

const CASE = 'C-000002';
const recorded = fixtures.cases[CASE];

interface Event {
  kind: string;
  fromState?: string;
  at: string;
}
interface Precedent {
  id: number;
  caseId: string;
  receiver: string;
  approver: string;
  decision: 'approved' | 'rejected';
  policyVersion: string;
  siteProfileVersion?: number;
  createdAt: string;
  active: boolean;
  retiredAt?: string;
  retiredBy?: string;
  retiredReason?: string;
}

/** The case as it waited for an approver: its events up to the request, an open task, no dispatch yet. */
function held() {
  const all = recorded.events as Event[];
  const cut = all.findIndex((e) => e.kind === 'state' && e.fromState === 'awaiting_approval');
  const events = cut < 0 ? all : all.slice(0, cut);
  const open = {
    state: 'awaiting_approval',
    version: events.filter((e) => e.kind === 'state').length,
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

function precedents(): Precedent[] {
  return [
    {
      id: 12,
      caseId: 'C-000301',
      receiver: 'Downstream Out',
      approver: 'approver',
      decision: 'approved',
      policyVersion: '2026-11-01.1',
      siteProfileVersion: 4,
      createdAt: '2026-11-02T10:02:11Z',
      active: true,
    },
    {
      id: 11,
      caseId: 'C-000287',
      receiver: 'Downstream Out',
      approver: 'mx',
      decision: 'rejected',
      policyVersion: '2026-10-25.2',
      siteProfileVersion: 3,
      createdAt: '2026-11-01T16:40:00Z',
      active: true,
    },
    {
      id: 9,
      caseId: 'C-000250',
      receiver: 'Downstream Out',
      approver: 'approver',
      decision: 'approved',
      policyVersion: '2026-10-25.2',
      createdAt: '2026-10-30T09:00:00Z',
      active: false,
      retiredAt: '2026-11-01T08:00:00Z',
      retiredBy: 'mx',
      retiredReason: "the receiver's contract changed",
    },
  ];
}

function summaryOf(list: Precedent[]) {
  const active = list.filter((p) => p.active);
  return {
    approved: active.filter((p) => p.decision === 'approved').length,
    rejected: active.filter((p) => p.decision === 'rejected').length,
    lastDecision: active[0]?.decision ?? '',
    lastApprover: active[0]?.approver ?? '',
    lastAt: active[0]?.createdAt ?? '',
    lastCaseId: active[0]?.caseId ?? '',
    samePolicy: false,
    windowDays: 180,
    signature: 'sha256:5e1c',
  };
}

const ME = {
  username: 'approver',
  operator: true,
  approver: true,
  can: { operate: true, approve: true, configure: true, scenarios: true, liveAgents: true },
};

/** The stand-in for a v1.35 server, signed in as an approver. Precedent 11 has been retired meanwhile by another. */
async function stubServer(page: Page) {
  const list = precedents();
  const view = held();
  const retired: { id: string; body: unknown; csrf: string | null }[] = [];
  const unknown: string[] = [];
  const json = (route: Route, body: unknown, status = 200) => route.fulfill({ status, json: body });
  await page.route('**/api/shutter/**', async (route) => {
    const request = route.request();
    const path = new URL(request.url()).pathname.replace(/^.*\/api\/shutter/, '');
    const c = `/cases/${CASE}`;
    if (request.method() === 'POST') {
      const m = /^\/precedents\/(\d+)\/retire$/.exec(path);
      if (!m) return json(route, { error: 'not_found', detail: 'Not on the stub' }, 404);
      retired.push({
        id: m[1],
        body: request.postDataJSON(),
        csrf: request.headers()['x-requested-with'] ?? null,
      });
      if (m[1] === '11')
        return json(
          route,
          { error: 'already_retired', detail: 'Precedent 11 was retired on 2026-11-02T10:00:00Z by mx' },
          409,
        );
      const p = list.find((x) => String(x.id) === m[1])!;
      Object.assign(p, {
        active: false,
        retiredAt: '2026-11-02T11:30:00Z',
        retiredBy: 'approver',
        retiredReason: (request.postDataJSON() as { reason: string }).reason,
      });
      return json(route, p);
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
      case '/cases':
        return json(route, { items: [{ ...recorded.summary, ...view.open }], total: 1 });
      case c:
        return json(route, view.detail);
      case `${c}/events`:
        return json(route, view.events);
      case `${c}/snapshot`:
        return json(route, {
          ...recorded.snapshot,
          summary: { ...recorded.snapshot.summary, precedents: summaryOf(precedents()) },
        });
      case `${c}/runs`:
        return json(route, withLiveClock(recorded.runs as never));
      case `${c}/plan`:
        return json(route, view.plan);
      case `${c}/approvals`:
        return json(route, view.approvals);
      case `${c}/attempts`:
        return json(route, []);
      case `${c}/escalations`:
        return json(route, []);
      case `${c}/precedents`:
        return json(route, {
          receiver: 'Downstream Out',
          conditions: recorded.snapshot.summary.catalogue.conditions,
          summary: summaryOf(list),
          precedents: list,
        });
      default:
        unknown.push(path);
        return json(route, { error: 'not_found', detail: 'Not on the stub' }, 404);
    }
  });
  return { retired, unknown };
}

/** The case page live, in Plain or with the Detail switch on Technical, once its board has its coordinator. */
async function openCase(page: Page, detail?: 'technical') {
  await page.goto(`./${detail ? '?detail=technical' : ''}#/cases/${CASE}`);
  await expect(page.getByRole('heading', { name: `Case ${CASE}`, exact: true })).toBeVisible();
  await expect(page.getByRole('region', { name: 'Trial environment' })).toHaveCount(0);
  const board = page.getByRole('region', { name: 'The board' });
  await expect(board.getByRole('region', { name: 'Coordinator' })).toBeVisible();
  return board;
}

/** A part of the page's words as they read, without a term's definition kept hidden for its description. */
const visible = (page: Page, testId: string) =>
  page
    .getByTestId(testId)
    .first()
    .evaluate((el) => {
      const copy = el.cloneNode(true) as HTMLElement;
      copy.querySelectorAll('[hidden]').forEach((h) => h.remove());
      return copy.textContent ?? '';
    });

/** Saves a picture for the restyle's record when E2E_SHOTS names a folder. */
async function shot(page: Page, name: string, target?: { screenshot: Page['screenshot'] }) {
  if (!process.env.E2E_SHOTS) return;
  await (target ?? page).screenshot({ path: `${process.env.E2E_SHOTS}/${name}.png` });
}

test.use({ viewport: { width: 1280, height: 900 } });

// A live page's first visit offers the trial ("New here?"), which would cover the case: it was seen before
test.beforeEach(({ page }) =>
  page.addInitScript(() => localStorage.setItem('shutter:live-welcome:v1', '2026-11-02T09:00:00Z')),
);

test.describe(`the live case page against a v1.35 server ${area.tag}`, () => {
  test('draws where it failed, names the patient and the message type, and offers the approver the decision', async ({
    page,
  }) => {
    const { unknown } = await stubServer(page);
    await openCase(page);
    const picture = page.getByRole('img', { name: /^Where it failed: PAS sent the transfer to WARD-B/ });
    await expect(picture).toContainText('Not delivered');
    await expect(picture).toContainText('Bed-management system');
    await expect(page.getByTestId('case-message-type')).toHaveText('2.5.1:ADT_A02');
    await expect(page.getByText('MRN1002', { exact: true })).toBeVisible();
    const action = page.getByTestId('case-action');
    await expect(action).toHaveAccessibleName('Needs you: decide on the resend');
    await page
      .getByRole('region', { name: 'Outcome' })
      .getByRole('button', { name: 'Outcome', exact: true })
      .click();
    await action.click();
    await expect(page.getByRole('heading', { name: 'What needs you now' })).toBeFocused();
    // The strip's Evidence stage opens the Evidence tab
    await page.getByRole('button', { name: 'Evidence: done, show the evidence' }).click();
    await expect(page.getByRole('tab', { name: 'Evidence' })).toHaveAttribute('aria-selected', 'true');
    expect(unknown).toEqual([]);
  });

  test('draws when each agent worked under the specialists: closed in Plain, the picture, its sentence and a table', async ({
    page,
  }) => {
    const stub = await stubServer(page);
    const board = await openCase(page);
    const toggle = board.getByRole('button', { name: 'When each agent worked' });
    await expect(toggle).toHaveAttribute('aria-expanded', 'false');
    // Under the specialists' cards and above the coordinator's
    const below = await board.getByRole('region', { name: 'Impact Analysis' }).boundingBox();
    const at = await toggle.boundingBox();
    const above = await board.getByRole('region', { name: 'Coordinator' }).boundingBox();
    expect(at!.y).toBeGreaterThan(below!.y + below!.height - 1);
    expect(at!.y + at!.height).toBeLessThan(above!.y + 1);
    await toggle.click();
    const picture = board.getByRole('img', {
      name: 'When each agent worked: the three specialists at the same time, then the coordinator; the pass took 31 s.',
    });
    await expect(picture).toBeVisible();
    await expect(board.getByTestId('run-timeline-sentence')).toHaveText(
      'The three specialists worked at the same time, then the coordinator wrote the plan. The pass took 31 s.',
    );
    await expect(board.getByTestId('run-timeline-figures')).toHaveCount(0);
    // Four bars in the members' hues, and the tool calls on them, one refused
    await expect(picture.locator('.run-clock-bar')).toHaveCount(4);
    await expect(picture.locator('.run-clock-mark')).toHaveCount(7);
    await expect(picture.locator('.run-clock-mark[data-refused]')).toHaveCount(1);
    const colours = await picture
      .locator('.run-clock-bar')
      .evaluateAll((bars) => bars.map((b) => getComputedStyle(b).fill));
    expect(new Set(colours).size).toBe(4);
    await shot(page, 'live-timeline-plain-light', board.getByTestId('run-timeline'));
    await board.getByRole('button', { name: 'As a table' }).click();
    const table = board.getByRole('table');
    await expect(table.getByRole('row')).toHaveCount(5);
    await expect(table.getByRole('row').nth(4)).toContainText('Coordinator');
    await expect(table.getByRole('row').nth(4)).toContainText('16.0 s');
    await expect(table.getByRole('row').nth(2)).toContainText('2, 1 refused');
    await shot(page, 'live-timeline-table-light', board.getByTestId('run-timeline'));
    expect(stub.unknown).toEqual([]);
  });

  test("opens it in Technical with each run's split, and moves nothing", async ({ page }) => {
    await stubServer(page);
    const board = await openCase(page, 'technical');
    await expect(board.getByRole('button', { name: 'When each agent worked' })).toHaveAttribute(
      'aria-expanded',
      'true',
    );
    await expect(board.getByTestId('run-timeline-figures').getByRole('listitem')).toHaveText([
      'Conformance: model 11.2 s, tools 0.8 s, 1,240 reasoning tokens',
      'Encounter Integrity: timings as recorded',
      'Impact Analysis: timings as recorded',
      'Coordinator: timings as recorded',
    ]);
    const moving = await board
      .getByTestId('run-timeline')
      .evaluate((el) => [el, ...el.querySelectorAll('*')].filter((n) => n.getAnimations().length > 0).length);
    expect(moving).toBe(0);
    await shot(page, 'live-timeline-technical-light', board.getByTestId('run-timeline'));
  });

  test('says the precedents under the approval, lists them in the Audit trail, and retires one with a reason', async ({
    page,
  }) => {
    const stub = await stubServer(page);
    await openCase(page);
    const outcome = page.getByRole('region', { name: 'Outcome' });
    const under = outcome.getByTestId('next-action-precedents');
    await expect(under).toBeVisible();
    expect(await visible(page, 'precedents-line')).toBe(
      'Precedents: approved and verified 1 time, rejected 1 time here in the last 180 days; last approved by approver on 2 Nov (case C-000301), under an earlier policy.',
    );
    await expect(under.getByRole('link', { name: 'C-000301' })).toBeVisible();
    await shot(page, 'live-precedents-under-the-approval', outcome);
    await under.getByRole('button', { name: 'See them in the audit trail' }).click();
    await expect(page.getByRole('tab', { name: 'Audit trail' })).toHaveAttribute('aria-selected', 'true');
    const section = page.getByRole('region', { name: 'Precedents' });
    await expect(section.getByRole('heading', { name: 'Precedents' })).toBeFocused();
    const table = section.getByRole('table');
    await expect(table.getByRole('row')).toHaveCount(4);
    const retiredRow = table.getByRole('row').nth(3);
    await expect(retiredRow).toContainText("Retired by mx on 1 Nov: the receiver's contract changed");
    await expect(retiredRow.getByRole('cell').nth(2)).toHaveCSS('text-decoration-line', 'line-through');
    await expect(section.getByRole('button', { name: /approve/i })).toHaveCount(0);
    await shot(page, 'live-precedents-audit-trail', section);

    await section.getByRole('button', { name: 'Retire the precedent from C-000301, 2 Nov' }).click();
    const dialog = page.getByRole('dialog', { name: 'Retire a precedent' });
    await expect(dialog.getByText('Live system')).toBeVisible();
    const submit = dialog.getByRole('button', { name: 'Retire it' });
    await expect(submit).toBeDisabled();
    await dialog
      .getByRole('textbox', { name: /Why retire it/ })
      .fill('a test approval on the training receiver');
    await shot(page, 'live-precedents-retire-dialog');
    await submit.click();
    await expect(dialog).toHaveCount(0);
    expect(stub.retired).toEqual([
      { id: '12', body: { reason: 'a test approval on the training receiver' }, csrf: 'Shutter' },
    ]);
    await expect(table.getByRole('row').nth(1)).toContainText(
      'Retired by approver on 2 Nov: a test approval on the training receiver',
    );
    await expect(section.getByTestId('precedents-line')).toHaveText(
      'Approved and verified 0 times, rejected 1 time here in the last 180 days; last rejected by mx on 1 Nov (case C-000287), under an earlier policy.',
    );
  });

  test('names who retired a precedent already, and when', async ({ page }) => {
    await stubServer(page);
    await openCase(page);
    await page.getByRole('tab', { name: 'Audit trail' }).click();
    const section = page.getByRole('region', { name: 'Precedents' });
    await section.getByRole('button', { name: 'See them' }).click();
    await section.getByRole('button', { name: 'Retire the precedent from C-000287, 1 Nov' }).click();
    const dialog = page.getByRole('dialog', { name: 'Retire a precedent' });
    await dialog.getByRole('textbox', { name: /Why retire it/ }).fill('stale');
    await dialog.getByRole('button', { name: 'Retire it' }).click();
    await expect(dialog.getByRole('alert')).toHaveText('Already retired by mx on 2 Nov, 10:00:00 GMT.');
    await expect(dialog.getByRole('button', { name: 'Retire it' })).toBeDisabled();
  });

  test("keeps the picture and the list within a phone's width, the names above their bars", async ({
    page,
  }) => {
    await page.setViewportSize({ width: 360, height: 800 });
    await stubServer(page);
    const board = await openCase(page, 'technical');
    const picture = board.getByRole('img', { name: /^When each agent worked: / });
    await expect(picture).toBeVisible();
    const fits = await picture.evaluate((svg) => {
      const box = svg.getBoundingClientRect();
      return [...svg.querySelectorAll('text')].every((t) => {
        const r = t.getBoundingClientRect();
        return r.left >= box.left - 1 && r.right <= box.right + 1;
      });
    });
    expect(fits).toBe(true);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(360);
    await shot(page, 'live-timeline-phone', board.getByTestId('run-timeline'));
    await page.getByRole('tab', { name: 'Audit trail' }).click();
    await expect(page.getByRole('region', { name: 'Precedents' }).getByRole('table')).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(360);
  });
});

for (const colorScheme of ['light', 'dark'] as const)
  test.describe(`accessibility of the run timeline and the precedents, ${colorScheme} ${area.tag}`, () => {
    test.use({ colorScheme });

    test('the board with its timeline open and the precedents under the approval, then their list and the retire dialog', async ({
      page,
    }) => {
      await stubServer(page);
      const board = await openCase(page, 'technical');
      await expect(board.getByRole('img', { name: /^When each agent worked: / })).toBeVisible();
      await board.getByRole('button', { name: 'As a table' }).click();
      await expect(board.getByRole('table')).toBeVisible();
      await expect(page.getByTestId('next-action-precedents')).toBeVisible();
      await expect(page.getByRole('status')).toHaveCount(0);
      expect(await audit(page)).toEqual([]);
      if (colorScheme === 'dark')
        await shot(page, 'live-timeline-technical-dark', board.getByTestId('run-timeline'));
      await page.getByRole('tab', { name: 'Audit trail' }).click();
      const section = page.getByRole('region', { name: 'Precedents' });
      await expect(section.getByRole('table')).toBeVisible();
      expect(await audit(page)).toEqual([]);
      if (colorScheme === 'dark') await shot(page, 'live-precedents-audit-trail-dark', section);
      await section.getByRole('button', { name: 'Retire the precedent from C-000301, 2 Nov' }).click();
      await expect(page.getByRole('dialog', { name: 'Retire a precedent' })).toBeVisible();
      expect(await audit(page)).toEqual([]);
    });
  });
