import { expect, test, type Page } from '@playwright/test';
import { audit } from './axe';
import { area } from './areas/case';
import { skipWelcome } from './guide';
import { go, signIn } from './helpers';

/**
 * The case page's precedents and its board's run timeline, in the trial. The recording holds the precedents its
 * approvals wrote: the held S2 case was the first, so its snapshot found none, and a later case of the same conditions
 * names the approvals before it. Its board was replayed, so the trial draws the pass as the recording ran it, with the
 * times as recorded (the live stand-in, case-live-trial.spec.ts, draws a live pass).
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
    await go(page, '/cases/C-000008?tab=audit');
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
    await shot(page, 'trial-c000008-audit-trail');
  });

  test('a later case of the same conditions names the approval before it, and lists it in the record', async ({
    page,
  }) => {
    await signIn(page);
    await go(page, '/cases/C-000009?tab=audit');
    const section = page.getByRole('region', { name: 'Precedents' });
    await expect(section.getByTestId('precedents-line')).toContainText(
      'Approved and verified 1 time, rejected 0 times here in the last 180 days; last approved by approver on 2 Nov (case C-000002).',
    );
    await section.getByRole('button', { name: 'See them' }).click();
    const table = section.getByRole('table');
    await expect(table.getByRole('row')).toHaveCount(2);
    await expect(table.getByRole('link', { name: 'C-000002' })).toHaveAttribute('href', /\/cases\/C-000002$/);
    await section.scrollIntoViewIfNeeded();
    await shot(page, 'trial-c000009-precedents');
  });

  test('the recorded board draws its replayed pass, with the times as recorded', async ({ page }) => {
    await signIn(page, { detail: 'technical' });
    await go(page, '/cases/C-000008', { detail: 'technical' });
    const board = page.getByRole('region', { name: 'The board' });
    await expect(board.getByRole('region', { name: 'Coordinator' })).toBeVisible();
    await expect(board.getByRole('button', { name: 'When each agent worked' })).toHaveAttribute(
      'aria-expanded',
      'true',
    );
    const picture = board.getByRole('img', {
      name: /^When each agent worked, replayed with the times as recorded: /,
    });
    await expect(picture).toBeVisible();
    await expect(board.getByTestId('run-timeline-replayed')).toHaveText(
      "Replayed: times as recorded, in seconds from the recorded pass's start.",
    );
    await expect(picture.locator('.run-clock-bar')).toHaveCount(4);
    // Every recorded tool call of the four runs is on its run's bar
    await expect(picture.locator('.run-clock-mark')).toHaveCount(17);
    const how = board.getByRole('button', { name: 'How a replay is drawn' });
    await expect(how).toHaveAttribute('aria-expanded', 'false');
    await how.click();
    await expect(board.getByTestId('run-timeline-replay-rule')).toBeVisible();
    await board.getByTestId('run-timeline').scrollIntoViewIfNeeded();
    await shot(page, 'trial-c000008-run-timeline');
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
