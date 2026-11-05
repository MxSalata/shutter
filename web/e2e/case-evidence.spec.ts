import { expect, test, type Page } from '@playwright/test';
import { skipWelcome } from './guide';
import { go, signIn } from './helpers';
import { area } from './areas/case-evidence';
import recordedAnswers from '../src/mocks/recorded-questions.json' with { type: 'json' };

/**
 * A case's Evidence and Audit trail tabs, and Ask about this case: the panel beside the case from 1440 px and a drawer
 * over it below, asking a suggested question, the trial's disabled box for a question of one's own, the What-if change
 * taken to the Site profile as a draft, a citation landing on its section of the Evidence tab, Escape, and the
 * full-screen sheet on a phone.
 */

// The recorded answers' own words, so a recording made again doesn't break the test: the first sentence of an answer.
type Recorded = {
  scenarios: Record<string, Record<string, { questions: Record<string, { answer: { answer: string } }> }>>;
};
const firstSentence = (scenario: string, receiver: string, turn: string) =>
  (recordedAnswers as unknown as Recorded).scenarios[scenario][receiver].questions[turn].answer.answer.split(
    /(?<=\.)\s/,
  )[0];

/** The bottom of the page's header (the trial's banner included), which a scrolled-to section must clear. */
async function headerBottom(page: Page) {
  const box = await page.locator('header').first().boundingBox();
  return box ? box.y + box.height : 0;
}

// The guide's welcome would cover the screens these tests are about; guide.spec.ts tests it
test.beforeEach(({ page }) => skipWelcome(page));

// Each group carries the area's tag, so `--grep @case-evidence` runs these with the area's shared checks
const tagged = { tag: area.tag };

test.describe('Ask about this case, from 1440 px', tagged, () => {
  test.use({ viewport: { width: 1440, height: 900 } });

  test('opens beside the case, asks a suggested question, and takes the What-if change to the Site profile as a draft', async ({
    page,
  }) => {
    await signIn(page);
    await go(page, '/cases/C-000008');
    const button = page.getByRole('button', { name: 'Ask about this case' });
    await button.click();
    await expect(page).toHaveURL(/#\/cases\/C-000008\?ask=1$/);
    const panel = page.getByRole('region', { name: 'Ask about this case' });
    await expect(panel.getByRole('heading', { name: 'Ask about this case' })).toBeFocused();
    // Beside the case: the case's heading stays in view on the left
    const side = await panel.boundingBox();
    const title = await page.getByRole('heading', { name: 'Case C-000008', exact: true }).boundingBox();
    expect(side!.x).toBeGreaterThan(title!.x + 200);
    await expect(panel).toContainText('Read-only.');
    const example = panel.getByRole('region', { name: 'Example conversation' });
    await expect(example).toContainText('Recorded from a real run on 1 November 2026 with claude-opus-5-5.');
    await expect(example).not.toContainText('API key');
    await expect(example.getByRole('article')).toHaveCount(3);
    // Each answer opens on its first sentences, the rest one click away
    await expect(example.getByRole('button', { name: 'Show the whole answer' }).first()).toHaveAttribute(
      'aria-expanded',
      'false',
    );

    await panel.getByRole('tab', { name: /Ask the board/ }).click();
    await panel.getByRole('button', { name: 'What did the dissenting specialist say?' }).click();
    const thread = panel.getByRole('region', { name: 'Conversation' });
    await expect(
      thread.getByRole('heading', { name: 'What did the dissenting specialist say?' }),
    ).toBeFocused();
    await expect(thread).toContainText(firstSentence('S8', 'Downstream Out', 'c4.1'));
    await expect(thread).not.toContainText('sample data');

    const card = panel.getByRole('region', { name: 'What if: the setting behind this outcome' });
    await expect(card).toContainText('If it were BEDMGR');
    await card.getByRole('link', { name: 'Open in Site profile' }).click();
    await expect(page).toHaveURL(/#\/site-profile\?suggest=/);
    const draft = page.getByRole('region', { name: 'A suggested change from case C-000008' });
    await expect(draft.getByRole('heading', { name: 'A suggested change from case C-000008' })).toBeFocused();
    await expect(draft.getByRole('table')).toContainText('BEDMGR');
  });

  test('a citation in an answer lands on its section of the Evidence tab, clear of the header, its heading focused', async ({
    page,
  }) => {
    await signIn(page);
    await go(page, '/cases/C-000008?ask=1');
    const panel = page.getByRole('region', { name: 'Ask about this case' });
    const first = panel.getByRole('region', { name: 'Example conversation' }).getByRole('article').first();
    await first.getByRole('button', { name: 'Downstream state' }).click();
    await expect(page.getByRole('tab', { name: 'Evidence' })).toHaveAttribute('aria-selected', 'true');
    const heading = page.getByRole('heading', { name: "Downstream Out's encounter", level: 3 });
    await expect(heading).toBeFocused();
    // Beside the case, the panel stays open
    await expect(panel).toBeVisible();
    const box = await heading.boundingBox();
    expect(box!.y).toBeGreaterThanOrEqual(await headerBottom(page));
    expect(box!.y).toBeLessThan(900 / 2);
  });
});

test.describe('Ask about this case, below 1440 px', tagged, () => {
  test('opens as a drawer over the case, which keeps its full width', async ({ page }) => {
    await signIn(page);
    await go(page, '/cases/C-000008');
    const title = page.getByRole('heading', { name: 'Case C-000008', exact: true });
    const main = page.locator('main');
    const before = await main.boundingBox();
    await page.getByRole('button', { name: 'Ask about this case' }).click();
    const drawer = page.getByRole('dialog', { name: 'Ask about this case' });
    await expect(drawer.getByRole('heading', { name: 'Ask about this case' })).toBeFocused();
    await expect(drawer.getByRole('region', { name: 'Example conversation' })).toBeVisible();
    // Not narrowed beside a panel (the scroll lock may take back a scrollbar's width)
    expect((await main.boundingBox())!.width).toBeGreaterThan(before!.width - 30);
    await expect(title).toBeAttached();
  });

  test('closes with Escape, returning focus to its button', async ({ page }) => {
    await signIn(page);
    await go(page, '/cases/C-000008?ask=1');
    const drawer = page.getByRole('dialog', { name: 'Ask about this case' });
    await expect(drawer.getByRole('heading', { name: 'Ask about this case' })).toBeFocused();
    await page.keyboard.press('Escape');
    await expect(drawer).toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Ask about this case' })).toBeFocused();
    await expect(page).toHaveURL(/#\/cases\/C-000008$/);
  });

  test('in the trial, shows the box for a question of your own disabled and steers to the suggested ones', async ({
    page,
  }) => {
    await signIn(page);
    await go(page, '/cases/C-000008?ask=1');
    const drawer = page.getByRole('dialog', { name: 'Ask about this case' });
    const box = drawer.getByRole('textbox', { name: 'Your own question' });
    await expect(box).toBeDisabled();
    await expect(box).toHaveAttribute('placeholder', 'In the trial, pick a suggested question');
    await expect(box).toHaveAccessibleDescription('Needs a real model: not in the trial.');
    await expect(drawer.getByRole('button', { name: 'Ask', exact: true })).toBeDisabled();
    // The suggested questions answer from the recording
    await drawer.getByRole('button', { name: 'Which movement is current?' }).click();
    const thread = drawer.getByRole('region', { name: 'Conversation' });
    await expect(thread.getByRole('heading', { name: 'Which movement is current?' })).toBeFocused();
    await expect(thread).toContainText(firstSentence('S8', 'Downstream Out', 'c2.1'));
  });

  test('in the trial, on a case with no recordings, the box steers to the cases that have them', async ({
    page,
  }) => {
    await signIn(page);
    await go(page, '/cases/C-000021?ask=1');
    const drawer = page.getByRole('dialog', { name: 'Ask about this case' });
    await expect(drawer.getByTestId('ask-recorded-cases').first()).toBeVisible();
    const box = drawer.getByRole('textbox', { name: 'Your own question' });
    await expect(box).toBeDisabled();
    await expect(box).toHaveAttribute('placeholder', 'In the trial, pick one of those cases');
  });

  test('a citation in an answer closes the drawer and lands on the cited evidence', async ({ page }) => {
    await signIn(page);
    await go(page, '/cases/C-000008?ask=1');
    const drawer = page.getByRole('dialog', { name: 'Ask about this case' });
    const first = drawer.getByRole('region', { name: 'Example conversation' }).getByRole('article').first();
    await first.getByRole('button', { name: 'Downstream state' }).click();
    await expect(drawer).toHaveCount(0);
    await expect(page).toHaveURL(/#\/cases\/C-000008\?tab=evidence$/);
    await expect(page.getByRole('heading', { name: "Downstream Out's encounter", level: 3 })).toBeFocused();
  });
});

test.describe('the Evidence and Audit trail tabs', tagged, () => {
  test('say who cited each section, and open what was recorded in Technical', async ({ page }) => {
    await signIn(page, { detail: 'technical' });
    await go(page, '/cases/C-000008?tab=evidence', { detail: 'technical' });
    const evidence = page.getByRole('region', { name: 'Evidence' });
    const message = evidence.getByRole('region', { name: 'The HL7 message' });
    await expect(message).toContainText('Cited by all three agents and the plan');
    await expect(evidence.getByRole('region', { name: 'Schema validation' })).toContainText(
      'Cited by Conformance, Impact Analysis and the plan',
    );
    await expect(message.getByRole('button', { name: 'The message, one segment per line' })).toHaveAttribute(
      'aria-expanded',
      'true',
    );
    await expect(message.getByRole('list', { name: "The message's segments" })).toContainText(
      'MSH-9 ADT^A02',
    );
    await expect(evidence).toContainText('Snapshot 1, taken 2 Nov, 14:18:54 GMT, 14:18:54Z');
    await expect(evidence.getByRole('button', { name: 'As the API sends it' })).toHaveAttribute(
      'aria-expanded',
      'true',
    );
  });

  test('keep the message and the timeline in Plain, their codes one click away', async ({ page }) => {
    await signIn(page);
    await go(page, '/cases/C-000008?tab=evidence');
    const message = page.getByRole('region', { name: 'The HL7 message' });
    // As read: a term's definition is in the page for its description, but hidden
    await expect(message).toContainText(
      'ADT^A02 transfer of ENC-1008 to WARD-B, sent by PAS at 15 Oct, 09:20:00 BST.',
      { useInnerText: true },
    );
    await expect(message.getByRole('button', { name: 'The message, one segment per line' })).toHaveAttribute(
      'aria-expanded',
      'false',
    );
    const timeline = page.getByRole('region', { name: 'The operation timeline' });
    await expect(timeline.getByRole('table')).toBeVisible();
    await expect(timeline.getByText('Same event time')).toHaveCount(2);
  });

  test('the audit trail says "Rationale as in the plan" instead of repeating it', async ({ page }) => {
    // A week after the recording, whenever the test runs: an event of another day carries its date
    await page.clock.setFixedTime(new Date('2026-11-09T12:00:00Z'));
    await signIn(page);
    await go(page, '/cases/C-000008?tab=audit');
    const timeline = page.getByRole('region', { name: 'Timeline' });
    await expect(timeline.getByText('Plan v1 (escalate). Rationale as in the plan.')).toBeVisible();
    await expect(timeline.getByText('The plan asks for a person. Rationale as in the plan.')).toBeVisible();
    await expect(timeline.getByText('2 Nov, 14:18:39 GMT').first()).toBeVisible();
  });
});

test.describe('a phone at 390 px', tagged, () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test.beforeEach(({ page }) => signIn(page));

  test('Ask about this case opens as a full-screen sheet', async ({ page }) => {
    await go(page, '/cases/C-000008');
    await page.getByRole('button', { name: 'Ask about this case' }).click();
    const sheet = page.getByRole('dialog', { name: 'Ask about this case' });
    await expect(sheet.getByRole('region', { name: 'Example conversation' })).toBeVisible();
    // Focus starts on the sheet's heading, as it does on the panel beside the case
    await expect(sheet.getByRole('heading', { name: 'Ask about this case' })).toBeFocused();
    await page.waitForFunction(() => document.getAnimations().every((a) => a.playState !== 'running'));
    const box = await sheet.boundingBox();
    expect(Math.round(box!.width)).toBe(390);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
    await page.keyboard.press('Escape');
    await expect(sheet).toBeHidden();
    await expect(page.getByRole('button', { name: 'Ask about this case' })).toBeFocused();
  });

  test('the operation timeline stacks, and the message wraps, with nothing scrolling sideways', async ({
    page,
  }) => {
    await go(page, '/cases/C-000008?tab=evidence');
    const timeline = page.getByRole('region', { name: 'The operation timeline' });
    await expect(timeline.getByRole('table')).toBeVisible();
    await page.getByRole('button', { name: 'The message, one segment per line' }).click();
    await expect(page.getByRole('list', { name: "The message's segments" })).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
  });
});
