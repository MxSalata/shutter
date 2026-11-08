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
  test('leads from the path card to the held S2 case and its approval', async ({ page }) => {
    await signIn(page);
    const card = page.getByRole('region', { name: 'Then follow this path' });
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
      .getByRole('region', { name: 'Then follow this path' })
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
      page.getByRole('region', { name: 'S8 side by side: Rules only and the board' }),
    ).toBeVisible();
  });

  test('says at a glance which of the two S8 runs was wrong, at every width', async ({ page }) => {
    for (const width of [1920, 1280, 390]) {
      await page.setViewportSize({ width, height: 900 });
      await go(page, '/cases/C-000008?show=compare');
      const rules = page.getByTestId('compare-rules');
      await expect(rules.getByTestId('compare-patient')).toHaveText(
        "Patient ends in WARD-B, over the bed manager's WARD-C",
      );
      await expect(rules.getByText('Not as expected')).toBeVisible();
      await expect(rules.getByText('Resolved', { exact: true })).toHaveCount(0);
      const board = page.getByTestId('compare-board');
      await expect(board.getByTestId('compare-patient')).toHaveText('No overwrite; a person decides');
      await expect(board.getByText('As expected')).toBeVisible();
      // The time and the digests wait behind their fold in Plain
      await expect(
        page.getByRole('region', { name: /^S8 side by side/ }).getByText('Snapshot digest'),
      ).toBeHidden();
      // The evidence reads on a phone: no column starts past the window's edge, and the page doesn't scroll sideways
      const cell = page
        .getByRole('region', { name: /^S8 side by side/ })
        .getByRole('cell', { name: /WARD-C at version 2/ })
        .last();
      const box = (await cell.boundingBox())!;
      expect(box.x + box.width).toBeLessThanOrEqual(width);
      if (width === 390) expect(box.x).toBeLessThan(100);
      expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
    }
  });

  test('takes the top button of the wrong write to the two runs, not to "No action needed"', async ({
    page,
  }) => {
    await signIn(page);
    await go(page, '/cases/C-000021');
    const action = page.getByTestId('case-action');
    await expect(action).toHaveText('Compare the two runs');
    await expect(action).toHaveAccessibleName('Not the expected outcome: compare the two runs');
    await action.click();
    await expect(page.getByRole('heading', { name: /^S8 side by side/ })).toBeFocused();
    await expect(page.getByRole('heading', { name: /^S8 side by side/ })).toBeInViewport();
  });

  test('keeps the pair for the demo role in the trial, where both runs are recorded', async ({ page }) => {
    await signIn(page, { as: 'demo' });
    await go(page, '/cases/C-000008?show=compare', { as: 'demo' });
    // The note that sends a reader to the trial is for a live demo: here it would point at the page it is on
    await expect(page.getByTestId('compare-rules')).toBeVisible();
    await expect(page.getByText(/Rules only isn't played/)).toHaveCount(0);
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
    // The steps wait behind the card's details, so the three cards keep one size
    await page.getByRole('button', { name: 'Why, and what to do' }).click();
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
    await expect(dialog).toContainText(
      'Nothing leaves this browser, and a reload starts the recording afresh.',
    );
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

test.describe('the case page made easier to read', () => {
  test('draws where the held S2 case failed, with the patient and the message type in the header', async ({
    page,
  }) => {
    await signIn(page);
    await go(page, '/cases/C-000002');
    const picture = page.getByRole('img', { name: /^Where it failed: PAS sent the transfer to WARD-B/ });
    await expect(picture).toBeVisible();
    await expect(picture).toContainText('Not delivered');
    await expect(picture).toContainText('HTTP 503 ward_unavailable');
    await expect(picture).toContainText('Waiting for approval');
    await expect(page.getByTestId('case-message-type')).toHaveText('2.5.1:ADT_A02');
    await expect(page.getByText('MRN1002', { exact: true })).toBeVisible();
  });

  test('stacks the path down a phone screen with no sideways scroll', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await signIn(page);
    await go(page, '/cases/C-000064');
    const nodes = page.locator('.fm-node');
    await expect(nodes).toHaveCount(3);
    const [a, b] = [await nodes.nth(0).boundingBox(), await nodes.nth(1).boundingBox()];
    expect(b!.y).toBeGreaterThan(a!.y + a!.height);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
  });

  test('takes the reader from the action button to "What needs you now", opening the band', async ({
    page,
  }) => {
    // The operator: the approver's and an escalation's buttons go to their own controls
    await page.goto('./?as=operator#/scenarios');
    await expect(page.getByRole('heading', { name: 'Scenarios', exact: true })).toBeVisible();
    await page.goto('./?as=operator#/cases/C-000002');
    const band = page.getByRole('region', { name: 'Outcome' });
    // Close the band first, as a reader may have
    await band.getByRole('button', { name: 'Outcome', exact: true }).click();
    await expect(band.getByRole('button', { name: 'Outcome', exact: true })).toHaveAttribute(
      'aria-expanded',
      'false',
    );
    await expect(band.getByTestId('outcome-line')).toHaveText('Waiting for approval');
    await page.getByRole('button', { name: 'No action for you: waiting for an approver' }).first().click();
    await expect(band.getByRole('button', { name: 'Outcome', exact: true })).toHaveAttribute(
      'aria-expanded',
      'true',
    );
    const heading = band.getByRole('heading', { name: 'What needs you now' });
    await expect(heading).toBeInViewport();
    await expect(heading).toBeFocused();
    await expect(band.getByRole('button', { name: 'Why?' })).toHaveAttribute('aria-expanded', 'true');
    // The band remembers the reader's choice: closed again, it stays closed on the next visit
    await band.getByRole('button', { name: 'Outcome', exact: true }).click();
    await page.reload();
    await expect(
      page.getByRole('region', { name: 'Outcome' }).getByRole('button', { name: 'Outcome', exact: true }),
    ).toHaveAttribute('aria-expanded', 'false');
  });

  test('keeps the action in reach in the sticky tab bar', async ({ page }) => {
    await signIn(page);
    await go(page, '/cases/C-000008');
    await page.getByRole('button', { name: /^6\. What was verified/ }).scrollIntoViewIfNeeded();
    await page.mouse.wheel(0, 1200);
    const compact = page.getByTestId('case-action-compact');
    await expect(compact).toBeInViewport();
    await expect(compact).toHaveAccessibleName('Needs you: escalate to a team');
    await compact.click();
    // It reaches the control it names: the panel's button, not a card that describes it
    const heading = page.getByRole('heading', { name: 'Escalations' });
    await expect(heading).toBeFocused();
    await expect(heading).toBeInViewport();
    await expect(page.getByRole('button', { name: /^Escalate to the/ })).toBeInViewport();
  });

  test('keeps the approve dialog in its own words while it closes', async ({ page }) => {
    await signIn(page);
    await go(page, '/cases/C-000002');
    await page.getByRole('button', { name: 'Approve plan' }).click();
    const dialog = page.getByRole('dialog', { name: 'Approve plan v1' });
    await expect(dialog).toBeVisible();
    // Watches the whole closing animation for what a screenshot could miss between frames
    await page.evaluate(() => {
      new MutationObserver(() => {
        if (document.body.textContent?.includes('Reject this plan'))
          (window as unknown as { flashed: boolean }).flashed = true;
      }).observe(document.body, { subtree: true, childList: true, characterData: true });
    });
    await dialog.getByRole('button', { name: 'Cancel' }).click();
    await expect(dialog).toBeHidden();
    expect(await page.evaluate(() => (window as unknown as { flashed?: boolean }).flashed)).toBeUndefined();
  });

  test('takes the approver from the action button to Approve and Reject', async ({ page }) => {
    await signIn(page);
    await go(page, '/cases/C-000002');
    await page.getByTestId('case-action').click();
    await expect(page.getByRole('heading', { name: 'Approval', exact: true })).toBeFocused();
    await expect(page.getByRole('button', { name: 'Approve plan' })).toBeInViewport();
  });

  test('opens a closed case with its band closed, the outcome still said', async ({ page }) => {
    await signIn(page);
    await go(page, '/cases/C-000058');
    const band = page.getByRole('region', { name: 'Outcome' });
    await expect(band.getByRole('button', { name: 'Outcome', exact: true })).toHaveAttribute(
      'aria-expanded',
      'false',
    );
    await expect(band.getByTestId('outcome-line')).toHaveText('Delivered: verified at the receiver');
    await expect(page.getByTestId('case-action')).toHaveAccessibleName('No action needed on this case');
    await expect(page.getByTestId('case-action')).toBeVisible();
  });

  test('opens the Evidence tab from the progress strip, its heading in view', async ({ page }) => {
    await signIn(page);
    await go(page, '/cases/C-000008');
    await page.getByRole('button', { name: 'Evidence: done, show the evidence' }).click();
    await expect(page.getByRole('tab', { name: 'Evidence' })).toHaveAttribute('aria-selected', 'true');
    const heading = page.getByRole('heading', { name: 'Evidence', exact: true, level: 2 });
    await expect(heading).toBeInViewport();
    await expect(heading).toBeFocused();
    // A stage the case did not reach is text, not a button
    await expect(page.getByRole('button', { name: /^Dispatch/ })).toHaveCount(0);
  });

  test('opens the gate and decision step from Plan and gate, on a phone with 44 px targets', async ({
    page,
  }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await signIn(page);
    await go(page, '/cases/C-000064');
    const stage = page.getByRole('button', {
      name: 'Plan and gate: stopped here, show the plan and the gate',
    });
    expect(Math.round((await stage.boundingBox())!.height * 100) / 100).toBeGreaterThanOrEqual(44);
    const compact = page.getByTestId('case-action-compact');
    const box = (await compact.boundingBox())!;
    // A sub-pixel layout can measure 43.99997: a 44 px target to the hundredth of a pixel
    expect(Math.round(box.height * 100) / 100).toBeGreaterThanOrEqual(44);
    expect(Math.round(box.width * 100) / 100).toBeGreaterThanOrEqual(44);
    await stage.click();
    await expect(page.getByRole('button', { name: /^4\. Gate and decision/ })).toHaveAttribute(
      'aria-expanded',
      'true',
    );
    await expect(page.getByRole('heading', { name: 'The gate', exact: true })).toBeFocused();
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
