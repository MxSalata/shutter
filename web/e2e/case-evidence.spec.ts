import { expect, test } from '@playwright/test';
import { skipWelcome } from './guide';
import { go, signIn } from './helpers';
import recordedAnswers from '../src/mocks/recorded-questions.json' with { type: 'json' };

/**
 * A case's evidence and Ask about this case: asking a suggested question beside the case, the What-if change taken
 * to the Site profile as a draft, Escape, and the full-screen sheet on a phone.
 */

// The recorded answers' own words, so a recording made again doesn't break the test: the first sentence of an answer.
type Recorded = {
  scenarios: Record<string, Record<string, { questions: Record<string, { answer: { answer: string } }> }>>;
};
const firstSentence = (scenario: string, receiver: string, turn: string) =>
  (recordedAnswers as unknown as Recorded).scenarios[scenario][receiver].questions[turn].answer.answer.split(
    /(?<=\.)\s/,
  )[0];

// The guide's welcome would cover the screens these tests are about; guide.spec.ts tests it
test.beforeEach(({ page }) => skipWelcome(page));

test.describe('Ask about this case', () => {
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
    // Beside the case at laptop width: the case's heading stays in view on the left
    const side = await panel.boundingBox();
    const title = await page.getByRole('heading', { name: 'Case C-000008', exact: true }).boundingBox();
    expect(side!.x).toBeGreaterThan(title!.x + 200);
    await expect(panel).toContainText('Read-only.');
    const example = panel.getByRole('region', { name: 'Example conversation' });
    await expect(example).toContainText(
      'Recorded live on 1 November 2026 with claude-opus-5-5. With an API key you can ask your own questions.',
    );
    await expect(example.getByRole('article')).toHaveCount(3);
    await expect(panel).toContainText(
      'Free text needs a model key. In this demo, pick a suggested question above.',
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
    await draft.getByRole('button', { name: 'Review and save…' }).click();
    const dialog = page.getByRole('dialog');
    await expect(dialog).toContainText(/Authoritative source: from .* to BEDMGR/);
    await dialog.getByRole('button', { name: 'Save version 11' }).click();
    await expect(page.getByText('Version 11 saved')).toBeVisible();
    await expect(page).toHaveURL(/#\/site-profile$/);
  });

  test('closes with Escape, returning focus to its button', async ({ page }) => {
    await signIn(page);
    await go(page, '/cases/C-000008?ask=1');
    const panel = page.getByRole('region', { name: 'Ask about this case' });
    await expect(panel.getByRole('heading', { name: 'Ask about this case' })).toBeFocused();
    await page.keyboard.press('Escape');
    await expect(panel).toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Ask about this case' })).toBeFocused();
    await expect(page).toHaveURL(/#\/cases\/C-000008$/);
  });
});

test.describe('a phone at 390 px', () => {
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
});
