import { expect, test } from '@playwright/test';
import { skipWelcome } from './guide';
import { go, READ_ONLY, signIn } from './helpers';

/**
 * The Agent library: the board as cards, the switches that change it, and the switches the live hospital's public
 * role does not get.
 */

/** The live hospital's public role: the address keeps `?as=demo` in every step. */
const AS_DEMO = { as: 'demo' } as const;

// The guide's welcome would cover the screens these tests are about; guide.spec.ts tests it
test.beforeEach(({ page }) => skipWelcome(page));

test.describe('the board as cards', () => {
  test('lays the members out as cards, and a change says it lasts only in the trial', async ({ page }) => {
    await signIn(page);
    await go(page, '/library');
    await expect(page.getByRole('heading', { name: 'Agent library', level: 1 })).toBeVisible();
    await expect(
      page.getByText(/three specialist agents and a coordinator agent, on IRIS AI Hub/),
    ).toBeVisible();
    for (const name of [
      'Conformance',
      'Encounter Integrity',
      'Impact Analysis',
      'Coordinator',
      'Single Investigator',
    ])
      await expect(page.getByRole('article', { name })).toBeVisible();
    // The question each member asks, on its card
    await expect(
      page
        .getByRole('article', { name: 'Conformance' })
        .getByText('Is the message itself acceptable to the receiver?'),
    ).toBeVisible();
    await expect(page.getByText('On the default board: 4 of 4')).toBeVisible();

    // A switch works, and the card says the change is the trial's own
    await page.getByRole('switch', { name: 'Impact Analysis on the default board' }).click();
    await expect(page.getByText('On the default board: 3 of 4')).toBeVisible();
    await expect(
      page.getByRole('article', { name: 'Impact Analysis' }).getByText('Changed in the trial only.'),
    ).toBeVisible();
  });

  test('shows the cards in a column on a phone, with no switch cut off', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await signIn(page);
    await go(page, '/library');
    const cards = page.getByRole('article');
    await expect(cards).toHaveCount(5);
    const boxes = await cards.evaluateAll((els) => els.map((e) => e.getBoundingClientRect()));
    for (const box of boxes) {
      expect(box.left).toBeGreaterThanOrEqual(0);
      expect(box.right).toBeLessThanOrEqual(390);
    }
    // One column: each card starts below the one before
    for (let i = 1; i < boxes.length; i++) expect(boxes[i]!.top).toBeGreaterThan(boxes[i - 1]!.top);
    await expect(page.getByRole('switch', { name: 'Conformance enabled' })).toBeVisible();
  });

  test('opens the code of every card in Technical', async ({ page }) => {
    await signIn(page, { detail: 'technical' });
    await go(page, '/library', { detail: 'technical' });
    const card = page.getByRole('article', { name: 'Conformance' });
    await expect(card.getByText('Shutter.Agent.Conformance · v1')).toBeVisible();
    await expect(card.getByText('Agent Conformance')).toBeVisible();
    await expect(card.getByText('SubmitFindings')).toBeVisible();
    await expect(page.getByText(/Each member is an IRIS AI Hub agent/)).toBeVisible();
  });
});

test.describe('the live hospital, as the public role sees it', () => {
  test('lets the switches be flipped, with a Save that is locked and says why', async ({ page }) => {
    await signIn(page, AS_DEMO);
    await go(page, '/library', AS_DEMO);
    await expect(page.getByText(READ_ONLY)).toBeVisible();
    const sw = page.getByRole('switch', { name: 'Impact Analysis on the default board' });
    await expect(sw).toBeEnabled();
    await sw.click();
    // The board follows the change on the page, as it does for an approver
    await expect(page.getByText('On the default board: 3 of 4')).toBeVisible();
    const bar = page.getByRole('region', { name: 'Unsaved changes' });
    await expect(bar.getByText('1 change')).toBeVisible();
    const save = bar.getByRole('button', { name: 'Save the board' });
    await expect(save).toHaveAttribute('aria-disabled', 'true');
    await expect(save).toHaveAccessibleDescription(READ_ONLY);
    await bar.getByRole('button', { name: 'Discard changes' }).click();
    await expect(bar).toHaveCount(0);
  });
});
