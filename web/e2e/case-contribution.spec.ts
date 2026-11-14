import { expect, test, type Page } from '@playwright/test';
import { audit } from './axe';
import { skipWelcome } from './guide';
import { go, signIn } from './helpers';

/**
 * What the agents contributed, on the case (the clarity review of 13 Nov, item 2), in the trial: on S2, S3 and S8 the
 * decision receipt names who proposed the plan, its recorded reason opens under it with the evidence it cites as links
 * to the case's own Evidence tab, and the gate's result and the writes are facts of their own. Checked at a laptop's
 * and a phone's width, light and dark, with axe; a plan the site's policy wrote names no agent; and every run on the
 * board is a browser recording, as the case's header says.
 */

// The guide's welcome would cover the screens these tests are about; guide.spec.ts tests it
test.beforeEach(({ page }) => skipWelcome(page));

const CASES = [
  {
    id: 'C-000002',
    scenario: 'S2',
    proposal: 'Resend the PAS transfer to WARD-B, once',
    reason: 'Why: Not delivered, still current',
    words: /^E2 preferred \(RP-2\.1\): the transfer was not committed \(no receipt\)/,
    gate: 'Eligible for approval',
    evidence: ['Encounter', 'Receipt'],
  },
  {
    id: 'C-000003',
    scenario: 'S3',
    proposal: 'Reconcile: no write to the receiver',
    reason: 'Why: Committed after all',
    words: /^Under RP-3\.1 the receipt decides whether a movement was committed\./,
    gate: 'Passed: no write',
    evidence: ['Encounter', 'Receipt'],
  },
  {
    id: 'C-000008',
    scenario: 'S8',
    proposal: 'Escalate: no write to the receiver',
    reason: 'Why: Two sources at the same time',
    words: /^E7 matches: another source system \(BEDMGR\) applied a movement with the same event time/,
    gate: 'Passed: no write',
    evidence: ['Encounter', 'Receipt', 'Timeline'],
  },
] as const;

/** Opens a case with its Outcome band open (a closed case's starts closed) and its agent runs read. */
async function openCase(page: Page, id: string) {
  await signIn(page);
  await go(page, `/cases/${id}`);
  await expect(page.getByRole('heading', { name: `Case ${id}`, exact: true })).toBeVisible();
  await expect(page.getByRole('status')).toHaveCount(0);
  const band = page.getByRole('button', { name: 'Outcome', exact: true });
  if ((await band.getAttribute('aria-expanded')) !== 'true') await band.click();
  return page.getByRole('region', { name: 'Decision receipt' });
}

/** A fact of the receipt, by its name. */
const fact = (page: Page, name: string) =>
  page.locator('.receipt-fact').filter({ has: page.locator('dt', { hasText: new RegExp(`^${name}$`) }) });

for (const width of [1280, 360])
  for (const colorScheme of ['light', 'dark'] as const)
    test.describe(`the agents' contribution on the receipt, ${width} px, ${colorScheme}`, () => {
      test.use({ colorScheme, viewport: { width, height: 800 } });

      for (const c of CASES)
        test(`${c.scenario}: the proposal, its reason and evidence, the gate result and the writes @case`, async ({
          page,
        }) => {
          const receipt = await openCase(page, c.id);
          // Who proposed, what, what the gate said and what was written: four facts, no JSON opened
          await expect(fact(page, "Coordinator agent's proposal")).toContainText(c.proposal);
          await expect(fact(page, 'Gate')).toContainText(c.gate);
          await expect(fact(page, 'Writes')).toContainText('0 writes');
          // The facts under What happened name their evidence
          const behind = page.getByRole('group', { name: 'The evidence this was read from' });
          await expect(behind.getByRole('button')).toHaveText([...c.evidence]);
          // The reason is closed at first, and opens from the keyboard under the proposal
          const toggle = receipt.getByRole('button', { name: c.reason });
          await expect(toggle).toHaveAttribute('aria-expanded', 'false');
          const body = page.locator('#proposal-reason');
          await expect(body).toBeHidden();
          await toggle.focus();
          await page.keyboard.press('Enter');
          await expect(toggle).toHaveAttribute('aria-expanded', 'true');
          await expect(
            body.getByText("The coordinator agent's reason, as its run recorded it"),
          ).toBeVisible();
          await expect(body.getByTestId('proposal-reason-words')).toHaveText(c.words);
          await expect(body.getByRole('button', { name: "See each agent's finding" })).toBeVisible();
          // The page itself never scrolls sideways, and nothing in the opened reason is cut off
          const wide = await page.evaluate(() => document.documentElement.scrollWidth);
          expect(wide).toBeLessThanOrEqual(width);
          const box = await body.boundingBox();
          expect(box!.x).toBeGreaterThanOrEqual(0);
          expect(box!.x + box!.width).toBeLessThanOrEqual(width);
          expect(await audit(page)).toEqual([]);
        });
    });

test.describe('the links from the receipt', () => {
  test('a fact under What happened opens its evidence on this case, with what was recorded @case', async ({
    page,
  }) => {
    await openCase(page, 'C-000008');
    await page
      .getByRole('group', { name: 'The evidence this was read from' })
      .getByRole('button', { name: 'Receipt' })
      .click();
    await expect(page.getByRole('tab', { name: 'Evidence' })).toHaveAttribute('aria-selected', 'true');
    await expect(page).toHaveURL(/#\/cases\/C-000008\?tab=evidence/);
    const heading = page.getByRole('heading', { name: "Downstream Out's receipt for this operation" });
    await expect(heading).toBeFocused();
    await expect(
      page.getByRole('button', { name: "Downstream Out's receipt for this operation: What was recorded" }),
    ).toHaveAttribute('aria-expanded', 'true');
  });

  test("the plan's catalogue entry and a section it cites open on the Evidence tab @case", async ({
    page,
  }) => {
    const receipt = await openCase(page, 'C-000008');
    await receipt.getByRole('button', { name: 'Why: Two sources at the same time' }).click();
    const body = page.locator('#proposal-reason');
    await body.getByRole('button', { name: 'Catalogue entry E7' }).click();
    await expect(page.getByRole('tab', { name: 'Evidence' })).toHaveAttribute('aria-selected', 'true');
    await expect(page.locator('#evidence-catalogue')).toBeFocused();
    await expect(
      page
        .locator('#evidence-catalogue')
        .getByRole('button', { name: 'Catalogue entry E7: why the plan follows it' }),
    ).toBeVisible();
  });

  test('a plan that follows an entry without citing it offers its sections, and no chip to a line that is not there @case', async ({
    page,
  }) => {
    const receipt = await openCase(page, 'C-000003');
    await receipt.getByRole('button', { name: 'Why: Committed after all' }).click();
    const body = page.locator('#proposal-reason');
    await expect(body.getByRole('button', { name: /^Catalogue entry/ })).toHaveCount(0);
    await body.getByRole('button', { name: 'Receipt' }).click();
    await expect(page.getByRole('tab', { name: 'Evidence' })).toHaveAttribute('aria-selected', 'true');
    await expect(
      page.getByRole('heading', { name: "Downstream Out's receipt for this operation" }),
    ).toBeFocused();
  });

  test("the reason leads to each agent's finding on the board, by touch on a phone @case", async ({
    browser,
  }) => {
    const context = await browser.newContext({ viewport: { width: 360, height: 800 }, hasTouch: true });
    const page = await context.newPage();
    await skipWelcome(page);
    const receipt = await openCase(page, 'C-000008');
    await receipt.getByRole('button', { name: 'Why: Two sources at the same time' }).tap();
    await page.locator('#proposal-reason').getByRole('button', { name: "See each agent's finding" }).tap();
    const board = page.getByRole('heading', { name: 'The board', exact: true });
    await expect(board).toBeFocused();
    await expect(board).toBeInViewport();
    await context.close();
  });
});

test.describe('no agent is claimed where none proposed', () => {
  test("a site policy case names the policy, with the policy's reason @case", async ({ page }) => {
    const receipt = await openCase(page, 'C-000028');
    await expect(fact(page, "Site policy's proposal, no agent")).toContainText(
      'Resend the PAS transfer to WARD-B, once',
    );
    await receipt.getByRole('button', { name: 'Why: Not delivered, still current' }).click();
    const body = page.locator('#proposal-reason');
    await expect(body.getByText("The site's policy gives this reason; no agent ran")).toBeVisible();
    await expect(body.getByText('No agent proposed this plan.')).toBeVisible();
    await expect(body.getByRole('button', { name: /finding/ })).toHaveCount(0);
    await expect(page.locator('#outcome')).not.toContainText(/agent's (proposal|reason)/);
    expect(await audit(page)).toEqual([]);
  });

  test('a Rules only case names the rules, with no reason to open @case', async ({ page }) => {
    const receipt = await openCase(page, 'C-000021');
    await expect(fact(page, "The rules' proposal, no agent")).toContainText(
      'Resend the PAS transfer to WARD-B, once',
    );
    await expect(fact(page, 'Writes')).toContainText('1 write');
    await expect(receipt.getByRole('button', { name: /^Why/ })).toHaveCount(0);
    await expect(page.locator('#outcome')).not.toContainText(/agent's (proposal|reason)/);
  });
});

test.describe('a run on the board, in the trial', () => {
  test('is a browser recording, as the case header says, and its tool calls are recorded ones @case', async ({
    page,
  }) => {
    await openCase(page, 'C-000008');
    await page.getByRole('button', { name: 'Details' }).click();
    await expect(page.getByText('Browser recording: no new inference')).toBeVisible();
    const board = page.getByRole('region', { name: 'The board' });
    const card = board.getByRole('region', { name: 'Conformance' });
    await expect(card).toContainText('Browser recording · claude-opus-5-5 · 14.7 s · 3 steps · 5 tool calls');
    await card.getByRole('button', { name: 'Show the finding' }).click();
    await board
      .getByRole('region', { name: 'Coordinator' })
      .getByRole('button', { name: 'Show the run' })
      .click();
    await expect(
      card.getByText('No model call now: this browser shows a recording of a run on claude-opus-5-5.'),
    ).toBeVisible();
    await expect(card.getByText('Recorded tool calls (5)')).toBeVisible();
    await expect(board.getByText('Recorded tool calls (2)')).toBeVisible();
    // Never a replay or a live run here: the trial runs nothing
    await expect(board).not.toContainText(/Recorded replay|Replay ·|Live model|Live ·/);
    expect(await audit(page)).toEqual([]);
  });
});
