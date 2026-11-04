import { expect, test } from '@playwright/test';
import { skipWelcome } from './guide';
import { go, signIn } from './helpers';

/**
 * Incidents: the guided path's outage incident, the list that leads to it, and the incident's story read in order.
 * The recording's I-000001 holds eight failed messages for six patient encounters; it ran for 1 min 42 s.
 */

// The guide's welcome would cover the screens these tests are about; guide.spec.ts tests it
test.beforeEach(({ page }) => skipWelcome(page));

test.describe('the guided path', () => {
  test('leads to the outage incident', async ({ page }) => {
    await signIn(page);
    await page
      .getByRole('region', { name: 'Then follow this path' })
      .getByRole('link', { name: 'Incident I-000001', exact: true })
      .click();
    await expect(page.getByRole('heading', { name: 'Incident I-000001', exact: true })).toBeVisible();
  });
});

test.describe('the list', () => {
  test('shows each incident with its outcome and leads to the page', async ({ page }) => {
    await signIn(page);
    await go(page, '/incidents');
    await expect(page.getByRole('heading', { name: 'Incidents', exact: true })).toBeVisible();
    const row = page
      .getByRole('row')
      .filter({ has: page.getByRole('link', { name: 'I-000001', exact: true }) });
    await expect(row).toContainText('All 6 chains verified');
    await expect(row).toContainText('8 cases in 6 chains');
    await expect(page.getByRole('region', { name: 'Incidents at a glance' })).toContainText('verified');
    await row.getByRole('link', { name: 'I-000001', exact: true }).click();
    await expect(page.getByRole('heading', { name: 'Incident I-000001', exact: true })).toBeVisible();
  });
});

test.describe('the incident', () => {
  test('opens with what a manager measures, then the chains in order', async ({ page }) => {
    await signIn(page);
    await go(page, '/incidents/I-000001');
    const outcome = page.getByRole('region', { name: 'Outcome' });
    await expect(outcome).toContainText(
      '8 failed messages for 6 patient encounters, all closed and verified at the receiver, in 1 min 42 s.',
    );
    await expect(outcome.getByRole('region', { name: 'The incident in figures' })).toContainText(
      'Open to closed',
    );
    // The ordered chain's two operations are an ordered list, the transfer before the discharge
    const ordered = page.getByRole('article', { name: 'Chain 2, ENC-1102' });
    const operations = ordered.getByRole('list', { name: 'Chain 2 operations, oldest first' });
    await expect(operations.getByRole('listitem')).toHaveCount(2);
    await expect(operations.getByRole('listitem').first()).toContainText('C-000038');
    await expect(operations.getByRole('listitem').last()).toContainText('C-000043');
    await expect(ordered).toContainText('Delivered, verified');
    // The IRIS row, in both modes
    await expect(page.getByText('In IRIS:')).toBeVisible();
  });

  test('says what the approval covers in a sentence, and the plan in another', async ({ page }) => {
    await signIn(page);
    await go(page, '/incidents/I-000001');
    await expect(page.getByRole('region', { name: 'Approval' })).toContainText(
      'One approval released the ordered chain: C-000038 then C-000043.',
    );
    await expect(page.getByRole('region', { name: 'The plan' })).toContainText(
      'One plan, approved once, covers the ordered chain.',
    );
    // The digest is behind "Everything the approval is bound to"
    await expect(page.getByRole('region', { name: 'The plan' }).getByText('sha256').first()).toBeHidden();
  });

  test('collapses the joined cases into one line that opens to the events', async ({ page }) => {
    await signIn(page);
    await go(page, '/incidents/I-000001');
    const timeline = page.getByRole('region', { name: 'Timeline' });
    const joined = timeline.getByRole('button', { name: /cases joined/ }).first();
    await expect(joined).toHaveAttribute('aria-expanded', 'false');
    await joined.click();
    await expect(joined).toHaveAttribute('aria-expanded', 'true');
    await expect(timeline.getByText(/Case C-000037 joined/)).toBeVisible();
  });

  test('shows the codes beside the words in Technical', async ({ page }) => {
    await signIn(page, { detail: 'technical' });
    await go(page, '/incidents/I-000001', { detail: 'technical' });
    const ordered = page.getByRole('article', { name: 'Chain 2, ENC-1102' });
    await expect(ordered.getByText('MRN1102', { exact: true })).toBeVisible();
    await expect(ordered.getByText('resend_chain').first()).toBeVisible();
    await expect(page.getByRole('region', { name: 'The plan' }).getByText('Plan digest')).toBeVisible();
  });
});
