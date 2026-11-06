import { expect, test } from '@playwright/test';
import { audit } from './axe';
import { skipWelcome } from './guide';
import { go, signIn } from './helpers';

/**
 * Watched namespaces in the trial: the plan comes first and changes nothing, the apply replays the recording, and the
 * page keeps within a phone's width.
 */
test.beforeEach(({ page }) => skipWelcome(page));

test.describe('Watched namespaces @settings', () => {
  test('is reached from Settings, shows the plan first, and applies only after the confirm', async ({
    page,
  }) => {
    await signIn(page);
    await go(page, '/settings');
    await page.getByRole('link', { name: 'Watched namespaces' }).click();
    await expect(page.getByRole('heading', { level: 1, name: 'Watched namespaces' })).toBeVisible();
    await expect(page.getByText(/Replayed from a recording/)).toBeVisible();

    await page.getByLabel('Namespace').selectOption('PATHOLOGY');
    await page.getByRole('button', { name: 'Read the plan' }).click();
    const plan = page.getByRole('region', { name: 'The plan for PATHOLOGY' });
    await expect(plan).toContainText('Nothing has changed yet');
    await expect(page.getByRole('table', { name: 'Watched namespaces' })).toHaveCount(0);

    await plan.getByRole('button', { name: 'Apply this plan…' }).click();
    const dialog = page.getByRole('dialog', { name: /Apply this plan to PATHOLOGY/ });
    await expect(dialog).toContainText('Trial only');
    await dialog.getByRole('button', { name: 'Apply the plan' }).click();

    await expect(page.getByRole('region', { name: 'What changed in PATHOLOGY' })).toBeVisible();
    await expect(page.getByRole('region', { name: 'Next steps for PATHOLOGY' })).toContainText(
      'OnboardCredential',
    );
    const row = page.getByRole('row', { name: /PATHOLOGY/ });
    await row.getByRole('button', { name: 'Send a test failure' }).click();
    await expect(page.getByText(/A test case opened/)).toBeVisible();
  });

  test('has no sideways scroll on a phone with a plan open, and passes the accessibility check', async ({
    page,
  }) => {
    await page.setViewportSize({ width: 375, height: 800 });
    await signIn(page);
    await go(page, '/settings/namespaces');
    await page.getByLabel('Namespace').selectOption('PATHOLOGY');
    await page.getByRole('button', { name: 'Read the plan' }).click();
    await expect(page.getByRole('region', { name: 'The plan for PATHOLOGY' })).toBeVisible();
    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
    );
    expect(overflow).toBeLessThanOrEqual(0);
    expect(await audit(page)).toEqual([]);
  });
});
