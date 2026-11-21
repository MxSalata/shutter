import { expect, test, type Page, type Route } from './test';
import fixtures from '../src/mocks/fixtures.json' with { type: 'json' };
import { audit } from './axe';
import { area } from './areas/case';

/**
 * Picking up where Shutter stopped, on the live case page of the build IRIS serves (the `iris-trial` project picks
 * this file up by its name's ending). One stand-in server holds the S2 case as a production restart left it, waiting
 * for its approval with the start sweep's note as its newest event (CONTRACTS 12), and keeps to the approval contract:
 * a decision on another plan digest or case version is refused 409 `stale_version`, on a case no longer waiting 409
 * `wrong_state`, and the same Idempotency-Key with the same body is answered from the first reply (CONTRACTS 5). The
 * stand-in can drop a decision's answer, before or after recording it, as a connection lost on the way would.
 * Nothing here reaches IRIS.
 */

const CASE = 'C-000002';
const recorded = fixtures.cases[CASE];
const START = '2026-11-02T14:40:00Z';

interface Event {
  seq: number;
  kind: string;
  fromState?: string;
  toState?: string;
  at: string;
  text?: string;
  actor?: string;
  ref?: string;
}
type Json = Record<string, unknown>;

/** The case as the stand-in holds it, every decision sent to it, and the answers it keeps by key. */
interface State {
  detail: Json & { state: string; version: number };
  events: Event[];
  view: { plan: Json & { version: number; digest: string } } & Json;
  /** The next decision's answer is dropped: before it is recorded, after, or not at all. */
  drop: 'before' | 'after' | null;
  sent: { key: string; body: string }[];
  recorded: number;
  replies: Map<string, { body: string; status: number; reply: unknown }>;
}

/** The case as a restart left it waiting for an approver: its events up to the request, then the start note. */
function restarted(): State {
  const all = recorded.events as Event[];
  const cut = all.findIndex((e) => e.kind === 'state' && e.fromState === 'awaiting_approval');
  const events = cut < 0 ? all : all.slice(0, cut);
  const plan = recorded.plan as unknown as State['view'] & { gateDecisions?: { stage: string }[] };
  const note: Event = {
    seq: events.length + 1,
    at: START,
    kind: 'error',
    fromState: '',
    toState: '',
    text: `The production started at ${START} while this case was awaiting_approval. Work in flight resumes when the production was stopped cleanly; if the case does not move on within 15 minutes, an approver can abandon it (POST /cases/${CASE}/abandon, or "Abandon the case" on the case page)`,
    actor: 'system',
    ref: `start:${START}`,
  };
  return {
    detail: {
      ...(recorded.detail as Json),
      state: 'awaiting_approval',
      version: events.filter((e) => e.kind === 'state').length,
      outcome: '',
      closedAt: '',
      currentApprovalId: '',
    },
    events: [...events, note],
    view: { ...plan, gateDecisions: (plan.gateDecisions ?? []).filter((g) => g.stage !== 'dispatch') },
    drop: null,
    sent: [],
    recorded: 0,
    replies: new Map(),
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

/** The decision as the server would take it: refused, or recorded with its state event. */
function decide(s: State, body: { decision: string; planDigest: string; expectedVersion: number }) {
  if (s.detail.state !== 'awaiting_approval')
    return {
      status: 409,
      reply: { error: 'wrong_state', detail: `The case is ${s.detail.state}, not awaiting approval` },
    };
  if (body.planDigest !== s.view.plan.digest || Number(body.expectedVersion) !== s.detail.version)
    return { status: 409, reply: { error: 'stale_version', detail: 'The case changed since it was read' } };
  const to = body.decision === 'approve' ? 'approved' : 'blocked';
  s.events = [
    ...s.events,
    {
      seq: s.events.length + 1,
      at: new Date().toISOString(),
      kind: 'state',
      fromState: 'awaiting_approval',
      toState: to,
      text: `${body.decision === 'approve' ? 'Approved' : 'Rejected'} by approver`,
      actor: 'approver',
      ref: '',
    },
  ];
  s.detail = { ...s.detail, state: to, version: s.detail.version + 1 };
  s.recorded += 1;
  return {
    status: 202,
    reply: { taskId: '77', decision: body.decision, caseId: CASE, approver: 'approver' },
  };
}

/** Routes the page's `/api/shutter` to the stand-in. */
async function stub(page: Page, s: State) {
  const json = (route: Route, body: unknown, status = 200) => route.fulfill({ status, json: body });
  await page.route('**/api/shutter/**', async (route) => {
    const request = route.request();
    const path = new URL(request.url()).pathname.replace(/^.*\/api\/shutter/, '');
    const c = `/cases/${CASE}`;
    if (request.method() === 'POST') {
      if (path !== `${c}/approvals`)
        return json(route, { error: 'not_found', detail: 'Not on the stub' }, 404);
      const key = (await request.headerValue('idempotency-key')) ?? '';
      const text = request.postData() ?? '';
      s.sent.push({ key, body: text });
      // The same key with the same body is answered from the first reply; with another body, refused
      const kept = s.replies.get(key);
      if (kept)
        return kept.body === text
          ? json(route, kept.reply, kept.status)
          : json(
              route,
              { error: 'idempotency_key_reused', detail: 'This key was used with another body' },
              409,
            );
      if (s.drop === 'before') {
        s.drop = null;
        return route.abort('failed');
      }
      const { status, reply } = decide(s, JSON.parse(text));
      if (status < 300) s.replies.set(key, { body: text, status, reply });
      if (s.drop === 'after') {
        s.drop = null;
        return route.abort('failed');
      }
      return json(route, reply, status);
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
        return json(route, RECOVERY_AT_REST);
      case `${c}/warehouse-history`:
        return json(route, { enabled: false, read: null });
      case '/cases':
        return json(route, { items: [{ ...recorded.summary, state: s.detail.state }], total: 1 });
      case c:
        return json(route, s.detail);
      case `${c}/events`:
        return json(route, s.events);
      case `${c}/snapshot`:
        return json(route, recorded.snapshot);
      case `${c}/runs`:
        return json(route, recorded.runs);
      case `${c}/plan`:
        return json(route, s.view);
      case `${c}/approvals`:
        return json(route, { approvals: [], tasks: [] });
      case `${c}/attempts`:
      case `${c}/escalations`:
        return json(route, []);
      default:
        return json(route, { error: 'not_found', detail: 'Not on the stub' }, 404);
    }
  });
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

// A live page's first visit offers the trial ("New here?"), which would cover the case: it was seen before
test.beforeEach(({ context }) =>
  context.addInitScript(() => localStorage.setItem('shutter:live-welcome:v1', '2026-11-02T09:00:00Z')),
);

test.describe(`picking up after a restart or a lost answer ${area.tag}`, () => {
  test('says the restart under the progress strip and in the audit trail, and is decided as before', async ({
    page,
  }) => {
    const s = restarted();
    await stub(page, s);
    await openCase(page);
    const notice = page.getByTestId('case-restart');
    await expect(notice).toContainText('The production restarted during this case');
    await expect(notice).toContainText(
      /while this case was waiting for approval, and nothing has moved since\. A clean stop keeps the approval task: decide on the plan as before\./,
    );
    expect(await audit(page)).toEqual([]);
    await shot(page, 'U145-05-restart-notice-1280-light');
    await page.getByRole('tab', { name: 'Audit trail' }).click();
    const timeline = page.getByRole('region', { name: 'Timeline' });
    await expect(timeline.getByText('Production started', { exact: true })).toBeVisible();
    // Decided as before: the notice goes once the case moves on
    await page.getByTestId('case-action').click();
    const review = page.getByRole('dialog', { name: 'Approve the resend: plan v1' });
    await review.getByRole('button', { name: 'Approve the resend' }).click();
    await expect(page.getByRole('dialog')).toHaveCount(0);
    await expect(notice).toHaveCount(0);
    expect(s.recorded).toBe(1);
  });

  test('a decision whose answer never came is sent again under the same key and recorded once', async ({
    page,
  }) => {
    const s = restarted();
    s.drop = 'before';
    await stub(page, s);
    await openCase(page);
    await page.getByTestId('case-action').click();
    const review = page.getByRole('dialog', { name: 'Approve the resend: plan v1' });
    await review.getByRole('textbox', { name: /Comment/ }).fill('Checked the ward');
    await review.getByRole('button', { name: 'Approve the resend' }).click();
    const said = review.getByTestId('review-error');
    await expect(said).toContainText(
      /^No answer came back \(.+\), so this page can't tell whether your decision was recorded\. Pressing "Approve the resend" again sends the same decision under the same key/,
    );
    await expect(review.getByRole('textbox', { name: /Comment/ })).toHaveAttribute('readonly', '');
    expect(await audit(page)).toEqual([]);
    await shot(page, 'U145-05-answer-lost-1280-light');
    await review.getByRole('button', { name: 'Approve the resend' }).click();
    await expect(page.getByRole('dialog')).toHaveCount(0);
    await expect(page.getByText('Approved by approver')).toBeVisible();
    expect(s.sent).toHaveLength(2);
    expect(s.sent[1]).toEqual(s.sent[0]);
    expect(s.recorded).toBe(1);
  });

  test('a decision recorded whose answer was lost is never called undecided', async ({ page }) => {
    const s = restarted();
    s.drop = 'after';
    await stub(page, s);
    await openCase(page);
    await page.getByTestId('case-action').click();
    const review = page.getByRole('dialog', { name: 'Approve the resend: plan v1' });
    await review.getByRole('button', { name: 'Approve the resend' }).click();
    const refusal = review.getByTestId('review-refusal');
    await expect(refusal).toContainText(
      'No answer came back for your decision, and the case has changed since: the change may be your decision, recorded. The Audit trail says who decided.',
    );
    await review.getByRole('button', { name: 'Review current plan' }).click();
    await expect(review.getByTestId('review-current-gone')).toHaveText(
      'The case is no longer waiting for a decision: it is approved now. Your decision may be what moved it: the Audit trail says who decided.',
    );
    await expect(review).not.toContainText('Nothing was decided');
    expect(await audit(page)).toEqual([]);
    await shot(page, 'U145-05-answer-lost-moved-1280-light');
    expect(s.sent).toHaveLength(1);
    expect(s.recorded).toBe(1);
  });
});
