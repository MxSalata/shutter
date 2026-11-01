import { expect, test } from '@playwright/test';
import { skipWelcome } from './guide';
import { go, READ_ONLY, signIn } from './helpers';

/**
 * The Site profile: the pre-filled draft and its review, kept for reading by the live hospital's public role.
 */

/** The live hospital's public role: the address keeps `?as=demo` in every step. */
const AS_DEMO = { as: 'demo' } as const;

// The guide's welcome would cover the screens these tests are about; guide.spec.ts tests it
test.beforeEach(({ page }) => skipWelcome(page));

test.describe('the live hospital, as the public role sees it', () => {
  test('keeps the pre-filled draft and its review for reading, with a note instead of Save', async ({
    page,
  }) => {
    await signIn(page, AS_DEMO);
    await go(page, '/site-profile?suggest=C-000008&fact=W1', AS_DEMO);
    const card = page.getByRole('region', { name: 'A suggested change from case C-000008' });
    await expect(card).toBeVisible();
    await expect(card.getByRole('button', { name: 'Review and save…' })).toHaveCount(0);
    await expect(page.getByRole('button', { name: /Review and save|Confirm these answers/ })).toHaveCount(0);
    await card.getByRole('button', { name: 'Review the change…' }).click();
    const dialog = page.getByRole('dialog');
    await expect(dialog.getByText(/Authoritative source: from .* to BEDMGR/)).toBeVisible();
    await expect(dialog.getByText(READ_ONLY)).toBeVisible();
    await expect(dialog.getByRole('button', { name: /^Save version/ })).toHaveCount(0);
    await dialog.getByRole('button', { name: 'Done' }).click();
    await expect(dialog).toHaveCount(0);
    await expect(page.getByText(READ_ONLY).first()).toBeVisible();
  });
});
