import { expect, test, type Page, type Route } from '@playwright/test';
import fixtures from '../src/mocks/fixtures.json' with { type: 'json' };
import { audit } from './axe';

/**
 * Set up the site on a live system whose approver switched typed answers on: a person describes a receiver in their own
 * words, Ask Shutter drafts its description, kind and tier, the draft marks them, Undo is one press away, and the Site
 * profile's review lists them and keeps its Save until they are ticked as read. The `iris-trial` project picks this file
 * up by its name's ending, since only the build IRIS serves has a live page; a stand-in answers `/api/shutter` in the
 * browser and records every call, so the test also proves that nothing but the review's save sends a profile.
 */

const ME = {
  username: 'approver',
  operator: true,
  approver: true,
  can: { operate: true, approve: true, configure: true, scenarios: true, liveAgents: true },
};

const stored = fixtures.siteProfile as unknown as {
  version: number;
  profile: Record<string, unknown> & { model_content?: Record<string, unknown> };
};
/** The stored profile with the site's switch on, as an approver saved it; every tier's release a person's approval. */
const PROFILE = {
  ...stored,
  source: 'api',
  profile: {
    ...stored.profile,
    model_content: { ...(stored.profile.model_content ?? {}), setup_answers: true },
    policy: {
      '1': { single: 'approval', ordered: 'approval', interleaved: 'board' },
      '2': { single: 'approval', ordered: 'approval', interleaved: 'board' },
      '3': { single: 'approval', ordered: 'per_chain', interleaved: 'board' },
    },
  },
};

const TEXT = 'It is the ward whiteboard, it only shows where patients are now. Tier 2.';
const SAY = 'I read a ward whiteboard that keeps only where patients are now, at tier 2.';
const TURN = {
  turnId: 'ST-000301',
  conversation: 'SC-000301',
  receiver: 'Bed Board',
  text: TEXT,
  state: 'answered',
  baseVersion: stored.version,
  draftRevision: 2,
  askedBy: 'approver',
  askedAt: '2026-11-15T10:00:00Z',
  answeredAt: '2026-11-15T10:00:06Z',
  error: null,
  mode: 'live',
  model: 'claude-opus-5-5',
  costUsd: 0.006,
  ensMessageId: '4400',
  turn: {
    say: SAY,
    proposals: [
      {
        field: 'receivers[].system',
        receiver: 'Bed Board',
        to: 'the ward whiteboard',
        quote: 'the ward whiteboard',
        from: null,
      },
      {
        field: 'receivers[].category',
        receiver: 'Bed Board',
        to: 'current_state',
        quote: 'it only shows where patients are now',
        from: null,
      },
      { field: 'receivers[].tier', receiver: 'Bed Board', to: 2, quote: 'Tier 2', from: null },
    ],
    ask: { field: 'receivers[].applies', receiver: 'Bed Board' },
  },
};

interface Sent {
  method: string;
  path: string;
  body: unknown;
}

/** The stand-in for `/api/shutter`: who is signed in, the stored profile, the turn route and the save. */
async function standIn(page: Page): Promise<Sent[]> {
  const sent: Sent[] = [];
  const json = (route: Route, body: unknown, status = 200) => route.fulfill({ status, json: body });
  await page.route('**/api/shutter/**', async (route) => {
    const request = route.request();
    const path = new URL(request.url()).pathname.replace(/^.*\/api\/shutter/, '');
    if (request.method() !== 'GET')
      sent.push({ method: request.method(), path, body: request.postDataJSON() });
    switch (`${request.method()} ${path}`) {
      case 'GET /me':
        return json(route, ME);
      case 'GET /health':
        return json(route, { ok: true, demo: false, version: 'stub', checks: [] });
      case 'GET /settings':
        return json(route, fixtures.settings);
      case 'GET /site-profile':
        return json(route, PROFILE);
      case 'GET /site-profile/history':
        return json(route, fixtures.siteProfileHistory);
      case 'GET /cases':
        return json(route, { items: [], total: 0 });
      case 'POST /site-profile/setup-turns':
        return json(route, { turnId: TURN.turnId, conversation: TURN.conversation, state: 'pending' }, 202);
      case `GET /site-profile/setup-turns/${TURN.turnId}`:
        return json(route, TURN);
      case 'PUT /site-profile': {
        const { expectedVersion: _expected, ...profile } = request.postDataJSON() as Record<string, unknown>;
        return json(route, {
          ...PROFILE,
          profile,
          version: PROFILE.version + 1,
          updatedBy: 'approver',
          updatedAt: '2026-11-15T10:05:00Z',
        });
      }
      default:
        return json(route, { error: 'not_found', detail: 'Not on the stub' }, 404);
    }
  });
  return sent;
}

test.beforeEach(({ page }) =>
  page.addInitScript(() => localStorage.setItem('shutter:live-welcome:v1', '2026-11-02T09:00:00Z')),
);

const sideways = (page: Page) =>
  page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth);

for (const colorScheme of ['light', 'dark'] as const)
  for (const width of [1280, 360])
    test(`at ${width} px in ${colorScheme}: a typed answer is drafted, marked, undone and drafted again, then saved after the tick`, async ({
      page,
    }) => {
      await page.emulateMedia({ colorScheme });
      await page.setViewportSize({ width, height: 900 });
      const sent = await standIn(page);
      await page.goto('./#/site-setup');
      await expect(page.getByTestId('setup-ask-shutter-does')).toContainText(
        'It sets nothing else and saves nothing.',
      );
      await expect(
        page.getByRole('region', { name: 'Where this page stands' }).getByText(/Do not type patient details/),
      ).toBeVisible();
      await page.getByRole('button', { name: 'Add a receiver' }).click();
      await page.getByRole('textbox', { name: 'Production item' }).fill('Bed Board');
      await page
        .getByRole('region', { name: 'Which receiver? Name it by its production item.' })
        .getByRole('button', { name: 'Next question' })
        .click();
      // By keyboard: the box, then Send
      const box = page.getByRole('textbox', { name: 'Or answer in your own words' });
      await box.focus();
      await page.keyboard.type(TEXT);
      await page.keyboard.press('Tab');
      await expect(page.getByRole('button', { name: 'Send to Ask Shutter' })).toBeFocused();
      await page.keyboard.press('Enter');
      const exchange = page.getByRole('list', { name: 'Your answers in your own words: What it is' });
      await expect(exchange.getByText(SAY)).toBeVisible();
      await expect(exchange.getByText(/^Drafted: What it is, Kind of system, Tier\./)).toBeVisible();
      // The question it suggested next is open, and is a person's own
      const applies = page.getByRole('region', {
        name: 'Does it apply messages in arrival order or by event time?',
      });
      await expect(applies.getByText('Only a person sets this.')).toBeVisible();
      await expect(applies.getByRole('textbox', { name: 'Or answer in your own words' })).toHaveCount(0);
      expect(await sideways(page)).toBe(false);
      expect(await audit(page)).toEqual([]);
      // The draft: marked, with the words it was read from
      if (width < 1200) await page.getByRole('tab', { name: /^Draft/ }).click();
      await expect(page.getByTestId('setup-quote-category')).toContainText(
        'it only shows where patients are now',
      );
      await expect(page.locator('[data-row="tier"]')).toContainText('Drafted by Ask Shutter');
      expect(await audit(page)).toEqual([]);
      // Undo puts the three answers back as they were: unanswered
      await page.getByRole('button', { name: 'Undo the drafted answer: Tier' }).click();
      await expect(page.locator('[data-row="tier"]')).toContainText('Not answered');
      await expect(page.locator('[data-row="category"]')).toContainText('Not answered');
      // Typed again, then on to the review
      if (width < 1200) await page.getByRole('tab', { name: 'Conversation' }).click();
      await page
        .getByRole('region', { name: 'What is the system, in a few words?' })
        .getByRole('button', { name: 'Answer: What it is' })
        .click();
      await page.getByRole('textbox', { name: 'Or answer in your own words' }).fill(TEXT);
      await page.getByRole('button', { name: 'Send to Ask Shutter' }).click();
      await expect(exchange.getByText(/^Drafted: What it is, Kind of system, Tier\./)).toHaveCount(1);
      await page
        .getByRole('region', { name: 'Unsaved changes' })
        .getByRole('button', { name: 'Review and save…' })
        .click();
      const dialog = page.getByRole('dialog');
      const drafted = dialog.getByRole('list', { name: 'Drafted by Ask Shutter (3)' });
      await expect(drafted.getByRole('listitem')).toHaveCount(3);
      await expect(drafted).toContainText('Read from the words “Tier 2”');
      const save = dialog.getByRole('button', { name: /^Save version/ });
      await expect(save).toBeDisabled();
      expect(await audit(page)).toEqual([]);
      await dialog.getByRole('checkbox', { name: 'I have read the answers Ask Shutter drafted.' }).check();
      await save.click();
      await expect(page.getByText(/^Version \d+ saved$/)).toBeVisible();
      // What went out: two typed answers to the turn route, and one profile, by the review's save alone
      expect(sent.map((s) => `${s.method} ${s.path}`)).toEqual([
        'POST /site-profile/setup-turns',
        'POST /site-profile/setup-turns',
        'PUT /site-profile',
      ]);
      expect(sent[0].body).toMatchObject({ receiver: 'Bed Board', text: TEXT, baseVersion: stored.version });
      expect(sent[1].body).toMatchObject({ conversation: TURN.conversation });
      const saved = sent[2].body as { receivers: Record<string, unknown>[] };
      expect(saved.receivers.at(-1)).toEqual({
        name: 'Bed Board',
        system: 'the ward whiteboard',
        category: 'current_state',
        tier: 2,
        features: { conditional_writes: false, receipts: false, history: false, dry_run: false },
      });
      expect(JSON.stringify(saved)).not.toMatch(/quote|turnId|conversation/);
    });
