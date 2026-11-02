import type { Page } from '@playwright/test';

/** The guide's progress on the device, as the app stores it. */
export const GUIDE_KEY = 'shutter:guide:v2';

/**
 * Marks the guide's welcome as already dismissed before the app starts, for tests about other things: the welcome
 * opens on a first entry into the trial and would cover the screen. Progress a test has made is left as it is.
 */
export function skipWelcome(page: Page) {
  return page.addInitScript((key) => {
    try {
      if (!localStorage.getItem(key))
        localStorage.setItem(
          key,
          JSON.stringify({ version: 2, scope: 'quick', at: null, completed: [], dismissed: true }),
        );
    } catch {
      // No storage: the welcome then opens, and the test shows it
    }
  }, GUIDE_KEY);
}
