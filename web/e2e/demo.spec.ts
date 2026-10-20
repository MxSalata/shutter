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
    await expect(page.getByRole('region', { name: 'Approval' })).toContainText('Waiting for an approver');
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
