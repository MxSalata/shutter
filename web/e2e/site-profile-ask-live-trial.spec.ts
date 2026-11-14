import { expect, test, type Route } from '@playwright/test';
import fixtures from '../src/mocks/fixtures.json' with { type: 'json' };
import { audit } from './axe';

/**
 * "Ask Shutter about this" on a live Site profile, with a model: the button beside a receiver's tier opens the panel
 * beside the form and asks the question once, with the question in the summary of the screen, and the answer is
 * attributed to the AI Hub agent that gave it, its run named. The `iris-trial` project picks this file up by its name's
 * ending, since only the build IRIS serves has a live page; a stand-in answers `/api/shutter` in the browser and records
 * every call, so the test also proves that asking sent no profile.
 */

const ME = {
  username: 'approver',
  operator: true,
  approver: true,
  can: { operate: true, approve: true, configure: true, scenarios: true, liveAgents: true },
};

const QUESTION = 'What does tier 2 mean for Downstream Out, and what would another tier change?';
const ANSWER =
  "Tier 2 is operations: the policy's tier 2 row decides who releases a write to Downstream Out. Tier 3 would follow the clinical safety row instead.";

test.use({ viewport: { width: 1280, height: 900 } });

// A live page's first visit offers the trial ("New here?"), which would cover the form: it was seen before
test.beforeEach(({ page }) =>
  page.addInitScript(() => localStorage.setItem('shutter:live-welcome:v1', '2026-11-02T09:00:00Z')),
);

test('asks the tier’s question live, attributes the answer to the AI Hub agent and saves nothing', async ({
  page,
}) => {
  const sent: { method: string; path: string; body: unknown }[] = [];
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
        return json(route, fixtures.siteProfile);
      case 'GET /site-profile/history':
        return json(route, fixtures.siteProfileHistory);
      case 'GET /cases':
        return json(route, { items: [], total: 0 });
      case 'POST /page-questions':
        return json(
          route,
          { questionId: 'P-000301', page: 'site-profile', state: 'pending', askedBy: 'approver' },
          202,
        );
      case 'GET /page-questions/P-000301':
        return json(route, {
          questionId: 'P-000301',
          tier: 'page',
          page: 'site-profile',
          question: QUESTION,
          state: 'answered',
          askedBy: 'approver',
          askedAt: '2026-11-14T10:00:00Z',
          answeredAt: '2026-11-14T10:00:08Z',
          error: null,
          mode: 'live',
          model: 'claude-opus-5-5',
          costUsd: 0.004,
          ensMessageId: '4321',
          answer: { answer: ANSWER, cites: ['page'], confidence: 'high' },
        });
      default:
        return json(route, { error: 'not_found', detail: 'Not on the stub' }, 404);
    }
  });

  await page.goto('./#/site-profile');
  const receiver = page.getByRole('group', { name: 'Receiver 1: Downstream Out' });
  const button = receiver.getByRole('button', { name: 'Ask Shutter about this: The tier of Downstream Out' });
  await button.click();
  const panel = page.getByRole('region', { name: 'Ask Shutter', exact: true });
  const card = panel.getByRole('region', { name: 'The tier of Downstream Out' });
  await expect(card.getByText(ANSWER)).toBeVisible();
  await expect(
    card.getByText(
      'Answered live by the Explain agent on IRIS AI Hub, with claude-opus-5-5. Its run is message 4321 in the Management Portal.',
    ),
  ).toBeVisible();
  await expect(card.getByText(/Live questions and the agent's trace are logged/)).toBeVisible();
  await expect(card.getByRole('button', { name: 'Written explanation' })).toHaveAttribute(
    'aria-expanded',
    'false',
  );
  // One question, to the page question route, with the question it is about in the summary; no profile was sent
  expect(sent).toHaveLength(1);
  expect(sent[0]).toMatchObject({
    method: 'POST',
    path: '/page-questions',
    body: {
      page: 'site-profile',
      question: QUESTION,
      context: {
        page: 'site-profile',
        title: 'Site profile',
        focus: { question: 'The tier of Downstream Out', answer: 'Tier 2, operations' },
      },
    },
  });
  await expect(receiver.getByRole('radio', { name: /2, operations/ })).toBeChecked();
  await expect(page.getByRole('region', { name: 'Unsaved changes' })).toHaveCount(0);
  expect(await audit(page)).toEqual([]);
});
