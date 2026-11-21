import { test as base, type BrowserContext, type Page } from '@playwright/test';

export { expect } from '@playwright/test';
export type { Locator, Page, Route } from '@playwright/test';

type TrialRole = 'approver' | 'operator';

/** Starts every page of a target (a page, or a context a test made itself) as if the tab had chosen the role. */
export function startAs(target: Page | BrowserContext, role: TrialRole = 'approver') {
  return target.addInitScript((r) => {
    try {
      if (!window.sessionStorage.getItem('shutter:trial:as'))
        window.sessionStorage.setItem('shutter:trial:as', r);
    } catch {
      // Storage refused: the page starts on the trial's sign-in page
    }
  }, role);
}

/**
 * The trial starts on its own sign-in page until the tab has chosen a role. Most tests are about the pages behind it,
 * so each page starts as if the tab had chosen `trialRole` (the approver), as a person who pressed Continue would; a
 * role the address names (`?as=`) still comes first, and a role chosen during the test is kept across its reloads.
 * A test of the start itself sets `test.use({ trialRole: null })`; a context a test makes itself takes `startAs`.
 */
export const test = base.extend<{ trialRole: TrialRole | null }>({
  trialRole: ['approver', { option: true }],
  context: async ({ context, trialRole }, provide) => {
    if (trialRole) await startAs(context, trialRole);
    await provide(context);
  },
});
