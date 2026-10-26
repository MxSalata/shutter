import { expect, test, type Page } from '@playwright/test';
import { skipWelcome } from './guide';

/**
 * What the demo build shows a judge first: the sign-in page's "Try the demo", then the Scenarios page's guided path
 * through the recorded cases, whose links open the cases they name.
 */
const go = (page: Page, path: string) => page.goto(`./#${path}`);

// The guide's welcome would cover the screens these tests are about; guide.spec.ts tests it
test.beforeEach(({ page }) => skipWelcome(page));

async function signIn(page: Page) {
  await go(page, '/login');
  await page.getByRole('button', { name: /Try the demo/ }).click();
  await expect(page.getByRole('heading', { name: 'Scenarios' })).toBeVisible();
}

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
    await expect(outcome).toContainText('Waiting for approval · 0 writes');
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
    await expect(page.getByRole('region', { name: 'Outcome' })).toContainText('Escalated · 0 writes');
    await expect(page.getByRole('button', { name: /^Why the board matters/ })).toHaveAttribute(
      'aria-expanded',
      'true',
    );
    await expect(
      page.getByRole('region', { name: 'S8 side by side: rules alone and the board' }),
    ).toBeVisible();
  });

  test("keeps the case page's tab in the address", async ({ page }) => {
    await signIn(page);
    await go(page, '/cases/C-000008');
    await page.getByRole('tab', { name: 'Evidence' }).click();
    await expect(page).toHaveURL(/#\/cases\/C-000008\?tab=evidence$/);
    await expect(page.getByRole('region', { name: 'Evidence' })).toContainText('Encounter timeline');
    // A link that names the tab opens it
    await go(page, '/cases/C-000009');
    await go(page, '/cases/C-000008?tab=evidence');
    await expect(page.getByRole('tab', { name: 'Evidence' })).toHaveAttribute('aria-selected', 'true');
    await page.getByRole('tab', { name: 'Audit trail' }).click();
    await expect(page.getByRole('region', { name: 'Timeline' })).toBeVisible();
    await expect(page.getByRole('region', { name: 'In the Management Portal' })).toBeVisible();
  });

  test('the cases list says who investigated each case and what its plan proposed', async ({ page }) => {
    await signIn(page);
    await go(page, '/cases');
    await expect(page.getByRole('columnheader', { name: 'Investigated by' })).toBeVisible();
    await expect(page.getByRole('columnheader', { name: 'Proposed action' })).toBeVisible();
    await expect(
      page.getByText(/^State is where the case is now\. Proposed action is what its plan proposed/),
    ).toBeVisible();
    const row = (id: string) => page.getByRole('row').filter({ has: page.getByRole('link', { name: id }) });
    await expect(row('C-000002')).toContainText('Board');
    await expect(row('C-000021')).toContainText('Rules only');
    await expect(row('C-000028')).toContainText('Site policy');
    await expect(row('C-000028')).toContainText('entry E2');
  });

  test('leads to the outage incident', async ({ page }) => {
    await signIn(page);
    await page
      .getByRole('region', { name: 'Start here' })
      .getByRole('link', { name: 'Incident I-000001', exact: true })
      .click();
    await expect(page.getByRole('heading', { name: 'Incident I-000001', exact: true })).toBeVisible();
  });
});

test.describe('the production review', () => {
  test('shows a finished review of each production, read only', async ({ page }) => {
    await signIn(page);
    await page.getByRole('link', { name: /Production review/ }).click();
    await expect(page.getByRole('heading', { name: 'Production review', exact: true })).toBeVisible();
    const past = page.getByRole('region', { name: 'Past reviews' });
    for (const [id, production] of [
      ['PR-000001', 'Shutter.Production'],
      ['PR-000003', 'Hospital.Production'],
    ]) {
      await go(page, '/reviews');
      await past.getByRole('link', { name: id, exact: true }).click();
      await expect(page.getByRole('heading', { name: `Review ${id}`, exact: true })).toBeVisible();
      await expect(page.getByText(`${production} in`, { exact: false }).first()).toBeVisible();
      const findings = page.getByRole('region', { name: 'Findings' });
      for (const code of ['NO_ALERT_CONSUMER', 'ALERTING_OFF', 'QUEUE_ALERTS_OFF', 'FEED_SILENCE_UNWATCHED'])
        await expect(findings.getByText(code, { exact: true })).toBeVisible();
      // The recorded reviews carry no count of HL7 TCP items, so the page says nothing about them
      await expect(findings).not.toContainText('No HL7');
      await expect(page.getByRole('region', { name: "The agent's ranking" })).toContainText(
        'No recorded explanation for this configuration',
      );
    }
    await expect(page.getByRole('region', { name: 'Findings' }).getByText('PURGE_MISSING')).toBeVisible();
  });
});

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
      'Example (sample data). With an API key you can ask your own questions.',
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
    await expect(thread).toContainText('Conformance proposed a resend with confidence 0.8');

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
    await dialog.getByRole('button', { name: 'Save version 10' }).click();
    await expect(page.getByText('Version 10 saved')).toBeVisible();
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
