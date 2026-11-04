import { expect, test, type Locator, type Page } from '@playwright/test';
import { audit, choosePastel, MODES } from './axe';
import { skipWelcome } from './guide';
import { go } from './helpers';

/**
 * "What this agent was sent and did" on the demo build, always the trial: the recording behind a board member's run,
 * opened from its card on S8's board. The live side (no control on a live page) is in RunRecording.test.tsx; trial.spec.ts
 * holds the entry chunk and keeps recordings out of a live page's scripts.
 */

test.beforeEach(({ page }) => skipWelcome(page));

async function encounterCard(page: Page) {
  await go(page, '/cases/C-000008');
  const card = page.getByRole('region', { name: 'Encounter Integrity' });
  await expect(card.getByRole('button', { name: 'Show the recording' })).toBeVisible();
  return card;
}

async function openRecording(card: Locator) {
  await card.getByRole('button', { name: 'Show the recording' }).click();
  const panel = card.getByRole('region', { name: 'What this agent was sent and did' });
  await expect(panel).toBeVisible();
  return panel;
}

/** Opens a part of the panel and waits for its opening to finish. */
async function openPart(panel: Locator, name: string | RegExp) {
  const part = panel.getByRole('button', { name });
  await part.click();
  await expect(part).toHaveAttribute('aria-expanded', 'true');
  await expect(panel.locator('[data-tech-detail="open"]').first()).toBeVisible();
}

test.describe('the recording on a laptop', () => {
  test.use({ viewport: { width: 1280, height: 800 } });

  test("reaches GetWardState's WARD-C in two clicks from the case, and sends no request", async ({
    page,
  }) => {
    const sent: string[] = [];
    const scripts: string[] = [];
    page.on('request', (r) => {
      const type = r.resourceType();
      if (type === 'script') scripts.push(new URL(r.url()).pathname);
      else if (['fetch', 'xhr', 'websocket', 'eventsource', 'ping'].includes(type)) sent.push(r.url());
    });
    const refused: string[] = [];
    page.on('console', (m) => {
      if (/Content Security Policy|Refused to/i.test(m.text())) refused.push(m.text());
    });
    const card = await encounterCard(page);
    const before = scripts.length;
    const origin = new URL(page.url()).origin;
    const panel = await openRecording(card);
    await expect(panel.getByTestId('recording-proof')).toContainText(
      'Recorded live on 25 Oct 2026 as case C-000112 on claude-opus-5-5; no model was called now.',
    );
    await expect(panel.getByRole('link', { name: /Its public file/ })).toHaveAttribute(
      'href',
      /fixtures\/records\/scenario-S8-ENC-1008-transfer-encounter-1\.json$/,
    );
    await expect(panel.getByTestId('recording-catalogue')).toContainText(
      "The request includes the catalogue's match and its preferred outcome, as advice",
    );
    await expect(panel.getByTestId('recording-catalogue')).toContainText("Conformance's dissent");
    await expect(panel.getByTestId('recording-limits')).toContainText('not its reasoning');
    await openPart(panel, /^What it did/);
    const ward = panel.locator('[data-tool="GetWardState"]');
    await expect(ward).toBeVisible();
    await expect(ward).toContainText('"ward": "WARD-C"');
    await expect(ward).toContainText('"version": 2');
    await expect(panel.getByTestId('recording-last-message')).toBeVisible();

    // Opening it loaded its code and two recordings, its own and the plan's, as scripts of the page's own origin
    const loaded = scripts.slice(before);
    expect(loaded.filter((s) => /RunRecording-/.test(s))).toHaveLength(1);
    expect(loaded.filter((s) => /scenario-S8-ENC-1008-transfer-/.test(s))).toHaveLength(2);
    expect(sent).toEqual([]);
    expect(refused).toEqual([]);
    expect(page.url().startsWith(origin)).toBe(true);
    const journal = await page.evaluate(() => window.shutterTrial?.journal.counts());
    expect(journal).toMatchObject({ refused: 0, violations: 0 });
  });

  test("reads at the board's full width, and closes back into its column", async ({ page }) => {
    const card = await encounterCard(page);
    const closed = (await card.boundingBox())!.width;
    const panel = await openRecording(card);
    const wide = (await card.boundingBox())!.width;
    expect(wide).toBeGreaterThan(closed * 2);
    await card.getByRole('button', { name: 'Hide the recording' }).click();
    await expect(panel).toHaveCount(0);
    expect((await card.boundingBox())!.width).toBe(closed);
  });

  test('opens without motion when the reader asks for less', async ({ browser }) => {
    const context = await browser.newContext({
      reducedMotion: 'reduce',
      viewport: { width: 1280, height: 800 },
      baseURL: test.info().project.use.baseURL,
    });
    const page = await context.newPage();
    await skipWelcome(page);
    const panel = await openRecording(await encounterCard(page));
    await openPart(panel, /^What it did/);
    await expect(panel.locator('[data-tool="GetWardState"]')).toBeVisible();
    await context.close();
  });

  test("says it quietly when the panel's code cannot load, and keeps the case page", async ({ page }) => {
    await page.route(/\/RunRecording-[^/]*\.js$/, (route) => route.abort());
    const card = await encounterCard(page);
    await card.getByRole('button', { name: 'Show the recording' }).click();
    await expect(card.getByRole('link', { name: /public recordings/ })).toHaveAttribute(
      'href',
      /tree\/main\/fixtures\/records$/,
    );
    await expect(page.getByRole('alert')).toHaveCount(0);
    await expect(page.getByRole('heading', { name: 'Case C-000008', exact: true })).toBeVisible();
    await expect(page.getByRole('region', { name: 'Coordinator' })).toBeVisible();
  });

  test('says it quietly when a recording cannot load', async ({ page }) => {
    await page.route(/\/scenario-S8-[^/]*\.js$/, (route) => route.abort());
    const card = await encounterCard(page);
    await card.getByRole('button', { name: 'Show the recording' }).click();
    await expect(card.getByRole('link', { name: /public recordings/ })).toBeVisible();
    await expect(page.getByRole('alert')).toHaveCount(0);
    await expect(page.getByRole('region', { name: 'Coordinator' })).toBeVisible();
  });
});

test.describe('the recording on a phone', () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test('wraps its long JSON inside the card, with no sideways scroll', async ({ page }) => {
    const card = await encounterCard(page);
    const panel = await openRecording(card);
    for (const part of ['Its instructions', 'Its request', /^What it did/]) await openPart(panel, part);
    await expect(panel.locator('[data-tool="GetWardState"]')).toContainText('WARD-C');
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
    const edge = (await card.boundingBox())!;
    const blocks = panel.locator('pre');
    expect(await blocks.count()).toBeGreaterThan(8);
    for (const block of await blocks.all()) {
      expect(await block.evaluate((e) => e.scrollWidth <= e.clientWidth)).toBe(true);
      const box = (await block.boundingBox())!;
      expect(box.x + box.width).toBeLessThanOrEqual(edge.x + edge.width);
    }
  });
});

for (const { colorScheme, contrast, palette } of MODES) {
  const mode = `${palette === 'pastel' ? 'pastel' : colorScheme}${contrast === 'more' ? ', high contrast' : ''}`;
  test.describe(`accessibility of the recording (axe-core, WCAG 2.1 A/AA), ${mode}`, () => {
    test.use({ colorScheme, contrast, viewport: { width: 1280, height: 800 } });
    if (palette === 'pastel') test.beforeEach(({ page }) => choosePastel(page));

    test('with the panel and all its parts open', async ({ page }) => {
      const panel = await openRecording(await encounterCard(page));
      for (const part of ['Its instructions', 'Its request', /^What it did/]) await openPart(panel, part);
      await expect(panel.locator('[data-tool="GetWardState"]')).toBeVisible();
      await expect(panel.getByTestId('recording-catalogue')).toContainText('dissent');
      expect(await audit(page)).toEqual([]);
    });
  });
}
