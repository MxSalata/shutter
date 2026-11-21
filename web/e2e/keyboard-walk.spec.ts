import { expect, test, type Locator } from './test';
import { go, signIn } from './helpers';
import { skipWelcome } from './guide';

/**
 * The keyboard and screen-reader walk through the states that change, on the trial: what a reader using only the keys
 * meets when the approval review turns to the other decision, when a scenario run plays and finishes, and when a
 * filter empties the Cases list and "Show every case" fills it again; and that the standing notices on the way are
 * notes, not alerts said over the page. A change is announced when it happens inside a live region that was already
 * on the page, so each check marks the region first and finds the mark still there. The stale and refused decisions
 * and a read that fails are walked on the build IRIS serves (keyboard-walk-live-trial.spec.ts), which can be made to
 * refuse.
 */

test.beforeEach(({ page }) => skipWelcome(page));

/** Marks a live region, so a later check can tell that it is the same element and so was announced, not re-made. */
const mark = (region: Locator) =>
  region.evaluate((el) => {
    (el as HTMLElement & { walkMark?: boolean }).walkMark = true;
  });
const marked = (region: Locator) =>
  region.evaluate((el) => (el as HTMLElement & { walkMark?: boolean }).walkMark === true);

test.describe('the keyboard walk on the trial', () => {
  test('says what the turned review does when "Reject instead" is pressed, and Escape goes back to the action', async ({
    page,
  }) => {
    await signIn(page);
    await go(page, '/cases/C-000002');
    // The trial's word that the case is held is a standing note on the page, not an alert said on every arrival
    await expect(page.getByRole('note').filter({ hasText: 'Held for you to decide' })).toBeVisible();
    await expect(page.getByRole('alert').filter({ hasText: 'Held for you to decide' })).toHaveCount(0);
    const action = page.getByTestId('case-action');
    await action.focus();
    await page.keyboard.press('Enter');
    const dialog = page.getByRole('dialog', { name: 'Approve the resend: plan v1' });
    await expect(dialog).toBeVisible();
    // The one review, whatever its title says: it is named for the decision it is on, which the press turns
    const said = page.getByRole('dialog').getByTestId('confirm-consequence');
    await expect(said).toHaveAttribute('aria-live', 'polite');
    await mark(said);
    await dialog.getByRole('button', { name: 'Reject instead' }).focus();
    await page.keyboard.press('Enter');
    const turned = page.getByRole('dialog', { name: 'Reject the resend: plan v1' });
    await expect(turned.getByRole('button', { name: 'Approve instead' })).toBeFocused();
    await expect(said).toHaveText(/^Nothing is sent\. The case stops as blocked/);
    expect(await marked(said)).toBe(true);
    await page.keyboard.press('Escape');
    await expect(turned).toBeHidden();
    await expect(action).toBeFocused();
  });

  test('keeps the focus on the run while S2 plays, and the next Tab reaches its case', async ({ page }) => {
    await go(page, '/');
    await page.getByRole('link', { name: 'Start with S2' }).focus();
    await page.keyboard.press('Enter');
    const run = page.getByRole('button', { name: 'Run S2 in Board mode' });
    await expect(run).toBeFocused();
    // The demo's site profile is a standing note on the page, not an alert said over the focused Run
    const note = page.getByRole('note').filter({ hasText: "Shutter is running on the demo's answers" });
    await expect(note).toBeVisible();
    await expect(
      page.getByRole('alert').filter({ hasText: "Shutter is running on the demo's answers" }),
    ).toHaveCount(0);
    // What the polite line says while the run plays, and every alert that appears: recorded from before the press
    await page.evaluate(() => {
      const w = window as unknown as { walkSaid: string[]; walkAlerts: string[] };
      w.walkSaid = [];
      w.walkAlerts = [];
      const said = document.querySelector('[data-testid="run-said"]')!;
      new MutationObserver(() => {
        const text = said.textContent ?? '';
        if (text && text !== w.walkSaid.at(-1)) w.walkSaid.push(text);
        for (const alert of document.querySelectorAll('[role="alert"]'))
          if (!w.walkAlerts.includes(alert.textContent ?? '')) w.walkAlerts.push(alert.textContent ?? '');
      }).observe(document.body, { childList: true, subtree: true, characterData: true });
    });
    await page.keyboard.press('Enter');
    // The pressed Run turns into a spinner: the focus is on the run's status, not dropped to the page
    const status = page.getByRole('region', { name: 'Scenario run' });
    await expect(status).toBeFocused();
    await expect(status).toContainText('S2 played (Board)', { timeout: 30_000 });
    await expect(status).toBeFocused();
    // Said once as it starts, plays and has played, never at each step; the playing banner is no alert
    await expect
      .poll(() => page.evaluate(() => (window as unknown as { walkSaid: string[] }).walkSaid))
      .toEqual([
        'S2 is starting in Board mode.',
        'S2 is playing in Board mode.',
        'S2 has played in Board mode.',
      ]);
    const alerts = await page.evaluate(() => (window as unknown as { walkAlerts: string[] }).walkAlerts);
    expect(alerts.filter((a) => /Playing S2|Now delivering/.test(a))).toEqual([]);
    const open = status.getByRole('link', { name: /C-000002/ });
    await expect(open).toBeVisible();
    for (let i = 0; i < 6 && !(await open.evaluate((el) => el === document.activeElement)); i++)
      await page.keyboard.press('Tab');
    await expect(open).toBeFocused();
  });

  test('says the count when a filter empties the list, and "Show every case" leaves the focus on the filters', async ({
    page,
  }) => {
    await signIn(page);
    await go(page, '/cases');
    await expect(page.getByRole('heading', { name: 'Cases', exact: true })).toBeVisible();
    const count = page.getByTestId('cases-count');
    await expect(count).toHaveAttribute('aria-live', 'polite');
    await expect(count).toHaveText(/^\d+ cases$/);
    await mark(count);
    const state = page.getByRole('combobox', { name: 'State' });
    await state.focus();
    // The first state in the list has no case in the recording
    await page.keyboard.press('ArrowDown');
    const all = page.getByRole('button', { name: 'Show every case' });
    await expect(all).toBeVisible();
    await expect(count).toHaveText('0 cases');
    expect(await marked(count)).toBe(true);
    await all.focus();
    await page.keyboard.press('Enter');
    await expect(all).toHaveCount(0);
    await expect(state).toBeFocused();
    await expect(state).toHaveValue('');
    await expect(count).toHaveText(/^[1-9]\d* cases$/);
    expect(await marked(count)).toBe(true);
  });
});
