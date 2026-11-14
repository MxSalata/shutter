import { expect, test } from '@playwright/test';
import { skipWelcome } from './guide';
import { go, READ_ONLY, signIn } from './helpers';

/**
 * The Site profile: the two halves (what the policy does, then the answers), the save bar and the review, and the
 * pre-filled draft and its review, which the live hospital's public role changes and reviews with a locked Save.
 */

/** The live hospital's public role: the address keeps `?as=demo` in every step. */
const AS_DEMO = { as: 'demo' } as const;

// The guide's welcome would cover the screens these tests are about; guide.spec.ts tests it
test.beforeEach(({ page }) => skipWelcome(page));

test.describe('the live hospital, as the public role sees it', () => {
  test('lets the pre-filled draft be changed and reviewed, with a Save that is locked and says why', async ({
    page,
  }) => {
    await signIn(page, AS_DEMO);
    await go(page, '/site-profile?suggest=C-000008&fact=W1', AS_DEMO);
    const card = page.getByRole('region', { name: 'A suggested change from case C-000008' });
    await expect(card).toBeVisible();
    await expect(card.getByText(READ_ONLY)).toBeVisible();
    // A change of the reader's own joins the suggested one, as an approver's would
    const receiver = page.getByRole('group', { name: 'Receiver 1: Downstream Out' });
    await receiver.getByRole('radio', { name: /3, clinical safety/ }).check();
    const bar = page.getByRole('region', { name: 'Unsaved changes' });
    await expect(bar.getByText('2 changes')).toBeVisible();
    await expect(bar.getByText(READ_ONLY)).toBeVisible();
    await bar.getByRole('button', { name: 'Review and save…' }).click();
    const dialog = page.getByRole('dialog');
    await expect(dialog.getByText(/Authoritative source: from .* to BEDMGR/)).toBeVisible();
    const save = dialog.getByRole('button', { name: /^Save version/ });
    await expect(save).toHaveAttribute('aria-disabled', 'true');
    await expect(save).toHaveAccessibleDescription(READ_ONLY);
    // Reached from the keyboard, and pressing it saves nothing
    await save.focus();
    await page.keyboard.press('Enter');
    await expect(dialog).toBeVisible();
    await dialog.getByRole('button', { name: 'Cancel' }).click();
    await expect(dialog).toHaveCount(0);
    await expect(bar.getByText('2 changes')).toBeVisible();
  });
});

test.describe('the trial, as the approver of the recorded runs', () => {
  test('shows the policy first: receivers with their tier, and who releases each write', async ({ page }) => {
    await signIn(page);
    await go(page, '/site-profile');
    const cards = page.getByRole('list', { name: 'The receivers and what each needs' });
    await expect(cards.getByRole('listitem', { name: 'Downstream Out' })).toContainText('Current state');
    await expect(cards.getByRole('listitem', { name: 'Downstream Out' })).toContainText('Tier 2, operations');
    await expect(cards.getByRole('listitem', { name: 'Records Out' })).toContainText('History of record');
    const matrix = page.getByRole('table', { name: 'Who releases each write' });
    await expect(matrix.getByRole('columnheader', { name: 'One failed message' })).toBeVisible();
    await expect(matrix.getByRole('rowheader', { name: /Tier 3: clinical safety/ })).toBeVisible();
    // The policy half comes before the answers
    const policy = await page.getByRole('heading', { name: "What this site's policy does" }).boundingBox();
    const answers = await page.getByRole('heading', { name: 'The answers', exact: true }).boundingBox();
    expect(policy!.y).toBeLessThan(answers!.y);
  });

  test('raises the save bar on a change, and saves it in the trial with the trial’s words', async ({
    page,
  }) => {
    await signIn(page);
    await go(page, '/site-profile');
    await expect(page.getByRole('region', { name: 'Unsaved changes' })).toHaveCount(0);
    await page.getByRole('switch', { name: /Downstream Out accepts cancels/ }).check();
    const bar = page.getByRole('region', { name: 'Unsaved changes' });
    await expect(bar).toContainText('1 change');
    await expect(bar).toContainText('A save lasts until you reload or leave.');
    await bar.getByRole('button', { name: 'Review and save…' }).click();
    const dialog = page.getByRole('dialog');
    await expect(dialog).toContainText('Trial only');
    await expect(dialog).toContainText("In the trial, saving changes only this browser's copy");
    await dialog.getByRole('button', { name: 'Save version 8' }).click();
    await expect(page.getByText('Version 8 saved')).toBeVisible();
    await expect(page.getByText('Saved in the trial. It lasts until you reload or leave.')).toBeVisible();
    await expect(bar).toHaveCount(0);
    await expect(page.getByText('Shipped answers')).toHaveCount(0);
  });

  test('jumps to a section of the answers from On this page, a select below 1408 px', async ({ page }) => {
    await signIn(page);
    await go(page, '/site-profile');
    await expect(page.getByRole('navigation', { name: 'On this page' })).toBeHidden();
    await page.getByRole('combobox', { name: 'On this page' }).selectOption({ label: 'Approvals, 7' });
    const heading = page.getByRole('heading', { name: 'Approvals', exact: true });
    await expect(heading).toBeFocused();
    await expect(heading).toBeInViewport();
  });

  test('shows On this page as a column from 1408 px', async ({ page }) => {
    await page.setViewportSize({ width: 1500, height: 900 });
    await signIn(page);
    await go(page, '/site-profile');
    const nav = page.getByRole('navigation', { name: 'On this page' });
    await expect(nav).toBeVisible();
    await expect(page.getByRole('combobox', { name: 'On this page' })).toBeHidden();
    await nav.getByRole('button', { name: 'Incidents, 8' }).click();
    await expect(page.getByRole('heading', { name: 'Incidents', exact: true })).toBeFocused();
  });

  // A receiver's questions sit in its group and question 1 outside it: the numbers, the icons and the folds line up
  for (const width of [1280, 360])
    test(`lines up the receivers' questions and folds, in a receiver's group or outside it, at ${width} px`, async ({
      page,
    }) => {
      await page.setViewportSize({ width, height: 900 });
      await signIn(page);
      await go(page, '/site-profile');
      const section = page.locator('#site-receivers');
      await expect(section.getByRole('group', { name: 'Receiver 2: Records Out' })).toBeVisible();
      const at = await section.evaluate((sec) => {
        const box = (e: Element) => e.getBoundingClientRect();
        const questions = [...sec.querySelectorAll('[data-question]')];
        // The folds, not a question's "Ask Shutter about this", which ends its question's row
        const folds = [...sec.querySelectorAll('fieldset button[aria-expanded]:not([data-ask-about])')];
        const intro = sec.querySelector('h2')!.nextElementSibling!;
        return {
          inGroup: questions.filter((q) => q.closest('fieldset')).length,
          outside: questions.filter((q) => !q.closest('fieldset')).length,
          numbers: questions.map((q) => box(q.firstElementChild!).left),
          icons: questions.map((q) => box(q.lastElementChild!).right),
          heading: box(sec.querySelector('h2')!).left,
          // Each receiver's first field, Production item
          fields: [...sec.querySelectorAll('fieldset')].map((f) => box(f.querySelector('input')!).left),
          intro: { left: box(intro).left, right: box(intro).right },
          folds: folds.map((f) => ({ name: f.textContent, left: box(f).left })),
          styles: folds.map((f) => {
            const css = getComputedStyle(f);
            return `${css.color} ${css.fontWeight} ${css.fontSize} ${css.backgroundColor}`;
          }),
        };
      });
      const spread = (xs: number[]) => Math.max(...xs) - Math.min(...xs);
      expect(at.outside).toBe(1);
      expect(at.inGroup).toBe(10);
      // Each number starts where the heading and the fields do, and each icon ends where the intro does
      expect(spread([...at.numbers, at.heading, at.intro.left, ...at.fields])).toBeLessThanOrEqual(1);
      expect(spread([...at.icons, at.intro.right])).toBeLessThanOrEqual(1);
      // The runbook line, the history policy, Keys and values and More about this question: one style, one edge
      expect(at.folds.map((f) => f.name)).toEqual(
        expect.arrayContaining(['Site runbook line', 'Advanced: its history policy', 'Keys and values']),
      );
      expect(spread([...at.folds.map((f) => f.left), at.heading])).toBeLessThanOrEqual(1);
      expect(new Set(at.styles).size).toBe(1);
    });

  test('puts each question’s key path in Keys and values, open in Technical', async ({ page }) => {
    await signIn(page, { detail: 'technical' });
    await go(page, '/site-profile', { detail: 'technical' });
    await expect(page.getByText('approvers.close_needs_approver', { exact: true }).first()).toBeVisible();
    await expect(page.getByText('feed.time_zone', { exact: true }).first()).toBeVisible();
    await expect(page.getByRole('table', { name: 'Who releases each write' })).toContainText('interleaved');
  });
});
