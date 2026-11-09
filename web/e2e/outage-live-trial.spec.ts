import { expect, test, type Page, type Route } from '@playwright/test';
import fixtures from '../src/mocks/fixtures.json' with { type: 'json' };
import type { Outage, OutageRow } from '../src/features/incidents/outage/types';
import { audit } from './axe';
import { area } from './areas/incidents';

/**
 * The Incidents page's receiver outages live, against a stand-in for a 1.4.0 server, on the build IRIS serves (the
 * `iris-trial` project picks this file up by its name's ending: only that build has a live page, and the recorded trial
 * answers the outage routes not_in_trial on purpose). The stub answers `/api/shutter` in the browser with three outages,
 * one per state of the send (CONTRACTS 17.8): an offered set at a receiver whose duplicates are unknown, where the
 * approval asks for the receiver check and each message offers Already handled by hand; a run sending one message at a
 * time; and a run that stopped at a failed resend, after one message the receiver reported it already held. It answers
 * the approval and the hand closure as the server does. Nothing here reaches IRIS.
 */

const NOW = new Date().toISOString().replace(/\.\d+Z$/, 'Z');
const MINUTES_AGO = (n: number) => new Date(Date.now() - n * 60_000).toISOString().replace(/\.\d+Z$/, 'Z');

interface Row {
  headerId: string;
  controlId: string;
  timeCreated: string;
  status: string;
  attempts: string;
  reason: string;
  patient: { id: string; authority: string } | null;
  sibling: null;
  acts: string[];
  closure: string | null;
  closedBy: string | null;
  closedAt: string | null;
}

const row = (headerId: string, controlId: string, reason = '', more: Partial<Row> = {}): Row => ({
  headerId,
  controlId,
  timeCreated: '2026-11-09 03:12:00',
  status: 'Error',
  attempts: 'never_opened',
  reason,
  patient: { id: '9997001001', authority: 'NHS' },
  sibling: null,
  acts: [],
  closure: null,
  closedBy: null,
  closedAt: null,
  ...more,
});

const reading = (receiver: string) => ({
  receiver,
  namespace: 'LABSITE',
  item: receiver,
  reading: 'healthy',
  status: 'OK',
  adapterState: 'connected',
  queue: 0,
  retry: 'bounded',
  checkedAt: NOW,
});

const resend = (
  runId: string,
  position: number,
  controlId: string,
  state: string,
  closure: string | null,
  words: string | null,
  caseId: string | null = null,
) => ({
  runId,
  position,
  headerId: String(800 + position),
  controlId,
  newHeaderId: closure ? String(900 + position) : null,
  state,
  closure,
  words,
  by: 'approver',
  at: MINUTES_AGO(4 - position),
  caseId,
});

const lists = (offered: OutageRow[] = [], closed: OutageRow[] = []) => ({
  queued: [],
  offered,
  reached: [],
  refused: [],
  closed,
});

const words = (first: string, doLine: string | null = null) => ({
  first,
  do: doLine,
  call: 'Call: the laboratory on 01632 960998. Approver here: approver. An operator can do nothing here, which is safe.',
  critical:
    "Shutter does not assess clinical urgency. If delayed reporting may require clinical action, contact the laboratory using the site's critical-results and downtime procedure. Do not re-enter or amend a result solely from this page.",
});

const BY_HAND = { acts: ['handled_by_hand'] };

/** The offered set at a receiver whose duplicates are unknown: two results, each with Already handled by hand. */
function offered(): Outage {
  return {
    id: '7',
    receiver: 'Results Out',
    namespace: 'LABSITE',
    item: 'Results Out',
    state: 'offered',
    kind: 'down',
    openedAt: MINUTES_AGO(40),
    closedAt: null,
    pausedUntil: null,
    readings: reading('Results Out'),
    alerts: [],
    lists: lists([
      row('41', 'N51', 'Shutter tried at 03:20; the connection never opened', BY_HAND),
      row('44', 'N52', '', BY_HAND),
    ]),
    openCases: [],
    version: 3,
    set: { status: 'computed', reason: null, digest: 'sha256:set7', computedAt: MINUTES_AGO(1) },
    approvable: true,
    approval: null,
    sentByShutter: 0,
    acts: ['pause', 'read_again', 'close', 'handled_by_hand'],
    resends: [],
    outcome: null,
    words: words(
      'Results Out was unreachable from 03:12 to 03:52. The engine does not retry at this operation: the 2 failed messages will not go by themselves. One approval can have the engine send them again, in order.',
      'Do: check the lab system for each message first. At this receiver a duplicate is unknown: before approving, check the receiver for each message. For one already entered by hand, choose Already handled by hand; Shutter then sends nothing for it.',
    ),
  };
}

/** A run under way: one sent, one sending, one waiting. */
function sending(): Outage {
  return {
    ...offered(),
    id: '8',
    receiver: 'Microbiology Out',
    item: 'Microbiology Out',
    readings: reading('Microbiology Out'),
    state: 'sending',
    version: 5,
    lists: lists(),
    set: { status: 'computed', reason: null, digest: 'sha256:set8', computedAt: MINUTES_AGO(3) },
    approval: {
      id: 'R8-4',
      by: 'approver',
      givenAt: MINUTES_AGO(3),
      goodUntil: MINUTES_AGO(-12),
      digest: 'sha256:set8',
      note: 'Checked with the duty biomedical scientist: none entered by hand',
    },
    acts: ['pause', 'close'],
    resends: [
      resend(
        'R8-4',
        1,
        'M71',
        'completed',
        'sent',
        'Resent by Shutter at 03:58 under approval R8-4 by approver; new header 901 Completed.',
        'C-000031',
      ),
      resend('R8-4', 2, 'M72', 'sending', null, null),
      resend('R8-4', 3, 'M73', 'approved', null, null),
    ],
    words: words(
      "The engine's connection recovered at 03:52. Shutter is sending the approved messages one at a time.",
    ),
  };
}

/** A run that stopped: one sent, one the receiver already held, one failed, one not sent. */
function stopped(): Outage {
  return {
    ...offered(),
    id: '9',
    receiver: 'Orders Out',
    item: 'Orders Out',
    readings: reading('Orders Out'),
    state: 'needs_person',
    version: 9,
    lists: lists(
      [],
      [
        row(
          '62',
          'O62',
          'Already delivered: the receiver reported it already holds this message (MSA-3: ALREADY HELD, entered by hand); the engine never delivered it by this route, and a hand entry would explain it. Shutter has not compared the stored result or amendment.',
          { closure: 'already_delivered', closedBy: 'system', closedAt: MINUTES_AGO(2) },
        ),
      ],
    ),
    set: {
      status: 'not_computed',
      reason: 'the resend of header 803 (new header 903) ended Suspended: the rest were not sent',
      digest: null,
    },
    approvable: true,
    approval: {
      id: 'R9-8',
      by: 'approver',
      givenAt: MINUTES_AGO(6),
      goodUntil: MINUTES_AGO(-9),
      digest: 'sha256:set9',
      note: 'The lab confirmed none of these were keyed in',
    },
    acts: ['pause', 'read_again', 'close'],
    resends: [
      resend(
        'R9-8',
        1,
        'O61',
        'completed',
        'sent',
        'Resent by Shutter at 03:55 under approval R9-8 by approver; new header 901 Completed.',
      ),
      resend(
        'R9-8',
        2,
        'O62',
        'closed_as_present',
        'already_delivered',
        'Already delivered: the receiver reported it already holds this message (MSA-3: ALREADY HELD, entered by hand); the engine never delivered it by this route, and a hand entry would explain it. Shutter has not compared the stored result or amendment.',
        'C-000032',
      ),
      resend(
        'R9-8',
        3,
        'O63',
        'failed',
        'failed',
        'new header 903 ended Suspended (the receiver answered AE: Refused by the application)',
        'C-000033',
      ),
      resend('R9-8', 4, 'O64', 'stopped', null, 'not sent: the run stopped'),
    ],
    words: words(
      "The engine's connection recovered at 03:52. A resend failed, and Shutter sent nothing more: a person reads the trace.",
      'Do: read the failed message in the Message Viewer with the laboratory before anything more is sent.',
    ),
  };
}

const ME = {
  approver: {
    username: 'approver',
    operator: true,
    approver: true,
    can: { operate: true, approve: true, configure: true, scenarios: true, liveAgents: true },
  },
  operator: {
    username: 'operator',
    operator: true,
    approver: false,
    can: { operate: true, approve: false, configure: false, scenarios: true, liveAgents: true },
  },
};

interface Post {
  path: string;
  body: Record<string, unknown>;
  csrf: string | null;
  key: string | null;
}

/** The stand-in for a 1.4.0 server: the three outages, and the approval and the hand closure as the server answers them. */
async function stubServer(page: Page, who: keyof typeof ME = 'approver') {
  const outages: Record<string, Outage> = {
    '7': offered(),
    '8': sending(),
    '9': stopped(),
  };
  const posts: Post[] = [];
  const unknown: string[] = [];
  const json = (route: Route, body: unknown, status = 200) => route.fulfill({ status, json: body });
  await page.route('**/api/shutter/**', async (route) => {
    const request = route.request();
    const url = new URL(request.url());
    const path = url.pathname.replace(/^.*\/api\/shutter/, '');
    if (request.method() === 'POST') {
      const body = (request.postDataJSON() ?? {}) as Record<string, unknown>;
      posts.push({
        path,
        body,
        csrf: request.headers()['x-requested-with'] ?? null,
        key: request.headers()['idempotency-key'] ?? null,
      });
      const approval = /^\/outages\/(\d+)\/approvals$/.exec(path);
      const act = /^\/outages\/(\d+)\/acts$/.exec(path);
      const o = outages[(approval ?? act)?.[1] ?? ''];
      if (!o) return json(route, { error: 'not_found', detail: 'Not on the stub' }, 404);
      if (body.version !== o.version)
        return json(
          route,
          {
            error: 'version_changed',
            detail: 'The outage has moved on: read it again',
            currentVersion: o.version,
          },
          409,
        );
      if (approval) {
        if (o.acts.includes('handled_by_hand') && body.receiverChecked !== true)
          return json(
            route,
            {
              error: 'receiver_check_needed',
              detail:
                'At this receiver a duplicate is unknown: check the receiver for these messages first, and say so with the approval.',
            },
            409,
          );
        const runId = `R${o.id}-${o.version}`;
        Object.assign(o, {
          state: 'sending',
          version: o.version + 1,
          acts: ['pause', 'close'],
          approval: {
            id: runId,
            by: 'approver',
            givenAt: NOW,
            goodUntil: NOW,
            digest: o.set.digest,
            note: body.note,
          },
          resends: o.lists.offered.map((r, i) => ({
            ...resend(runId, i + 1, r.controlId, i === 0 ? 'sending' : 'approved', null, null),
            headerId: r.headerId,
          })),
          lists: lists(),
        });
        return json(route, o);
      }
      if (body.act === 'handled_by_hand') {
        const found = o.lists.offered.find((r) => r.headerId === body.headerId);
        if (!found)
          return json(
            route,
            { error: 'bad_request', detail: 'headerId must be a message the set offers' },
            400,
          );
        const text = `Handled by hand, recorded by approver at 04:01: ${String(body.note)}. Shutter sent nothing for it.`;
        o.lists = lists(
          o.lists.offered.filter((r) => r !== found),
          [
            ...(o.lists.closed ?? []),
            {
              ...found,
              acts: [],
              reason: text,
              closure: 'handled_by_hand',
              closedBy: 'approver',
              closedAt: NOW,
            },
          ],
        );
        o.resends = [
          ...(o.resends ?? []),
          {
            ...resend(`H${o.id}`, 0, found.controlId, 'handled_by_hand', 'handled_by_hand', text),
            headerId: found.headerId,
            newHeaderId: null,
          },
        ];
        o.version += 1;
        return json(route, o);
      }
      return json(route, { error: 'bad_request', detail: 'Not on the stub' }, 400);
    }
    switch (path) {
      case '/me':
        return json(route, ME[who]);
      case '/health':
        return json(route, { ok: true, demo: false, version: 'stub', checks: [] });
      case '/settings':
        return json(route, fixtures.settings);
      case '/site-profile':
        return json(route, fixtures.siteProfile);
      case '/scenarios':
        return json(route, { scenarios: fixtures.scenarios, run: null });
      case '/incidents': {
        const items = Object.values(fixtures.incidents).map((i) => i.summary);
        return json(route, { items, total: items.length });
      }
      // What the shell and the page also read: the case list's badge and the recovery switch, at rest
      case '/cases':
        return json(route, { items: [], total: 0 });
      case '/recovery-control':
        return json(route, {
          mode: 'enabled',
          generation: 1,
          stopped: false,
          stoppedAt: '',
          stoppedBy: '',
          stopReason: '',
          outstanding: [],
          outstandingCount: 0,
          readable: true,
          covers:
            'Rehearsals, recovery writes, blind-resend previews and outage resends that Shutter itself starts; a resend under way halts before its next message.',
          doesNotCover:
            "The hospital's ordinary feed and its retries, other systems or people writing to the receiver, Shutter's own records, and read-back of earlier attempts.",
        });
      case '/outages':
        return json(route, {
          items: Object.values(outages),
          receivers: Object.values(outages).map((o) => o.readings),
        });
      default:
        unknown.push(path);
        return json(route, { error: 'not_found', detail: 'Not on the stub' }, 404);
    }
  });
  return { posts, unknown };
}

async function openIncidents(page: Page) {
  await page.goto('./#/incidents');
  await expect(page.getByRole('heading', { name: 'Incidents', exact: true })).toBeVisible();
  await expect(page.getByRole('region', { name: 'Trial environment' })).toHaveCount(0);
  await expect(page.getByRole('region', { name: 'Outage 7, Results Out' })).toBeVisible();
}

/** Saves a picture for the record when E2E_SHOTS names a folder. */
async function shot(page: Page, name: string, target?: { screenshot: Page['screenshot'] }) {
  if (!process.env.E2E_SHOTS) return;
  await (target ?? page).screenshot({ path: `${process.env.E2E_SHOTS}/${name}.png`, animations: 'disabled' });
}

// A live page's first visit offers the trial ("New here?"), which would cover the page: it was seen before
test.beforeEach(({ page }) =>
  page.addInitScript(() => localStorage.setItem('shutter:live-welcome:v1', '2026-11-02T09:00:00Z')),
);

for (const colorScheme of ['light', 'dark'] as const)
  test.describe(`the outage cards' send, live, ${colorScheme} ${area.tag}`, () => {
    test.use({ colorScheme });

    for (const width of [1280, 390])
      test(`shows each state of the send at ${width} px, with no sideways scroll, and passes axe`, async ({
        page,
      }) => {
        await page.setViewportSize({ width, height: 900 });
        const stub = await stubServer(page);
        await openIncidents(page);
        const offeredCard = page.getByRole('region', { name: 'Outage 7, Results Out' });
        await expect(offeredCard.getByRole('button', { name: 'Approve the resend…' })).toBeVisible();
        await expect(
          offeredCard.getByRole('button', { name: /^Already handled by hand: control id / }),
        ).toHaveCount(2);

        const sendingCard = page.getByRole('region', { name: 'Outage 8, Microbiology Out' });
        await expect(sendingCard.getByRole('status')).toContainText(
          'Sending 2 of 3, one at a time, in order.',
        );
        await expect(sendingCard.getByRole('button', { name: /Approve/ })).toHaveCount(0);

        const stoppedCard = page.getByRole('region', { name: 'Outage 9, Orders Out' });
        await expect(stoppedCard.getByTestId('outage-failed-resend')).toHaveText(
          'Control id O63: New header 903 ended Suspended (the receiver answered AE: Refused by the application). Nothing more was sent; a person reads the trace.',
        );
        const ledger = stoppedCard.getByRole('list', { name: /Each message sent, in order/ });
        await expect(ledger.getByRole('listitem')).toHaveCount(4);
        await expect(ledger.getByRole('listitem').nth(1)).toContainText('Already delivered');
        await expect(ledger.getByRole('listitem').nth(2)).toContainText('Failed');
        await expect(ledger.getByRole('listitem').nth(3)).toContainText('Not sent');
        await expect(stoppedCard.getByTestId('outage-closed')).toContainText(
          'Control id O62 (header 62)Already delivered',
        );
        await expect(stoppedCard.getByRole('button', { name: /Approve|Already handled/ })).toHaveCount(0);

        const sideways = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
        expect(sideways).toBeLessThanOrEqual(0);
        expect(await audit(page)).toEqual([]);
        await shot(page, `outages-${width}-${colorScheme}`, page.getByTestId('outages'));
        expect(stub.unknown).toEqual([]);
      });

    test('approves the set only once the receiver is checked, then reads it as sending', async ({ page }) => {
      const stub = await stubServer(page);
      await openIncidents(page);
      const card = page.getByRole('region', { name: 'Outage 7, Results Out' });
      await card.getByRole('button', { name: 'Approve the resend…' }).click();
      const dialog = page.getByRole('dialog', { name: 'Approve the resend' });
      await expect(dialog.getByText('Live system')).toBeVisible();
      await expect(dialog.getByTestId('confirm-consequence')).toHaveText(
        'This has the engine send these 2 messages to Results Out again, one at a time, in this order: each is the stored message, unchanged.',
      );
      // The note has the focus, and the keyboard reaches the check and the approval
      const note = dialog.getByRole('textbox', { name: /What was checked, and with whom/ });
      await expect(note).toBeFocused();
      await note.fill('Checked both in the lab system with the duty biomedical scientist');
      const approve = dialog.getByRole('button', { name: 'Approve and resend' });
      await expect(approve).toBeDisabled();
      const check = dialog.getByRole('checkbox', {
        name: 'I checked the receiver for each of these messages',
      });
      await expect(check).toHaveAccessibleDescription(/could be filed twice/);
      await check.focus();
      await page.keyboard.press('Space');
      await expect(approve).toBeEnabled();
      expect(await audit(page)).toEqual([]);
      if (colorScheme === 'dark') await shot(page, 'approve-dialog-1280-dark');
      else await shot(page, 'approve-dialog-1280-light');
      await approve.click();
      await expect(dialog).toHaveCount(0);
      expect(stub.posts).toEqual([
        {
          path: '/outages/7/approvals',
          body: {
            digest: 'sha256:set7',
            note: 'Checked both in the lab system with the duty biomedical scientist',
            version: 3,
            receiverChecked: true,
          },
          csrf: 'Shutter',
          key: expect.any(String),
        },
      ]);
      await expect(card.getByRole('status')).toContainText('Sending 1 of 2, one at a time, in order.');
      await expect(card.getByRole('button', { name: /Approve|Already handled/ })).toHaveCount(0);
    });

    test('closes one message as already handled by hand after a confirmation, sending nothing', async ({
      page,
    }) => {
      const stub = await stubServer(page);
      await openIncidents(page);
      const card = page.getByRole('region', { name: 'Outage 7, Results Out' });
      await card.getByRole('button', { name: 'Already handled by hand: control id N52' }).click();
      const dialog = page.getByRole('dialog', { name: 'Already handled by hand' });
      await expect(dialog.getByTestId('confirm-consequence')).toHaveText(
        'Shutter will send nothing for control id N52 (header 44), take it off the list and close its cases as handled by hand.',
      );
      const confirm = dialog.getByRole('button', { name: 'Close it, send nothing' });
      await expect(confirm).toBeDisabled();
      await dialog
        .getByRole('textbox', { name: /What you checked at the receiver/ })
        .fill('Entered by hand at 03:40 by the lab, seen on its screen');
      expect(await audit(page)).toEqual([]);
      await shot(page, `handled-by-hand-dialog-1280-${colorScheme}`);
      await confirm.click();
      await expect(dialog).toHaveCount(0);
      expect(stub.posts).toEqual([
        {
          path: '/outages/7/acts',
          body: {
            act: 'handled_by_hand',
            headerId: '44',
            note: 'Entered by hand at 03:40 by the lab, seen on its screen',
            version: 3,
          },
          csrf: 'Shutter',
          key: expect.any(String),
        },
      ]);
      await expect(card.getByTestId('outage-closed')).toContainText(
        'Control id N52 (header 44)Handled by hand',
      );
      await expect(card.getByRole('button', { name: /^Already handled by hand: control id / })).toHaveCount(
        1,
      );
      await expect(card.getByTestId('outage-resends')).toContainText('Closed by hand, nothing sent (1)');
    });
  });

test(`shows an operator the cards with no control of the send ${area.tag}`, async ({ page }) => {
  await stubServer(page, 'operator');
  await openIncidents(page);
  const outages = page.getByTestId('outages');
  await expect(outages.getByRole('region', { name: 'Outage 9, Orders Out' })).toContainText(
    'A resend failed',
  );
  await expect(
    outages.getByRole('button', { name: /Approve|Already handled|Pause|Close|Read again/ }),
  ).toHaveCount(0);
});
