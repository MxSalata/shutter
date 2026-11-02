import { expect, test } from '@playwright/test';
import { skipWelcome } from './guide';
import { go, signIn } from './helpers';

/**
 * A case's page: the guided path's S2 case and its approval, the S8 comparison, S22's two receivers, the tab in the
 * address, and Approve and Reject for the live hospital's public role.
 */

/** The live hospital's public role: the address keeps `?as=demo` in every step. */
const AS_DEMO = { as: 'demo' } as const;

// The guide's welcome would cover the screens these tests are about; guide.spec.ts tests it
test.beforeEach(({ page }) => skipWelcome(page));

test.describe('the guided path', () => {
  test('leads from the Start here card to the held S2 case and its approval', async ({ page }) => {
    await signIn(page);
    const card = page.getByRole('region', { name: 'Start here' });
    await expect(card).toBeVisible();
    for (const name of [
      'Case C-000002',
      'Case C-000021',
      'Case C-000008',
      'Case C-000012',
      'Incident I-000001',
    ])
      await expect(card.getByRole('link', { name, exact: true })).toBeVisible();
    await card.getByRole('link', { name: 'Case C-000002', exact: true }).click();
    await expect(page.getByRole('heading', { name: 'Case C-000002', exact: true })).toBeVisible();
    const outcome = page.getByRole('region', { name: 'Outcome' });
    await expect(outcome.getByTestId('outcome-line')).toHaveText('Waiting for approval');
    await expect(outcome).toContainText('Tested the fix at the receiver; sent nothing yet');
    await expect(outcome.getByRole('heading', { name: 'What needs you now' })).toBeVisible();
    await expect(outcome).toContainText('Approve or reject plan v1');
    await expect(page.getByRole('region', { name: 'Approval', exact: true })).toContainText(
      'Waiting for approval',
    );
  });

  test('opens the S8 comparison from the guide, behind why the board matters', async ({ page }) => {
    await signIn(page);
    await page
      .getByRole('region', { name: 'Start here' })
      .getByRole('link', { name: 'Rules and board side by side' })
      .first()
      .click();
    await expect(page.getByRole('heading', { name: 'Case C-000008', exact: true })).toBeVisible();
    await expect(page.getByRole('region', { name: 'Outcome' }).getByTestId('outcome-line')).toHaveText(
      'Escalated: a person decides',
    );
    await expect(page.getByRole('button', { name: /^Why the board matters/ })).toHaveAttribute(
      'aria-expanded',
      'true',
    );
    await expect(
      page.getByRole('region', { name: 'S8 side by side: rules alone and the board' }),
    ).toBeVisible();
  });

  test('shows the same overtaken transfer closed at one receiver and sent for correction at the other', async ({
    page,
  }) => {
    await signIn(page);
    await go(page, '/site-profile');
    const cards = page.getByRole('list', { name: 'The receivers and what each needs' });
    await expect(cards.getByRole('listitem', { name: 'Downstream Out' })).toContainText('Current state');
    await expect(cards.getByRole('listitem', { name: 'Records Out' })).toContainText('History of record');
    await go(page, '/cases/C-000054');
    await expect(page.getByTestId('case-receiver')).toContainText('Current state');
    await expect(page.getByTestId('correction-steps')).toHaveCount(0);
    await go(page, '/cases/C-000055');
    await expect(page.getByTestId('case-receiver')).toContainText('History of record');
    const steps = page.getByTestId('correction-steps');
    await expect(steps.getByRole('heading', { name: 'Correcting the history at Records Out' })).toBeVisible();
    await expect(steps.getByRole('listitem')).toHaveCount(8);
  });

  test("keeps the case page's tab in the address", async ({ page }) => {
    await signIn(page);
    await go(page, '/cases/C-000008');
    await page.getByRole('tab', { name: 'Evidence' }).click();
    await expect(page).toHaveURL(/#\/cases\/C-000008\?tab=evidence$/);
    await expect(page.getByRole('region', { name: 'Evidence' })).toContainText('The operation timeline');
    // A link that names the tab opens it
    await go(page, '/cases/C-000009');
    await go(page, '/cases/C-000008?tab=evidence');
    await expect(page.getByRole('tab', { name: 'Evidence' })).toHaveAttribute('aria-selected', 'true');
    await page.getByRole('tab', { name: 'Audit trail' }).click();
    await expect(page.getByRole('region', { name: 'Timeline' })).toBeVisible();
    await expect(page.getByRole('region', { name: 'In the Management Portal' })).toBeVisible();
  });
});

test.describe('the S2 approval in the trial', () => {
  test('plays out what the recording did after the approval, and ends delivered and verified', async ({
    page,
  }) => {
    await signIn(page);
    await go(page, '/cases/C-000002');
    const outcome = page.getByRole('region', { name: 'Outcome' });
    await expect(outcome.getByTestId('outcome-line')).toHaveText('Waiting for approval');
    // The guide waits for the page's event once the replay has played
    const replayed = page.evaluate(
      () =>
        new Promise<boolean>((resolve) =>
          window.addEventListener('shutter:replay-done', () => resolve(true), { once: true }),
        ),
    );
    await page.getByRole('button', { name: 'Approve plan' }).click();
    const dialog = page.getByRole('dialog', { name: 'Approve plan v1' });
    await expect(dialog).toContainText('Nothing leaves this browser.');
    await expect(dialog.getByText('Trial only')).toBeVisible();
    await dialog.getByRole('button', { name: 'Approve this plan' }).click();
    await expect(outcome.getByTestId('outcome-line')).toHaveText('Delivered: verified at the receiver');
    expect(await replayed).toBe(true);
    await expect(outcome).toHaveAttribute('data-tone', 'positive');
    await expect(page.getByTestId('replay-note')).toHaveText(
      'Replayed from the recording: approved 2 Nov, 14:16 UTC. Your approval is noted at the end of the audit trail.',
    );
    const stages = page.locator('.lifecycle-step');
    await expect(stages).toHaveCount(7);
    for (const i of [4, 5, 6]) await expect(stages.nth(i)).toHaveAttribute('data-revealed', 'true');
    // The lifecycle and the band both in view at the end
    await expect(page.locator('#case-lifecycle')).toBeInViewport();
    await expect(outcome.getByTestId('outcome-line')).toBeInViewport();
  });

  test('shows Convene the board and Reinvestigate disabled with their reason', async ({ page }) => {
    await signIn(page);
    await go(page, '/cases/C-000008');
    for (const name of ['Convene the board', 'Reinvestigate']) {
      const button = page.getByRole('button', { name, exact: true });
      await expect(button).toBeDisabled();
      await expect(button).toHaveAccessibleDescription('Needs a real model: not in the trial');
    }
  });

  test('keeps the tabs under the header while the page scrolls', async ({ page }) => {
    await signIn(page);
    await go(page, '/cases/C-000008');
    const tabs = page.getByRole('tablist', { name: 'The case in detail' });
    await page.getByRole('button', { name: /^6\. What was verified/ }).scrollIntoViewIfNeeded();
    await page.mouse.wheel(0, 1200);
    await expect(tabs).toBeInViewport();
  });
});

test.describe('the live hospital, as the public role sees it', () => {
  test('keeps Approve and Reject', async ({ page }) => {
    await signIn(page, AS_DEMO);
    await go(page, '/cases/C-000002', AS_DEMO);
    await expect(page.getByRole('heading', { name: 'Case C-000002', exact: true })).toBeVisible();
    for (const step of await page.getByRole('button', { name: /^\d\. / }).all())
      if ((await step.getAttribute('aria-expanded')) !== 'true') await step.click();
    await expect(page.getByRole('button', { name: 'Approve plan' })).toBeEnabled();
    await expect(page.getByRole('button', { name: 'Reject plan' })).toBeEnabled();
  });
});
