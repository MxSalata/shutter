import { expect, test } from '@playwright/test';
import { skipWelcome } from './guide';
import { go, signIn } from './helpers';

/**
 * The Cases list: who investigated each case and what its plan proposed.
 */

// The guide's welcome would cover the screens these tests are about; guide.spec.ts tests it
test.beforeEach(({ page }) => skipWelcome(page));

test.describe('the guided path', () => {
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
});
