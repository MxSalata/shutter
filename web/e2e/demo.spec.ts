import { expect, test, type Page } from '@playwright/test';

/**
 * What the demo build shows a judge first: the sign-in page's "Try the demo", then the Scenarios page's guided path
 * through the recorded cases, whose links open the cases they name.
 */
const go = (page: Page, path: string) => page.goto(`./#${path}`);

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
    await expect(outcome).toContainText('Awaiting approval · 0 writes');
    await expect(outcome).toContainText('Next action: Approve or reject plan v1');
    await expect(page.getByRole('region', { name: 'Approval' })).toContainText('Waiting for an approver');
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

  test('the cases list says who investigated each case', async ({ page }) => {
    await signIn(page);
    await go(page, '/cases');
    await expect(page.getByRole('columnheader', { name: 'Investigated by' })).toBeVisible();
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
