import { expect, test, type Page } from '@playwright/test';
import { audit } from './axe';
import { area } from './areas/case';
import { skipWelcome } from './guide';
import { go, signIn } from './helpers';

/**
 * The case page's precedents and its board's run timeline, in the trial. The recording was made before precedents
 * were written, so every case says none, in the server's default window; and its board was replayed with a start
 * stamped when it was replayed, which does not fit the recording's durations, so the trial draws no timeline (the live
 * stand-in, case-live-trial.spec.ts, draws one).
 */

// The guide's welcome would cover the screens these tests are about; guide.spec.ts tests it
test.beforeEach(({ page }) => skipWelcome(page));

/** A part of the page's words as they read, without a term's definition kept hidden for its description. */
const visible = (page: Page, testId: string) =>
  page
    .getByTestId(testId)
    .first()
    .evaluate((el) => {
      const copy = el.cloneNode(true) as HTMLElement;
      copy.querySelectorAll('[hidden]').forEach((h) => h.remove());
      return copy.textContent ?? '';
    });

/** Saves a picture of the page for the restyle's record when E2E_SHOTS names a folder. */
async function shot(page: Page, name: string) {
  if (process.env.E2E_SHOTS)
    await page.screenshot({ path: `${process.env.E2E_SHOTS}/${name}.png`, fullPage: false });
}

test.describe(`precedents in the trial ${area.tag}`, () => {
  test('the held S2 case says under its approval that no approver has seen its conditions', async ({
    page,
  }) => {
    await signIn(page);
    await go(page, '/cases/C-000002');
    const outcome = page.getByRole('region', { name: 'Outcome' });
    await expect(outcome.getByRole('heading', { name: 'What needs you now' })).toBeVisible();
    const precedents = outcome.getByTestId('next-action-precedents');
    await expect(precedents).toBeVisible();
    expect(await visible(page, 'precedents-line')).toBe(
      'Precedents: no approver has seen these conditions at this receiver in the last 180 days.',
    );
    // The word is defined on a hover, a focus and a tap
    await precedents.getByText('Precedents', { exact: true }).focus();
    await expect(page.getByRole('tooltip')).toContainText(
      'What an approver decided before on the same evidence',
    );
    await precedents.scrollIntoViewIfNeeded();
    await shot(page, 'trial-c000002-what-needs-you-now');
  });

  test("every case's Audit trail names them, with their record a click away", async ({ page }) => {
    await signIn(page);
    await go(page, '/cases/C-000009?tab=audit');
    const section = page.getByRole('region', { name: 'Precedents' });
    await expect(section.getByRole('heading', { level: 2, name: 'Precedents' })).toBeVisible();
    await expect(section.getByTestId('precedents-line')).toHaveText(
      'No approver has seen these conditions at this receiver in the last 180 days.',
    );
    await expect(section).toContainText('It informs a decision and never releases anything.');
    const record = section.getByRole('button', { name: 'See the record' });
    await expect(record).toHaveAttribute('aria-expanded', 'false');
    await record.click();
    await expect(
      section.getByText('No precedent is recorded for these conditions at this receiver.'),
    ).toBeVisible();
    await section.scrollIntoViewIfNeeded();
    await shot(page, 'trial-c000009-audit-trail');
  });

  test('the recorded board draws no timeline: its replayed start does not fit its recorded durations', async ({
    page,
  }) => {
    await signIn(page, { detail: 'technical' });
    await go(page, '/cases/C-000008', { detail: 'technical' });
    const board = page.getByRole('region', { name: 'The board' });
    await expect(board.getByRole('region', { name: 'Coordinator' })).toBeVisible();
    await expect(board.getByRole('button', { name: 'When each agent worked' })).toHaveCount(0);
    await expect(board.getByRole('img', { name: /^When each agent worked/ })).toHaveCount(0);
  });
});

for (const colorScheme of ['light', 'dark'] as const)
  test.describe(`accessibility of the precedents in the trial, ${colorScheme} ${area.tag}`, () => {
    test.use({ colorScheme });

    test('under the approval of the held case, and in the Audit trail with the record open', async ({
      page,
    }) => {
      await signIn(page);
      await go(page, '/cases/C-000002');
      await expect(page.getByTestId('next-action-precedents')).toBeVisible();
      await expect(page.getByRole('status')).toHaveCount(0);
      expect(await audit(page)).toEqual([]);
      await page.getByRole('tab', { name: 'Audit trail' }).click();
      const section = page.getByRole('region', { name: 'Precedents' });
      await section.getByRole('button', { name: 'See the record' }).click();
      await expect(
        section.getByText('No precedent is recorded for these conditions at this receiver.'),
      ).toBeVisible();
      expect(await audit(page)).toEqual([]);
    });
  });
