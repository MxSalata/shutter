import { expect, test } from '@playwright/test';
import { skipWelcome } from './guide';
import { go, signIn } from './helpers';

/**
 * Settings and costs: the real cost first, the agents with their marks, the costs and the prices, and the second layer
 * the Technical switch opens.
 */

// The guide's welcome would cover the screens these tests are about; guide.spec.ts tests it
test.beforeEach(({ page }) => skipWelcome(page));

test.describe('Settings and costs @settings', () => {
  test('opens on what the real agents cost, and the zeros come last', async ({ page }) => {
    await signIn(page);
    await go(page, '/settings');
    const summary = page.getByRole('region', { name: 'Summary', exact: true });
    await expect(summary).toContainText('$0.34 to $0.50');
    await expect(summary).toContainText('100 runs');
    // The labels are drawn in capitals, which innerText reflects
    const text = (await summary.innerText()).toUpperCase();
    const at = [
      'A BOARD PASS WITH REAL AGENTS',
      'RECORDED WITH THE REAL AGENTS',
      'SPENT HERE',
      'REPLAYED RUNS',
    ].map((label) => text.indexOf(label));
    expect(at.every((i) => i >= 0)).toBe(true);
    expect([...at].sort((a, b) => a - b)).toEqual(at);
    await expect(summary.getByRole('link', { name: 'Evaluation' })).toBeVisible();
  });

  test('says where a replay comes from, in words that never call the trial live', async ({ page }) => {
    await signIn(page);
    await go(page, '/settings');
    const intro = page.getByTestId('agents-intro');
    await expect(intro).toContainText('IRIS AI Hub (build 154)');
    await expect(intro).toContainText('claude-opus-5-5');
    await expect(intro).toContainText('needs no model provider here');
    await expect(
      page.getByRole('table', { name: 'Production items that run an agent' }).getByRole('row'),
    ).toHaveCount(6);
    // What is read, not what a closed detail holds
    for (const name of ['Summary', 'Agents', 'Costs', 'Prices used for costs'])
      await expect(page.getByRole('region', { name, exact: true })).not.toContainText(/\blive\b/i, {
        useInnerText: true,
      });
  });

  test('puts the cases behind one line, and the table opens from it', async ({ page }) => {
    await signIn(page);
    await go(page, '/settings');
    const toggle = page.getByRole('button', { name: /^Every case \(\d+\)/ });
    await expect(toggle).toHaveAttribute('aria-expanded', 'false');
    await toggle.click();
    await expect(page.getByRole('table', { name: 'Costs by case' })).toBeVisible();
  });

  test('shows the stored source of a price on focus', async ({ page }) => {
    await signIn(page);
    await go(page, '/settings');
    await expect(page.getByText('List price, read 16 Oct 2026')).toHaveCount(4);
    await page.getByRole('button', { name: /^Source of claude-opus-5-5's prices/ }).focus();
    await expect(page.getByRole('tooltip')).toContainText('Anthropic list prices per million tokens');
  });

  test("carries the guide's targets on the Agents and Costs sections", async ({ page }) => {
    await signIn(page);
    await go(page, '/settings');
    await expect(page.locator('[data-tour="settings-agents"]')).toBeVisible();
    await expect(page.locator('[data-tour="settings-costs"]')).toBeVisible();
  });

  test('opens the production items, what the instance lacks and the API in Technical', async ({ page }) => {
    await signIn(page, { detail: 'technical' });
    await go(page, '/settings', { detail: 'technical' });
    await expect(page.getByRole('table', { name: 'Settings of the agent items' })).toBeVisible();
    await expect(
      page.getByText(/^Not on this instance: AI Hub, the live runner, a model provider\./),
    ).toBeVisible();
    await expect(page.getByText('Shutter.Agent.Coordinator', { exact: true })).toBeVisible();
    await expect(page.getByText('GET /api/shutter/settings', { exact: true })).toBeVisible();
    await expect(page.getByText('GET /api/shutter/costs', { exact: true })).toBeVisible();
    // How the modes work is prose: closed in both modes
    await expect(page.getByRole('button', { name: 'How the modes work' })).toHaveAttribute(
      'aria-expanded',
      'false',
    );
  });
});

test.describe('Settings and costs on a phone @settings', () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test('puts two tiles on a row, lets the cost range wrap, and scrolls nothing sideways', async ({
    page,
  }) => {
    await signIn(page);
    await go(page, '/settings');
    const tiles = page.getByRole('region', { name: 'Summary', exact: true }).locator('.stat-tile');
    await expect(tiles).toHaveCount(4);
    const tops = await tiles.evaluateAll((els) => els.map((e) => Math.round(e.getBoundingClientRect().top)));
    expect(tops[0]).toBe(tops[1]);
    expect(tops[2]).toBe(tops[3]);
    expect(tops[2]).toBeGreaterThan(tops[0]);
    await expect(page.getByText('$0.34 to $0.50')).toBeVisible();
    const sideways = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
    );
    expect(sideways).toBeLessThanOrEqual(0);
  });

  test('stacks the agents as compact rows and the prices one model at a time', async ({ page }) => {
    await signIn(page);
    await go(page, '/settings');
    const agents = page.getByRole('table', { name: 'Production items that run an agent' });
    const first = agents.getByRole('row').nth(1);
    await expect(first).toContainText('Conformance');
    await expect(first).toContainText('Replay');
    // The badge shares the name's line: their middles are level
    const [name, badge] = await first.getByRole('cell').evaluateAll((cells) =>
      cells.slice(0, 2).map((c) => {
        const r = c.getBoundingClientRect();
        return r.top + r.height / 2;
      }),
    );
    expect(Math.abs(name - badge)).toBeLessThanOrEqual(2);
    const prices = page.getByRole('table', { name: 'Prices per million tokens' });
    await expect(prices.getByRole('cell').first()).toBeVisible();
    const widths = await prices
      .getByRole('row')
      .evaluateAll((rows) => rows.map((r) => r.scrollWidth - r.clientWidth));
    expect(Math.max(...widths)).toBeLessThanOrEqual(0);
  });
});
