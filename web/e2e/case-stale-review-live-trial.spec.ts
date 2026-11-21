import { expect, test, type Page, type Route } from './test';
import fixtures from '../src/mocks/fixtures.json' with { type: 'json' };
import { audit } from './axe';
import { area } from './areas/case';

/**
 * A stale approval on the live case page, in two tabs, on the build IRIS serves (the `iris-trial` project picks this
 * file up by its name's ending; the demo build is always the trial). Both tabs of one browser are signed in as the same
 * approver against one stand-in server, which holds the S2 case as it waited for its approval and keeps to the
 * approval contract: a decision on another plan digest or case version is refused 409 `stale_version`, on a case no
 * longer waiting 409 `wrong_state`. Tab A opens the review of plan v1; tab B rejects plan v1 and reopens the case,
 * which the stand-in re-plans at once as plan v2 on the receiver at version 2 (a real server collects and investigates
 * first). Tab A's decision on plan v1 is refused, the review says why and what changed, and "Review current plan"
 * reaches a fresh review of plan v2, on the same case, that needs its own press. Nothing here reaches IRIS.
 */

const CASE = 'C-000002';
const recorded = fixtures.cases[CASE];

interface Event {
  kind: string;
  fromState?: string;
  at: string;
}
type Json = Record<string, unknown>;

/** The case as the stand-in holds it: its detail, plan and evidence, and every decision sent to it. */
interface State {
  detail: Json & { state: string; version: number };
  view: { plan: Json & { version: number; digest: string } } & Json;
  snapshot: Json;
  decisions: {
    decision: string;
    planDigest: string;
    expectedVersion: number;
    comment: string;
    answer: number;
  }[];
}

/** The case as it waited for an approver: its events up to the request, no dispatch yet. */
function held(): State {
  const all = recorded.events as Event[];
  const cut = all.findIndex((e) => e.kind === 'state' && e.fromState === 'awaiting_approval');
  const events = cut < 0 ? all : all.slice(0, cut);
  const plan = recorded.plan as unknown as State['view'] & { gateDecisions?: { stage: string }[] };
  return {
    detail: {
      ...(recorded.detail as Json),
      state: 'awaiting_approval',
      version: events.filter((e) => e.kind === 'state').length,
      outcome: '',
      closedAt: '',
      currentApprovalId: '',
    },
    view: { ...plan, gateDecisions: (plan.gateDecisions ?? []).filter((g) => g.stage !== 'dispatch') },
    snapshot: recorded.snapshot as Json,
    decisions: [],
  };
}

/**
 * The case re-planned: the receiver moved the patient to bed BAY1-03 (version 2) meanwhile, so the fresh evidence and
 * plan v2 are conditional on version 2. The plan's action is the same resend.
 */
function replan(s: State) {
  const summary = s.snapshot.summary as { ward_state: Json };
  s.detail = { ...s.detail, state: 'awaiting_approval', version: s.detail.version + 2 };
  s.view = {
    ...s.view,
    plan: {
      ...s.view.plan,
      id: '902',
      version: 2,
      digest: 'sha256:2f0c9d1e7b3a4c5d6e7f8091a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5',
      expectedVersion: 2,
      summary:
        'The receiver now holds the patient on WARD-A, bed BAY1-03, at version 2. Resend the operation unchanged, conditional on version 2.',
    },
  };
  s.snapshot = {
    ...s.snapshot,
    id: '1025',
    seq: 2,
    digest: 'sha256:5a6b7c8d9e0f1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f708192a3',
    materialDigest: 'sha256:6b7c8d9e0f1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f708192a3b4',
    takenAt: '2026-11-02T14:31:05Z',
    summary: { ...summary, ward_state: { ...summary.ward_state, bed: 'BAY1-03', version: 2 } },
  };
}

const ME = {
  username: 'approver',
  operator: true,
  approver: true,
  can: { operate: true, approve: true, configure: true, scenarios: true, liveAgents: true },
};

const RECOVERY_AT_REST = {
  mode: 'enabled',
  generation: 1,
  stopped: false,
  stoppedAt: '',
  stoppedBy: '',
  stopReason: '',
  outstanding: [],
  outstandingCount: 0,
  readable: true,
  covers: 'Recovery writes that Shutter itself starts.',
  doesNotCover: "The hospital's ordinary feed and its retries.",
};

/** One tab's view of the stand-in: `hold` answers its reads as they were (a tab that has not read since); `failing` fails its evidence read. */
interface Tab {
  hold: State | null;
  failing: boolean;
}

/** Routes a tab's `/api/shutter` to the one stand-in server both tabs share. */
async function stub(page: Page, s: State): Promise<Tab> {
  const tab: Tab = { hold: null, failing: false };
  const json = (route: Route, body: unknown, status = 200) => route.fulfill({ status, json: body });
  await page.route('**/api/shutter/**', async (route) => {
    const request = route.request();
    const path = new URL(request.url()).pathname.replace(/^.*\/api\/shutter/, '');
    const c = `/cases/${CASE}`;
    if (request.method() === 'POST') {
      if (path === `${c}/approvals`) {
        const body = request.postDataJSON() as State['decisions'][number];
        const answer = (status: number, reply: unknown) => {
          s.decisions.push({ ...body, answer: status });
          return json(route, reply, status);
        };
        if (s.detail.state !== 'awaiting_approval')
          return answer(409, {
            error: 'wrong_state',
            detail: `The case is ${s.detail.state}, not awaiting approval`,
          });
        if (body.planDigest !== s.view.plan.digest)
          return answer(409, {
            error: 'stale_version',
            detail: "planDigest is not the current plan's digest",
            currentDigest: s.view.plan.digest,
          });
        if (Number(body.expectedVersion) !== s.detail.version)
          return answer(409, {
            error: 'stale_version',
            detail: "expectedVersion is not the case's version",
            currentVersion: s.detail.version,
          });
        s.detail = {
          ...s.detail,
          state: body.decision === 'approve' ? 'approved' : 'blocked',
          version: s.detail.version + 1,
        };
        return answer(202, { taskId: '77', decision: body.decision, caseId: CASE, approver: 'approver' });
      }
      if (path === `${c}/reinvestigate`) {
        if (!['blocked', 'escalated', 'failed'].includes(s.detail.state))
          return json(route, { error: 'wrong_state', detail: `The case is ${s.detail.state}` }, 409);
        replan(s);
        return json(route, { caseId: CASE, state: 'collecting' }, 202);
      }
      return json(route, { error: 'not_found', detail: 'Not on the stub' }, 404);
    }
    const now = tab.hold ?? s;
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
        return json(route, RECOVERY_AT_REST);
      case `${c}/warehouse-history`:
        return json(route, { enabled: false, read: null });
      case '/cases':
        return json(route, { items: [{ ...recorded.summary, state: now.detail.state }], total: 1 });
      case c:
        return json(route, now.detail);
      case `${c}/events`:
        return json(route, recorded.events.slice(0, 8));
      case `${c}/snapshot`:
        if (tab.failing)
          return json(route, { error: 'unavailable', detail: 'The evidence store did not answer' }, 503);
        return json(route, now.snapshot);
      case `${c}/runs`:
        return json(route, recorded.runs);
      case `${c}/plan`:
        return json(route, now.view);
      case `${c}/approvals`:
        return json(route, { approvals: [], tasks: [] });
      case `${c}/attempts`:
      case `${c}/escalations`:
        return json(route, []);
      default:
        return json(route, { error: 'not_found', detail: 'Not on the stub' }, 404);
    }
  });
  return tab;
}

async function openCase(page: Page) {
  await page.goto(`./#/cases/${CASE}`);
  await expect(page.getByRole('heading', { name: `Case ${CASE}`, exact: true })).toBeVisible();
  await expect(page.getByRole('region', { name: 'Trial environment' })).toHaveCount(0);
  await expect(page.getByTestId('case-action')).toBeVisible();
}

/** Saves a picture when E2E_SHOTS names a folder. */
async function shot(page: Page, name: string) {
  if (!process.env.E2E_SHOTS) return;
  await page.screenshot({ path: `${process.env.E2E_SHOTS}/${name}.png` });
}

test.use({ viewport: { width: 1280, height: 900 } });

// A live Home's first visit offers the trial ("New here?"): it was seen before, so a pass through Home finds nothing over it
test.beforeEach(({ context }) =>
  context.addInitScript(() => localStorage.setItem('shutter:live-welcome:v1', '2026-11-02T09:00:00Z')),
);

test.describe(`a stale approval in two tabs ${area.tag}`, () => {
  test('blocks the stale decision, says what changed and reaches a fresh review of the same case', async ({
    page,
    context,
  }) => {
    const s = held();
    const a = await stub(page, s);
    await openCase(page);
    await page.getByTestId('case-action').click();
    const stale = page.getByRole('dialog', { name: 'Approve the resend: plan v1' });
    await expect(stale.getByTestId('plan-action')).toHaveText(
      'Resend the PAS transfer to WARD-B, once, only if the bed-management system is still at version 1.',
    );
    await stale.getByRole('textbox', { name: /Comment/ }).fill('Read plan one');
    // Tab A reads nothing more for now, as a tab whose next refresh has not come yet
    a.hold = structuredClone(s);

    // Tab B: the same approver rejects plan v1 and reopens the case, which is re-planned as plan v2
    const other = await context.newPage();
    await stub(other, s);
    await openCase(other);
    await other.getByTestId('case-action').click();
    const reviewB = other.getByRole('dialog', { name: 'Approve the resend: plan v1' });
    await reviewB.getByRole('button', { name: 'Reject instead' }).click();
    await other
      .getByRole('dialog', { name: 'Reject the resend: plan v1' })
      .getByRole('button', { name: 'Reject the resend' })
      .click();
    await expect(other.getByRole('dialog')).toHaveCount(0);
    await other.getByRole('button', { name: 'Reinvestigate' }).click();
    const reopen = other.getByRole('dialog', { name: `Reinvestigate ${CASE}` });
    await reopen
      .getByRole('textbox', { name: /Why look again/ })
      .fill('The ward moved the patient to another bed');
    await reopen.getByRole('button', { name: 'Reopen the case' }).click();
    await expect(reopen).toBeHidden();
    expect(s.view.plan.version).toBe(2);

    // Tab A: the decision on plan v1 is refused, and the review says so in its own words
    await page.bringToFront();
    await stale.getByRole('button', { name: 'Approve the resend' }).focus();
    await page.keyboard.press('Enter');
    const refusal = stale.getByTestId('review-refusal');
    await expect(refusal).toHaveText(
      'Approval no longer valid: the plan or the case changed since you opened this, so this decision was not recorded. Review the current plan to decide again.',
    );
    await expect(refusal).toHaveAttribute('role', 'alert');
    await expect(stale.getByRole('button', { name: 'Approve the resend' })).toHaveCount(0);
    await expect(stale.getByRole('button', { name: 'Reject instead' })).toHaveCount(0);
    const again = stale.getByRole('button', { name: 'Review current plan' });
    await expect(again).toBeFocused();
    expect(await audit(page)).toEqual([]);

    // The current state can't be read for now: the review says so and offers no decision
    a.failing = true;
    await page.keyboard.press('Enter');
    await expect(stale.getByTestId('review-current-failed')).toHaveText(
      /^The current plan could not be read: .*\. Nothing was decided; try again, or cancel\.$/,
    );
    await expect(stale.getByRole('button', { name: 'Approve the resend' })).toHaveCount(0);
    await expect(refusal).toBeVisible();
    await expect(again).toBeFocused();

    // Tab A reads the case again: what changed is said beside the refusal, against the plan the person read
    a.failing = false;
    a.hold = null;
    const changed = stale.getByTestId('what-changed');
    await expect(changed).toBeVisible();
    const row = (label: string) =>
      changed.getByRole('row').filter({ has: page.getByRole('rowheader', { name: label }) });
    await expect(row('Plan')).toContainText('v2 (was v1)');
    await expect(row('Receiver version')).toContainText('2 (was 1)');
    await expect(row('Action')).toContainText('Unchanged: Resend the PAS transfer to WARD-B, once');
    await expect(row('Evidence')).toContainText(
      'WARD-A, bed BAY1-03 at version 2 (was WARD-A, bed BAY1-01 at version 1)',
    );
    await shot(page, 'U3-read-failed-then-changes-1280-light');

    // "Review current plan", by keyboard: a fresh review of plan v2 on the same case, focus at its top
    await again.focus();
    await page.keyboard.press('Enter');
    const fresh = page.getByRole('dialog', { name: 'Approve the resend: plan v2' });
    await expect(fresh).toBeVisible();
    const note = fresh.getByRole('group', { name: 'Now reviewing the current plan, v2' });
    await expect(note).toBeFocused();
    await expect(note).toContainText(
      'Your decision on plan v1 was not recorded: the plan changed, and this is plan v2. Nothing is decided until you confirm it.',
    );
    await expect(fresh.getByRole('status').filter({ hasText: 'Plan v2 is open for review.' })).toHaveText(
      'Plan v2 is open for review. Nothing is decided until you confirm it.',
    );
    await expect(fresh.getByTestId('plan-action')).toHaveText(
      'Resend the PAS transfer to WARD-B, once, only if the bed-management system is still at version 2.',
    );
    await expect(fresh.getByRole('textbox', { name: /Comment/ })).toHaveValue('');
    await expect(page).toHaveURL(new RegExp(`#/cases/${CASE}$`));
    expect(await audit(page)).toEqual([]);
    await shot(page, 'U3-fresh-review-1280-light');
    // Reading it sent nothing: only tab B's rejection and tab A's refused approval reached the server
    expect(s.decisions.map((d) => [d.decision, d.answer])).toEqual([
      ['reject', 202],
      ['approve', 409],
    ]);

    // Its own confirming press sends plan v2's digest and the version just read, with nothing of the stale review
    await fresh.getByRole('button', { name: 'Approve the resend' }).click();
    await expect(page.getByText('Approved by approver')).toBeVisible();
    expect(s.decisions.at(-1)).toMatchObject({
      decision: 'approve',
      planDigest: s.view.plan.digest,
      comment: '',
      answer: 202,
    });
    expect(s.decisions).toHaveLength(3);
    await expect(page.getByRole('heading', { name: `Case ${CASE}`, exact: true })).toBeVisible();
  });

  test('stops an open review as soon as the page reads the change, and moves keyboard focus on', async ({
    page,
    context,
  }) => {
    const s = held();
    const a = await stub(page, s);
    await openCase(page);
    await page.getByTestId('case-action').click();
    const stale = page.getByRole('dialog', { name: 'Approve the resend: plan v1' });
    await stale.getByRole('button', { name: 'Approve the resend' }).focus();
    // Tab A reads nothing more while tab B acts: its next read is of the case re-planned, not of a moment between
    a.hold = structuredClone(s);
    // Tab B's rejection and reopening, as the stand-in records them
    const other = await context.newPage();
    await stub(other, s);
    await openCase(other);
    await other.getByTestId('case-action').click();
    await other.getByRole('dialog').getByRole('button', { name: 'Reject instead' }).click();
    await other
      .getByRole('dialog', { name: 'Reject the resend: plan v1' })
      .getByRole('button', { name: 'Reject the resend' })
      .click();
    await expect(other.getByRole('dialog')).toHaveCount(0);
    await other.getByRole('button', { name: 'Reinvestigate' }).click();
    const reopen = other.getByRole('dialog', { name: `Reinvestigate ${CASE}` });
    await reopen.getByRole('textbox', { name: /Why look again/ }).fill('The ward moved the patient');
    await reopen.getByRole('button', { name: 'Reopen the case' }).click();
    await expect(reopen).toBeHidden();
    expect(s.view.plan.version).toBe(2);
    await page.bringToFront();
    a.hold = null;
    // Tab A's next read stops the review before anything is pressed: nothing was sent from it
    await expect(stale.getByTestId('review-refusal')).toHaveText(
      "The plan or the case changed since you opened this, so this decision can't be recorded. Review the current plan to decide again.",
    );
    await expect(stale.getByRole('button', { name: 'Review current plan' })).toBeFocused();
    await expect(stale.getByTestId('what-changed')).toContainText('v2 (was v1)');
    expect(s.decisions.map((d) => d.decision)).toEqual(['reject']);
    await page.keyboard.press('Enter');
    await expect(
      page
        .getByRole('dialog', { name: 'Approve the resend: plan v2' })
        .getByRole('group', { name: 'Now reviewing the current plan, v2' }),
    ).toBeFocused();
  });
});

for (const colorScheme of ['light', 'dark'] as const)
  for (const width of [1280, 360])
    test.describe(`the stopped and the fresh review, ${colorScheme} at ${width} ${area.tag}`, () => {
      test.use({ colorScheme, viewport: { width, height: width === 360 ? 780 : 900 } });

      test('pass the accessibility audit and stay within the width', async ({ page }) => {
        const s = held();
        const a = await stub(page, s);
        await openCase(page);
        await page.getByTestId('case-action').click();
        const stale = page.getByRole('dialog', { name: 'Approve the resend: plan v1' });
        await expect(stale.getByRole('button', { name: 'Approve the resend' })).toBeVisible();
        a.hold = structuredClone(s);
        // Another tab's rejection and reopening, recorded on the stand-in as tab B's are above
        s.detail = { ...s.detail, state: 'blocked', version: s.detail.version + 1 };
        replan(s);
        await stale.getByRole('button', { name: 'Approve the resend' }).click();
        await expect(stale.getByTestId('review-refusal')).toBeVisible();
        a.hold = null;
        await expect(stale.getByTestId('what-changed')).toBeVisible();
        expect(await audit(page)).toEqual([]);
        expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
        await shot(page, `U3-stale-refused-${width}-${colorScheme}`);
        await stale.getByRole('button', { name: 'Review current plan' }).click();
        const fresh = page.getByRole('dialog', { name: 'Approve the resend: plan v2' });
        await expect(fresh.getByTestId('review-replaces')).toBeFocused();
        expect(await audit(page)).toEqual([]);
        expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
        await shot(page, `U3-fresh-review-${width}-${colorScheme}`);
      });

      test('a review stopped by a decision in another tab says the case no longer waits', async ({
        page,
      }) => {
        const s = held();
        await stub(page, s);
        await openCase(page);
        await page.getByTestId('case-action').click();
        const stale = page.getByRole('dialog', { name: 'Approve the resend: plan v1' });
        await expect(stale.getByRole('button', { name: 'Approve the resend' })).toBeVisible();
        // Another tab rejected plan v1: the page's next read stops this review, with no word of deciding again
        s.detail = { ...s.detail, state: 'blocked', version: s.detail.version + 1 };
        await expect(stale.getByTestId('review-refusal')).toHaveText(
          "The plan or the case changed since you opened this, so this decision can't be recorded. The case was no longer waiting for a decision when this page last read it.",
        );
        await expect(stale.getByTestId('what-changed')).toContainText('Blocked (was Waiting for approval)');
        expect(await audit(page)).toEqual([]);
        expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
        await shot(page, `U3-left-approval-${width}-${colorScheme}`);
      });
    });
